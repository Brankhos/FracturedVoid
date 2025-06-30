--!strict

local Players = game:GetService("Players")

------------------------------------------------------------------------------------------------------------------------------------------------

local TerrainGenerator = {
	HORIZONTAL_MASK = Vector3.new(1, 0, 1)
}

-- Sabitler
local CHUNK_TIMEOUT: number = 10
local CHUNK_SCALE: number = 20
local RENDER_DISTANCE: number = 50
local X_SCALE: number = 90
local Z_SCALE: number = 90
local GENERATION_SEED: number = math.random()
local TERRAIN_TYPE: Enum.Material = Enum.Material.Glacier

-- Yükseklik sınırları
local SURFACE_HEIGHT: number = 3

-- Yükseklik-nadirlik sistemi
local MIN_HEIGHT: number = 0
local MAX_HEIGHT: number = 50
local HEIGHT_RANGE: number = MAX_HEIGHT - MIN_HEIGHT
local RARITY_POWER: number = 1

-- Önbelleklenmiş sabitler 
local CHUNK_SIZE: number = 4 * CHUNK_SCALE
local CHUNK_SIZE_INV: number = 1 / CHUNK_SIZE
local RENDER_RANGE: number = math.max(1, RENDER_DISTANCE / CHUNK_SCALE)
local VOXEL_SIZE: number = 4
local VOXEL_HALF: number = VOXEL_SIZE / 2

-- Optimizasyon sabitleri
local X_SCALE_INV: number = 1 / X_SCALE
local Z_SCALE_INV: number = 1 / Z_SCALE
local NOISE_OFFSET: number = 0.5
local PRIORITY_MULTIPLIER: number = 50
local MAX_PRIORITY: number = 100
local MIN_PRIORITY: number = -100

-- Flat ve blend zone için sabitler
local FLAT_RADIUS: number = 24
local BLEND_RADIUS: number = 75
local FLAT_RADIUS_SQ: number = FLAT_RADIUS * FLAT_RADIUS
local BLEND_EDGE: number = FLAT_RADIUS + BLEND_RADIUS

------------------------------------------------------------------------------------------------------------------------------------------------

-- Type definitions
type ChunkData = {
	removeAt: number,
	terrainBlocks: {{
		cframe: CFrame,
		size: Vector3
	}}
}

export type ChunkRequest = {
	x: number,
	z: number,
	priority: number
}

local CHUNKS: {[number]: {[number]: ChunkData}} = {}

-- Modül durumu
local isRunning: boolean = false
local connection: thread? = nil

------------------------------------------------------------------------------------------------------------------------------------------------

