local Players = game:GetService("Players")

------------------------------------------------------------------------------------------------------------------------------------------------

local BASE_HEIGHT 		= 100				-- The main height factor for the terrain.
local CHUNK_SCALE 		= 3 				-- The grid scale for terrain generation. Should be kept relatively low if used in real-time.
local RENDER_DISTANCE 	= 100 				-- The length/width of chunks in voxels that should be around the player at all times (artırıldı)
local X_SCALE 			= 90			-- How much we should strech the X scale of the generation noise
local Z_SCALE 			= 90			-- How much we should strech the Z scale of the generation noise
local GENERATION_SEED	= math.random() 	-- Seed for determining the main height map of the terrain.
local TERRAIN_TYPE = Enum.Material.Ice --Terrain Type

-- Yeni optimizasyon sabitleri
local CHUNK_CLEANUP_DISTANCE = RENDER_DISTANCE * 1.5 -- Chunk'ları silmek için mesafe
local UPDATE_INTERVAL = 0.5 -- Terrain güncelleme aralığı (saniye) - daha hızlı güncelleme
local MAX_CHUNKS_PER_UPDATE = 20 -- Her güncellemede maksimum oluşturulacak chunk sayısı (artırıldı)
local SAFETY_DISTANCE = 20 -- Oyuncuya minimum güvenli mesafe (chunk biriminde)

------------------------------------------------------------------------------------------------------------------------------------------------

local chunks = {} -- Chunk bilgilerini saklamak için geliştirilmiş tablo
local chunkQueue = {} -- Oluşturulacak chunk'lar için kuyruk
local lastPlayerPositions = {} -- Oyuncuların son pozisyonlarını takip etmek için
local playerVelocities = {} -- Oyuncuların hızlarını takip etmek için

-- Chunk bilgilerini saklamak için yapı
local function createChunkInfo(timestamp)
	return {
		timestamp = timestamp,
		lastAccessed = timestamp
	}
end

-- Chunk'ın var olup olmadığını kontrol eder
local function chunkExists(chunkX, chunkZ)
	if not chunks[chunkX] then
		chunks[chunkX] = {}
	end
	return chunks[chunkX][chunkZ] ~= nil
end

-- Chunk'ı işaretler ve son erişim zamanını günceller
local function markChunkAccessed(chunkX, chunkZ)
	if not chunks[chunkX] then
		chunks[chunkX] = {}
	end
	if chunks[chunkX][chunkZ] then
		chunks[chunkX][chunkZ].lastAccessed = tick()
	else
		chunks[chunkX][chunkZ] = createChunkInfo(tick())
	end
end

-- Terrain oluşturma fonksiyonu (optimize edilmiş)
local function mountLayer(x, heightY, z, material)
	local beginY = -BASE_HEIGHT
	local endY = heightY
	local cframe = CFrame.new(x * 4 + 2, (beginY + endY) * 4 / 2, z * 4 + 2)
	local size = Vector3.new(4, (endY - beginY) * 4, 4)
	workspace.Terrain:FillBlock(cframe, size, material)	
end

-- Chunk oluşturma fonksiyonu
function makeChunk(chunkX, chunkZ)
	-- Chunk'ı işaretle (oluşturulduğunu belirt)
	markChunkAccessed(chunkX, chunkZ)
	
	local rootPosition = Vector3.new(chunkX * CHUNK_SCALE, 0, chunkZ * CHUNK_SCALE)
	
	for x = 0, CHUNK_SCALE - 1 do
		for z = 0, CHUNK_SCALE - 1 do
			local cx = (chunkX * CHUNK_SCALE) + x
			local cz = (chunkZ * CHUNK_SCALE) + z
			local noise = math.noise(GENERATION_SEED, cx / X_SCALE, cz / Z_SCALE)
			local cy = noise * BASE_HEIGHT
			mountLayer(cx, cy, cz, TERRAIN_TYPE)
		end
	end
end

