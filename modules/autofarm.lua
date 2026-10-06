-- modules/autofarm.lua  (v2: anda de verdade até o NPC, sem teleporte)
--
-- O que faz:
--   * Procura NPCs (todos, ou só os que você filtrar) e CAMINHA até a área deles usando
--     pathfinding (desvia de paredes, pula obstáculos). Nada de teletransporte.
--   * Perto do NPC: fica na distância certa da hitbox, mira nele (mesmo com Trava Shift)
--     e ataca sozinho.
--   * Desvia quando o NPC começa uma animação de ataque.
--   * Se a vida ficar baixa, recua; volta quando recuperar.
--   * Detecta a morte do NPC e vai para o próximo. Se não houver NPC (respawn), volta para a área.
--
-- Uso:
--   Autofarm.enable(player, distanceFn)
--   Autofarm.enable(player, distanceFn, {
--       targetNames = { "Scorpion" },                 -- só ataca NPCs com esse texto no nome
--       farmPoint   = Vector3.new(100, 5, -300),      -- área de farm (anda até lá se não houver NPC)
--       areaRadius  = 120,                            -- só NPCs a até 120 studs do farmPoint
--   })
--   Autofarm.disable()
--   Autofarm.getKills()
--
-- Teclas (enquanto ligado):
--   RightControl = pausa / retoma TUDO (andar + cliques). Use ao abrir menus.
--   F7           = imprime no Output os dados do NPC mais próximo (diagnóstico)
--
-- Diagnóstico: { debug = true } imprime linhas [Autofarm] no Output / Console (F9).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local PathfindingService = game:GetService("PathfindingService")

local Autofarm = {}

local AIM_STEP  = "AutofarmAim"
local MY_RADIUS = 1.5 -- raio aproximado do seu personagem (studs)

