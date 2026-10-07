-- autofarm_lite.lua (v4 enxuto)
-- Acha NPC -> anda até ele -> vira pra ele -> ataca -> próximo.
--
-- Uso:
--   Autofarm.enable(player, function() return 3 end, {
--       attackRemote = ReplicatedStorage.Remotes.Attack,  -- remote do seu M1
--       attackArgs   = function(npc) return npc end,      -- argumentos do M1 (opcional)
--       targetNames  = { "Galactic" },                    -- opcional: só NPCs com esse texto no nome
--       range        = 8,                                 -- opcional: distância (HRP a HRP) para atacar
--       debug        = true,
--   })
--   Autofarm.disable()

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local Autofarm = {}
local session = 0
local kills = 0

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

local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Anda até o destino usando pathfinding (recalcula a cada 1s)
local function walkTo(st, hrp, hum, goal)
	local now = os.clock()
	if now - st.pathTime > 1 then
		st.pathTime = now
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function() path:ComputeAsync(hrp.Position, goal) end)
		st.pathOk = ok and path.Status == Enum.PathStatus.Success
		st.waypoints = st.pathOk and path:GetWaypoints() or nil
		st.wp = 2
	end

	local wps = st.waypoints
	local wp = wps and wps[st.wp]
	while wp and flat(wp.Position, hrp.Position) < 3 do
		st.wp += 1
		wp = wps[st.wp]
	end

	if wp then
		if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
		hum:MoveTo(wp.Position)
	else
		hum:MoveTo(goal)
	end
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
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then pcall(function() tool:Activate() end) end
	end
end

function Autofarm.enable(player, distanceFn, options)
	Autofarm.disable()

	local o = { searchRadius = 500, attackInterval = 0.15, debug = false }
	for k, v in pairs(options or {}) do o[k] = v end
	local range = o.range or ((distanceFn and distanceFn() or 3) + 5)

	if not o.attackRemote and not o.clickFn then
		warn("[Autofarm] sem attackRemote/clickFn: só vai tentar tool:Activate()")
	end

	session += 1
	local id = session
	local st = { pathTime = 0, wp = 2, pathOk = false }

	task.spawn(function()
		local target, lastAttack, lastScan, lastDbg = nil, 0, 0, 0
		local stuckPos, stuckT = Vector3.zero, 0
		local lastHum

		while session == id do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")

			if hrp and hum and hum.Health > 0 then
				lastHum = hum
				local now = os.clock()

				-- alvo morreu / sumiu
				if target and not alive(target) then
					local th = target:FindFirstChildOfClass("Humanoid")
					if th and th.Health <= 0 then kills += 1 end
					target = nil
				end

				-- procura alvo (no máx. 2x por segundo)
				if not target and now - lastScan > 0.5 then
					lastScan = now
					target = findTarget(char, hrp, o)
					st.pathTime = 0
				end

				if target then
					local npos = getRoot(target).Position
					local dist = flat(hrp.Position, npos)

					if dist > range then
						hum.AutoRotate = true
						walkTo(st, hrp, hum, npos)

						-- travado? pula
						if now - stuckT > 1.5 then
							if (hrp.Position - stuckPos).Magnitude < 1 then hum.Jump = true end
							stuckPos, stuckT = hrp.Position, now
						end
					else
						-- perto: fica parado, vira pro NPC e ataca
						hum.AutoRotate = false
						hum:MoveTo(hrp.Position)
						hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(npos.X, hrp.Position.Y, npos.Z))

						if now - lastAttack >= o.attackInterval then
							lastAttack = now
							attack(o, char, target)
						end
					end

					if o.debug and now - lastDbg > 1 then
						lastDbg = now
						print(string.format("[Autofarm] alvo=%s dist=%.1f range=%.1f walkspeed=%.0f caminho=%s kills=%d",
							target.Name, dist, range, hum.WalkSpeed, tostring(st.pathOk), kills))
					end
				elseif o.debug and now - lastDbg > 1 then
					lastDbg = now
					print("[Autofarm] sem alvo | kills:", kills)
				end
			end

			task.wait(0.05)
		end

		if lastHum then lastHum.AutoRotate = true end
	end)
end

function Autofarm.disable()
	session += 1 -- encerra o loop atual
end

function Autofarm.getKills()
	return kills
end

return Autofarm