-- Yardımcı fonksiyonlar
local function smootherstep(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function chunkExists(chunkX: number, chunkZ: number): boolean
	chunkX = math.floor(chunkX)
	chunkZ = math.floor(chunkZ)
	
	if not CHUNKS[chunkX] then
		CHUNKS[chunkX] = {}
	end
	if not CHUNKS[chunkX][chunkZ] then
		return false
	end
	CHUNKS[chunkX][chunkZ].removeAt = tick() + CHUNK_TIMEOUT
	return true
end

local function calculatePriority(distance: number, playerSpeed: number, maxDistance: number): number
	local distanceFactor: number = math.min(distance / maxDistance, 1)
	local speedFactor: number = math.min(playerSpeed / 100, 1)
	
	local distancePriority: number = (1 - distanceFactor) * PRIORITY_MULTIPLIER
	local speedPriority: number = speedFactor * PRIORITY_MULTIPLIER
	
	local totalPriority: number = distancePriority + speedPriority
	
	return math.max(MIN_PRIORITY, math.min(MAX_PRIORITY, totalPriority))
end

local function getChunkCoordinates(position: Vector3): (number, number)
	local chunkX: number = math.floor(position.X * CHUNK_SIZE_INV)
	local chunkZ: number = math.floor(position.Z * CHUNK_SIZE_INV)
	return math.floor(chunkX), math.floor(chunkZ)
end

local function getChunkDistanceSquared(chunkX: number, chunkZ: number, playerChunkX: number, playerChunkZ: number): number
	local dx: number = chunkX - playerChunkX
	local dz: number = chunkZ - playerChunkZ
	return dx * dx + dz * dz
end

local function getChunkDistance(chunkX: number, chunkZ: number, playerChunkX: number, playerChunkZ: number): number
	return math.sqrt(getChunkDistanceSquared(chunkX, chunkZ, playerChunkX, playerChunkZ))
end

local function createChunkKey(x: number, z: number): number
	return x * 1000000 + z
end

function TerrainGenerator.predictPlayerPosition(character: Model): Vector3?
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not (humanoidRootPart :: BasePart) then return nil end
	local humanoidRootPartTyped = humanoidRootPart :: BasePart
	
	if not character.PrimaryPart or not (character.PrimaryPart :: BasePart) then return nil end
	local primaryPart = character.PrimaryPart :: BasePart
	
	local velocity: Vector3 = primaryPart.AssemblyLinearVelocity * TerrainGenerator.HORIZONTAL_MASK
	
	return humanoidRootPartTyped.Position + velocity
end

function TerrainGenerator.checkSurroundings(location: Vector3, playerSpeed: number): {ChunkRequest}
	local chunkX: number, chunkZ: number = getChunkCoordinates(location)
	local maxDistance: number = RENDER_RANGE * 2
	
	local totalChunks: number = (RENDER_RANGE * 2 + 1) * (RENDER_RANGE * 2 + 1)
	local chunk: {ChunkRequest} = table.create(totalChunks)
	local chunkIndex: number = 0
	
	for x: number = -RENDER_RANGE, RENDER_RANGE do
		for z: number = -RENDER_RANGE, RENDER_RANGE do
			local cx: number = chunkX + x
			local cz: number = chunkZ + z
			
			local distanceSq: number = getChunkDistanceSquared(cx, cz, chunkX, chunkZ)
			local distance: number = math.sqrt(distanceSq)
			local priority: number = calculatePriority(distance, playerSpeed, maxDistance)
			
			chunkIndex = chunkIndex + 1
			chunk[chunkIndex] = {x = cx, z = cz, priority = priority}
		end
	end
	
	return chunk
end

-- İki nokta arasında düz hat boyunca chunk'ları oluştur (optimize edilmiş)
function TerrainGenerator.generatePathBetweenPoints(startPos: Vector3, endPos: Vector3, playerSpeed: number): {ChunkRequest}
	local startChunkX: number, startChunkZ: number = getChunkCoordinates(startPos)
	local endChunkX: number, endChunkZ: number = getChunkCoordinates(endPos)
	
	local dx: number = math.abs(endChunkX - startChunkX)
	local dy: number = math.abs(endChunkZ - startChunkZ)
	local sx: number = startChunkX < endChunkX and 1 or -1
	local sz: number = startChunkZ < endChunkZ and 1 or -1
	local err: number = dx - dy
	
	local x: number = startChunkX
	local z: number = startChunkZ
	local maxDistance: number = RENDER_RANGE * 2
	
	local chunk: {ChunkRequest} = {}
	local processedChunks: {[number]: boolean} = {}
	
	while true do
		local chunkKey: number = createChunkKey(x, z)
		if not processedChunks[chunkKey] then
			processedChunks[chunkKey] = true
			
			for offsetX: number = -RENDER_RANGE, RENDER_RANGE do
				for offsetZ: number = -RENDER_RANGE, RENDER_RANGE do
					local cx: number = x + offsetX
					local cz: number = z + offsetZ
					
					local distance: number = getChunkDistance(cx, cz, startChunkX, startChunkZ)
					local priority: number = calculatePriority(distance, playerSpeed, maxDistance)
					
					table.insert(chunk, {x = cx, z = cz, priority = priority})
				end
			end
		end
		
		if x == endChunkX and z == endChunkZ then
			break
		end
		
		local e2: number = 2 * err
		if e2 > -dy then
			err = err - dy
			x = x + sx
		end
		if e2 < dx then
			err = err + dx
			z = z + sz
		end
	end
	return chunk
end

--Takes calculated values and generates terrain
local function mountLayer(x: number, heightY: number, z: number, material: Enum.Material): (CFrame?, Vector3?)
	local beginY: number = heightY - SURFACE_HEIGHT
	local endY: number = heightY
	if endY > MIN_HEIGHT and endY > beginY then
		local cframe: CFrame = CFrame.new(x * VOXEL_SIZE + VOXEL_HALF, (beginY + endY) * VOXEL_HALF, z * VOXEL_SIZE + VOXEL_HALF)
		local size: Vector3 = Vector3.new(VOXEL_SIZE, (endY - beginY) * VOXEL_SIZE, VOXEL_SIZE)
		workspace.Terrain:FillBlock(cframe, size, material)
		return cframe, size
	else
		return nil, nil
	end
end

local function getBlendedHeight(x: number, z: number, normalHeight: number): number
	local distSq: number = x * x + z * z
	if distSq <= FLAT_RADIUS_SQ then
		return MIN_HEIGHT
	end
	if distSq <= BLEND_EDGE * BLEND_EDGE then
		local dist: number = math.sqrt(distSq)
		local t: number = (dist - FLAT_RADIUS) / BLEND_RADIUS
		local blend: number = smootherstep(t)
		return MIN_HEIGHT * (1 - blend) + normalHeight * blend
	else
		return normalHeight
	end
end

--Prepares values for terrain generation
function TerrainGenerator.makeChunk(chunkX: number, chunkZ: number): ()
	chunkX = math.floor(chunkX)
	chunkZ = math.floor(chunkZ)
	
	if chunkExists(chunkX, chunkZ) then return end
	local baseX: number, baseZ: number = chunkX * CHUNK_SCALE, chunkZ * CHUNK_SCALE
	local chunkData: ChunkData = { removeAt = tick() + CHUNK_TIMEOUT, terrainBlocks = {} }
	local terrainBlocks: {{
		cframe: CFrame,
		size: Vector3
	}} = chunkData.terrainBlocks

	for x: number = 0, CHUNK_SCALE - 1 do
		local cx: number = baseX + x
		local cxScale: number = cx * X_SCALE_INV
		for z: number = 0, CHUNK_SCALE - 1 do
			local cz: number = baseZ + z
			local czScale: number = cz * Z_SCALE_INV
			local distSq: number = cx * cx + cz * cz
			if distSq > FLAT_RADIUS_SQ then
				local noise: number = math.noise(GENERATION_SEED, cxScale, czScale)
				local normalizedNoise: number = (noise + 1) * NOISE_OFFSET
				local rarityFactor: number = normalizedNoise
				for i: number = 2, RARITY_POWER do
					rarityFactor = rarityFactor * normalizedNoise
				end
				local heightOffset: number = rarityFactor * HEIGHT_RANGE
				local cy: number = getBlendedHeight(cx, cz, MIN_HEIGHT + heightOffset)
				local cframe: CFrame?, size: Vector3? = mountLayer(cx, cy, cz, TERRAIN_TYPE)
				if cframe and size then
					table.insert(terrainBlocks, { cframe = cframe, size = size })
				end
			end
		end
	end
	CHUNKS[chunkX][chunkZ] = chunkData
end

function TerrainGenerator.removeTimeoutChunk(): ()
	local currentTime: number = tick()
	
	for chunkX: number, chunkZData: {[number]: ChunkData} in pairs(CHUNKS) do
		for chunkZ: number, chunkInfo: ChunkData in pairs(chunkZData) do
			if chunkInfo.removeAt and chunkInfo.removeAt < currentTime then
				if chunkInfo.terrainBlocks then
					for _, block: {
						cframe: CFrame,
						size: Vector3
					} in pairs(chunkInfo.terrainBlocks) do
						if block.cframe and block.size then
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

function TerrainGenerator.mergeDuplicateChunks(chunks: {ChunkRequest}): {ChunkRequest}
	local uniqueChunks: {[number]: ChunkRequest} = {}
	
	for _, chunk: ChunkRequest in ipairs(chunks) do
		local key: number = createChunkKey(chunk.x, chunk.z)
		
		if not uniqueChunks[key] then
			uniqueChunks[key] = chunk
		else
			if chunk.priority > uniqueChunks[key].priority then
				uniqueChunks[key] = chunk
			end
		end
	end
	
	local result: {ChunkRequest} = {}
	for _, chunk: ChunkRequest in pairs(uniqueChunks) do
		table.insert(result, chunk)
	end
	
	return result
end

function TerrainGenerator.combine(...: {ChunkRequest}?): {ChunkRequest}
    local args = {...}
    local combined: {ChunkRequest} = {}
    
    for i: number = 1, #args do
        if args[i] then
            for _, v: ChunkRequest in ipairs(args[i] :: {ChunkRequest}) do
                table.insert(combined, v)
            end
        end
    end
    
    return combined
end

function TerrainGenerator.getTerrainHeightAtPosition(position: Vector3): number
	local chunkX: number, chunkZ: number = getChunkCoordinates(position)
	chunkX = math.floor(chunkX)
	chunkZ = math.floor(chunkZ)
	
	if not CHUNKS[chunkX] then
		return MIN_HEIGHT
	end
	
	if not CHUNKS[chunkX][chunkZ] then
		return MIN_HEIGHT
	end
	
	local chunkData: ChunkData = CHUNKS[chunkX][chunkZ]
	local maxHeight: number = MIN_HEIGHT
	
	for _, block: {
		cframe: CFrame,
		size: Vector3
	} in pairs(chunkData.terrainBlocks) do
		if block.cframe and block.size then
			local blockTopY: number = block.cframe.Position.Y + (block.size.Y / 2)
			if blockTopY > maxHeight then
				maxHeight = blockTopY
			end
		end
	end
	
	return maxHeight
end

function TerrainGenerator.teleportPlayerToSurface(player: Player): ()
    local character: Model? = player.Character or player.CharacterAdded:Wait()
    if not character then 
        return 
    end
    
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    if not humanoidRootPart or not (humanoidRootPart :: BasePart) then 
        return 
    end
    local humanoidRootPartTyped = humanoidRootPart :: BasePart
    
    local currentCFrame: CFrame = humanoidRootPartTyped.CFrame
    local currentPosition: Vector3 = currentCFrame.Position
    
    local surfaceHeight: number = TerrainGenerator.getTerrainHeightAtPosition(currentPosition) + 5
    
    local newPosition: Vector3 = Vector3.new(currentPosition.X, surfaceHeight, currentPosition.Z)
    local newCFrame: CFrame = CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position)
    
    humanoidRootPartTyped.CFrame = newCFrame
