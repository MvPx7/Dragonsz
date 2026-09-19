local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Fly = {}

local flyConn = nil
local flyAttach = nil
local flyLinVel = nil
local flyAlign = nil
local verticalInput = 0 -- -1 (descer) | 0 | 1 (subir) -> botões da UI no mobile

-- Chamado pela UI (botões ▲ / ▼ no mobile)
function Fly.setVertical(dir)
	verticalInput = math.clamp(tonumber(dir) or 0, -1, 1)
end

function Fly.stopPhysics()
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyLinVel and flyLinVel.Parent then flyLinVel:Destroy() end
	if flyAlign and flyAlign.Parent then flyAlign:Destroy() end
	if flyAttach and flyAttach.Parent then flyAttach:Destroy() end
	flyLinVel = nil; flyAlign = nil; flyAttach = nil
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

	-- Evita duplicar a física se enable for chamado duas vezes
	Fly.stopPhysics()

	hum.WalkSpeed     = 0
	hum.JumpHeight    = 0
	hum.PlatformStand = true

	-- Controles nativos do Roblox (joystick no mobile / WASD / gamepad)
	local controls = nil
	pcall(function()
		local ps = player:FindFirstChild("PlayerScripts") or player:WaitForChild("PlayerScripts", 2)
		local pm = ps and (ps:FindFirstChild("PlayerModule") or ps:WaitForChild("PlayerModule", 2))
		if pm then controls = require(pm):GetControls() end
	end)

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

	flyAlign                     = Instance.new("AlignOrientation")
	flyAlign.Name                = "_FlyAlign"
	flyAlign.RigidityEnabled     = false
	flyAlign.MaxTorque           = 1e6
	flyAlign.MaxAngularVelocity  = math.huge
	flyAlign.Responsiveness      = 200
	flyAlign.Mode                = Enum.OrientationAlignmentMode.OneAttachment
	flyAlign.Attachment0         = flyAttach
	flyAlign.Parent              = hrp

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

		local cam = camera.CFrame

		-- 1) Teclado (PC)
		local kbMove = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then kbMove += cam.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then kbMove -= cam.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then kbMove -= cam.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then kbMove += cam.RightVector end

		local move = kbMove

		-- 2) Joystick (mobile) / gamepad: só usa se o teclado não estiver em uso
		if kbMove.Magnitude == 0 then
			local mv = Vector3.zero
			if controls then
				local ok, v = pcall(controls.GetMoveVector, controls)
				if ok and typeof(v) == "Vector3" then mv = v end
			end
			if mv.Magnitude > 0.05 then
				-- MoveVector: X = direita, Z = trás (relativo à câmera)
				move += cam.LookVector * (-mv.Z) + cam.RightVector * mv.X
			elseif hum2 and hum2.MoveDirection.Magnitude > 0.05 then
				-- Fallback: MoveDirection (mundo, plano horizontal)
				local md = hum2.MoveDirection
				local flatLook = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
				if flatLook.Magnitude < 0.01 then
					flatLook = Vector3.new(0, 0, -1)
				else
					flatLook = flatLook.Unit
				end
				local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
				move += cam.LookVector * md:Dot(flatLook) + cam.RightVector * md:Dot(flatRight)
			end
		end

		-- 3) Vertical: Espaço / Ctrl (PC) ou botões ▲ ▼ (mobile)
		local vert = verticalInput
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then vert += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vert -= 1 end
		move += Vector3.new(0, math.clamp(vert, -1, 1), 0)

		flyLinVel.VectorVelocity = move.Magnitude > 0.01 and move.Unit * getFlySpeed() or Vector3.zero

		if flyAlign and flyAlign.Parent then
			flyAlign.CFrame = getAlignedCF()
		end
	end)
end

function Fly.disable(player)
	verticalInput = 0
	Fly.stopPhysics()
	Fly.restoreHumanoid(player)
end

return Fly
