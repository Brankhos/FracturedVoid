--!strict

local TerrainGenerator = {
	CHUNK_RADIUS = 10,
	CHUNK_DISTANCE = 1,
	CHUNK_TIMEOUT_MAX = 20,
	CHUNK_TIMEOUT_MIN = 3,
	SURFACE_HEIGHT = 3,
	RARITY_POWER = 1,
	MIN_HEIGHT = 0,
	MAX_HEIGHT = 50,
	VOXEL_SIZE = 4,
	TERRAIN_TYPE = Enum.Material.Glacier
}

------------------------------------------------------------------------------------------------------------------------------------------------
-- Konfigürasyon
------------------------------------------------------------------------------------------------------------------------------------------------
local GENERATION_SEED: number = math.random()

------------------------------------------------------------------------------------------------------------------------------------------------
-- Parametreler
------------------------------------------------------------------------------------------------------------------------------------------------
TerrainGenerator.CHUNK_RADIUS *= TerrainGenerator.VOXEL_SIZE
local CHUNK_LENGTH: number = TerrainGenerator.CHUNK_RADIUS * 2
local HORIZONTAL_MASK: Vector3 = Vector3.new(1, 0, 1)
local HEIGHT_RANGE: number = TerrainGenerator.MAX_HEIGHT - TerrainGenerator.MIN_HEIGHT
local VOXEL_HALF: number = TerrainGenerator.VOXEL_SIZE / 2
local X_SCALE: number = 90
local Z_SCALE: number = 90
local NOISE_OFFSET: number = 0.5
local FLAT_RADIUS: number = 24
local BLEND_RADIUS: number = 75
local FLAT_RADIUS_SQ: number = FLAT_RADIUS * FLAT_RADIUS
local BLEND_EDGE: number = FLAT_RADIUS + BLEND_RADIUS

------------------------------------------------------------------------------------------------------------------------------------------------
-- Tanımlar
------------------------------------------------------------------------------------------------------------------------------------------------

export type TerrainBlock = {
	cframe: CFrame?,
	size: Vector3?,
	part: Part?
}

export type ChunkInfo = {
	priority: number,
	timeout: number,
	terrainBlocks: {TerrainBlock}?
}

export type ChunkVector = {
	x: number,
	z: number,
}

export type ChunkData = {
	chunk: ChunkVector,
	info: ChunkInfo
}
export type Chunks = {[number]: {[number]: ChunkInfo}}


local CHUNKS: Chunks = {}

------------------------------------------------------------------------------------------------------------------------------------------------
-- Yardımcı Fonksiyonlar
------------------------------------------------------------------------------------------------------------------------------------------------

local function chunkExists(chunk: ChunkVector): boolean
	local chunkX: number, chunkZ: number = chunk.x, chunk.z
	
	if not CHUNKS[chunkX] then
		CHUNKS[chunkX] = {} :: {[number]: ChunkInfo}
	end
	if not CHUNKS[chunkX][chunkZ] then
		return false
	end
	CHUNKS[chunkX][chunkZ].timeout = TerrainGenerator.getChunkTimeout(CHUNKS[chunkX][chunkZ].priority)
	return true
end

local function getChunkCoordinates(position: Vector3): ChunkVector
	local chunkX: number = math.floor(position.X / CHUNK_LENGTH) * CHUNK_LENGTH + TerrainGenerator.CHUNK_RADIUS
	local chunkZ: number = math.floor(position.Z / CHUNK_LENGTH) * CHUNK_LENGTH + TerrainGenerator.CHUNK_RADIUS
	return {x = chunkX, z = chunkZ} :: ChunkVector
end

local function getPredictChunkCoordinates(humanoidRootPart: BasePart?, timeInterval: number): ChunkVector
	if not humanoidRootPart then
		return {x = 0, z = 0} :: ChunkVector
	end
	local velocity: Vector3 = humanoidRootPart.AssemblyLinearVelocity * HORIZONTAL_MASK
	if velocity.Magnitude == 0 then
		return getChunkCoordinates(humanoidRootPart.Position) :: ChunkVector
	end
	return getChunkCoordinates(humanoidRootPart.Position + velocity * timeInterval) :: ChunkVector
end

