local Teleport = {}

local savedPosition = nil

function Teleport.markPosition(player)
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	savedPosition = hrp.Position
	print(string.format("[Dragonsz TP] Posição salva: %.1f, %.1f, %.1f", savedPosition.X, savedPosition.Y, savedPosition.Z))
	return savedPosition
end

function Teleport.goToPosition(player)
	if not savedPosition then
		print("[Dragonsz TP] Nenhuma posição salva.")
		return false
	end
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	hrp.CFrame = CFrame.new(savedPosition)
	return true
end

function Teleport.teleportToCoords(player, rawCoords)
	local x, y, z = rawCoords:match("^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$")
	if not x or not y or not z then
		return false, "✕  Formato inválido. Use: X, Y, Z"
	end
	local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
	if not nx or not ny or not nz then
		return false, "✕  Valores inválidos."
	end
	local char = player.Character
	if not char then return false, "Personagem não encontrado" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "RootPart não encontrado" end
	
	hrp.CFrame = CFrame.new(Vector3.new(nx, ny, nz))
	return true, string.format("✓  %.0f, %.0f, %.0f", nx, ny, nz)
end

function Teleport.getSavedPosition()
	return savedPosition
end

return Teleport
