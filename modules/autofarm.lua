local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Autofarm = {}

-- Ajustes (valores menores = mais rápido, mas mais pesado para o jogo)
local ATTACK_INTERVAL = 0.12 -- segundos entre cada ataque (antes: 1 ataque por frame, ~60 por segundo)
local SEARCH_INTERVAL = 0.3  -- segundos entre buscas de alvo quando não há nenhum

local conns = {}   -- todas as conexões, para desligar tudo de uma vez
local npcs = {}    -- [model] = humanoid  (lista em cache, mantida por eventos)
local target = nil
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

		-- Gruda no NPC à distância configurada
		local nHrp = rootOf(target)
		local dir = hrp.Position - nHrp.Position
		if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
		local targetPos = nHrp.Position + dir.Unit * distanceFn()
		hrp.CFrame = CFrame.new(targetPos, nHrp.Position)
		hrp.AssemblyLinearVelocity = Vector3.zero -- evita a física "brigar" com o teleporte

		-- Ataca com intervalo, em vez de a cada frame
		attackTimer = attackTimer + dt
		if attackTimer >= ATTACK_INTERVAL then
			attackTimer = 0
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and tool:FindFirstChild("Handle") then
				local attack = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("Fire")
				if attack then
					pcall(function() attack:FireServer() end)
				else
					pcall(function() tool:Activate() end)
				end
			end
		end
	end)
end

function Autofarm.disable()
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	npcs = {}
	target = nil
	attackTimer, searchTimer = 0, 0
end

return Autofarm
