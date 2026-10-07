-- autofarm.lua (versão final, arquivo único)
-- Autofarm "grudado" com AUTO-CALIBRAÇÃO:
--   * Fica em volta do NPC (órbita ou atrás), sempre virado pra ele, atacando sem mouse.
--   * Distância calculada por NPC (raio do corpo + seu raio + folga), então NPC grande funciona.
--   * Vigia a vida do NPC: se você está em posição, atacando, e ele NÃO perde vida, testa
--     outros perfis (distâncias, órbita/parado, altura) até achar o que acerta.
--   * Memoriza o perfil que funcionou para cada nome de NPC (o próximo "Kick Boxer" já começa certo).
--   * Se nenhum perfil acertar aquele NPC, ignora ele por um tempo e vai pro próximo.
--   * Vida baixa: foge PARA LONGE do NPC (retreatDistance) e fica parado esperando recuperar
--     (e chama onLowHealth, ex.: usar cura).
--   * Autofarm.inspect(): imprime no Output os dados do NPC mais próximo (vida, atributos, nível...).
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
-- Escolha de alvo:
--   priority = "nearest" | "lowestHp" | "highestHp"   (padrão: nearest)
--   farmPoint = Vector3.new(x,y,z), areaRadius = 150   só farma NPCs perto desse ponto
--   npcFilter = function(npc) return true end          filtro extra (ex.: por nível)
--   hud = true                                         painel na tela com status e kills
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
--   minHealthPct = 0 (desligado; 0.3 = recua com 30% de vida) / resumeHealthPct = 0.7 / safeHeight = 60 / onLowHealth = function(pct) end
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
local hudGui

