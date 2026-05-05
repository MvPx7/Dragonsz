local RunService = game:GetService("RunService")

local Noclip = {}
local ncConn = nil

function Noclip.enable(player)
	ncConn = RunService.Stepped:Connect(function()
		local char = player.Character
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end)
end

function Noclip.disable(player)
	if ncConn then ncConn:Disconnect(); ncConn = nil end
	local char = player.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = true end
		end
	end
end

return Noclip