end

-- Ana döngü fonksiyonu
local function mainLoop(): ()
	while isRunning do
		local chunks: {ChunkRequest} = {}
		
		for _, player: Player in pairs(Players:GetPlayers()) do
			if player.Character then
				local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
				if humanoidRootPart and (humanoidRootPart :: BasePart) then
					local humanoidRootPartTyped = humanoidRootPart :: BasePart
					local humanoid = player.Character:FindFirstChild("Humanoid")
					if humanoid and (humanoid :: Humanoid) then
						local humanoidTyped = humanoid :: Humanoid
						humanoidTyped.WalkSpeed = 100
					end
					local currentPosition: Vector3 = humanoidRootPartTyped.Position
					
					if not player.Character.PrimaryPart or not (player.Character.PrimaryPart :: BasePart) then
						continue
					end
					local primaryPart = player.Character.PrimaryPart :: BasePart
					
					local velocity: Vector3 = primaryPart.AssemblyLinearVelocity * TerrainGenerator.HORIZONTAL_MASK
					local playerSpeed: number = velocity.Magnitude
					
					local predictedPosition: Vector3? = TerrainGenerator.predictPlayerPosition(player.Character)
					
					if predictedPosition and predictedPosition ~= currentPosition then
						chunks = TerrainGenerator.combine(chunks, TerrainGenerator.generatePathBetweenPoints(currentPosition, predictedPosition, playerSpeed))
					else
						chunks = TerrainGenerator.combine(chunks, TerrainGenerator.checkSurroundings(currentPosition, playerSpeed))
					end
				end
			end
		end
		
		chunks = TerrainGenerator.mergeDuplicateChunks(chunks)
		
		table.sort(chunks, function(a: ChunkRequest, b: ChunkRequest): boolean return a.priority > b.priority end)
		
		for _, chunk: ChunkRequest in ipairs(chunks) do
			TerrainGenerator.makeChunk(chunk.x, chunk.z)
		end
		
		TerrainGenerator.removeTimeoutChunk()

		for _, player: Player in pairs(Players:GetPlayers()) do
			if player.Character then
				local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
				if humanoidRootPart and (humanoidRootPart :: BasePart) then
					local humanoidRootPartTyped = humanoidRootPart :: BasePart
					local terrainHeight: number = TerrainGenerator.getTerrainHeightAtPosition(humanoidRootPartTyped.Position)
					
					if humanoidRootPartTyped.Position.Y < terrainHeight then
						TerrainGenerator.teleportPlayerToSurface(player)
					end
				end
			end
		end
		
		task.wait(1)
	end
