--!optimize 2
--!strict
--!native


local TerrainGenerator = {
	CHUNK_RADIUS = 5,
	CHUNK_DISTANCE = 5,
	CHUNK_TIMEOUT_MAX = 20,
	CHUNK_TIMEOUT_MIN = 3,
	SURFACE_HEIGHT = 3,
	RARITY_POWER = 1,
	MIN_HEIGHT = 0,
	MAX_HEIGHT = 50,
	VOXEL_SIZE = 4,
	TERRAIN_TYPE = Enum.Material.Glacier
}

local Players: Players = game:GetService("Players")

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
local X_SCALE: number = 300
local Z_SCALE: number = 300
local NOISE_OFFSET: number = 0.5


-- Modül durumu
local isRunning: boolean = false
local connection: thread? = nil
local isProcessing: boolean = false


------------------------------------------------------------------------------------------------------------------------------------------------
-- Debug Parametreleri
------------------------------------------------------------------------------------------------------------------------------------------------
local visualize = false


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

-- Priority değerine göre timeout hesaplar
local function getChunkTimeout(priority: number): number
    -- Priority -100 ile +100 arasında, timeout MIN ile MAX arasında olmalı
    local normalizedPriority: number = (priority + 100) / 200 -- 0 ile 1 arasına normalize et
    local timeout: number = TerrainGenerator.CHUNK_TIMEOUT_MIN + 
                   (TerrainGenerator.CHUNK_TIMEOUT_MAX - TerrainGenerator.CHUNK_TIMEOUT_MIN) * normalizedPriority

    return (tick() + math.clamp(timeout, TerrainGenerator.CHUNK_TIMEOUT_MIN, TerrainGenerator.CHUNK_TIMEOUT_MAX)) :: number
end

local function chunkExists(chunk: ChunkVector): boolean
	local chunkX: number, chunkZ: number = chunk.x, chunk.z
	
	if not CHUNKS[chunkX] then
		CHUNKS[chunkX] = {} :: {[number]: ChunkInfo}
	end
	if not CHUNKS[chunkX][chunkZ] then
		return false
	end
	CHUNKS[chunkX][chunkZ].timeout = getChunkTimeout(CHUNKS[chunkX][chunkZ].priority)
	return true
end

local function getChunkCoordinates(position: Vector3): ChunkVector
	local chunkX: number = math.floor(position.X / CHUNK_LENGTH) * CHUNK_LENGTH + TerrainGenerator.CHUNK_RADIUS
	local chunkZ: number = math.floor(position.Z / CHUNK_LENGTH) * CHUNK_LENGTH + TerrainGenerator.CHUNK_RADIUS
	return {x = chunkX, z = chunkZ} :: ChunkVector
end

local function getPredictChunkCoordinates(humanoidRootPart: BasePart, timeInterval: number): ChunkVector
	local velocity: Vector3 = humanoidRootPart.AssemblyLinearVelocity * HORIZONTAL_MASK
	if velocity.Magnitude == 0 then
		return getChunkCoordinates(humanoidRootPart.Position) :: ChunkVector
	end
	return getChunkCoordinates(humanoidRootPart.Position + velocity * timeInterval) :: ChunkVector
end

local function splitPoints(fromChunk: ChunkVector, toChunk: ChunkVector): {ChunkVector}
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


