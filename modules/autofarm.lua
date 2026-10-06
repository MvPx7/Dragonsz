-- modules/autofarm.lua
-- Segue o NPC mais próximo, mantém o personagem MIRANDO nele (mesmo com Trava Shift),
-- ataca sozinho, detecta quando o NPC morre e troca de alvo.
--
-- Uso:
--   Autofarm.enable(player, distanceFn)            -- distanceFn() = folga em studs entre os corpos
--   Autofarm.enable(player, distanceFn, { ... })   -- opções (opcional)
--   Autofarm.disable()
--   Autofarm.getKills()
--
-- Teclas (enquanto ligado):
--   RightControl = pausa / retoma TUDO (movimento + cliques). Use ao abrir menus.
--   F7           = imprime no Output os dados do NPC mais próximo (para diagnosticar a morte)
--
-- Diagnóstico: Autofarm.enable(player, distanceFn, { debug = true })

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Autofarm = {}

local MOVE_STEP = "AutofarmFollow"
local AIM_STEP  = "AutofarmAim"
local MY_RADIUS = 1.5 -- raio aproximado do seu personagem (studs)

local DEFAULTS = {
	behindNpc         = true,    -- fica nas costas do NPC
	lockAim           = true,    -- personagem sempre virado para o NPC (vence a Trava Shift)
	attackInterval    = 0.15,    -- segundos entre ataques
	attackMode        = "auto",  -- "auto" | "native" | "click" | "hold" | "tool"
	clickFn           = nil,     -- função própria de ataque (substitui attackMode)
	isDeadFn          = nil,     -- função(npc) -> true se o NPC está morto
	onKill            = nil,     -- função(npc, totalMortes) chamada quando o alvo morre
	safeClick         = true,    -- NÃO clica com menu aberto / mouse sobre botão / janela sem foco
	useBarDetection   = true,    -- detecta morte pela barra de vida do NPC chegando a zero
	pauseKey          = Enum.KeyCode.RightControl,
	dumpKey           = Enum.KeyCode.F7,
	captureController = false,   -- chama VirtualUser:CaptureController() ao ligar
	debug             = false,   -- imprime diagnóstico no Output
	smoothing         = 20,      -- maior = segue mais rápido; menor = mais suave
	retargetEvery     = 0.5,     -- segundos entre buscas de alvo
	reachPadding      = 1.5,     -- tolerância extra do alcance (studs)
	requireRange      = false,   -- true = só ataca dentro do alcance estimado
	stuckTimeout      = 8,       -- segundos sem o NPC perder vida => ignora e troca de alvo (0 = desliga)
	heightOffset      = 0,       -- ajuste de altura em relação ao NPC
}

local state = nil

local function log(s, ...)
	if s and s.opts.debug then
		print("[Autofarm]", ...)
	end
end

----------------------------------------------------------------
-- Detecção de morte (vários sinais, porque cada jogo faz de um jeito)
----------------------------------------------------------------
local DEAD_FLAGS = { dead = true, isdead = true, died = true, dying = true, isdying = true }
local HP_NAMES = {
	health = true, hp = true, currenthealth = true, currenthp = true, curhealth = true, curhp = true,
}

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- Atributos / valores do modelo dizendo que morreu
local function dataSaysDead(npc)
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local holders = { npc }
	if hum then table.insert(holders, hum) end

	for _, h in ipairs(holders) do
		for k, v in pairs(h:GetAttributes()) do
			local key = string.lower(tostring(k))
			if DEAD_FLAGS[key] and v == true then return "atributo " .. tostring(k) .. " = true" end
			if HP_NAMES[key] and type(v) == "number" and v <= 0 then return "atributo " .. tostring(k) .. " <= 0" end
		end
	end

	for _, c in ipairs(npc:GetChildren()) do
		if c:IsA("ValueBase") then
			local key = string.lower(c.Name)
			if DEAD_FLAGS[key] and c.Value == true then return "valor " .. c.Name .. " = true" end
			if HP_NAMES[key] and type(c.Value) == "number" and c.Value <= 0 then return "valor " .. c.Name .. " <= 0" end
		end
	end
	return nil