local DEFAULTS = {
	-- Alvos e área
	targetNames       = nil,     -- { "Scorpion" } só NPCs cujo nome contenha algum desses textos
	npcFilter         = nil,     -- função(npc) -> true/false (filtro extra)
	farmPoint         = nil,     -- Vector3 | BasePart | função -> Vector3 : área de farm
	areaRadius        = 120,     -- (com farmPoint) só considera NPCs a até X studs dele
	searchRadius      = 500,     -- só considera NPCs a até X studs de você

	-- Movimento (anda de verdade)
	engageDistance    = 14,      -- studs do corpo do NPC em que passa de "viajar" para "combate"
	pathRecompute     = 1.5,     -- segundos entre recálculos do caminho
	waypointReach     = 3.5,     -- distância para considerar um waypoint alcançado
	behindNpc         = true,    -- tenta ficar nas costas do NPC
	lockAim           = true,    -- personagem sempre virado para o NPC em combate (vence a Trava Shift)

	-- Defesa
	dodgeOnAttack     = true,    -- desvia quando o NPC começa uma animação de ataque
	dodgeBack         = 7,       -- quantos studs recua ao desviar
	dodgeMaxTime      = 1.2,     -- tempo máximo de cada desvio (s)
	isAttackAnimFn    = nil,     -- função(track) -> true se a animação do NPC é um ataque
	attackWhileDodging = false,  -- ataca enquanto desvia?
	minHealthPct      = 0.3,     -- recua quando a vida ficar abaixo disso (0 desliga)
	resumeHealthPct   = 0.7,     -- volta ao combate acima disso
	retreatDistance   = 35,      -- até onde recua (studs)
	retreatMaxTime    = 15,      -- tempo máximo recuado (s)
	onLowHealth       = nil,     -- função(pctVida): chamada ao recuar (ex.: usar cura)

	-- Ataque
	attackInterval    = 0.15,    -- segundos entre ataques
	attackMode        = "auto",  -- "auto" | "native" | "click" | "hold" | "tool"
	clickFn           = nil,     -- função própria de ataque (substitui attackMode)
	requireRange      = true,    -- só ataca dentro do alcance estimado
	reachPadding      = 1.5,     -- tolerância extra do alcance (studs)
	safeClick         = true,    -- NÃO clica com menu aberto / mouse sobre botão / janela sem foco

	-- Morte / alvo
	isDeadFn          = nil,     -- função(npc) -> true se o NPC está morto
	onKill            = nil,     -- função(npc, totalMortes)
	useBarDetection   = true,    -- detecta morte pela barra de vida do NPC chegando a zero
	stuckTimeout      = 8,       -- s em combate sem o NPC perder vida => ignora e troca de alvo (0 = desliga)
	retargetEvery     = 0.5,     -- segundos entre buscas de alvo

	-- Geral
	pauseKey          = Enum.KeyCode.RightControl,
	dumpKey           = Enum.KeyCode.F7,
	captureController = false,
	debug             = false,
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

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

----------------------------------------------------------------
-- Detecção de morte (vários sinais, porque cada jogo faz de um jeito)
----------------------------------------------------------------
local DEAD_FLAGS = { dead = true, isdead = true, died = true, dying = true, isdying = true }
local HP_NAMES = {
	health = true, hp = true, currenthealth = true, currenthp = true, curhealth = true, curhp = true,
}

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

----------------------------------------------------------------
-- Área de farm e escolha de alvo
----------------------------------------------------------------
local function getFarmPoint(s)
	local fp = s.opts.farmPoint
	if typeof(fp) == "function" then
		local ok, v = pcall(fp)
		fp = ok and v or nil
	end
	if typeof(fp) == "Vector3" then return fp end
	if typeof(fp) == "CFrame" then return fp.Position end
	if typeof(fp) == "Instance" and fp:IsA("BasePart") then return fp.Position end
	return nil
end

local function passesFilters(s, npc)
	local names = s.opts.targetNames
	if names and #names > 0 then
		local lname = string.lower(npc.Name)
		local match = false
		for _, n in ipairs(names) do
			if string.find(lname, string.lower(n), 1, true) then match = true break end
		end
		if not match then return false end
	end
	if s.opts.npcFilter then
		local ok, res = pcall(s.opts.npcFilter, npc)
		if not ok or not res then return false end
	end
	return true
end

local function pickTarget(s, hrp, myChar)
	local area = getFarmPoint(s)
	local nearest, nearestDist = nil, math.huge

	for _, obj in ipairs(workspace:GetDescendants()) do
		if isNPC(obj, myChar) and passesFilters(s, obj) then
			local root = getRoot(obj)
			local d = (hrp.Position - root.Position).Magnitude
			if d <= s.opts.searchRadius and d < nearestDist then
				if not area or (root.Position - area).Magnitude <= s.opts.areaRadius then
					nearest, nearestDist = obj, d
				end
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
			if obj.Active and obj.BackgroundTransparency < 0.95 then
				return true
			end
		end
	end
	return false
end

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

local function dropTarget(s, npc, killed, reason)
	if s.target ~= npc then return end
	clearTargetConns(s)
	s.target = nil
	s.bars = {}
	s.path = nil
	s.waypoints = nil
	s.lastScan = 0

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
	s.prevPlaying = {}
	s.dodgeUntil = 0
	s.path = nil
	s.waypoints = nil
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
	local animator = npc:FindFirstChildWhichIsA("Animator", true)
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			print("   anim tocando:", t.Name, "prioridade=", t.Priority.Name, "loop=", t.Looped, "duração=", t.Length)
		end
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
-- Diagnóstico (debug = true)
----------------------------------------------------------------
local function debugTick(s, hrp, mode)
	if not s.opts.debug then return end
	local now = os.clock()
	if now - s.lastDebug < 1 then return end
	s.lastDebug = now

	local npc = s.target
	if not npc then
		log(s, "modo=" .. mode, "| sem alvo | kills:", s.kills)
		return
	end

	local nHrp = getRoot(npc)
	local dist = nHrp and flatDist(hrp.Position, nHrp.Position) or -1
	local hum = npc:FindFirstChildOfClass("Humanoid")
	log(s, string.format(
		"modo=%s alvo=%s vida=%s dist=%.1f alcance=%.1f | por segundo: ataques=%d bloqueados=%d | kills=%d%s",
		mode, npc.Name,
		hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "sem humanoid",
		dist, getReach(s), s.swings, s.blocked, s.kills,
		s.paused and " | PAUSADO" or ""
	))
	s.swings, s.blocked = 0, 0
end

----------------------------------------------------------------
-- Navegação (anda de verdade, com pathfinding)
----------------------------------------------------------------
local function followPath(s, hrp, hum, goal)
	local now = os.clock()
	local needNew = (not s.path)
		or (now - s.pathTime > s.opts.pathRecompute)
		or (s.pathGoal and (s.pathGoal - goal).Magnitude > 8)

	if needNew then
		s.path = true
		s.pathTime = now
		s.pathGoal = goal

		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
		})
		local ok = pcall(function() path:ComputeAsync(hrp.Position, goal) end)
		if ok and path.Status == Enum.PathStatus.Success then
			s.waypoints = path:GetWaypoints()
			s.wpIndex = 2 -- o 1 é onde você já está
		else
			s.waypoints = nil
		end
	end

	local wps = s.waypoints
	if not wps then
		hum:MoveTo(goal) -- sem caminho calculado: tenta em linha reta
		return
	end

	local wp = wps[s.wpIndex]
	while wp and flatDist(hrp.Position, wp.Position) < s.opts.waypointReach do
		s.wpIndex += 1
		wp = wps[s.wpIndex]
	end

	if not wp then
		hum:MoveTo(goal)
		return
	end
	if wp.Action == Enum.PathWaypointAction.Jump then
		hum.Jump = true
	end
	hum:MoveTo(wp.Position)
