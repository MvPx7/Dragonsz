-- autofarm_v7.lua
-- Autofarm "grudado" com AUTO-CALIBRAÇÃO:
--   * Fica em volta do NPC (órbita ou atrás), sempre virado pra ele, atacando sem mouse.
--   * Distância calculada por NPC (raio do corpo + seu raio + folga), então NPC grande funciona.
--   * Vigia a vida do NPC: se você está em posição, atacando, e ele NÃO perde vida, testa
--     outros perfis (distâncias, órbita/parado, altura) até achar o que acerta.
--   * Memoriza o perfil que funcionou para cada nome de NPC (o próximo "Kick Boxer" já começa certo).
--   * Se nenhum perfil acertar aquele NPC, ignora ele por um tempo e vai pro próximo.
--   * Vida baixa: sobe pra longe do chão e espera recuperar (e chama onLowHealth, ex.: usar cura).
--
-- Uso:
--   Autofarm.enable(player, function() return 3 end, {
--       attackRemote = ReplicatedStorage.Remotes.Attack,  -- remote do seu M1
--       attackArgs   = function(npc) return npc end,      -- argumentos do M1 (opcional)
--       targetNames  = { "Kick Boxer", "Namek" },         -- opcional
--       debug        = true,
--   })
--   Autofarm.disable()
--   Autofarm.listRemotes()
--
-- Opções úteis:
--   orbit = true         gira em volta (false = fica atrás)
--   gap = 3              folga da hitbox (ajuste ao vivo com [ e ])
--   hitboxScale = 1      multiplica o raio medido
--   radiusFn = function(npc) return 6 end     força o raio de algum NPC
--   hpFn = function(npc) return npc:GetAttribute("HP") end   se a vida do NPC NÃO for Humanoid.Health
--   burst = 1            quantos ataques por disparo (aumente com cuidado: o servidor pode limitar)
--   attackInterval = 0.12
--   autoCalibrate = true / calibrateAfter = 1.2 (s sem dano para trocar de perfil) / skipAfterFail = 20
--   minHealthPct = 0.3 / resumeHealthPct = 0.7 / safeHeight = 60 / onLowHealth = function(pct) end
--
-- Teclas: RightControl = pausa/retoma | [ e ] = diminui/aumenta a folga

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Autofarm = {}
local session = 0
local kills = 0
local conns = {}
local lastHum