end

-- Barras (GuiObjects) do NPC que começaram com largura > 0: se zerarem, o NPC morreu
local function collectBars(npc)
	local bars = {}
	for _, d in ipairs(npc:GetDescendants()) do
		if #bars >= 60 then break end
		if d:IsA("GuiObject") and not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then
			if d.Size.X.Scale >= 0.05 then
				table.insert(bars, d)
			end
		end
	end
	return bars
end

-- Retorna o motivo da morte (string) ou nil se está vivo
local function deathReason(s, npc)
	if not npc:IsDescendantOf(workspace) then return nil end

	local hum = npc:FindFirstChildOfClass("Humanoid")
	if not hum then return "Humanoid removido" end
	if hum.Health <= 0 then return "Humanoid.Health <= 0" end
	if hum:GetState() == Enum.HumanoidStateType.Dead then return "estado Dead" end

	local d = dataSaysDead(npc)
	if d then return d end

	if s.opts.useBarDetection then
		for _, b in ipairs(s.bars) do
			if b.Parent and b.Size.X.Scale <= 0.01 and b.Size.X.Offset <= 1 then
				return "barra de vida zerada: " .. b:GetFullName()
			end
		end
	end

	if s.opts.isDeadFn then
		local ok, dead = pcall(s.opts.isDeadFn, npc)
		if ok and dead then return "isDeadFn" end
	end
	return nil
end

-- Versão leve usada na busca de alvos
local function isAlive(npc)
	if not npc or not npc.Parent or not npc:IsDescendantOf(workspace) then return false end
	if state and state.dead[npc] and os.clock() < state.dead[npc] then return false end

	local hum = npc:FindFirstChildOfClass("Humanoid")
	if not hum or getRoot(npc) == nil then return false end
	if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return false end
	if dataSaysDead(npc) then return false end

	if state and state.opts.isDeadFn then
		local ok, dead = pcall(state.opts.isDeadFn, npc)
		if ok and dead then return false end
	end
	return true
end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function isNPC(model, myChar)
	if not model:IsA("Model") or model == myChar then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	if state and state.ignored[model] and os.clock() < state.ignored[model] then return false end
	return isAlive(model)
end

-- Raio horizontal real do NPC (caixa que envolve o modelo inteiro)
local function getRadius(model)
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Z) / 2
end

local function getReach(s)
	return s.radius + MY_RADIUS + s.distanceFn() + s.opts.reachPadding
end

local function pickTarget(hrp, myChar)
	local nearest, nearestDist = nil, math.huge
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isNPC(obj, myChar) then
			local d = (hrp.Position - getRoot(obj).Position).Magnitude
			if d < nearestDist then
				nearest, nearestDist = obj, d
			end
		end
	end
	return nearest
end

-- Vira SÓ o personagem para o NPC (na horizontal), sem tocar na câmera
local function aimAtTarget(s, hrp)
	local nHrp = s.target and getRoot(s.target)
	if not nHrp then return end
	local p = hrp.Position
	local look = Vector3.new(nHrp.Position.X, p.Y, nHrp.Position.Z)
	if (look - p).Magnitude < 0.05 then return end
	hrp.CFrame = CFrame.lookAt(p, look)
end

----------------------------------------------------------------
-- Segurança do clique (evita clicar em menus)
----------------------------------------------------------------
local function cursorOverUi(s)
	local pg = s.player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end

	local loc = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local positions = { loc - inset, loc }

	for _, pos in ipairs(positions) do
		for _, obj in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y)) do
			if obj:IsA("GuiButton") then
				return true
			end
			-- painéis de menu costumam ser Frames "Active" com fundo visível
			if obj.Active and obj.BackgroundTransparency < 0.95 then
				return true
			end
		end
	end
	return false
end

-- true = pode clicar. Retorna também o motivo quando não pode.
local function safeToClick(s)
	if not s.focused then return false, "janela sem foco" end
	if GuiService.MenuIsOpen then return false, "menu do Roblox aberto" end
	if UserInputService:GetFocusedTextBox() then return false, "digitando em caixa de texto" end
	if cursorOverUi(s) then return false, "mouse sobre botão/menu" end
	return true