local function splitPoints2(fromChunk: ChunkVector, toChunk: ChunkVector): {ChunkVector}
    -- Hızlı erken dönüş kontrolleri
    if fromChunk.x == toChunk.x and fromChunk.z == toChunk.z then
        return {fromChunk} :: {ChunkVector}
    end
    
    if (fromChunk.x == 0 and fromChunk.z == 0) or (toChunk.x == 0 and toChunk.z == 0) then
        return {} :: {ChunkVector}
    end

    -- Önceden hesaplanmış sabitler (global scope'ta olmalı ama burada da çalışır)
    local splitSize: number = TerrainGenerator.CHUNK_RADIUS * TerrainGenerator.CHUNK_DISTANCE * 2
    local splitSizeSq: number = splitSize * splitSize
    local chunkLength: number = CHUNK_LENGTH
    local chunkRadius: number = TerrainGenerator.CHUNK_RADIUS
    
    -- Farkları hesapla (tek seferde)
    local dx: number = toChunk.x - fromChunk.x
    local dy: number = toChunk.z - fromChunk.z
    local distanceSq: number = dx * dx + dy * dy

    -- Hızlı mesafe kontrolü
    if distanceSq <= splitSizeSq then
        return {fromChunk, toChunk} :: {ChunkVector}
    end

    -- Tek karekök hesaplama
    local distance: number = math.sqrt(distanceSq)
    
    -- Yön vektörleri (normalize edilmiş)
    local dirX: number = dx / distance
    local dirY: number = dy / distance
    
    -- Adım vektörleri (önceden hesaplanmış)
    local stepX: number = dirX * splitSize
    local stepY: number = dirY * splitSize
    
    -- Adım sayısı (ceil yerine daha hızlı yöntem)
    local steps: number = math.floor((distance - 0.001) / splitSize) + 1
    
    -- Array boyutunu önceden belirle (bellek optimizasyonu)
    local points: {ChunkVector} = table.create(steps + 1)
    points[1] = fromChunk
    
    -- Ana döngü (maksimum optimize)
    local currentX: number = fromChunk.x
    local currentZ: number = fromChunk.z
    local pointIndex: number = 2
    
    for i: number = 1, steps - 1 do
        -- Sınır kontrolü (optimize edilmiş)
        local newX: number = currentX + stepX
        local newY: number = currentZ + stepY
        
        if dx > 0 and newX > toChunk.x then
            newX = toChunk.x
        elseif dx < 0 and newX < toChunk.x then
            newX = toChunk.x
        end
        
        if dy > 0 and newY > toChunk.z then
            newY = toChunk.z
        elseif dy < 0 and newY < toChunk.z then
            newY = toChunk.z
        end
        
        -- Chunk koordinatları (inline hesaplama)
        local chunkX: number = math.floor(newX / chunkLength) * chunkLength + chunkRadius
        local chunkZ: number = math.floor(newY / chunkLength) * chunkLength + chunkRadius
        
        -- Tekrarlanan nokta kontrolü (optimize edilmiş)
        local lastPoint: ChunkVector = points[pointIndex - 1]
        if lastPoint.x ~= chunkX or lastPoint.z ~= chunkZ then
            points[pointIndex] = {x = chunkX, z = chunkZ} :: ChunkVector
            pointIndex = pointIndex + 1
        end
        
        currentX = newX
        currentZ = newY
    end
    
    -- Son nokta kontrolü (optimize edilmiş)
    local lastPoint: ChunkVector = points[pointIndex - 1]
    if lastPoint.x ~= toChunk.x or lastPoint.z ~= toChunk.z then
        points[pointIndex] = toChunk
        pointIndex = pointIndex + 1
    end
    
    -- Array boyutunu düzelt (gereksiz elemanları kaldır)
    if pointIndex <= #points then
        for i: number = pointIndex, #points do
            points[i] = nil
        end
    end
    
    return points :: {ChunkVector}
end

local function splitPoints(fromChunk: ChunkVector, toChunk: ChunkVector): {ChunkVector}
    local points: {ChunkVector} = {}
    
    -- Geçersiz nokta kontrolü
    if (fromChunk.x == 0 and fromChunk.z == 0) or (toChunk.x == 0 and toChunk.z == 0) then
        return points :: {ChunkVector}
    end
    
    table.insert(points, fromChunk)  -- Başlangıç noktası

    -- Aynı noktadaysa direkt dön
    if fromChunk.x == toChunk.x and fromChunk.z == toChunk.z then
        return points :: {ChunkVector}
    end

    local splitSize: number = TerrainGenerator.CHUNK_RADIUS * TerrainGenerator.CHUNK_DISTANCE * 2
    local dx: number, dy: number = toChunk.x - fromChunk.x, toChunk.z - fromChunk.z
    local distance: number = math.sqrt(dx^2 + dy^2)  -- Öklid mesafesi

    -- splitSize'tan küçükse direkt bitiş noktasını ekle
    if distance <= splitSize then
        table.insert(points, toChunk :: ChunkVector)
        return points :: {ChunkVector}
    end

    -- Normalleştirilmiş yön vektörü (birim vektör)
    local dirX: number, dirY: number = dx/distance, dy/distance

    -- Kaç adım atılacağını hesapla (splitSize'a göre)
    local steps: number = math.ceil(distance / splitSize)

    -- Ara noktaları oluştur
    for i: number = 1, steps - 1 do
        local newX: number = fromChunk.x + dirX * splitSize * i
        local newY: number = fromChunk.z + dirY * splitSize * i

        -- Sınır kontrolü (x2/y2'yi geçmemek için)
        if (dx > 0 and newX > toChunk.x) or (dx < 0 and newX < toChunk.x) then
            newX = toChunk.x
        end
        if (dy > 0 and newY > toChunk.z) or (dy < 0 and newY < toChunk.z) then
            newY = toChunk.z
        end
        
        local newPoint = getChunkCoordinates(Vector3.new(math.floor(newX), 0, math.floor(newY))) :: ChunkVector
        
        -- Tekrarlanan nokta kontrolü
        local shouldAdd = true
        if #points > 0 then
            local lastPoint = points[#points]
            if lastPoint.x == newPoint.x and lastPoint.z == newPoint.z then
                shouldAdd = false
            end
        end
        
        if shouldAdd then
            table.insert(points, newPoint)
        end
    end

    -- Son noktayı ekle (tekrarlanan nokta kontrolü ile)
    if #points > 0 then
        local lastPoint = points[#points]
        if not (lastPoint.x == toChunk.x and lastPoint.z == toChunk.z) then
            table.insert(points, toChunk :: ChunkVector)
        end
    else
        table.insert(points, toChunk :: ChunkVector)
    end

    return points :: {ChunkVector}
end
------------------------------------------------------------------------------------------------------------------------------------------------
-- Modül Fonksiyonları
------------------------------------------------------------------------------------------------------------------------------------------------



function TerrainGenerator.getSurroundingChunks(
    playerChunk: ChunkVector,
    humanoidRootPart: BasePart?
): {ChunkData}
	if not humanoidRootPart then
		return {} :: {ChunkData}
	end

    local totalChunks: number = (2 * TerrainGenerator.CHUNK_DISTANCE + 1) ^ 2
    local surroundingChunks: {ChunkData} = table.create(totalChunks)
    local chunkSize: number = TerrainGenerator.CHUNK_RADIUS * 2
    local index: number = 1

	local playerPosition: Vector3 = humanoidRootPart.Position
	local playerVelocity: Vector3 = humanoidRootPart.AssemblyLinearVelocity * HORIZONTAL_MASK
	local speed: number = playerVelocity.Magnitude
	local direction: Vector3 = speed > 0.01 and playerVelocity.Unit or Vector3.zero

	-- Yatay pozisyon için 2D vektör
    local playerX: number = playerPosition.X
    local playerZ: number = playerPosition.Z

	local maxDistance: number = TerrainGenerator.CHUNK_RADIUS * TerrainGenerator.CHUNK_DISTANCE * 2

    for x: number = -TerrainGenerator.CHUNK_DISTANCE, TerrainGenerator.CHUNK_DISTANCE do
        for z: number = -TerrainGenerator.CHUNK_DISTANCE, TerrainGenerator.CHUNK_DISTANCE do

			local chunkCenterX: number = playerChunk.x + x * chunkSize
			local chunkCenterZ: number = playerChunk.z + z * chunkSize

			-- Mesafe hesaplama (optimize edilmiş)
			local dx: number = chunkCenterX - playerX
			local dz: number = chunkCenterZ - playerZ
			local distance: number = math.sqrt(dx*dx + dz*dz)

			local distancePriority: number = 30 * (1 - math.clamp(distance / maxDistance, 0, 1)) -- Yakın chunklar daha öncelikli

			-- Gelişmiş yön önceliği hesaplama
			local directionPriority: number = 0
            local speedPriority: number = 0

			if speed > 0.01 then
				speedPriority = math.clamp(speed / 10, 0, 30)
                
                -- Chunk'a doğru yön vektörü
                local toChunkDirection: Vector3 = Vector3.new(dx, 0, dz).Unit
                
                -- Mevcut hareket yönü ile chunk yönü arasındaki açı
                local dotProduct: number = direction:Dot(toChunkDirection)
                local angle: number = math.acos(math.clamp(dotProduct, -1, 1))
                local angleDegrees: number = math.deg(angle)
                
                -- Yön önceliği hesaplama (gelişmiş)
                if angleDegrees <= 30 then
                    -- Oyuncunun önündeki chunk'lar (yüksek öncelik)
                    directionPriority = 40 * (1 - angleDegrees / 30)
                elseif angleDegrees <= 90 then
                    -- Oyuncunun yanındaki chunk'lar (orta öncelik)
                    directionPriority = 20 * (1 - (angleDegrees - 30) / 60)
                elseif angleDegrees <= 150 then
                    -- Oyuncunun arkasındaki chunk'lar (düşük öncelik)
                    directionPriority = 10 * (1 - (angleDegrees - 90) / 60)
                else
                    -- Oyuncunun tam arkasındaki chunk'lar (çok düşük öncelik)
                    directionPriority = 5 * (1 - (angleDegrees - 150) / 30)
                end
                
                -- Hız bazlı yön değiştirme olasılığı
                local turnProbability: number = math.clamp(speed / 50, 0, 1) -- Hızlı oyuncular daha sık döner
                local turnBonus: number = 15 * turnProbability -- Dönüş bonusu
                
                -- Yakın chunk'lara dönüş bonusu
                local nearChunkBonus: number = 0
                if distance < chunkSize * 2 then -- 2 chunk mesafede
                    nearChunkBonus = 20 * (1 - distance / (chunkSize * 2))
                end
                
                directionPriority = directionPriority + turnBonus + nearChunkBonus
                directionPriority = math.clamp(directionPriority, 0, 60) -- Maksimum 60
            
			end

			local totalPriority: number = math.clamp(directionPriority + speedPriority + distancePriority - 50, -100, 100)

            surroundingChunks[index] = {
                chunk = {
                    x = chunkCenterX,
                    z = chunkCenterZ
                },
				info = {
					priority = totalPriority,
					timeout = TerrainGenerator.getChunkTimeout(totalPriority)
				}
            }
            index += 1
        end
    end

    return surroundingChunks :: {ChunkData}
end

-- Priority değerine göre timeout hesaplar
function TerrainGenerator.getChunkTimeout(priority: number): number
    -- Priority -100 ile +100 arasında, timeout MIN ile MAX arasında olmalı
    local normalizedPriority: number = (priority + 100) / 200 -- 0 ile 1 arasına normalize et
    local timeout: number = TerrainGenerator.CHUNK_TIMEOUT_MIN + 
                   (TerrainGenerator.CHUNK_TIMEOUT_MAX - TerrainGenerator.CHUNK_TIMEOUT_MIN) * normalizedPriority

    return tick() + math.clamp(timeout, TerrainGenerator.CHUNK_TIMEOUT_MIN, TerrainGenerator.CHUNK_TIMEOUT_MAX)
end

function TerrainGenerator.GenerateChunks(humanoidRootPart: BasePart?, timeInterval: number): Chunks
	local chunks: Chunks = {}

	if not humanoidRootPart then
		return chunks :: Chunks
	end

	-- Oyuncunun chunk pozisyonunu hesapla
	local playerChunk: ChunkVector = getChunkCoordinates(humanoidRootPart.Position)

	if playerChunk.x == 0 and playerChunk.z == 0 then
		return chunks :: Chunks
	end
	
	local predictedChunk: ChunkVector = getPredictChunkCoordinates(humanoidRootPart, timeInterval)

	if predictedChunk.x == 0 and predictedChunk.z == 0 then
		return chunks :: Chunks
	end

	local testSplitedPoints: {ChunkVector} = splitPoints2(playerChunk, predictedChunk)
	
	local splitedPoints: {ChunkVector} = splitPoints(playerChunk, predictedChunk)
	if #splitedPoints == 0 then
		return chunks :: Chunks
	end

	for _: number, chunk: ChunkVector in ipairs(splitedPoints) do
		local surroundingChunks: {ChunkData} = TerrainGenerator.getSurroundingChunks(chunk, humanoidRootPart)
		for _: number, chunkData: ChunkData in ipairs(surroundingChunks) do
			if not chunks[chunkData.chunk.x] then
				chunks[chunkData.chunk.x] = {}
			end
			if not chunks[chunkData.chunk.x][chunkData.chunk.z] then
				chunks[chunkData.chunk.x][chunkData.chunk.z] = chunkData.info
			elseif chunkData.info.priority > chunks[chunkData.chunk.x][chunkData.chunk.z].priority then
				chunks[chunkData.chunk.x][chunkData.chunk.z] = chunkData.info
			end
		end
	end

	return chunks :: Chunks
end

-- Birden fazla chunks'ı birleştiren fonksiyon
function TerrainGenerator.MergeChunks(...: Chunks): Chunks
	local mergedChunks: Chunks = {}
	local chunksList: {Chunks} = {...}

	if #chunksList == 0 then
		return mergedChunks :: Chunks
	end
	
	-- Her chunks setini işle
	for _: number, chunks: Chunks in ipairs(chunksList) do
		-- Her X koordinatını kontrol et
		for chunkX: number, zChunks: {[number]: ChunkInfo} in pairs(chunks) do
			-- X koordinatı için array oluştur
			if not mergedChunks[chunkX] then
				mergedChunks[chunkX] = {}
			end
			
			-- Her Z koordinatını kontrol et
			for chunkZ: number, chunkInfo: ChunkInfo in pairs(zChunks) do
				-- Chunk yoksa ekle, varsa priority'ye göre karşılaştır
				if not mergedChunks[chunkX][chunkZ] then
					mergedChunks[chunkX][chunkZ] = chunkInfo
				elseif chunkInfo.priority > mergedChunks[chunkX][chunkZ].priority then
					-- Daha yüksek priority varsa güncelle
					mergedChunks[chunkX][chunkZ] = chunkInfo
				end
			end
		end
	end
	
	return mergedChunks :: Chunks
end


function TerrainGenerator.RemoveTimeoutChunks()
	for chunkX: number, zChunks: {[number]: ChunkInfo} in pairs(CHUNKS) do
		for chunkZ: number, chunkInfo: ChunkInfo in pairs(zChunks) do
			if chunkInfo.timeout < tick() then
				if chunkInfo.terrainBlocks then
					for _: number, block: TerrainBlock in pairs(chunkInfo.terrainBlocks) do
						if block.part then
							block.part:Destroy()
							block.part = nil
						elseif block.cframe and block.size then
							workspace.Terrain:FillBlock(block.cframe, block.size, Enum.Material.Air)
						end
					end
				end
				CHUNKS[chunkX][chunkZ] = nil
			end
		end
		if next(CHUNKS[chunkX]) == nil then
			CHUNKS[chunkX] = nil
		end
	end
end
function TerrainGenerator.generateGround(chunks: Chunks)
	-- Terrain generation sabitleri

	local function mountLayer(x: number, heightY: number, z: number, material: Enum.Material): (CFrame?, Vector3?)
		local beginY: number = heightY - TerrainGenerator.SURFACE_HEIGHT
		local endY: number = heightY
		local cframe: CFrame = CFrame.new(x + VOXEL_HALF, (beginY + endY) * VOXEL_HALF, z + VOXEL_HALF)
		local size: Vector3 = Vector3.new(TerrainGenerator.VOXEL_SIZE, (endY - beginY) * TerrainGenerator.VOXEL_SIZE, TerrainGenerator.VOXEL_SIZE)
		workspace.Terrain:FillBlock(cframe, size, material)
		return cframe, size
	end
	

	-- Her chunk için terrain oluştur
	for chunkX: number, zChunks: {[number]: ChunkInfo} in pairs(chunks) do
		for chunkZ: number, chunkInfo: ChunkInfo in pairs(zChunks) do
			if chunkExists({x = chunkX, z = chunkZ}) then
				continue
			end
			
			-- Chunk merkezi koordinatları
			local chunkCenterX: number = chunkX
			local chunkCenterZ: number = chunkZ
			
			-- Chunk için tek bir terrain block oluştur
			local terrainBlocks: {TerrainBlock} = {}
			
			-- Chunk'ın sınırlarını hesapla (merkezden CHUNK_RADIUS kadar)
			local startX: number = chunkCenterX - TerrainGenerator.CHUNK_RADIUS
			local endX: number = chunkCenterX + TerrainGenerator.CHUNK_RADIUS
			local startZ: number = chunkCenterZ - TerrainGenerator.CHUNK_RADIUS
			local endZ: number = chunkCenterZ + TerrainGenerator.CHUNK_RADIUS
			
			-- Chunk içindeki her voxel için terrain oluştur
			for x: number = startX, endX, TerrainGenerator.VOXEL_SIZE do
				for z: number = startZ, endZ, TerrainGenerator.VOXEL_SIZE do
					local cy: number = TerrainGenerator.MIN_HEIGHT
					local cframe: CFrame?, size: Vector3? = mountLayer(x, cy, z, TerrainGenerator.TERRAIN_TYPE)
					
					if cframe and size then
						table.insert(terrainBlocks, { cframe = cframe, size = size })
					end
				
				end
			end
			
			-- Chunk'ı kaydet
			chunkInfo.terrainBlocks = terrainBlocks
			CHUNKS[chunkX][chunkZ] = chunkInfo
		end
	end
end


-- Tüm chunk'ları temizle
function TerrainGenerator.ClearAllChunks(): ()
	for chunkX: number, chunkZData: {[number]: ChunkInfo} in pairs(CHUNKS) do
		for chunkZ: number, chunkInfo: ChunkInfo in pairs(chunkZData) do
			if chunkInfo.terrainBlocks then
				for _: number, block: TerrainBlock in pairs(chunkInfo.terrainBlocks) do
					if block.part then
						block.part:Destroy()
						block.part = nil
					elseif block.cframe and block.size then
						workspace.Terrain:FillBlock(block.cframe, block.size, Enum.Material.Air)
					end
				end
			end
			CHUNKS[chunkX][chunkZ] = nil
		end
		if next(CHUNKS[chunkX]) == nil then
			CHUNKS[chunkX] = nil
		end
	end
	
	CHUNKS = {}
end

------------------------------------------------------------------------------------------------------------------------------------------------
-- Debug Fonksiyonları
------------------------------------------------------------------------------------------------------------------------------------------------

-- splitPoints ve splitPoints2 fonksiyonlarını test eder
function TerrainGenerator.testSplitPointsAlgorithms()
    print("=== SplitPoints Algoritmaları Testi ===")
    
    -- Test senaryoları
    local testCases = {
        
        {
            name = "Uzun Mesafe Test",
            from = {x = 40, z = 40},
            to = {x = 400, z = 400}
        },
        {
            name = "Yatay Çizgi Test",
            from = {x = 40, z = 40},
            to = {x = 200, z = 40}
        },
        {
            name = "Dikey Çizgi Test",
            from = {x = 40, z = 40},
            to = {x = 40, z = 200}
        },
        {
            name = "Çapraz Uzun Test",
            from = {x = 40, z = 40},
            to = {x = 600, z = 600}
        },
        {
            name = "Aynı Nokta Test",
            from = {x = 40, z = 40},
            to = {x = 40, z = 40}
        },
        {
            name = "Kısa Mesafe Test",
            from = {x = 40, z = 40},
            to = {x = 80, z = 80}
        },
    }
    
    local TEST_ITERATIONS = 100 -- Her fonksiyonu 100 kez test et
    
    -- Genel istatistikler için değişkenler
    local totalOptimizedWins = 0
    local totalNormalWins = 0
    local totalOptimizedTime = 0
    local totalNormalTime = 0
    local totalTests = 0
    
    for _, testCase in ipairs(testCases) do
        print("\n--- " .. testCase.name .. " ---")
        
        local fromChunk: ChunkVector = testCase.from
        local toChunk: ChunkVector = testCase.to
        
        -- Performans ölçümü için değişkenler
        local optimizedTimes: {number} = {}
        local normalTimes: {number} = {}
        local optimizedResults: {ChunkVector} = {}
        local normalResults: {ChunkVector} = {}
        
        -- 100 kez sırayla test et
        for i = 1, TEST_ITERATIONS do
            -- splitPoints2 testi
            local startTime = tick()
            local optimizedResult = splitPoints2(fromChunk, toChunk)
            local optimizedTime = tick() - startTime
            table.insert(optimizedTimes, optimizedTime)
            if i == 1 then -- İlk sonucu sakla
                optimizedResults = optimizedResult
            end
            
            -- splitPoints testi
            startTime = tick()
            local normalResult = splitPoints(fromChunk, toChunk)
            local normalTime = tick() - startTime
            table.insert(normalTimes, normalTime)
            if i == 1 then -- İlk sonucu sakla
                normalResults = normalResult
            end
        end
        
        -- Ortalama süreleri hesapla
        local optimizedTotal = 0
        local normalTotal = 0
        
        for _, time in ipairs(optimizedTimes) do
            optimizedTotal = optimizedTotal + time
        end
        
        for _, time in ipairs(normalTimes) do
            normalTotal = normalTotal + time
        end
        
        local optimizedAvg = optimizedTotal / TEST_ITERATIONS
        local normalAvg = normalTotal / TEST_ITERATIONS
        
        -- Genel istatistiklere ekle
        totalOptimizedTime = totalOptimizedTime + optimizedAvg
        totalNormalTime = totalNormalTime + normalAvg
        totalTests = totalTests + 1
        
        if optimizedAvg < normalAvg then
            totalOptimizedWins = totalOptimizedWins + 1
        else
            totalNormalWins = totalNormalWins + 1
        end
        
        -- Sonuçları yazdır
        print("Optimize Edilmiş Algoritma (splitPoints2):")
        print("  Ortalama Süre: " .. string.format("%.8f", optimizedAvg) .. " saniye")
        print("  Toplam Süre: " .. string.format("%.6f", optimizedTotal) .. " saniye")
        print("  Nokta Sayısı: " .. #optimizedResults)
        print("  Noktalar: " .. TerrainGenerator.pointsToString(optimizedResults))
        
        print("Normal Algoritma (splitPoints):")
        print("  Ortalama Süre: " .. string.format("%.8f", normalAvg) .. " saniye")
        print("  Toplam Süre: " .. string.format("%.6f", normalTotal) .. " saniye")
        print("  Nokta Sayısı: " .. #normalResults)
        print("  Noktalar: " .. TerrainGenerator.pointsToString(normalResults))
        
        -- Performans karşılaştırması
        if optimizedAvg < normalAvg then
            local speedup = normalAvg / optimizedAvg
            print("  Optimize " .. string.format("%.2f", speedup) .. "x daha hızlı")
        else
            local slowdown = optimizedAvg / normalAvg
            print("  Normal " .. string.format("%.2f", slowdown) .. "x daha hızlı")
        end
        
        -- Nokta sayısı karşılaştırması
        local pointDiff = math.abs(#optimizedResults - #normalResults)
        if pointDiff > 0 then
            print("  Nokta sayısı farkı: " .. pointDiff)
        else
            print("  Aynı nokta sayısı")
        end
        
        -- En hızlı ve en yavaş süreleri göster
        local optimizedMin = math.min(table.unpack(optimizedTimes))
        local optimizedMax = math.max(table.unpack(optimizedTimes))
        local normalMin = math.min(table.unpack(normalTimes))
        local normalMax = math.max(table.unpack(normalTimes))
        
        print("  Optimize Min/Max: " .. string.format("%.8f", optimizedMin) .. "/" .. string.format("%.8f", optimizedMax))
        print("  Normal Min/Max: " .. string.format("%.8f", normalMin) .. "/" .. string.format("%.8f", normalMax))
    end
    
    -- Genel performans özeti
    print("\n" .. string.rep("=", 60))
    print("=== GENEL PERFORMANS ÖZETİ ===")
    print(string.rep("=", 60))
    
    local overallOptimizedAvg = totalOptimizedTime / totalTests
    local overallNormalAvg = totalNormalTime / totalTests
    
    print("Toplam Test Senaryosu: " .. totalTests)
    print("Optimize Edilmiş Algoritma (splitPoints2):")
    print("  Genel Ortalama: " .. string.format("%.8f", overallOptimizedAvg) .. " saniye")
    print("  Kazanan Test Sayısı: " .. totalOptimizedWins .. "/" .. totalTests)
    
    print("Normal Algoritma (splitPoints):")
    print("  Genel Ortalama: " .. string.format("%.8f", overallNormalAvg) .. " saniye")
    print("  Kazanan Test Sayısı: " .. totalNormalWins .. "/" .. totalTests)
    
    -- Genel karşılaştırma
    if overallOptimizedAvg < overallNormalAvg then
        local overallSpeedup = overallNormalAvg / overallOptimizedAvg
        print("\n🏆 SONUÇ: Optimize Edilmiş Algoritma (splitPoints2) genel olarak " .. string.format("%.2f", overallSpeedup) .. "x daha hızlı!")
    else
        local overallSlowdown = overallOptimizedAvg / overallNormalAvg
        print("\n🏆 SONUÇ: Normal Algoritma (splitPoints) genel olarak " .. string.format("%.2f", overallSlowdown) .. "x daha hızlı!")
    end
    
    print("\n=== Test Tamamlandı ===")
end 

-- Nokta listesini string'e çeviren yardımcı fonksiyon
function TerrainGenerator.pointsToString(points: {ChunkVector}): string
    if #points == 0 then
        return "[]"
    end
    
    local result = "["
    for i, point in ipairs(points) do
        result = result .. "(" .. point.x .. "," .. point.z .. ")"
        if i < #points then
            result = result .. ", "
        end
    end
    result = result .. "]"
    return result
end

function TerrainGenerator.visualizeChunks( chunks: Chunks)

    -- Her chunk için küp oluştur
    for chunkX: number, zChunks: {[number]: ChunkInfo} in pairs(chunks) do
		for chunkZ: number, chunkInfo: ChunkInfo in pairs(zChunks) do
			local lastChunkInfo: ChunkInfo = nil

			if not chunkExists({x = chunkX, z = chunkZ}) then
				lastChunkInfo = CHUNKS[chunkX][chunkZ]

				local part: Part = Instance.new("Part")
				part.Name = "ChunkVisualizer"
				part.Anchored = true
				part.CanCollide = false
				part.Size = Vector3.new(TerrainGenerator.CHUNK_RADIUS * 2, 1, TerrainGenerator.CHUNK_RADIUS * 2)
				part.Position = Vector3.new(chunkX + TerrainGenerator.CHUNK_RADIUS, 0, chunkZ + TerrainGenerator.CHUNK_RADIUS)
				part.Transparency = 0.5
				part.Parent = workspace

				-- Debug bilgisi (sadece chunk merkezinde)
				local gui: BillboardGui = Instance.new("BillboardGui")
				gui.Size = UDim2.new(0, 200, 0, 50)
				gui.StudsOffset = Vector3.new(0, 2, 0)
				
				local label: TextLabel = Instance.new("TextLabel")
				label.Size = UDim2.new(1, 0, 1, 0)
				label.BackgroundTransparency = 1
				label.Text = string.format("[%d,%d]\nPrio: %.1f\nTimeout: %.1f", chunkX, chunkZ, chunkInfo.priority, chunkInfo.timeout)
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextStrokeTransparency = 0
				label.Parent = gui
				gui.Parent = part


				chunkInfo.terrainBlocks = {
					{part = part}
				}

				CHUNKS[chunkX][chunkZ] = chunkInfo

			end

			if not lastChunkInfo then
				lastChunkInfo = CHUNKS[chunkX][chunkZ]
			end
			if lastChunkInfo.terrainBlocks then
				local part: Part = lastChunkInfo.terrainBlocks[1].part :: Part
				
				-- Priority'ye göre renk belirle (-100: kırmızı, 0: sarı, +100: yeşil)
				if chunkInfo.priority < 0 then
					part.Color = Color3.new(1, 0, 0):Lerp(Color3.new(1, 1, 0), math.clamp(-chunkInfo.priority / 100, 0, 1)) -- Kırmızı -> Sarı
				else
					part.Color = Color3.new(1, 1, 0):Lerp(Color3.new(0, 1, 0), math.clamp(chunkInfo.priority / 100, 0, 1)) -- Sarı -> Yeşil
				end
				
				
				-- Debug bilgisi (sadece chunk merkezinde)
				local gui: BillboardGui = part:FindFirstChild("BillboardGui") :: BillboardGui
				
				local label: TextLabel = gui:FindFirstChild("TextLabel") :: TextLabel
				label.Text = string.format("[%d,%d]\nPrio: %.1f\nTimeout: %.1f", chunkX, chunkZ, chunkInfo.priority, chunkInfo.timeout)

			end
		end
	end
end

return TerrainGenerator