end

-- Se parado por >1,5s enquanto deveria andar: pula e recalcula o caminho
local function antiStuck(s, hrp, hum)
	local now = os.clock()
	if now - s.stuckCheck < 1.5 then return end
	if (hrp.Position - s.stuckPos).Magnitude < 1 then
		hum.Jump = true
		s.path = nil
	end
	s.stuckPos = hrp.Position
	s.stuckCheck = now
end

local ATTACK_PRIORITIES = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}

-- Detecta o início de uma animação de ataque do NPC e agenda um desvio
local function pollAttackAnim(s)
	local npc = s.target
	if not npc then return end
	local animator = npc:FindFirstChildWhichIsA("Animator", true)
	if not animator then return end

	local playing = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		playing[track] = true
		if not s.prevPlaying[track] then
			local isAttack
			if s.opts.isAttackAnimFn then
				local ok, r = pcall(s.opts.isAttackAnimFn, track)
				isAttack = ok and r == true
			else
				isAttack = (not track.Looped) and ATTACK_PRIORITIES[track.Priority] == true
			end

			log(s, "anim do NPC:", track.Name, "| prioridade:", track.Priority.Name,
				"| loop:", track.Looped, "| duração:", string.format("%.2f", track.Length),
				"| ataque?", isAttack)

			if isAttack and s.opts.dodgeOnAttack then
				local len = track.Length > 0 and track.Length or 0.8
				s.dodgeUntil = os.clock() + math.min(len, s.opts.dodgeMaxTime)
				s.dodgeSide = -s.dodgeSide
			end
		end
	end
	s.prevPlaying = playing
end

local function dodgePosition(s, hrp, npcPos)
	local away = Vector3.new(hrp.Position.X - npcPos.X, 0, hrp.Position.Z - npcPos.Z)
	if away.Magnitude < 0.01 then
		away = -hrp.CFrame.LookVector
		away = Vector3.new(away.X, 0, away.Z)
	end
	away = away.Unit
	local rotated = CFrame.Angles(0, math.rad(35) * s.dodgeSide, 0):VectorToWorldSpace(away)
	local dist = s.radius + MY_RADIUS + s.distanceFn() + s.opts.dodgeBack
	return Vector3.new(npcPos.X, hrp.Position.Y, npcPos.Z) + rotated * dist
end

