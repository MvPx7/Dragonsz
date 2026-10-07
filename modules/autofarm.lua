-- autofarm_v6.lua
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
-- [  e  ]      = diminui / aumenta a folga da hitbox em tempo real (ajuste até acertar)
--
-- Hitbox: a distância é calculada POR NPC = raio do corpo + raio seu + folga (gap).
--   gap vem do distanceFn() (ou da opção gap) e pode ser ajustado com [ e ].
--   radiusFn = function(npc) return raioEmStuds end   -- opcional, para forçar o raio de algum NPC
--   hitboxScale = 1                                    -- multiplica o raio medido (ex.: 1.2 para NPCs grandes)

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

local MY_RADIUS = 1.5

-- Raio horizontal do corpo do NPC (ignora acessórios/ferramentas, que inflam a caixa).
-- Para cada parte do corpo: distância do centro da parte até a raiz + metade do tamanho dela.
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
		gap            = nil,   -- folga entre a hitbox do NPC e você (padrão: distanceFn())
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
	local gap = o.gap or (distanceFn and distanceFn() or 3)
	local radius, distance = 0, 0

	if not o.attackRemote and not o.clickFn then
		warn("[Autofarm] SEM attackRemote/clickFn: o ataque vai depender de mouse1click/tool:Activate e provavelmente não funciona. Use Autofarm.listRemotes() para achar o remote do ataque.")
	end

	session += 1
	local id = session
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
				if target then
					local r = o.radiusFn and o.radiusFn(target) or bodyRadius(target)
					radius = r * (o.hitboxScale or 1)
					print(string.format("[Autofarm] alvo: %s | raio do corpo: %.1f", target.Name, radius))
				end
			end
			return
		end

		distance = radius + MY_RADIUS + gap

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
			print(string.format("[Autofarm] alvo=%s raio=%.1f distancia=%.1f gap=%.1f ataques/s=%d kills=%d remote=%s",
				target.Name, radius, distance, gap, swings, kills, tostring(o.attackRemote ~= nil or o.clickFn ~= nil)))
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
