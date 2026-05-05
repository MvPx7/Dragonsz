local Players = game:GetService("Players")

local Esp = {}

local espObjs = {}
local espBBObjs = {}
local espConn = nil

local NPC_HL_COLOR = Color3.fromRGB(200, 100, 255)
local NPC_HL_FILL  = Color3.fromRGB(80, 20, 120)

function Esp.isNPC(model, localPlayer)
	if not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	if model == localPlayer.Character then return false end
	return model:FindFirstChildOfClass("Humanoid") ~= nil
end

function Esp.addNpcHighlight(model)
	if espObjs[model] then return end

	local hl               = Instance.new("Highlight")
	hl.Adornee             = model
	hl.FillColor           = NPC_HL_FILL
	hl.OutlineColor        = NPC_HL_COLOR
	hl.FillTransparency    = 0.5
	hl.OutlineTransparency = 0
	hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent              = model
	espObjs[model]         = hl

	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if hrp then
		local bb       = Instance.new("BillboardGui")
		bb.Name        = "_NpcEspBB"
		bb.AlwaysOnTop = true
		bb.Size        = UDim2.new(0, 160, 0, 26)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.Parent      = hrp
		espBBObjs[model] = bb

		local nameLbl                  = Instance.new("TextLabel")
		nameLbl.Size                   = UDim2.new(1, 0, 1, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text                   = model.Name
		nameLbl.TextColor3             = NPC_HL_COLOR
		nameLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
		nameLbl.TextStrokeTransparency = 0.3
		nameLbl.TextSize               = 13
		nameLbl.Font                   = Enum.Font.GothamBold
		nameLbl.Parent                 = bb
	end
end

function Esp.removeNpcHighlight(model)
	if espObjs[model] and espObjs[model].Parent then
		espObjs[model]:Destroy()
	end
	espObjs[model] = nil
	if espBBObjs[model] and espBBObjs[model].Parent then
		espBBObjs[model]:Destroy()
	end
	espBBObjs[model] = nil
end

function Esp.enable(localPlayer, isEspOn)
	for _, obj in ipairs(workspace:GetDescendants()) do
		if Esp.isNPC(obj, localPlayer) then Esp.addNpcHighlight(obj) end
	end
	espConn = workspace.DescendantAdded:Connect(function(obj)
		if isEspOn() and Esp.isNPC(obj, localPlayer) then
			task.wait(0.05)
			Esp.addNpcHighlight(obj)
		end
	end)
end

function Esp.disable()
	if espConn then espConn:Disconnect(); espConn = nil end
	for model in pairs(espObjs) do Esp.removeNpcHighlight(model) end
end

return Esp