local function updateTargetState(s, now)
	if s.target and not s.target:IsDescendantOf(workspace) then
		dropTarget(s, s.target, false, "removido do jogo")
	end

	if s.target then
		local reason = deathReason(s, s.target)
		if reason then
			local npc = s.target
			s.dead[npc] = now + 60
			dropTarget(s, npc, true, reason)
		end
	end

	-- Em combate e o NPC não perde vida há muito tempo: ignora por 15s e troca
	if s.target and s.opts.stuckTimeout > 0 then
		local th = s.target:FindFirstChildOfClass("Humanoid")
		if th then
			if th.Health < s.lastHealth - 0.01 or not s.engaged then s.lastProgress = now end
			s.lastHealth = th.Health
			if now - s.lastProgress > s.opts.stuckTimeout then
				s.ignored[s.target] = now + 15
				dropTarget(s, s.target, false, "sem perder vida há " .. s.opts.stuckTimeout .. "s (ignorado por 15s)")
			end
		end
	end
end

local function navStep(s)
	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		s.engaged = false
		return
	end

	-- Pausado: devolve o controle ao jogador
	if s.paused then
		if s.prevAutoRotate ~= nil then
			hum.AutoRotate = s.prevAutoRotate
			s.prevAutoRotate = nil
			hum:MoveTo(hrp.Position)
		end
		s.engaged = false
		return
	end
	if s.prevAutoRotate == nil then s.prevAutoRotate = hum.AutoRotate end

	local now = os.clock()

	-- Vida baixa: recua e espera recuperar
	if s.opts.minHealthPct > 0 and hum.MaxHealth > 0 then
		local pct = hum.Health / hum.MaxHealth
		if s.retreating then
			if pct >= s.opts.resumeHealthPct or now - s.retreatStart > s.opts.retreatMaxTime then
				s.retreating = false
				log(s, "voltando ao combate | vida:", string.format("%.0f%%", pct * 100))
			end
		elseif pct <= s.opts.minHealthPct then
			s.retreating = true
			s.retreatStart = now
			log(s, "vida baixa, recuando |", string.format("%.0f%%", pct * 100))
			if s.opts.onLowHealth then task.spawn(s.opts.onLowHealth, pct) end
		end
	end

	updateTargetState(s, now)

	-- Sem alvo: procura
	if not s.target and now - s.lastScan >= s.opts.retargetEvery then
		s.lastScan = now
		local found = pickTarget(s, hrp, char)
		if found then setTarget(s, found) end
	end

	-- Recuo
	if s.retreating then
		s.engaged = false
		hum.AutoRotate = true
		local root = s.target and getRoot(s.target)
		if root then
			local away = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
			if away.Magnitude < 0.01 then away = Vector3.new(0, 0, 1) end
			if away.Magnitude < s.opts.retreatDistance then
				hum:MoveTo(hrp.Position + away.Unit * 10)
			end
		end
		debugTick(s, hrp, "recuo")
		return
	end

	-- Sem alvo: anda até a área de farm (ou última área onde havia NPC)
	if not s.target then
		s.engaged = false
		hum.AutoRotate = true
		local area = getFarmPoint(s) or s.lastAreaPoint
		if area and flatDist(hrp.Position, area) > 10 then
			followPath(s, hrp, hum, area)
			antiStuck(s, hrp, hum)
		end
		debugTick(s, hrp, "indo para a área")
		return
	end

	local npc = s.target
	local nHrp = getRoot(npc)
	if not nHrp then return end
	local npcPos = nHrp.Position
	s.lastAreaPoint = npcPos

	pollAttackAnim(s)

	local offset = s.radius + MY_RADIUS + s.distanceFn()
	local flat = flatDist(hrp.Position, npcPos)

	-- Longe: viaja andando até perto do NPC
	if flat > offset + s.opts.engageDistance then
		s.engaged = false
		hum.AutoRotate = true
		followPath(s, hrp, hum, npcPos)
		antiStuck(s, hrp, hum)
		debugTick(s, hrp, "viajando")
		return
	end

	-- Perto: combate
	s.engaged = true
	hum.AutoRotate = false
	s.path = nil

	local goal
	if s.opts.dodgeOnAttack and now < s.dodgeUntil then
		goal = dodgePosition(s, hrp, npcPos)
	else
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
		goal = Vector3.new(npcPos.X, hrp.Position.Y, npcPos.Z) + dir.Unit * offset
	end
	hum:MoveTo(goal)

	debugTick(s, hrp, (s.opts.dodgeOnAttack and now < s.dodgeUntil) and "desviando" or "combate")
