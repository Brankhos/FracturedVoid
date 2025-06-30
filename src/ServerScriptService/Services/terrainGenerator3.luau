local Terrain = workspace.Terrain

-- Tam yuvarlak tepe oluşturmak için yükseklik fonksiyonu
local function getTerrainHeight(x, z, radius)
	-- Merkeze olan uzaklığı hesapla
	local distance = math.sqrt(x * x + z * z)
	
	-- Eğer yarıçapın dışındaysa 0 yükseklik
	if distance > radius then
		return 0
	end
	
	-- Tepe yüksekliği (yarıçapın yarısı kadar)
	local maxHeight = radius / 2
	
	-- Yumuşak geçiş için cosine fonksiyonu kullan
	local heightRatio = math.cos((distance / radius) * (math.pi / 2))
	local height = maxHeight * heightRatio
	
	return math.floor(height)
end

-- 0,0,0 konumundan tam yuvarlak tepe şeklinde çimen alanı oluştur
local function createGrassArea()
	local radius = 15 -- Alanı büyüttük
	
	-- Daha sık voxel yerleştir (0.5 birim aralıklarla)
	for x = -radius * 2, radius * 2 do
		for z = -radius * 2, radius * 2 do
			local xPos = x
			local zPos = z
			
			-- Dairesel alan kontrolü (x² + z² ≤ radius²)
			if (xPos * xPos + zPos * zPos) <= (radius * radius) then
				local terrainHeight = getTerrainHeight(xPos, zPos, radius)
				local position = Vector3.new(xPos, 5 + terrainHeight, zPos)
				local blockCFrame = CFrame.new(position)
				local blockSize = Vector3.new(0.5, 0.5, 0.5) -- Daha küçük voxel'ler
				
				-- Çimen ekle
				Terrain:FillBlock(blockCFrame, blockSize, Enum.Material.Glacier)
			end
		end
	end
	
	print("Tam yuvarlak tepe şeklinde çimen alanı oluşturuldu: merkez (0,0,0), yarıçap 15, tepe yüksekliği 7.5")
end

-- Oyun başladığında çimen alanını oluştur
createGrassArea()