end

----------------------------------------------------------------
-- Alvo
----------------------------------------------------------------
local function clearTargetConns(s)
	for _, c in ipairs(s.targetConns) do c:Disconnect() end
	s.targetConns = {}
end

-- Solta o alvo atual. killed = true quando ele morreu (conta como kill)
local function dropTarget(s, npc, killed, reason)
	if s.target ~= npc then return end -- evita contar duas vezes
	clearTargetConns(s)
	s.target = nil
	s.bars = {}
	s.lastScan = 0 -- procura o próximo alvo imediatamente

	log(s, "alvo solto:", npc.Name, "| motivo:", reason or "?", "| kill:", killed)

	if killed then
		s.kills += 1
		if s.opts.onKill then
			task.spawn(s.opts.onKill, npc, s.kills)
		end
	end
end

local function describeNpc(npc)
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local parts = {}
	if hum then
		table.insert(parts, string.format("Health=%.1f/%.1f", hum.Health, hum.MaxHealth))
	end
	for k, v in pairs(npc:GetAttributes()) do
		table.insert(parts, "attr " .. tostring(k) .. "=" .. tostring(v))
	end
	for _, c in ipairs(npc:GetChildren()) do
		if c:IsA("ValueBase") then
			table.insert(parts, c.ClassName .. " " .. c.Name .. "=" .. tostring(c.Value))
		end
	end
	return table.concat(parts, " | ")
end