end

local function navLoop(s)
	while state == s do
		local ok, err = pcall(navStep, s)
		if not ok then
			local t = os.clock()
			if t - s.lastErr > 5 then
				s.lastErr = t
				warn("[Autofarm] erro na navegação:", err)
			end
		end
		task.wait(0.1)
	end
end

-- Roda DEPOIS da câmera: a Trava Shift vira o personagem para onde a câmera olha,
-- então reaplicamos a mira no NPC logo depois. A câmera não é alterada.
local function aim()
	local s = state
	if not s or s.paused or not s.opts.lockAim or not s.engaged or s.retreating or not s.target then return end
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
	if not s or s.paused or s.retreating or not s.engaged or not isAlive(s.target) then return end

	local now = os.clock()
	if now - s.lastAttack < s.opts.attackInterval then return end

	-- Não ataca enquanto desvia
	if s.opts.dodgeOnAttack and not s.opts.attackWhileDodging and now < s.dodgeUntil then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	local nPos = getRoot(s.target).Position
	if s.opts.requireRange and flatDist(hrp.Position, nPos) > getReach(s) then return end

	-- Sem ferramenta na mão: tenta equipar (no máximo 1x por segundo)
	if not char:FindFirstChildOfClass("Tool") and now - s.lastEquip > 1 then
		local backpack = s.player:FindFirstChildOfClass("Backpack")
		local first = backpack and backpack:FindFirstChildOfClass("Tool")
		if first then
			s.lastEquip = now
			hum:EquipTool(first)
			return
		end
	end

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
		prevPlaying   = {},
		radius        = 0,
		kills         = 0,
		lastAttack    = 0,
		lastScan      = 0,
		lastEquip     = 0,
		lastDebug     = 0,
		lastErr       = 0,
		lastHealth    = 0,
		lastProgress  = 0,
		swings        = 0,
		blocked       = 0,
		dodgeUntil    = 0,
		dodgeSide     = 1,
		retreating    = false,
		retreatStart  = 0,
		engaged       = false,
		paused        = false,
		focused       = true,
		path          = nil,
		pathTime      = 0,
		stuckCheck    = 0,
		stuckPos      = Vector3.zero,
		lastAreaPoint = nil,
	}
	state = s

	if type(mouse1click) ~= "function" and (opts.attackMode == "auto" or opts.attackMode == "native") and not opts.clickFn then
		warn("[Autofarm] mouse1click não existe neste ambiente: o clique automático pode não funcionar.")
	end

	if opts.captureController then
		pcall(function() VirtualUser:CaptureController() end)
	end

	table.insert(s.conns, UserInputService.WindowFocused:Connect(function() s.focused = true end))
	table.insert(s.conns, UserInputService.WindowFocusReleased:Connect(function() s.focused = false end))

	table.insert(s.conns, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == opts.pauseKey then
			s.paused = not s.paused
			print("[Autofarm]", s.paused and "PAUSADO (aperte RightControl de novo para retomar)" or "RETOMADO")
		elseif input.KeyCode == opts.dumpKey then
			dumpNearest(s)
		end
	end))

	log(s, "ligado | attackMode =", opts.attackMode, "| mouse1click disponível =", type(mouse1click) == "function")

	RunService:BindToRenderStep(AIM_STEP, Enum.RenderPriority.Camera.Value + 1, aim)
	s.attackConn = RunService.Heartbeat:Connect(attack)
	task.spawn(navLoop, s)
end

function Autofarm.disable()
	if not state then return end
	local s = state
	state = nil -- faz o loop de navegação terminar

	pcall(function() RunService:UnbindFromRenderStep(AIM_STEP) end)
	if s.attackConn then s.attackConn:Disconnect() end
	for _, c in ipairs(s.conns) do c:Disconnect() end
	clearTargetConns(s)

	local char = s.player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hum then
		if s.prevAutoRotate ~= nil then hum.AutoRotate = s.prevAutoRotate end
		if hrp then hum:MoveTo(hrp.Position) end
	end
end

function Autofarm.getKills()
	return state and state.kills or 0
end

return Autofarm