local MY_RADIUS = 1.5

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function getRoot(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
end

local function alive(npc)
	local h = npc.Parent and npc:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and getRoot(npc) ~= nil
end

-- Raio horizontal do corpo (ignora acessórios/ferramentas, que inflam a caixa)
local function bodyRadius(npc)
	local root = getRoot(npc)
	if not root then return 3 end
	local r = math.max(root.Size.X, root.Size.Z) / 2
	for _, p in ipairs(npc:GetChildren()) do
		if p:IsA("BasePart") and p ~= root then
			local off = Vector3.new(p.Position.X - root.Position.X, 0, p.Position.Z - root.Position.Z).Magnitude
			r = math.max(r, off + math.min(p.Size.X, p.Size.Z) / 2)
		end
	end
	return r
end

local function nameOk(npc, names)
	if not names then return true end
	local n = npc.Name:lower()
	for _, x in ipairs(names) do
		if n:find(x:lower(), 1, true) then return true end
	end
	return false
end

local function readHp(o, npc)
	if o.hpFn then
		local ok, v = pcall(o.hpFn, npc)
		if ok and type(v) == "number" then return v end
	end
	local h = npc:FindFirstChildOfClass("Humanoid")
	return h and h.Health or 0
end

local function findTarget(char, hrp, o, ignored)
	local best, bestD = nil, o.searchRadius
	local now = os.clock()
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") then
			local npc = h.Parent
			if npc:IsA("Model") and npc ~= char and not Players:GetPlayerFromCharacter(npc)
				and alive(npc) and nameOk(npc, o.targetNames)
				and (not ignored[npc] or now > ignored[npc]) then
				local d = (getRoot(npc).Position - hrp.Position).Magnitude
				if d < bestD then best, bestD = npc, d end
			end
		end
	end
	return best
end

-- Perfis de posicionamento que a auto-calibração testa, em ordem
local function buildProfiles(o)
	local list = {}
	local deltas = { 0, -1, 1, -2, 2, 3 }
	for _, orbit in ipairs({ o.orbit, not o.orbit }) do
		for _, dg in ipairs(deltas) do
			table.insert(list, { dg = dg, orbit = orbit })
		end
	end
	table.insert(list, { dg = 0, orbit = false, h = 2 })
	table.insert(list, { dg = 0, orbit = false, h = -1.5 })
	return list
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
		if type(mouse1click) == "function" then pcall(mouse1click) end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then pcall(function() tool:Activate() end) end
	end
end

----------------------------------------------------------------
-- Principal
----------------------------------------------------------------
function Autofarm.enable(player, distanceFn, options)
	Autofarm.disable()

	local o = {
		searchRadius    = 1000,
		gap             = nil,
		heightOffset    = 0,
		orbit           = true,
		orbitSpeed      = 2.5,
		snapRange       = 20,
		travelSpeed     = 150,
		teleport        = false,
		attackInterval  = 0.12,
		burst           = 1,
		autoCalibrate   = true,
		calibrateAfter  = 1.2,
		skipAfterFail   = 20,
		minHealthPct    = 0.3,
		resumeHealthPct = 0.7,
		safeHeight      = 60,
		lowHealthMaxTime = 15,
		debug           = false,
	}
	for k, v in pairs(options or {}) do o[k] = v end

	if not o.attackRemote and not o.clickFn then
		warn("[Autofarm] SEM attackRemote/clickFn: o ataque depende de mouse1click/tool:Activate. Use Autofarm.listRemotes() para achar o remote.")
	end

	session += 1
	local id = session

	local gap = o.gap or (distanceFn and distanceFn() or 3)
	local radius, distance = 0, 0
	local profiles = buildProfiles(o)
	local learned, ignored = {}, {}
	local profIdx, profStart, lastHp, lastDamage = 1, 0, 0, 0
	local failCycles, everSawDamage, calibrating = 0, false, o.autoCalibrate
	local retreating, retreatStart = false, 0
	local inPos = false
	local paused = false
	local target, angle = nil, 0
	local lastAttack, lastScan, lastDbg, lastEquip, swings = 0, 0, 0, 0, 0

	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.RightControl then
			paused = not paused
			print("[Autofarm]", paused and "PAUSADO" or "RETOMADO")
		elseif input.KeyCode == Enum.KeyCode.LeftBracket then
			gap = math.max(-MY_RADIUS, gap - 0.5)
			print("[Autofarm] gap =", gap)
		elseif input.KeyCode == Enum.KeyCode.RightBracket then
			gap += 0.5
			print("[Autofarm] gap =", gap)
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

		-- vida baixa: sobe e espera recuperar
		if o.minHealthPct > 0 and hum.MaxHealth > 0 then
			local pct = hum.Health / hum.MaxHealth
			if retreating then
				if pct >= o.resumeHealthPct or now - retreatStart > o.lowHealthMaxTime then
					retreating = false
				end
			elseif pct <= o.minHealthPct then
				retreating, retreatStart = true, now
				if o.debug then print("[Autofarm] vida baixa, recuando:", math.floor(pct * 100) .. "%") end
				if o.onLowHealth then task.spawn(o.onLowHealth, pct) end
			end
		end

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
				target = findTarget(char, hrp, o, ignored)
				if target then
					local r = o.radiusFn and o.radiusFn(target) or bodyRadius(target)
					radius = r * (o.hitboxScale or 1)
					profIdx = learned[target.Name] or 1
					profStart, lastDamage, inPos = now, now, false
					lastHp = readHp(o, target)
					print(string.format("[Autofarm] alvo: %s | raio: %.1f | perfil inicial: %d%s",
						target.Name, radius, profIdx, learned[target.Name] and " (aprendido)" or ""))
				end
			end
			return
		end

		-- posição desejada segundo o perfil atual
		local prof = profiles[profIdx]
		distance = math.max(radius + MY_RADIUS + gap + prof.dg, 1)

		local npcRoot = getRoot(target)
		local npcPos = npcRoot.Position
		local myPos = hrp.Position

		local desired
		if prof.orbit then
			angle += o.orbitSpeed * dt
			desired = npcPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		else
			desired = (npcRoot.CFrame * CFrame.new(0, 0, distance)).Position -- atrás do NPC
		end
		desired = Vector3.new(desired.X, npcPos.Y + o.heightOffset + (prof.h or 0), desired.Z)
		if retreating then desired += Vector3.new(0, o.safeHeight, 0) end

		-- grudado: vai direto; longe: desliza rápido
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

		inPos = (newPos - desired).Magnitude < 1 and not retreating

		-- ataque
		if inPos then
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
				for _ = 1, o.burst do
					swings += 1
					attack(o, char, target)
				end
			end
		end

		-- vigia o dano e calibra
		local hp = readHp(o, target)
		if hp < lastHp - 0.01 then
			lastDamage = now
			everSawDamage = true
			failCycles = 0
			if learned[target.Name] ~= profIdx then
				learned[target.Name] = profIdx
				if o.debug then
					print(string.format("[Autofarm] perfil %d acertou em '%s' (dist=%.1f, orbita=%s) - memorizado",
						profIdx, target.Name, distance, tostring(prof.orbit)))
				end
			end
		end
		lastHp = hp

		if not inPos then profStart = now end -- o relógio só conta quando você está em posição

		if calibrating and inPos and now - math.max(lastDamage, profStart) > o.calibrateAfter then
			profIdx += 1
			profStart = now
			if profIdx > #profiles then
				profIdx = 1
				failCycles += 1
				if everSawDamage then
					print("[Autofarm] nenhum perfil acertou em", target.Name, "- ignorando por", o.skipAfterFail, "s")
					ignored[target] = now + o.skipAfterFail
					target = nil
				elseif failCycles >= 2 then
					calibrating = false
					warn("[Autofarm] Não detectei dano em NENHUM NPC. Provável: attackRemote errado, ou a vida do NPC não é Humanoid.Health (use hpFn). Calibração desligada.")
				end
			elseif o.debug then
				print(string.format("[Autofarm] sem dano, testando perfil %d/%d", profIdx, #profiles))
			end
		end

		if o.debug and now - lastDbg > 1 and target then
			lastDbg = now
			print(string.format("[Autofarm] %s | raio=%.1f dist=%.1f gap=%.1f perfil=%d/%d | ataques/s=%d | kills=%d | remote=%s",
				target.Name, radius, distance, gap, profIdx, #profiles, swings, kills,
				tostring(o.attackRemote ~= nil or o.clickFn ~= nil)))
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
