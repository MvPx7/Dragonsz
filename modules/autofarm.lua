local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Autofarm = {}

-- ===== Ajustes =====
local ATTACK_INTERVAL = 0.12   -- segundos entre cada ataque/clique
local SEARCH_INTERVAL = 0.3    -- segundos entre buscas de alvo quando não há nenhum
local ORBIT_SPEED     = 2.5    -- velocidade da volta em radianos/s
local FLIP_MIN        = 1.5    -- o sentido da volta inverte sozinho a cada FLIP_MIN..FLIP_MAX segundos
local FLIP_MAX        = 3
local ATTACK_MODE     = "auto" -- "auto": usa o evento da ferramenta se existir, senão clica (M1) | "click": sempre clica

-- Esquiva: quando o NPC começa uma animação de ataque, o jogador recua para fora do alcance
local DODGE_ENABLED = true
local SAFE_RADIUS   = 22       -- distância (studs) para onde recua ao detectar um ataque
local DODGE_HOLD    = 0.7      -- segundos que fica longe depois de detectar o ataque
local DODGE_POLL    = 0.05     -- de quanto em quanto tempo verifica se o NPC está atacando

-- Mira fixa: a câmera fica travada olhando para o NPC (o mouse/câmera não "balançam" mais)
local LOCK_CAMERA = true
local CAM_BACK    = 7          -- distância da câmera atrás do jogador
local CAM_HEIGHT  = 5          -- altura da câmera

local DEAD_IGNORE = 4          -- segundos que um NPC morto é ignorado (evita bater no corpo)
local DEBUG       = false      -- true = mostra no console as animações do NPC (ajuda a calibrar a esquiva)

local okVim, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
if not okVim then VIM = nil end

-- Prioridades de animação que costumam ser ataques (idle/andar usam prioridades mais baixas)
local ACTION = {}
for _, name in ipairs({ "Action", "Action2", "Action3", "Action4" }) do
	local ok, p = pcall(function() return Enum.AnimationPriority[name] end)
	if ok and p then ACTION[p] = true end
