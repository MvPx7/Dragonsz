local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Autofarm = {}

-- ===== Ajustes =====
local ATTACK_INTERVAL = 0.12 -- segundos entre cada ataque/clique
local SEARCH_INTERVAL = 0.3  -- segundos entre buscas de alvo quando não há nenhum
local ORBIT_SPEED     = 2.5  -- velocidade da volta em radianos/s (2.5 = uma volta a cada ~2,5s)
local FLIP_MIN        = 1.5  -- o sentido da volta se inverte sozinho a cada FLIP_MIN..FLIP_MAX segundos,
local FLIP_MAX        = 3    -- para o NPC não conseguir prever o caminho
local ATTACK_MODE     = "auto" -- "auto": usa o evento da ferramenta se existir, senão clica (M1)
                               -- "click": sempre simula o clique M1

-- Serviço usado para simular o clique (existe em executores; se não existir, tenta mouse1click)
local okVim, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
if not okVim then VIM = nil end

local conns = {}   -- todas as conexões, para desligar tudo de uma vez
local npcs = {}    -- [model] = humanoid  (lista em cache, mantida por eventos)
local target = nil
local orbitTarget = nil
local angle, orbitDir, flipLeft = 0, 1, 2
local attackTimer, searchTimer = 0, 0

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function register(hum)
	local model = hum.Parent
	if not model or not model:IsA("Model") then return end
	if Players:GetPlayerFromCharacter(model) then return end
	npcs[model] = hum
end

local function unregister(model)
	if not model then return end
	npcs[model] = nil
	if target == model then target = nil end
end

-- Procura só dentro da lista em cache (poucos itens), nunca no workspace inteiro.
local function pickTarget(hrp)
	local best, bestDist = nil, math.huge
	for model, hum in pairs(npcs) do
		if not model:IsDescendantOf(workspace) or Players:GetPlayerFromCharacter(model) then
			npcs[model] = nil
		elseif hum.Health > 0 then
			local r = rootOf(model)
			if r then
				local d = (hrp.Position - r.Position).Magnitude
				if d < bestDist then
					best, bestDist = model, d
				end
			end
		end
	end
	return best
end

-- Simula o clique do botão esquerdo no centro da tela (o "M1")
local function clickM1()
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize or Vector2.new(800, 600)
	local x, y = size.X / 2, size.Y / 2
	if VIM then
		VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
		VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
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

-- Começa a orbitar a partir de onde o jogador já está (sem pulo brusco)
local function startOrbit(hrp, nHrp)
	local rel = hrp.Position - nHrp.Position
	angle = math.atan2(rel.Z, rel.X)
	orbitDir = (math.random() < 0.5) and 1 or -1
	flipLeft = FLIP_MIN + math.random() * (FLIP_MAX - FLIP_MIN)
end

function Autofarm.enable(player, distanceFn)
	Autofarm.disable() -- garante que nunca existam duas conexões ao mesmo tempo

	-- Varredura única ao ligar; depois a lista é atualizada por eventos.
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") then register(obj) end
	end
	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("Humanoid") then register(obj) end
	end)
	conns[#conns + 1] = workspace.DescendantRemoving:Connect(function(obj)
		if obj:IsA("Humanoid") then unregister(obj.Parent) end
	end)

	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Mantém o mesmo alvo até ele morrer ou sumir
		if target then
			local hum = npcs[target]
			if not hum or hum.Health <= 0 or not rootOf(target) then target = nil end
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

		-- Gira em volta do NPC, na distância configurada, sempre olhando para ele
		angle = angle + ORBIT_SPEED * orbitDir * dt
		flipLeft = flipLeft - dt
		if flipLeft <= 0 then
			orbitDir = -orbitDir
			flipLeft = FLIP_MIN + math.random() * (FLIP_MAX - FLIP_MIN)
		end
		local radius = distanceFn()
		local c = nHrp.Position
		local pos = Vector3.new(c.X + math.cos(angle) * radius, c.Y, c.Z + math.sin(angle) * radius)
		hrp.CFrame = CFrame.new(pos, Vector3.new(c.X, pos.Y, c.Z))
		hrp.AssemblyLinearVelocity = Vector3.zero -- evita a física "brigar" com o teleporte

		-- Ataca com intervalo
		attackTimer = attackTimer + dt
		if attackTimer >= ATTACK_INTERVAL then
			attackTimer = 0
			attack(char)
		end
	end)
end

function Autofarm.disable()
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	npcs = {}
	target, orbitTarget = nil, nil
	attackTimer, searchTimer = 0, 0
end

return Autofarm