-- Chunk'ı silme fonksiyonu
local function removeChunk(chunkX, chunkZ)
	if not chunkExists(chunkX, chunkZ) then
		return
	end
	
	-- Chunk alanındaki terrain'i temizle
	local startX = chunkX * CHUNK_SCALE
	local startZ = chunkZ * CHUNK_SCALE
	local endX = startX + CHUNK_SCALE
	local endZ = startZ + CHUNK_SCALE
	
	-- Chunk alanını hava ile doldur (terrain'i kaldır)
	local cframe = CFrame.new(
		(startX + endX) * 2, 
		-BASE_HEIGHT * 2, 
		(startZ + endZ) * 2
	)
	local size = Vector3.new(CHUNK_SCALE * 8, BASE_HEIGHT * 8, CHUNK_SCALE * 8)
	workspace.Terrain:FillBlock(cframe, size, Enum.Material.Air)
	
	-- Chunk kaydını sil
	chunks[chunkX][chunkZ] = nil
	if next(chunks[chunkX]) == nil then
		chunks[chunkX] = nil
	end
end

-- Oyuncu çevresini kontrol etme (optimize edilmiş)
function checkSurroundings(location, playerId)
	local chunkX, chunkZ = math.floor(location.X / 4 / CHUNK_SCALE), math.floor(location.Z / 4 / CHUNK_SCALE)
	local range = math.max(1, RENDER_DISTANCE / CHUNK_SCALE)
	
	-- Oyuncunun etrafındaki chunk'ları kontrol et
	for x = -range, range do
		for z = -range, range do
			local cx = chunkX + x
			local cz = chunkZ + z
			
			-- Chunk zaten varsa sadece erişim zamanını güncelle
			if chunkExists(cx, cz) then
				markChunkAccessed(cx, cz)
			else
				-- Yeni chunk'ı kuyruğa ekle (oyuncuya yakın olanlar daha yüksek öncelik)
				local distance = math.abs(x) + math.abs(z)
				local priority = distance -- Daha yakın = daha düşük sayı = daha yüksek öncelik
				table.insert(chunkQueue, {x = cx, z = cz, priority = priority})
			end
		end
	end
	
	-- Kuyruğu önceliğe göre sırala (oyuncuya yakın olanlar önce)
	table.sort(chunkQueue, function(a, b) return a.priority < b.priority end)
end

-- Eski chunk'ları temizleme
local function cleanupOldChunks()
	local currentTime = tick()
	local cleanupRange = math.max(1, CHUNK_CLEANUP_DISTANCE / CHUNK_SCALE)
	
	for chunkX, chunkZData in pairs(chunks) do
		for chunkZ, chunkInfo in pairs(chunkZData) do
			-- Son erişimden bu yana geçen süreyi kontrol et
			if currentTime - chunkInfo.lastAccessed > UPDATE_INTERVAL * 3 then
				-- Bu chunk'a yakın oyuncu var mı kontrol et
				local hasNearbyPlayer = false
				for _, player in pairs(Players:GetPlayers()) do
					if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
						local playerChunkX = math.floor(player.Character.HumanoidRootPart.Position.X / 4 / CHUNK_SCALE)
						local playerChunkZ = math.floor(player.Character.HumanoidRootPart.Position.Z / 4 / CHUNK_SCALE)
						
						if math.abs(chunkX - playerChunkX) <= cleanupRange and 
						   math.abs(chunkZ - playerChunkZ) <= cleanupRange then
							hasNearbyPlayer = true
							break
						end
					end
				end
				
				-- Yakında oyuncu yoksa chunk'ı sil
				if not hasNearbyPlayer then
					removeChunk(chunkX, chunkZ)
				end
			end
		end
	end
end

-- Oyuncunun hareket yönünü tahmin et
local function predictPlayerMovement(playerId, currentPosition)
	local lastPos = lastPlayerPositions[playerId]
	if not lastPos then
		lastPlayerPositions[playerId] = currentPosition
		return Vector3.new(0, 0, 0)
	end
	
	local velocity = (currentPosition - lastPos) / UPDATE_INTERVAL
	playerVelocities[playerId] = velocity
	lastPlayerPositions[playerId] = currentPosition
	
	return velocity
end

-- Tahmin edilen pozisyonda chunk'ları önceden oluştur
local function preloadChunksInDirection(playerId, currentPosition, velocity)
	if velocity.Magnitude < 10 then return end -- Çok yavaş hareket ediyorsa gerek yok
	
	local predictionTime = 2 -- 2 saniye sonraki pozisyonu tahmin et
	local predictedPosition = currentPosition + (velocity * predictionTime)
	
	local chunkX, chunkZ = math.floor(predictedPosition.X / 4 / CHUNK_SCALE), math.floor(predictedPosition.Z / 4 / CHUNK_SCALE)
	local range = math.max(1, SAFETY_DISTANCE / CHUNK_SCALE)
	
	-- Tahmin edilen pozisyon etrafındaki chunk'ları yüksek öncelikle kuyruğa ekle
	for x = -range, range do
		for z = -range, range do
			local cx = chunkX + x
			local cz = chunkZ + z
			
			if not chunkExists(cx, cz) then
				local distance = math.abs(x) + math.abs(z)
				local priority = distance - 100 -- Çok yüksek öncelik (negatif sayı)
				table.insert(chunkQueue, {x = cx, z = cz, priority = priority})
			end
		end
	end
end

-- Ana döngü (optimize edilmiş)
while true do
	local currentTime = tick()
	
	-- Oyuncuların pozisyonlarını kontrol et
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character then
			local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				local currentPosition = humanoidRootPart.Position
				
				-- Oyuncunun hareket yönünü tahmin et
				local velocity = predictPlayerMovement(player.UserId, currentPosition)
				
				-- Mevcut pozisyon etrafındaki chunk'ları kontrol et
				checkSurroundings(currentPosition, player.UserId)
				
				-- Hareket yönünde önceden chunk'ları yükle
				preloadChunksInDirection(player.UserId, currentPosition, velocity)
			end
		end
	end
	
	-- Kuyruktan chunk'ları oluştur (sınırlı sayıda)
	local chunksCreated = 0
	while #chunkQueue > 0 and chunksCreated < MAX_CHUNKS_PER_UPDATE do
		local chunkData = table.remove(chunkQueue, 1)
		print("Chunk oluşturuluyor:", chunkData.x, chunkData.z, "Öncelik:", chunkData.priority)
		makeChunk(chunkData.x, chunkData.z)
		chunksCreated = chunksCreated + 1
	end
	
	-- Eski chunk'ları temizle
	cleanupOldChunks()
	
	-- Performans bilgilerini yazdır (debug için)
	if #chunkQueue > 0 or chunksCreated > 0 then
		print("Chunk kuyruğu:", #chunkQueue, "Oluşturulan:", chunksCreated, "Toplam chunk:", #chunks)
	end
	
	task.wait(UPDATE_INTERVAL)
end