end

------------------------------------------------------------------------------------------------------------------------------------------------

-- Modül API'si

-- TerrainGenerator'ı başlat
function TerrainGenerator.Start(): ()
	if isRunning then
		warn("TerrainGenerator zaten çalışıyor!")
		return
	end
	
	isRunning = true
	connection = task.spawn(mainLoop)
end

-- TerrainGenerator'ı durdur
function TerrainGenerator.Stop(): ()
	if not isRunning then
		warn("TerrainGenerator zaten durdurulmuş!")
		return
	end
	
	isRunning = false
	connection = nil
end

-- TerrainGenerator'ın çalışıp çalışmadığını kontrol et
function TerrainGenerator.IsRunning(): boolean
	return isRunning
end

-- Belirli bir pozisyondaki terrain yüksekliğini al
function TerrainGenerator.GetTerrainHeight(position: Vector3): number
	return TerrainGenerator.getTerrainHeightAtPosition(position)
end

-- Oyuncuyu yüzeye ışınla
function TerrainGenerator.TeleportPlayerToSurface(player: Player): ()
	TerrainGenerator.teleportPlayerToSurface(player)
end

-- Tüm chunk'ları temizle
function TerrainGenerator.ClearAllChunks(): ()
	for chunkX: number, chunkZData: {[number]: ChunkData} in pairs(CHUNKS) do
		for chunkZ: number, chunkInfo: ChunkData in pairs(chunkZData) do
			if chunkInfo.terrainBlocks then
				for _, block: {
					cframe: CFrame,
					size: Vector3
				} in pairs(chunkInfo.terrainBlocks) do
					if block.cframe and block.size then
						workspace.Terrain:FillBlock(block.cframe, block.size, Enum.Material.Air)
					end
				end
			end
		end
	end
	
	CHUNKS = {}