local function getSurroundingChunks(
    playerChunk: ChunkVector,
    humanoidRootPart: BasePart
): {ChunkData}

    -- Ultra optimize sabitler (inline)
    local surroundingChunks: {ChunkData} = table.create((2 * TerrainGenerator.CHUNK_DISTANCE + 1) ^ 2)
    local chunkSize: number = TerrainGenerator.CHUNK_RADIUS * 2
    local maxDistance: number = TerrainGenerator.CHUNK_RADIUS * TerrainGenerator.CHUNK_DISTANCE * 2
    local timeoutMin: number = TerrainGenerator.CHUNK_TIMEOUT_MIN
    local timeoutMax: number = TerrainGenerator.CHUNK_TIMEOUT_MAX
    local timeoutRange: number = timeoutMax - timeoutMin
    local currentTime: number = tick()
    local chunkDistance: number = TerrainGenerator.CHUNK_DISTANCE

	local playerPosition: Vector3 = humanoidRootPart.Position
	local playerVelocity: Vector3 = humanoidRootPart.AssemblyLinearVelocity * HORIZONTAL_MASK
	local speed: number = playerVelocity.Magnitude
    local playerX: number = playerPosition.X
    local playerZ: number = playerPosition.Z

    local index: number = 1

    -- Hız kontrolü (inline)
    if speed <= 0.01 then
        -- Ultra basit hız 0 hesaplama
        for x: number = -chunkDistance, chunkDistance do
            local chunkCenterX: number = playerChunk.x + x * chunkSize
            local dx: number = chunkCenterX - playerX
            local dxSq: number = dx * dx
            
            for z: number = -chunkDistance, chunkDistance do
                local chunkCenterZ: number = playerChunk.z + z * chunkSize
                local dz: number = chunkCenterZ - playerZ
                local distance: number = math.sqrt(dxSq + dz * dz)
                local totalPriority: number = math.clamp(30 * (1 - math.clamp(distance * maxDistance, 0, 1)) - 50, -100, 100)

                surroundingChunks[index] = {
                    chunk = {x = chunkCenterX, z = chunkCenterZ},
                    info = {
                        priority = totalPriority,
                        timeout = currentTime + math.clamp(timeoutMin + timeoutRange * ((totalPriority + 100) / 200), timeoutMin, timeoutMax)
                    }
                }
                index += 1
            end
        end
    else
        -- Ultra optimize hız hesaplama
        local speedPriority: number = math.clamp(speed / 10, 0, 30)
        local direction: Vector3 = playerVelocity.Unit
        local speedRatio: number = speed / 50
        local turnBonus: number = 15 * math.clamp(speedRatio, 0, 1)
        local nearChunkThreshold: number = chunkSize * 2
        
        -- Direction vektörlerini önceden hesapla
        local dirX: number = direction.X
        local dirZ: number = direction.Z
        
        for x: number = -chunkDistance, chunkDistance do
            local chunkCenterX: number = playerChunk.x + x * chunkSize
            local dx: number = chunkCenterX - playerX
            local dxSq: number = dx * dx
            
            for z: number = -chunkDistance, chunkDistance do
                local chunkCenterZ: number = playerChunk.z + z * chunkSize
                local dz: number = chunkCenterZ - playerZ
                local dzSq: number = dz * dz
                
                -- Inline mesafe hesaplama
                local distance: number = math.sqrt(dxSq + dzSq)
                local distancePriority: number = 30 * (1 - math.clamp(distance * maxDistance, 0, 1))

                -- Ultra optimize yön hesaplama (Vector3 oluşturmadan)
                local dotProduct: number = (dirX * dx + dirZ * dz) * distance
                local angleDegrees: number = math.deg(math.acos(math.clamp(dotProduct, -1, 1)))
                local directionPriority: number = 0
                
                -- Inline açı hesaplama
                if angleDegrees <= 30 then
                    directionPriority = 40 * (1 - angleDegrees / 30)
                elseif angleDegrees <= 90 then
                    directionPriority = 20 * (1 - (angleDegrees - 30) / 60)
                elseif angleDegrees <= 150 then
                    directionPriority = 10 * (1 - (angleDegrees - 90) / 60)
                else
                    directionPriority = 5 * (1 - (angleDegrees - 150) / 30)
                end
                
                -- Inline yakın chunk bonusu
                if distance < nearChunkThreshold then
                    directionPriority = directionPriority + 20 * (1 - distance * nearChunkThreshold)
                end
                
                directionPriority = math.clamp(directionPriority + turnBonus, 0, 60)
                local totalPriority: number = math.clamp(directionPriority + speedPriority + distancePriority - 50, -100, 100)

                surroundingChunks[index] = {
                    chunk = {x = chunkCenterX, z = chunkCenterZ},
                    info = {
                        priority = totalPriority,
                        timeout = currentTime + math.clamp(timeoutMin + timeoutRange * ((totalPriority + 100) / 200), timeoutMin, timeoutMax)
                    }
                }
                index += 1
            end
        end
    end

    return surroundingChunks :: {ChunkData}
end

local function mountLayer(x: number, heightY: number, z: number, material: Enum.Material): (CFrame, Vector3)
    local beginY: number = heightY - TerrainGenerator.SURFACE_HEIGHT
    local endY: number = heightY
    local cframe: CFrame = CFrame.new(x + VOXEL_HALF, (beginY + endY) * VOXEL_HALF, z + VOXEL_HALF)
    local size: Vector3 = Vector3.new(TerrainGenerator.VOXEL_SIZE, (endY - beginY) * TerrainGenerator.VOXEL_SIZE, TerrainGenerator.VOXEL_SIZE)
    workspace.Terrain:FillBlock(cframe, size, material)
    return cframe, size
end