local function setTarget(s, npc)
	clearTargetConns(s)
	s.target = npc
	if not npc then return end

	s.radius = getRadius(npc)
	s.bars = collectBars(npc)
	local h0 = npc:FindFirstChildOfClass("Humanoid")
	s.lastHealth = h0 and h0.Health or 0
	s.lastProgress = os.clock()
	log(s, "novo alvo:", npc.Name, "| raio:", string.format("%.1f", s.radius), "| barras:", #s.bars, "|", describeNpc(npc))

	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		table.insert(s.targetConns, hum.Died:Connect(function()
			s.dead[npc] = os.clock() + 60
			dropTarget(s, npc, true, "Humanoid.Died")
		end))
	end
	-- NPC removido do jogo sem morrer (despawn): só troca de alvo, sem contar kill
	table.insert(s.targetConns, npc.AncestryChanged:Connect(function(_, parent)
		if not parent then dropTarget(s, npc, false, "removido do jogo") end
	end))
end

----------------------------------------------------------------
-- Dump de dados do NPC (tecla F7)
----------------------------------------------------------------
local function dumpModel(npc, label)
	print("[Autofarm][DUMP]", label, npc:GetFullName())
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		print("   Humanoid:", string.format("Health=%.2f Max=%.2f Estado=%s", hum.Health, hum.MaxHealth, hum:GetState().Name))
		for k, v in pairs(hum:GetAttributes()) do print("   attr(Humanoid)", k, v) end
	else
		print("   Humanoid: nenhum")
	end
	for k, v in pairs(npc:GetAttributes()) do print("   attr", k, v) end
	for _, c in ipairs(npc:GetChildren()) do
		if c:IsA("ValueBase") then print("   valor", c.ClassName, c.Name, c.Value) end
	end
	local root = getRoot(npc)
	if root then
		print("   Raiz:", root.Name, "Anchored=", root.Anchored, "Transparency=", root.Transparency, "CanCollide=", root.CanCollide)
	end
	local n = 0
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("GuiObject") and n < 40 then
			n += 1
			local extra = d:IsA("TextLabel") and (" texto=" .. d.Text) or ""
			print("   gui", d.ClassName, d:GetFullName(), "Size.X=", d.Size.X.Scale, d.Size.X.Offset, "Visible=", d.Visible, extra)
		end
	end
end

local function dumpNearest(s)
	local char = s.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local nearest, nearestDist = nil, math.huge
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj ~= char and not Players:GetPlayerFromCharacter(obj)
			and obj:FindFirstChildOfClass("Humanoid") and getRoot(obj) then
			local d = (hrp.Position - getRoot(obj).Position).Magnitude
			if d < nearestDist then nearest, nearestDist = obj, d end
		end
	end

	if nearest then dumpModel(nearest, "NPC mais próximo (inclui mortos)") end
	if s.target and s.target ~= nearest then dumpModel(s.target, "alvo atual") end
	print("[Autofarm][DUMP] fim")
end

----------------------------------------------------------------
-- Diagnóstico (só roda com debug = true)
----------------------------------------------------------------
local function watchTool(s, tool)
	if not tool or s.watchedTool == tool then return end
	if s.toolConn then s.toolConn:Disconnect() end
	s.watchedTool = tool
	s.toolConn = tool.Activated:Connect(function()
		s.toolActivated += 1
	end)
	log(s, "ferramenta equipada:", tool.Name)
end

local function debugTick(s, char, hrp)
	if not s.opts.debug then return end
	local now = os.clock()
	if now - s.lastDebug < 1 then return end
	s.lastDebug = now

	local tool = char:FindFirstChildOfClass("Tool")
	watchTool(s, tool)

	local npc = s.target
	if not npc then
		log(s, "sem alvo | kills:", s.kills)
		return
	end

	local nHrp = getRoot(npc)
	local toNpc = nHrp and Vector3.new(nHrp.Position.X - hrp.Position.X, 0, nHrp.Position.Z - hrp.Position.Z) or Vector3.zero
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	local aimErr = 0
	if toNpc.Magnitude > 0.01 and look.Magnitude > 0.01 then
		aimErr = math.deg(math.acos(math.clamp(toNpc.Unit:Dot(look.Unit), -1, 1)))
	end
	local hum = npc:FindFirstChildOfClass("Humanoid")

	log(s, string.format(
		"alvo=%s vida=%s dist=%.1f alcance=%.1f mira_erro=%.0f° | por segundo: ataques=%d bloqueados=%d fora_alcance=%d | kills=%d%s",
		npc.Name,
		hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "sem humanoid",
		toNpc.Magnitude, getReach(s), aimErr,
		s.swings, s.blocked, s.outOfRange, s.kills,
		s.paused and " | PAUSADO" or ""
	))
	s.swings, s.outOfRange, s.toolActivated, s.uisClicks, s.blocked = 0, 0, 0, 0, 0
end

----------------------------------------------------------------
-- Movimento (antes da câmera, para não tremer)
----------------------------------------------------------------
local function follow(dt)
	local s = state
	if not s then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- Pausado: devolve o controle ao jogador
	if s.paused then
		if s.prevAutoRotate ~= nil then
			hum.AutoRotate = s.prevAutoRotate
			s.prevAutoRotate = nil
		end
		return
	end

	-- Impede o personagem de girar sozinho
	if s.prevAutoRotate == nil then s.prevAutoRotate = hum.AutoRotate end
	hum.AutoRotate = false

	-- Alvo removido do jogo
	if s.target and not s.target:IsDescendantOf(workspace) then
		dropTarget(s, s.target, false, "removido do jogo")
	end

	-- Alvo morreu? (vários sinais)
	if s.target then
		local reason = deathReason(s, s.target)
		if reason then
			local npc = s.target
			s.dead[npc] = os.clock() + 60 -- não volta a escolher o cadáver
			dropTarget(s, npc, true, reason)
		end
	end

	-- Alvo que não perde vida há muito tempo (travado/invulnerável): ignora por 15s e troca
	if s.target and s.opts.stuckTimeout > 0 then
		local th = s.target:FindFirstChildOfClass("Humanoid")
		if th then
			local t = os.clock()
			if th.Health < s.lastHealth - 0.01 then s.lastProgress = t end
			s.lastHealth = th.Health
			if t - s.lastProgress > s.opts.stuckTimeout then
				s.ignored[s.target] = t + 15
				dropTarget(s, s.target, false, "sem perder vida há " .. s.opts.stuckTimeout .. "s (ignorado por 15s)")
			end
		end
	end

	-- Sem alvo: procura o mais próximo
	if not s.target then
		local now = os.clock()
		if now - s.lastScan >= s.opts.retargetEvery then
			s.lastScan = now
			local found = pickTarget(hrp, char)
			if found then setTarget(s, found) end
		end
	end

	debugTick(s, char, hrp)

	local npc = s.target
	if not npc then return end
	local nHrp = getRoot(npc)
	if not nHrp then return end

	-- Distância centro-a-centro = raio do NPC + seu raio + folga configurada
	local offset = s.radius + MY_RADIUS + s.distanceFn()
	local npcPos = nHrp.Position

	local dir
	if s.opts.behindNpc then
		dir = -nHrp.CFrame.LookVector
	else
		dir = hrp.Position - npcPos
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		dir = -hrp.CFrame.LookVector
		dir = Vector3.new(dir.X, 0, dir.Z)
	end

	local goalPos = npcPos + dir.Unit * offset
	goalPos = Vector3.new(goalPos.X, npcPos.Y + s.opts.heightOffset, goalPos.Z)

	-- Posição suave (independe do FPS)
	local alpha = 1 - math.exp(-s.opts.smoothing * dt)
	local newPos = hrp.Position:Lerp(goalPos, alpha)

	local lookAt = Vector3.new(npcPos.X, newPos.Y, npcPos.Z)
	if (lookAt - newPos).Magnitude > 0.05 then
		hrp.CFrame = CFrame.lookAt(newPos, lookAt)
	else
		hrp.CFrame = CFrame.new(newPos) * hrp.CFrame.Rotation
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Roda DEPOIS da câmera: a Trava Shift vira o personagem para onde a câmera olha,
-- então reaplicamos a mira no NPC logo depois. A câmera não é alterada.
local function aim()
	local s = state
	if not s or s.paused or not s.opts.lockAim or not s.target then return end
	local char = s.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then aimAtTarget(s, hrp) end
end

----------------------------------------------------------------
-- Ataque automático
----------------------------------------------------------------
local function swing(s, char)
	if s.opts.clickFn then
		pcall(s.opts.clickFn)
		return
	end

	local mode = s.opts.attackMode
	local cam = workspace.CurrentCamera

	-- "mouse1click" só existe em alguns ambientes de execução; no Roblox normal é nil
	local hasNative = type(mouse1click) == "function"

	local useNative = (mode == "native") or (mode == "auto" and hasNative)
	local useClick  = (mode == "click") or (mode == "auto" and not hasNative)
	local useHold   = (mode == "hold")
	local useTool   = (mode == "tool") or (mode == "auto")

	-- Cliques de mouse acontecem onde o cursor está: só clica se for seguro
	if useNative or useClick or useHold then
		local ok, why = true, nil
		if s.opts.safeClick then ok, why = safeToClick(s) end
		if not ok then
			s.blocked += 1
			s.lastBlockReason = why
			useNative, useClick, useHold = false, false, false
		end
	end

	if useNative and hasNative then
		pcall(mouse1click)
	end

	if useClick then
		pcall(function()
			VirtualUser:ClickButton1(Vector2.new(0, 0), cam.CFrame)
		end)
	end

	if useHold then
		pcall(function() VirtualUser:Button1Down(Vector2.new(0, 0), cam.CFrame) end)
		task.delay(0.05, function()
			pcall(function() VirtualUser:Button1Up(Vector2.new(0, 0), cam.CFrame) end)
		end)
	end

	if useTool then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			pcall(function() tool:Activate() end)
			local remote = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("Fire")
			if remote and remote:IsA("RemoteEvent") then
				pcall(function() remote:FireServer() end)
			end
		end
	end
end

local function attack()
	local s = state
	if not s or s.paused or not isAlive(s.target) then return end

	local now = os.clock()
	if now - s.lastAttack < s.opts.attackInterval then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- Alcance estimado
	local nPos = getRoot(s.target).Position
	local flat = Vector3.new(hrp.Position.X - nPos.X, 0, hrp.Position.Z - nPos.Z).Magnitude
	if flat > getReach(s) then
		s.outOfRange += 1
		if s.opts.requireRange then return end
	end

	-- Sem ferramenta na mão: tenta equipar (no máximo 1x por segundo, sem travar o ataque)
	if not char:FindFirstChildOfClass("Tool") and now - s.lastEquip > 1 then
		local backpack = s.player:FindFirstChildOfClass("Backpack")
		local first = backpack and backpack:FindFirstChildOfClass("Tool")
		if first then
			s.lastEquip = now
			hum:EquipTool(first)
			return
		end
	end

	-- Garante a mira no NPC no instante do golpe
	if s.opts.lockAim then aimAtTarget(s, hrp) end

	s.lastAttack = now
	s.swings += 1
	swing(s, char)
end

----------------------------------------------------------------
-- API pública
----------------------------------------------------------------
function Autofarm.enable(player, distanceFn, options)
	Autofarm.disable()

	local opts = table.clone(DEFAULTS)
	if options then
		for k, v in pairs(options) do opts[k] = v end
	end

	local s = {
		player        = player,
		distanceFn    = distanceFn or function() return 3 end,
		opts          = opts,
		target        = nil,
		targetConns   = {},
		conns         = {},
		bars          = {},
		dead          = {},
		ignored       = {},
		radius        = 0,
		kills         = 0,
		lastAttack    = 0,
		lastScan      = 0,
		lastEquip     = 0,
		lastDebug     = 0,
		lastHealth    = 0,
		lastProgress  = 0,
		swings        = 0,
		blocked       = 0,
		outOfRange    = 0,
		toolActivated = 0,
		uisClicks     = 0,
		paused        = false,
		focused       = true,
	}
	state = s

	if type(mouse1click) ~= "function" and (opts.attackMode == "auto" or opts.attackMode == "native") and not opts.clickFn then
		warn("[Autofarm] mouse1click não existe neste ambiente: o clique automático pode não funcionar.")
	end

	if opts.captureController then
		pcall(function() VirtualUser:CaptureController() end)
	end

	-- Foco da janela: nunca clica se o Roblox não estiver em foco
	table.insert(s.conns, UserInputService.WindowFocused:Connect(function() s.focused = true end))
	table.insert(s.conns, UserInputService.WindowFocusReleased:Connect(function() s.focused = false end))

	-- Teclas de pausa e dump
	table.insert(s.conns, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if opts.debug and input.UserInputType == Enum.UserInputType.MouseButton1 then
			s.uisClicks += 1
		end
		if gameProcessed then return end
		if input.KeyCode == opts.pauseKey then
			s.paused = not s.paused
			print("[Autofarm]", s.paused and "PAUSADO (aperte RightControl de novo para retomar)" or "RETOMADO")
		elseif input.KeyCode == opts.dumpKey then
			dumpNearest(s)
		end
	end))

	log(s, "ligado | attackMode =", opts.attackMode, "| mouse1click disponível =", type(mouse1click) == "function")

	RunService:BindToRenderStep(MOVE_STEP, Enum.RenderPriority.Camera.Value - 1, follow)
	RunService:BindToRenderStep(AIM_STEP, Enum.RenderPriority.Camera.Value + 1, aim)
	s.attackConn = RunService.Heartbeat:Connect(attack)
end

function Autofarm.disable()
	if not state then return end

	pcall(function() RunService:UnbindFromRenderStep(MOVE_STEP) end)
	pcall(function() RunService:UnbindFromRenderStep(AIM_STEP) end)
	if state.attackConn then state.attackConn:Disconnect() end
	if state.toolConn then state.toolConn:Disconnect() end
	for _, c in ipairs(state.conns) do c:Disconnect() end
	clearTargetConns(state)

	local char = state.player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum and state.prevAutoRotate ~= nil then
		hum.AutoRotate = state.prevAutoRotate
	end

	state = nil
end

function Autofarm.getKills()
	return state and state.kills or 0
end

return Autofarm
