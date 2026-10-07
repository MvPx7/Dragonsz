-- autofarm_v5.lua
-- Estilo autofarm "grudado": o personagem fica posicionado em volta do NPC a cada frame
-- (atrás dele ou girando em órbita), sempre virado pra ele, atacando sem depender do mouse.
-- Se o NPC estiver longe, desliza até ele rápido (sem teleporte, a não ser que você ligue).
--
-- Uso:
--   Autofarm.enable(player, function() return 3 end, {
--       attackRemote = ReplicatedStorage.Remotes.Attack,  -- remote do seu M1  <-- IMPORTANTE
--       attackArgs   = function(npc) return npc end,      -- argumentos que o M1 manda (opcional)
--       targetNames  = { "Kick Boxer" },                  -- opcional
--       orbit        = true,                              -- gira em volta do NPC (false = fica atrás)
--       debug        = true,
--   })
--   Autofarm.disable()
--   Autofarm.listRemotes()  -- lista os RemoteEvents do ReplicatedStorage (pra achar o do ataque)
--
-- RightControl = pausa / retoma

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Autofarm = {}
local session = 0
local kills = 0
local conns = {}
local lastHum

local function getRoot(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
end

local function alive(npc)
	local h = npc.Parent and npc:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and getRoot(npc) ~= nil
end

local function nameOk(npc, names)
	if not names then return true end
	local n = npc.Name:lower()
	for _, x in ipairs(names) do
		if n:find(x:lower(), 1, true) then return true end
	end
	return false
end

local function findTarget(char, hrp, o)
	local best, bestD = nil, o.searchRadius
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") then
			local npc = h.Parent
			if npc:IsA("Model") and npc ~= char and not Players:GetPlayerFromCharacter(npc)
				and alive(npc) and nameOk(npc, o.targetNames) then
				local d = (getRoot(npc).Position - hrp.Position).Magnitude
				if d < bestD then best, bestD = npc, d end
			end
		end
	end
	return best
end

local function attack(o, char, npc)
	if o.clickFn then
		pcall(o.clickFn, npc)
	elseif o.attackRemote then
		pcall(function()
			if o.attackArgs then
				o.attackRemote:FireServer(o.attackArgs(npc))
			else
				o.attackRemote:FireServer()
			end
		end)
	else
		-- fallback (depende do jogo / do mouse): só use se não tiver o remote
		if type(mouse1click) == "function" then pcall(mouse1click) end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then pcall(function() tool:Activate() end) end
	end
end

function Autofarm.enable(player, distanceFn, options)
	Autofarm.disable()

	local o = {
		searchRadius   = 1000,
		distance       = nil,   -- studs do centro do NPC (padrão: distanceFn() + 2)
		heightOffset   = 0,     -- sobe/desce em relação ao NPC
		orbit          = true,  -- true = gira em volta; false = fica atrás do NPC
		orbitSpeed     = 2.5,   -- radianos por segundo
		snapRange      = 20,    -- até essa distância do ponto ideal, "gruda" direto
		travelSpeed    = 150,   -- studs/s para chegar até o NPC quando está longe
		teleport       = false, -- true = vai direto, sem deslizar
		attackInterval = 0.12,
		debug          = false,
	}
	for k, v in pairs(options or {}) do o[k] = v end
	local distance = o.distance or ((distanceFn and distanceFn() or 3) + 2)

	if not o.attackRemote and not o.clickFn then
		warn("[Autofarm] SEM attackRemote/clickFn: o ataque vai depender de mouse1click/tool:Activate e provavelmente não funciona. Use Autofarm.listRemotes() para achar o remote do ataque.")
	end

	session += 1
	local id = session
	local paused = false
	local target, angle = nil, 0
	local lastAttack, lastScan, lastDbg, lastEquip, swings = 0, 0, 0, 0, 0

	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == Enum.KeyCode.RightControl then
			paused = not paused
			print("[Autofarm]", paused and "PAUSADO" or "RETOMADO")
		end
	end))

	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if session ~= id or paused then return end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end
		lastHum = hum

		local now = os.clock()

		-- alvo morreu / sumiu
		if target and not alive(target) then
			local th = target:FindFirstChildOfClass("Humanoid")
			if th and th.Health <= 0 then kills += 1 end
			target = nil
		end

		-- procura próximo alvo
		if not target then
			if now - lastScan > 0.3 then
				lastScan = now
				target = findTarget(char, hrp, o)
			end
			return
		end

		local npcRoot = getRoot(target)
		local npcPos = npcRoot.Position
		local myPos = hrp.Position

		-- ponto ideal em volta do NPC
		local desired
		if o.orbit then
			angle += o.orbitSpeed * dt
			desired = npcPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		else
			desired = (npcRoot.CFrame * CFrame.new(0, 0, distance)).Position -- atrás do NPC
		end
		desired = Vector3.new(desired.X, npcPos.Y + o.heightOffset, desired.Z)

		-- grudado: vai pro ponto; longe: desliza até ele
		local delta = desired - myPos
		local d = delta.Magnitude
		local newPos
		if o.teleport or d <= o.snapRange then
			newPos = desired
		else
			newPos = myPos + delta.Unit * math.min(d, o.travelSpeed * dt)
		end

		hum.AutoRotate = false
		hrp.CFrame = CFrame.lookAt(newPos, Vector3.new(npcPos.X, newPos.Y, npcPos.Z))
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		-- ataque (só quando já está em volta do NPC)
		if (newPos - desired).Magnitude < 1 then
			-- sem ferramenta na mão: equipa (1x por segundo)
			if not char:FindFirstChildOfClass("Tool") and now - lastEquip > 1 then
				local bp = player:FindFirstChildOfClass("Backpack")
				local first = bp and bp:FindFirstChildOfClass("Tool")
				if first then
					lastEquip = now
					hum:EquipTool(first)
				end
			end

			if now - lastAttack >= o.attackInterval then
				lastAttack = now
				swings += 1
				attack(o, char, target)
			end
		end

		if o.debug and now - lastDbg > 1 then
			lastDbg = now
			print(string.format("[Autofarm] alvo=%s distAoPonto=%.1f ataques/s=%d kills=%d remote=%s",
				target.Name, d, swings, kills, tostring(o.attackRemote ~= nil or o.clickFn ~= nil)))
			swings = 0
		end
	end))
end

function Autofarm.disable()
	session += 1
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	if lastHum then
		lastHum.AutoRotate = true
		lastHum = nil
	end
end

function Autofarm.listRemotes()
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			print(d.ClassName, d:GetFullName())
		end
	end
end

function Autofarm.getKills()
	return kills
end

return Autofarm
