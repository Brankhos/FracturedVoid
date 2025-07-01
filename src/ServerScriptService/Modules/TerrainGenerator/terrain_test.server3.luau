local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- Parametreler
local AREA_SIZE = Vector3.new(150, 3, 150)
local BLOCK_SIZE = Vector3.new(50, 3, 50)
local DROP_INTERVAL = 1 -- saniye
local PART_LIFETIME = 5 -- saniye
local DROP_HEIGHT = 20
local DROPS_PER_SECOND = 10
local SWITCH_INTERVAL = 10 -- saniye

-- Konumlar
local terrainCenter = Vector3.new(-80, 0, 0)
local partCenter = Vector3.new(80, 0, 0)

-- Terrain oluştur
local terrain = Workspace.Terrain
for x = -1, 1 do
	for z = -1, 1 do
		local position = terrainCenter + Vector3.new(x * BLOCK_SIZE.X, 0, z * BLOCK_SIZE.Z)
		terrain:FillBlock(CFrame.new(position), BLOCK_SIZE, Enum.Material.Grass)
	end
end

-- Part alanı oluştur
for x = -1, 1 do
	for z = -1, 1 do
		local part = Instance.new("Part")
		part.Size = BLOCK_SIZE
		part.Position = partCenter + Vector3.new(x * BLOCK_SIZE.X, BLOCK_SIZE.Y / 2, z * BLOCK_SIZE.Z)
		part.Anchored = true
		part.Material = Enum.Material.Grass
		part.Parent = Workspace
	end
end

-- Düşen Part üreten fonksiyon
local function dropParts(center)
	for i = 1, DROPS_PER_SECOND do
		local drop = Instance.new("Part")
		drop.Size = Vector3.new(5, 5, 5)
		drop.Position = center + Vector3.new(
			math.random(-20, 20),
			DROP_HEIGHT,
			math.random(-20, 20)
		)
		drop.Anchored = false
		drop.CanCollide = true
		drop.Parent = Workspace
		Debris:AddItem(drop, PART_LIFETIME)
	end
end

-- Başlangıç: Terrain ile başla
local useTerrain = true
local switchTimer = 0

while true do
	-- Aktif bölgeyi belirle
	local currentCenter = useTerrain and terrainCenter or partCenter

	-- Parçaları düşür
	dropParts(currentCenter)

	-- Zamanlayıcı
	switchTimer += DROP_INTERVAL

	-- 10 saniyede bir bölgeyi değiştir
	if switchTimer >= SWITCH_INTERVAL then
		useTerrain = not useTerrain
		switchTimer = 0
		print("Switching drop area! Now dropping on:", useTerrain and "Terrain" or "Part Area")
	end

	task.wait(DROP_INTERVAL)
end
