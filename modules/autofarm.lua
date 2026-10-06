-- modules/autofarm.lua
-- Segue o NPC mais próximo, fica na distância certa da hitbox e ataca.
-- Uso (igual ao anterior):
--   Autofarm.enable(player, distanceFn)            -- distanceFn() = folga em studs entre os corpos
--   Autofarm.enable(player, distanceFn, { ... })   -- opções (opcional)
--   Autofarm.disable()

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Autofarm = {}

local STEP_NAME = "AutofarmFollow"
local MY_RADIUS = 1.5 -- raio aproximado do seu personagem (studs)

local DEFAULTS = {
	behindNpc      = true,  -- fica nas costas do NPC (ataques costumam sair pela frente)
	attackInterval = 0.15,  -- segundos entre ataques
	smoothing      = 20,    -- maior = segue mais rápido; menor = mais suave
	retargetEvery  = 0.5,   -- segundos entre buscas de novo alvo (quando não há alvo)
	reachPadding   = 1.5,   -- tolerância extra do alcance de ataque (studs)
	heightOffset   = 0,     -- ajuste de altura em relação ao NPC
}

local state = nil

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isAlive(npc)
	if not npc or not npc.Parent or not npc:IsDescendantOf(workspace) then return false end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and getRoot(npc) ~= nil
end

local function isNPC(model, myChar)
	if not model:IsA("Model") or model == myChar then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	return isAlive(model)
end

-- Raio horizontal real do NPC (usa a caixa que envolve o modelo inteiro)
local function getRadius(model)
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Z) / 2
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

----------------------------------------------------------------
-- Movimento (roda antes da câmera, em RenderStep, para não tremer)
----------------------------------------------------------------
local function follow(dt)
	local s = state
	if not s then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- Impede o personagem de girar sozinho (evita briga com a câmera)
	if s.prevAutoRotate == nil then s.prevAutoRotate = hum.AutoRotate end
	hum.AutoRotate = false

	-- Só procura alvo novo quando o atual morreu/sumiu (sem ficar trocando de alvo)
	if not isAlive(s.target) then
		s.target = nil
		local now = os.clock()
		if now - s.lastScan >= s.opts.retargetEvery then
			s.lastScan = now
			s.target = pickTarget(hrp, char)
			s.radius = s.target and getRadius(s.target) or 0
		end
	end

	local npc = s.target
	if not npc then return end
	local nHrp = getRoot(npc)

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

	-- Olha só na horizontal (sem inclinar o personagem, que bagunçava a câmera)
	local lookAt = Vector3.new(npcPos.X, goalPos.Y, npcPos.Z)
	local goal = CFrame.lookAt(goalPos, lookAt)

	-- Movimento suave (independe do FPS)
	local alpha = 1 - math.exp(-s.opts.smoothing * dt)
	hrp.CFrame = hrp.CFrame:Lerp(goal, alpha)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

----------------------------------------------------------------
-- Ataque
----------------------------------------------------------------
local function attack()
	local s = state
	if not s or not isAlive(s.target) then return end

	local now = os.clock()
	if now - s.lastAttack < s.opts.attackInterval then return end

	local char = s.player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- Só ataca se estiver dentro do alcance (evita bater no ar)
	local nPos = getRoot(s.target).Position
	local flat = Vector3.new(hrp.Position.X - nPos.X, 0, hrp.Position.Z - nPos.Z).Magnitude
	local reach = s.radius + MY_RADIUS + s.distanceFn() + s.opts.reachPadding
	if flat > reach then return end

	-- Equipa uma ferramenta automaticamente se não houver nenhuma na mão
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		local backpack = s.player:FindFirstChildOfClass("Backpack")
		local first = backpack and backpack:FindFirstChildOfClass("Tool")
		if first then hum:EquipTool(first) end
		return
	end

	s.lastAttack = now
	pcall(function() tool:Activate() end)

	local remote = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("Fire")
	if remote and remote:IsA("RemoteEvent") then
		pcall(function() remote:FireServer() end)
	end
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
		player     = player,
		distanceFn = distanceFn or function() return 3 end,
		opts       = opts,
		target     = nil,
		radius     = 0,
		lastAttack = 0,
		lastScan   = 0,
	}

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value - 1, follow)
	state.attackConn = RunService.Heartbeat:Connect(attack)
end

function Autofarm.disable()
	if not state then return end

	pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
	if state.attackConn then state.attackConn:Disconnect() end

	local char = state.player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum and state.prevAutoRotate ~= nil then
		hum.AutoRotate = state.prevAutoRotate
	end

	state = nil
end

return Autofarm
