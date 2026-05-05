local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Autofarm = {}
local autofarmConn = nil

local function isNPC(model)
	if not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	return model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function findNearestNpc(player)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local nearest, nearestDist = nil, math.huge
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isNPC(obj) then
			local nHrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
			if nHrp then
				local d = (hrp.Position - nHrp.Position).Magnitude
				if d < nearestDist then
					nearest     = obj
					nearestDist = d
				end
			end
		end
	end
	return nearest
end

function Autofarm.enable(player, distanceFn)
	autofarmConn = RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local npc = findNearestNpc(player)
		if not npc then return end
		local nHrp = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
		if not nHrp then return end

		local npcHum = npc:FindFirstChildOfClass("Humanoid")
		if npcHum and npcHum.Health <= 0 then return end

		-- Gruda no NPC à distância configurada
		local dir  = (hrp.Position - nHrp.Position)
		local dist = dir.Magnitude
		if dist > 0.1 then
			local targetPos = nHrp.Position + dir.Unit * distanceFn()
			hrp.CFrame = CFrame.new(targetPos, nHrp.Position)
		end

		-- Ataca usando ferramentas equipadas ou simula clique
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			local handle = tool:FindFirstChild("Handle")
			if handle then
				local attack = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("Fire")
				if attack then
					pcall(function() attack:FireServer() end)
				end
			end
		end
	end)
end

function Autofarm.disable()
	if autofarmConn then autofarmConn:Disconnect(); autofarmConn = nil end
end

return Autofarm