local function generateGround(chunks: Chunks): ()
	-- Terrain generation sabitleri

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
				local cxScale: number = x / X_SCALE
		
				for z: number = startZ, endZ, TerrainGenerator.VOXEL_SIZE do

					local czScale: number = z / Z_SCALE

					local noise: number = math.noise(GENERATION_SEED, cxScale, czScale)
					local normalizedNoise: number = (noise + 1) * NOISE_OFFSET
					local rarityFactor: number = normalizedNoise
					for i: number = 2, TerrainGenerator.RARITY_POWER do
						rarityFactor = rarityFactor * normalizedNoise
					end
					
					-- MAX_HEIGHT'yi aşabilen ama clamp ile sınırlanan yükseklik
					local maxPossibleHeight: number = TerrainGenerator.MAX_HEIGHT * 1.5  -- MAX_HEIGHT'nin %50 fazlası
					local heightOffset: number = rarityFactor * (maxPossibleHeight - TerrainGenerator.MIN_HEIGHT)
					local rawHeight: number = TerrainGenerator.MIN_HEIGHT + heightOffset
					local cy: number = math.clamp(rawHeight, TerrainGenerator.MIN_HEIGHT, TerrainGenerator.MAX_HEIGHT)
					
					local cframe: CFrame, size: Vector3 = mountLayer(x, cy, z, TerrainGenerator.TERRAIN_TYPE)
					
					table.insert(terrainBlocks, { cframe = cframe, size = size })
				
				end
			end
			
			-- Chunk'ı kaydet
			chunkInfo.terrainBlocks = terrainBlocks
			CHUNKS[chunkX][chunkZ] = chunkInfo
		end
	end
end

local function GenerateChunks(humanoidRootPart: BasePart, timeInterval: number): Chunks
	local chunks: Chunks = {}

	-- Oyuncunun chunk pozisyonunu hesapla
	local playerChunk: ChunkVector = getChunkCoordinates(humanoidRootPart.Position)

	if playerChunk.x == 0 and playerChunk.z == 0 then
		return chunks :: Chunks
	end
	
	local predictedChunk: ChunkVector = getPredictChunkCoordinates(humanoidRootPart, timeInterval)

	if predictedChunk.x == 0 and predictedChunk.z == 0 then
		return chunks :: Chunks
	end

	local splitedPoints: {ChunkVector} = splitPoints(playerChunk, predictedChunk)
	if #splitedPoints == 0 then
		return chunks :: Chunks
	end

	for _: number, chunk: ChunkVector in ipairs(splitedPoints) do
		local surroundingChunks: {ChunkData} = getSurroundingChunks(chunk, humanoidRootPart)

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
local function MergeChunks(...: Chunks): Chunks
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

local function RemoveTimeoutChunks(): ()
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
------------------------------------------------------------------------------------------------------------------------------------------------
-- Modül Fonksiyonları
------------------------------------------------------------------------------------------------------------------------------------------------



-- Tüm chunk'ları temizle
function TerrainGenerator.ClearAllChunks(): ()
	while isProcessing do
		task.wait(0.1)
	end

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
function TerrainGenerator.Calculate(): ()
	while isRunning do
		isProcessing = true
		
		-- Hata kontrolü için pcall kullan
		local success, errorMessage = pcall(function()
			local players: {Player} = Players:GetPlayers()

			local playerChunks: {Chunks} = {}
			
			for i: number = 1, #players do
				local player: Player = players[i]
				if player.Character then
					local humanoidRootPart: BasePart? = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if humanoidRootPart then
						local humanoid: Humanoid? = player.Character:FindFirstChild("Humanoid") :: Humanoid?
						if humanoid then
							humanoid.WalkSpeed = 100
						end
						table.insert(playerChunks, GenerateChunks(humanoidRootPart, 1.0))
					end
				end
			end
			local chunks: Chunks = MergeChunks(table.unpack(playerChunks))
			
			if visualize then
				TerrainGenerator.visualizeChunks(chunks)
			else
				generateGround(chunks)
			end

			RemoveTimeoutChunks()
		end)
		
		-- Hata kontrolü
		if not success then
			warn("TerrainGenerator hatası:", errorMessage)
			isProcessing = false
			TerrainGenerator.Stop()
			TerrainGenerator.ClearAllChunks()
			return
		end
		
		isProcessing = false
		task.wait(1)
	end
	isProcessing = false
end

function TerrainGenerator.Start(): ()
	if isRunning then
		warn("TerrainGenerator zaten çalışıyor!")
		return
	end

	isRunning = true
	connection = task.spawn(TerrainGenerator.Calculate)

end

function TerrainGenerator.Stop(): ()
	if not isRunning then
		warn("TerrainGenerator zaten durdurulmuş!")
		return
	end

	isRunning = false
	if connection then
		task.cancel(connection)
		isProcessing = false
	end
	connection = nil
end
------------------------------------------------------------------------------------------------------------------------------------------------
-- Debug Fonksiyonları
------------------------------------------------------------------------------------------------------------------------------------------------

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


function TerrainGenerator.runPerformanceTest()
    task.wait(5)
    
end

return TerrainGenerator