end

-- Modül ayarlarını güncelle
function TerrainGenerator.UpdateSettings(settings: {
	chunkTimeout: number?,
	chunkScale: number?,
	renderDistance: number?,
	xScale: number?,
	zScale: number?,
	terrainType: Enum.Material?,
	surfaceHeight: number?,
	minHeight: number?,
	maxHeight: number?,
	rarityPower: number?,
	flatRadius: number?,
	blendRadius: number?
}): ()
	if settings.chunkTimeout then
		CHUNK_TIMEOUT = settings.chunkTimeout
	end
	if settings.chunkScale then
		CHUNK_SCALE = settings.chunkScale
	end
	if settings.renderDistance then
		RENDER_DISTANCE = settings.renderDistance
	end
	if settings.xScale then
		X_SCALE = settings.xScale
	end
	if settings.zScale then
		Z_SCALE = settings.zScale
	end
	if settings.terrainType then
		TERRAIN_TYPE = settings.terrainType
	end
	if settings.surfaceHeight then
		SURFACE_HEIGHT = settings.surfaceHeight
	end
	if settings.minHeight then
		MIN_HEIGHT = settings.minHeight
	end
	if settings.maxHeight then
		MAX_HEIGHT = settings.maxHeight
	end
	if settings.rarityPower then
		RARITY_POWER = settings.rarityPower
	end
	if settings.flatRadius then
		FLAT_RADIUS = settings.flatRadius
	end
	if settings.blendRadius then
		BLEND_RADIUS = settings.blendRadius
	end
	
	-- Sabitleri yeniden hesapla
	CHUNK_SIZE = 4 * CHUNK_SCALE
	CHUNK_SIZE_INV = 1 / CHUNK_SIZE
	RENDER_RANGE = math.max(1, RENDER_DISTANCE / CHUNK_SCALE)
	X_SCALE_INV = 1 / X_SCALE
	Z_SCALE_INV = 1 / Z_SCALE
	HEIGHT_RANGE = MAX_HEIGHT - MIN_HEIGHT
	FLAT_RADIUS_SQ = FLAT_RADIUS * FLAT_RADIUS
	BLEND_EDGE = FLAT_RADIUS + BLEND_RADIUS
end

-- Mevcut ayarları al
function TerrainGenerator.GetSettings(): {
	chunkTimeout: number,
	chunkScale: number,
	renderDistance: number,
	xScale: number,
	zScale: number,
	terrainType: Enum.Material,
	surfaceHeight: number,
	minHeight: number,
	maxHeight: number,
	rarityPower: number,
	flatRadius: number,
	blendRadius: number
}
	return {
		chunkTimeout = CHUNK_TIMEOUT,
		chunkScale = CHUNK_SCALE,
		renderDistance = RENDER_DISTANCE,
		xScale = X_SCALE,
		zScale = Z_SCALE,
		terrainType = TERRAIN_TYPE,
		surfaceHeight = SURFACE_HEIGHT,
		minHeight = MIN_HEIGHT,
		maxHeight = MAX_HEIGHT,
		rarityPower = RARITY_POWER,
		flatRadius = FLAT_RADIUS,
		blendRadius = BLEND_RADIUS
	}
end

return TerrainGenerator