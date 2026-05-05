local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Highlight = {}

local hlObjs = {}
local bbObjs = {}
local hlConns = {}
local hlAdded = nil

function Highlight.removeFor(p)
	if hlObjs[p] and hlObjs[p].Parent then hlObjs[p]:Destroy() end
	hlObjs[p] = nil
	if bbObjs[p] and bbObjs[p].Parent then bbObjs[p]:Destroy() end
	bbObjs[p] = nil
	if hlConns[p] then hlConns[p]:Disconnect(); hlConns[p] = nil end
end

function Highlight.buildFor(p, char, localPlayer, hlColor, hlFill)
	if not char then return end
	Highlight.removeFor(p)

	local hl               = Instance.new("Highlight")
	hl.Adornee             = char
	hl.FillColor           = hlFill
	hl.OutlineColor        = hlColor
	hl.FillTransparency    = 0.5
	hl.OutlineTransparency = 0
	hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent              = char
	hlObjs[p]              = hl

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local bb       = Instance.new("BillboardGui")
		bb.AlwaysOnTop = true
		bb.Size        = UDim2.new(0, 140, 0, 36)
		bb.StudsOffset = Vector3.new(0, 3.5, 0)
		bb.Parent      = hrp
		bbObjs[p]      = bb

		local nl                  = Instance.new("TextLabel")
		nl.Size                   = UDim2.new(1, 0, 0, 18)
		nl.Position               = UDim2.new(0, 0, 0, 0)
		nl.BackgroundTransparency = 1
		nl.Text                   = p.DisplayName
		nl.TextColor3             = hlColor
		nl.TextStrokeColor3       = Color3.new(0, 0, 0)
		nl.TextStrokeTransparency = 0.3
		nl.TextSize               = 13
		nl.Font                   = Enum.Font.GothamBold
		nl.Parent                 = bb

		local distLbl                  = Instance.new("TextLabel")
		distLbl.Name                   = "DistLabel"
		distLbl.Size                   = UDim2.new(1, 0, 0, 14)
		distLbl.Position               = UDim2.new(0, 0, 0, 20)
		distLbl.BackgroundTransparency = 1
		distLbl.Text                   = "-- m"
		distLbl.TextColor3             = Color3.fromRGB(200, 230, 255)
		distLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
		distLbl.TextStrokeTransparency = 0.3
		distLbl.TextSize               = 11
		distLbl.Font                   = Enum.Font.Code
		distLbl.Parent                 = bb

		hlConns[p] = RunService.Heartbeat:Connect(function()
			local myChar = localPlayer.Character
			local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
			local tHrp   = char:FindFirstChild("HumanoidRootPart")
			if myHrp and tHrp and distLbl.Parent then
				local dist = math.floor((myHrp.Position - tHrp.Position).Magnitude)
				distLbl.Text = dist .. " m"
			end
		end)
	end
end

function Highlight.enable(localPlayer, hlColor, hlFill, isHlOn)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then
			Highlight.buildFor(p, p.Character, localPlayer, hlColor, hlFill)
			p.CharacterAdded:Connect(function(c)
				task.wait(0.1)
				if isHlOn() then Highlight.buildFor(p, c, localPlayer, hlColor, hlFill) end
			end)
		end
	end
	hlAdded = Players.PlayerAdded:Connect(function(p)
		if not isHlOn() or p == localPlayer then return end
		Highlight.buildFor(p, p.Character, localPlayer, hlColor, hlFill)
		p.CharacterAdded:Connect(function(c)
			task.wait(0.1)
			if isHlOn() then Highlight.buildFor(p, c, localPlayer, hlColor, hlFill) end
		end)
	end)
end

function Highlight.disable()
	for p in pairs(hlObjs) do Highlight.removeFor(p) end
	for p in pairs(bbObjs) do Highlight.removeFor(p) end
	if hlAdded then hlAdded:Disconnect(); hlAdded = nil end
end

return Highlight
