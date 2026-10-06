-- modules/autofarm.lua
-- Segue o NPC mais próximo, mantém o personagem MIRANDO nele (mesmo com Trava Shift),
-- ataca sozinho e detecta quando o NPC morre para pegar o próximo.
--
-- Uso:
--   Autofarm.enable(player, distanceFn)            -- distanceFn() = folga em studs entre os corpos
--   Autofarm.enable(player, distanceFn, { ... })   -- opções (opcional)
--   Autofarm.disable()
--   Autofarm.getKills()
--
-- Diagnóstico: Autofarm.enable(player, distanceFn, { debug = true })
-- e olhe as linhas [Autofarm] no Output / Console (F9).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

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
	isDeadFn          = nil,     -- função(npc) -> true se o NPC está morto (jogos com vida própria)
	onKill            = nil,     -- função(npc, totalMortes) chamada quando o alvo morre
	captureController = false,   -- chama VirtualUser:CaptureController() ao ligar
	debug             = false,   -- imprime diagnóstico no Output
	smoothing         = 20,      -- maior = segue mais rápido; menor = mais suave
	retargetEvery     = 0.5,     -- segundos entre buscas de alvo
	reachPadding      = 1.5,     -- tolerância extra do alcance (studs)
	heightOffset      = 0,       -- ajuste de altura em relação ao NPC
}

local state = nil

local function log(s, ...)
	if s and s.opts.debug then
		print("[Autofarm]", ...)
	end
end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isAlive(npc)
	if not npc or not npc.Parent or not npc:IsDescendantOf(workspace) then return false end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if not hum or getRoot(npc) == nil then return false end
	if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return false end
	if state and state.opts.isDeadFn then
		local ok, dead = pcall(state.opts.isDeadFn, npc)
		if ok and dead then return false end
	end
	return true
end

local function isNPC(model, myChar)
	if not model:IsA("Model") or model == myChar then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
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
-- Alvo e detecção de morte
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
	log(s, "novo alvo:", npc.Name, "| raio:", string.format("%.1f", s.radius), "|", describeNpc(npc))

	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		table.insert(s.targetConns, hum.Died:Connect(function()
			dropTarget(s, npc, true, "Humanoid.Died")
		end))
	end
	-- NPC removido do jogo sem morrer (despawn): só troca de alvo, sem contar kill
	table.insert(s.targetConns, npc.AncestryChanged:Connect(function(_, parent)
		if not parent then dropTarget(s, npc, false, "removido do jogo") end
	end))
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
		"alvo=%s vida=%s dist=%.1f alcance=%.1f mira_erro=%.0f° ferramenta=%s | por segundo: ataques=%d fora_alcance=%d Tool.Activated=%d M1_no_UIS=%d | kills=%d",
		npc.Name,
		hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "sem humanoid",
		toNpc.Magnitude, getReach(s), aimErr,
		tool and tool.Name or "nenhuma",
		s.swings, s.outOfRange, s.toolActivated, s.uisClicks, s.kills
	))
	s.swings, s.outOfRange, s.toolActivated, s.uisClicks = 0, 0, 0, 0
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

	-- Impede o personagem de girar sozinho
	if s.prevAutoRotate == nil then s.prevAutoRotate = hum.AutoRotate end
	hum.AutoRotate = false

	-- Garantia: se o alvo morreu/sumiu e o evento não chegou, solta agora
	if s.target and not isAlive(s.target) then
		local stillInGame = s.target:IsDescendantOf(workspace)
		dropTarget(s, s.target, stillInGame, "checagem de vida")
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
	if not s or not s.opts.lockAim or not s.target then return end
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
	if not s or not isAlive(s.target) then return end

	local now = os.clock()
	if now - s.lastAttack < s.opts.attackInterval then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- Só ataca se estiver dentro do alcance
	local nPos = getRoot(s.target).Position
	local flat = Vector3.new(hrp.Position.X - nPos.X, 0, hrp.Position.Z - nPos.Z).Magnitude
	if flat > getReach(s) then
		s.outOfRange += 1
		return
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

	-- Garante a mira no NPC no instante do golpe (depois da física, antes de enviar ao servidor)
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

	state = {
		player        = player,
		distanceFn    = distanceFn or function() return 3 end,
		opts          = opts,
		target        = nil,
		targetConns   = {},
		radius        = 0,
		kills         = 0,
		lastAttack    = 0,
		lastScan      = 0,
		lastEquip     = 0,
		lastDebug     = 0,
		swings        = 0,
		outOfRange    = 0,
		toolActivated = 0,
		uisClicks     = 0,
	}

	if opts.captureController then
		pcall(function() VirtualUser:CaptureController() end)
	end

	if opts.debug then
		-- Mostra se o clique simulado chega no UserInputService do jogo
		state.uisConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				state.uisClicks += 1
			end
		end)
		log(state, "ligado | attackMode =", opts.attackMode, "| mouse1click disponível =", type(mouse1click) == "function")
	end

	RunService:BindToRenderStep(MOVE_STEP, Enum.RenderPriority.Camera.Value - 1, follow)
	RunService:BindToRenderStep(AIM_STEP, Enum.RenderPriority.Camera.Value + 1, aim)
	state.attackConn = RunService.Heartbeat:Connect(attack)
end

function Autofarm.disable()
	if not state then return end

	pcall(function() RunService:UnbindFromRenderStep(MOVE_STEP) end)
	pcall(function() RunService:UnbindFromRenderStep(AIM_STEP) end)
	if state.attackConn then state.attackConn:Disconnect() end
	if state.uisConn then state.uisConn:Disconnect() end
	if state.toolConn then state.toolConn:Disconnect() end
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