end
local IGNORE_NAMES = { "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "emote", "dance" }

local active = false
local conns = {}       -- todas as conexões, para desligar tudo de uma vez
local npcs = {}        -- [model] = humanoid (lista em cache, mantida por eventos)
local died = {}        -- [model] = conexão do evento Died
local ignoredUntil = {} -- [model] = os.clock() até quando ignorar
local seenAnims = {}
local target, orbitTarget = nil, nil
local angle, orbitDir, flipLeft = 0, 1, 2
local attackTimer, searchTimer, pollTimer, dodgeUntil = 0, 0, 0, 0
local onStopCb = nil
local camLocked, savedCamType = false, nil
local CAM_STEP = "DragonszFarmCam"

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function usable(model, hum)
	return hum.Health > 0 and (ignoredUntil[model] or 0) <= os.clock()
end

local function markDead(model)
	ignoredUntil[model] = os.clock() + DEAD_IGNORE
	if target == model then target = nil end
end

local function register(hum)
	local model = hum.Parent
	if not model or not model:IsA("Model") then return end
	if Players:GetPlayerFromCharacter(model) then return end
	npcs[model] = hum
	if died[model] then died[model]:Disconnect() end
	died[model] = hum.Died:Connect(function() markDead(model) end) -- reage na hora, sem esperar o próximo frame
end

local function unregister(model)
	if not model then return end
	npcs[model] = nil
	ignoredUntil[model] = nil
	if died[model] then died[model]:Disconnect(); died[model] = nil end
	if target == model then target = nil end
end

-- Procura só dentro da lista em cache (poucos itens), nunca no workspace inteiro.
local function pickTarget(hrp)
	local best, bestDist = nil, math.huge
	for model, hum in pairs(npcs) do
		if not model:IsDescendantOf(workspace) or Players:GetPlayerFromCharacter(model) then
			unregister(model)
		elseif usable(model, hum) then
			local r = rootOf(model)
			if r then
				local d = (hrp.Position - r.Position).Magnitude
				if d < bestDist then best, bestDist = model, d end
			end
		end
	end
	return best
end

-- O NPC está tocando uma animação de ataque?
local function isAttacking(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return false end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if DEBUG then
			local key = track.Name .. "|" .. tostring(track.Priority)
			if not seenAnims[key] then
				seenAnims[key] = true
				print(string.format("[Dragonsz DEBUG] animação do NPC: '%s'  prioridade=%s  loop=%s",
					track.Name, tostring(track.Priority), tostring(track.Looped)))
			end
		end
		if track.IsPlaying and not track.Looped and track.WeightCurrent > 0.1 and ACTION[track.Priority] then
			local n = track.Name:lower()
			local skip = false
			for _, w in ipairs(IGNORE_NAMES) do
				if n:find(w, 1, true) then skip = true; break end
			end
			if not skip then return true end
		end
	end
	return false
end

-- Clique M1 no lugar onde o mouse já está (o cursor não se mexe)
local function clickM1()
	local pos = UIS:GetMouseLocation()
	if VIM then
		VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
		VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
	elseif mouse1click then
		mouse1click()
	end
end

local function attack(char)
	if ATTACK_MODE == "auto" then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool and tool:FindFirstChild("Handle") then
			local remote = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("Fire")
			if remote then
				pcall(function() remote:FireServer() end)
				return
			end
		end
	end
	pcall(clickM1)
end

local function startOrbit(hrp, nHrp)
	local rel = hrp.Position - nHrp.Position
	angle = math.atan2(rel.Z, rel.X)
	orbitDir = (math.random() < 0.5) and 1 or -1
	flipLeft = FLIP_MIN + math.random() * (FLIP_MAX - FLIP_MIN)
end

local function lockCamera(player)
	if not LOCK_CAMERA or camLocked then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	savedCamType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
	camLocked = true
	RunService:BindToRenderStep(CAM_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		local c = workspace.CurrentCamera
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local nHrp = target and rootOf(target)
		if not c or not hrp or not nHrp then return end
		local away = hrp.Position - nHrp.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.1 then away = Vector3.new(0, 0, 1) end
		local camPos = hrp.Position + away.Unit * CAM_BACK + Vector3.new(0, CAM_HEIGHT, 0)
		c.CFrame = CFrame.new(camPos, nHrp.Position)
	end)
end

local function unlockCamera()
	if not camLocked then return end
	camLocked = false
	pcall(function() RunService:UnbindFromRenderStep(CAM_STEP) end)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = savedCamType or Enum.CameraType.Custom
		local lp = Players.LocalPlayer
		local hum = lp and lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
	end
end

-- Desliga sozinho (ex.: o jogador morreu) e avisa a UI, se ela registrou um callback
local function stop(reason)
	if not active then return end
	local cb = Autofarm.onStopped or onStopCb
	Autofarm.disable()
	print("[Dragonsz Autofarm] desligado: " .. tostring(reason))
	if cb then pcall(cb, reason) end
end

-- onStop (opcional): função chamada quando o autofarm desliga sozinho, para a UI desmarcar o botão.
function Autofarm.enable(player, distanceFn, onStop)
	Autofarm.disable() -- garante que nunca existam duas conexões ao mesmo tempo
	active = true
	onStopCb = onStop

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") then register(obj) end
	end
	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("Humanoid") then register(obj) end
	end)
	conns[#conns + 1] = workspace.DescendantRemoving:Connect(function(obj)
		if obj:IsA("Humanoid") then unregister(obj.Parent) end
	end)

	-- Se o jogador morrer (ou o personagem for removido), desliga
	conns[#conns + 1] = player.CharacterRemoving:Connect(function() stop("o personagem foi removido") end)
	local myChar = player.Character
	local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
	if myHum then
		conns[#conns + 1] = myHum.Died:Connect(function() stop("você morreu") end)
	end

	lockCamera(player)

	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then stop("você morreu"); return end
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Mantém o mesmo alvo até ele morrer ou sumir
		if target then
			local nh = npcs[target]
			if not nh or not usable(target, nh) or not rootOf(target) then target = nil end
		end
		if not target then
			searchTimer = searchTimer + dt
			if searchTimer < SEARCH_INTERVAL then return end
			searchTimer = 0
			target = pickTarget(hrp)
			if not target then return end
		end

		local nHrp = rootOf(target)
		if orbitTarget ~= target then
			orbitTarget = target
			startOrbit(hrp, nHrp)
		end

		-- Esquiva: ataque do NPC detectado -> recua para fora do alcance por um instante
		if DODGE_ENABLED then
			pollTimer = pollTimer + dt
			if pollTimer >= DODGE_POLL then
				pollTimer = 0
				if isAttacking(npcs[target]) then dodgeUntil = os.clock() + DODGE_HOLD end
			end
		end
		local dodging = os.clock() < dodgeUntil

		-- Gira em volta do NPC, sempre olhando para ele
		angle = angle + ORBIT_SPEED * orbitDir * dt
		flipLeft = flipLeft - dt
		if flipLeft <= 0 then
			orbitDir = -orbitDir
			flipLeft = FLIP_MIN + math.random() * (FLIP_MAX - FLIP_MIN)
		end
		local radius = distanceFn()
		if dodging then radius = math.max(radius, SAFE_RADIUS) end
		local c = nHrp.Position
		local pos = Vector3.new(c.X + math.cos(angle) * radius, c.Y, c.Z + math.sin(angle) * radius)
		hrp.CFrame = CFrame.new(pos, Vector3.new(c.X, pos.Y, c.Z))
		hrp.AssemblyLinearVelocity = Vector3.zero

		-- Ataca (nunca durante a esquiva, nunca em NPC morto)
		attackTimer = attackTimer + dt
		if attackTimer >= ATTACK_INTERVAL then
			attackTimer = 0
			local nh = npcs[target]
			if not dodging and nh and usable(target, nh) then attack(char) end
		end
	end)
end

function Autofarm.disable()
	active = false
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	for _, c in pairs(died) do c:Disconnect() end
	died, npcs, ignoredUntil = {}, {}, {}
	target, orbitTarget, onStopCb = nil, nil, nil
	attackTimer, searchTimer, pollTimer, dodgeUntil = 0, 0, 0, 0
	unlockCamera()
end

return Autofarm
