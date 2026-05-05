local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Fly = {}

local flyConn = nil
local flyAttach = nil
local flyLinVel = nil
local flyGyro = nil

function Fly.stopPhysics()
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyLinVel and flyLinVel.Parent then flyLinVel:Destroy() end
	if flyGyro and flyGyro.Parent then flyGyro:Destroy() end
	if flyAttach and flyAttach.Parent then flyAttach:Destroy() end
	flyLinVel = nil; flyGyro = nil; flyAttach = nil
end

function Fly.restoreHumanoid(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	task.wait()
	hum.WalkSpeed  = 16
	hum.JumpHeight = 7.2
end

function Fly.enable(player, camera, getFlySpeed)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	hum.WalkSpeed    = 0
	hum.JumpHeight   = 0
	hum.PlatformStand = true

	flyAttach        = Instance.new("Attachment")
	flyAttach.Name   = "_FlyAttach"
	flyAttach.Parent = hrp

	flyLinVel                        = Instance.new("LinearVelocity")
	flyLinVel.Name                   = "_FlyLinVel"
	flyLinVel.Attachment0            = flyAttach
	flyLinVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	flyLinVel.MaxForce               = 1e6
	flyLinVel.RelativeTo             = Enum.ActuatorRelativeTo.World
	flyLinVel.VectorVelocity         = Vector3.zero
	flyLinVel.Parent                 = hrp

	local alignOri          = Instance.new("AlignOrientation")
	alignOri.Name           = "_FlyAlign"
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque      = 1e6
	alignOri.MaxAngularVelocity = math.huge
	alignOri.Responsiveness = 200
	alignOri.Mode           = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0    = flyAttach
	alignOri.Parent         = hrp

	local function getAlignedCF()
		local camLook = camera.CFrame.LookVector
		local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1)
		end
		return CFrame.lookAt(Vector3.zero, flatLook)
	end

	flyConn = RunService.Heartbeat:Connect(function()
		local c = player.Character
		if not c then return end
		local h = c:FindFirstChild("HumanoidRootPart")
		if not h or not flyLinVel or not flyLinVel.Parent then return end

		local hum2 = c:FindFirstChildOfClass("Humanoid")
		if hum2 then hum2.PlatformStand = true end

		local cam  = camera.CFrame
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W)           then move += cam.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.S)           then move -= cam.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.A)           then move -= cam.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D)           then move += cam.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then move += Vector3.new(0,1,0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end

		local hMove = Vector3.new(move.X, 0, move.Z)
		local vMove = Vector3.new(0, move.Y, 0)
		local finalMove = hMove + vMove
		flyLinVel.VectorVelocity = finalMove.Magnitude > 0 and finalMove.Unit * getFlySpeed() or Vector3.zero

		if alignOri and alignOri.Parent then
			alignOri.CFrame = getAlignedCF()
		end
	end)
end

function Fly.disable(player)
	Fly.stopPhysics()
	Fly.restoreHumanoid(player)
end

return Fly