local MY_RADIUS = 1.5

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function getRoot(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
end

local function alive(npc)
	if not npc.Parent or not npc:IsDescendantOf(workspace) then return false end
	local h = npc:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and getRoot(npc) ~= nil
end

----------------------------------------------------------------
-- Cache de NPCs (monta UMA vez, depois só eventos) -> sem travar o jogo
----------------------------------------------------------------
local npcSet = {}
local cacheConns = {}

local function addHumanoid(h)
	local m = h.Parent
	if m and m:IsA("Model") then npcSet[m] = true end
end

local function buildCache()
	for _, c in ipairs(cacheConns) do c:Disconnect() end
	cacheConns = {}
	npcSet = {}
	table.insert(cacheConns, workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Humanoid") then addHumanoid(d) end
	end))
	table.insert(cacheConns, workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("Humanoid") and d.Parent then npcSet[d.Parent] = nil end
	end))
	-- varredura inicial em pedaços (cede o frame a cada 3000 itens)
	task.spawn(function()
		local list = workspace:GetDescendants()
		for i, d in ipairs(list) do
			if d:IsA("Humanoid") then addHumanoid(d) end
			if i % 3000 == 0 then task.wait() end
		end
	end)
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
	local best, bestScore = nil, math.huge
	local now = os.clock()
	for npc in pairs(npcSet) do
		if not npc.Parent then
			npcSet[npc] = nil
		elseif npc ~= char and not Players:GetPlayerFromCharacter(npc)
			and alive(npc) and nameOk(npc, o.targetNames)
			and (not ignored[npc] or now > ignored[npc]) then
			local pos = getRoot(npc).Position
			local d = (pos - hrp.Position).Magnitude
			local inArea = (not o.farmPoint) or (pos - o.farmPoint).Magnitude <= o.areaRadius
			local pass = true
			if o.npcFilter then
				local ok, r = pcall(o.npcFilter, npc)
				pass = (ok and r) and true or false
			end
			if d <= o.searchRadius and inArea and pass then
				local score = d
				if o.priority == "lowestHp" then
					score = readHp(o, npc) + d * 0.01
				elseif o.priority == "highestHp" then
					score = -readHp(o, npc) + d * 0.01
				end
				if score < bestScore then best, bestScore = npc, score end
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
		priority        = "nearest",
		farmPoint       = nil,
		areaRadius      = 150,
		hud             = true,
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
		minHealthPct    = 0,     -- 0 = nunca recua. Ex.: 0.3 = foge quando a vida cair abaixo de 30%
		resumeHealthPct = 0.7,
		safeHeight      = 40,
		retreatDistance = 150,
		lowHealthMaxTime = 15,
		debug           = false,
	}
	for k, v in pairs(options or {}) do o[k] = v end

	if not o.attackRemote and not o.clickFn then
		warn("[Autofarm] SEM attackRemote/clickFn: o ataque depende de mouse1click/tool:Activate. Use Autofarm.listRemotes() para achar o remote.")
	end

	session += 1
	local id = session
	buildCache()

	local hudLabel, lastHud = nil, 0
	if o.hud then
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then
			hudGui = Instance.new("ScreenGui")
			hudGui.Name = "AutofarmHud"
			hudGui.ResetOnSpawn = false
			hudGui.DisplayOrder = 100
			hudLabel = Instance.new("TextLabel")
			hudLabel.Size = UDim2.fromOffset(270, 66)
			hudLabel.Position = UDim2.new(0, 10, 0.5, -33)
			hudLabel.BackgroundColor3 = Color3.new(0, 0, 0)
			hudLabel.BackgroundTransparency = 0.4
			hudLabel.TextColor3 = Color3.new(1, 1, 1)
			hudLabel.Font = Enum.Font.Code
			hudLabel.TextSize = 14
			hudLabel.TextXAlignment = Enum.TextXAlignment.Left
			hudLabel.Text = ""
			hudLabel.Parent = hudGui
			hudGui.Parent = pg
		end
	end

	local gap = o.gap or (distanceFn and distanceFn() or 3)
	local radius, distance = 0, 0
	local profiles = buildProfiles(o)
	local learned, ignored = {}, {}
	local profIdx, profStart, lastHp, lastDamage = 1, 0, 0, 0
	local failCycles, everSawDamage, calibrating = 0, false, o.autoCalibrate
	local retreating, retreatStart, safePos = false, 0, nil
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
		if session ~= id then return end

		if hudLabel and os.clock() - lastHud > 0.25 then
			lastHud = os.clock()
			local hp = target and readHp(o, target) or 0
			hudLabel.Text = string.format(" AUTOFARM %s\n Alvo: %s (vida %.0f)\n Kills: %d | perfil %d/%d | gap %.1f",
				paused and "[PAUSADO]" or "[ON]", target and target.Name or "procurando...", hp, kills, profIdx, #profiles, gap)
		end

		if paused then return end

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
					safePos = nil
					print("[Autofarm] recuo terminou, voltando ao combate")
				end
			elseif pct <= o.minHealthPct then
				retreating, retreatStart, safePos = true, now, nil
				print("[Autofarm] VIDA BAIXA (" .. math.floor(pct * 100) .. "%): recuando para longe e esperando recuperar. Para desligar isso: minHealthPct = 0")
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
		if retreating then
			-- ponto seguro FIXO, longe do NPC (calculado uma vez, não segue o NPC)
			if not safePos then
				local away = Vector3.new(myPos.X - npcPos.X, 0, myPos.Z - npcPos.Z)
				if away.Magnitude < 0.01 then away = Vector3.new(0, 0, 1) end
				safePos = npcPos + away.Unit * o.retreatDistance + Vector3.new(0, o.safeHeight, 0)
			end
			desired = safePos
		end

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
	for _, c in ipairs(cacheConns) do c:Disconnect() end
	cacheConns = {}
	npcSet = {}
	if hudGui then
		hudGui:Destroy()
		hudGui = nil
	end
	if lastHum then
		lastHum.AutoRotate = true
		lastHum = nil
	end
end

-- Imprime os dados do NPC mais próximo (vida, atributos, valores, nível...)
function Autofarm.inspect()
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local best, bestD = nil, math.huge
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") and h.Parent:IsA("Model") and h.Parent ~= char
			and not Players:GetPlayerFromCharacter(h.Parent) and getRoot(h.Parent) then
			local d = (getRoot(h.Parent).Position - hrp.Position).Magnitude
			if d < bestD then best, bestD = h.Parent, d end
		end
	end
	if not best then print("[Autofarm][inspect] nenhum NPC") return end
	print("[Autofarm][inspect]", best:GetFullName())
	local hum = best:FindFirstChildOfClass("Humanoid")
	print("  Humanoid:", hum.Health, "/", hum.MaxHealth)
	for k, v in pairs(best:GetAttributes()) do print("  attr", k, v) end
	for k, v in pairs(hum:GetAttributes()) do print("  attr(Humanoid)", k, v) end
	for _, c in ipairs(best:GetChildren()) do
		if c:IsA("ValueBase") then print("  valor", c.ClassName, c.Name, c.Value) end
	end
	local p = Players.LocalPlayer
	for k, v in pairs(p:GetAttributes()) do print("  [você] attr", k, v) end
	local ls = p:FindFirstChild("leaderstats")
	if ls then
		for _, c in ipairs(ls:GetChildren()) do print("  [você] leaderstats", c.Name, c.Value) end
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
