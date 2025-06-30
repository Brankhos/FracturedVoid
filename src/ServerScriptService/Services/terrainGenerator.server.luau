--!strict

------------------------------------------------------------------------------------------------------------------------------------------------
local Players: Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Modülü yükle
local TerrainGenerator = require(ServerScriptService.Modules.TerrainGenerator)
local TerrainGeneratorOld = require(ServerScriptService.Modules.TerrainGenerator.old)

------------------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------------------
-- Test argumanı
------------------------------------------------------------------------------------------------------------------------------------------------
local tryOld = false
local visualize = false

------------------------------------------------------------------------------------------------------------------------------------------------
-- Performans Takip Sistemi
------------------------------------------------------------------------------------------------------------------------------------------------

local PerformanceMonitor = {
	-- Performans istatistikleri
	stats = {
		totalIterations = 0,
		averageExecutionTime = 0,
		minExecutionTime = math.huge,
		maxExecutionTime = 0,
		totalExecutionTime = 0,
		lastUpdateTime = 0,
		updateInterval = 10, -- 10 saniyede bir güncelle
		iterationCount = 0
	},
	startTime = 0,
	
	-- Performans ölçümü başlat
	StartMeasurement = function(self: any)
		self.startTime = tick()
	end,
	
	-- Performans ölçümü bitir ve kaydet
	EndMeasurement = function(self: any)
		if not self.startTime then return end
		
		local executionTime: number = tick() - self.startTime
		local stats: any = self.stats
		
		stats.totalIterations = stats.totalIterations + 1
		stats.iterationCount = stats.iterationCount + 1
		stats.totalExecutionTime = stats.totalExecutionTime + executionTime
		stats.averageExecutionTime = stats.totalExecutionTime / stats.totalIterations
		stats.minExecutionTime = math.min(stats.minExecutionTime, executionTime)
		stats.maxExecutionTime = math.max(stats.maxExecutionTime, executionTime)
		
		-- Belirli aralıklarla performans raporu yazdır
		if tick() - stats.lastUpdateTime >= stats.updateInterval then
			self:PrintPerformanceReport()
			stats.lastUpdateTime = tick()
			stats.iterationCount = 0
			self:ResetStats()
		end
		
		self.startTime = 0
	end,
	
	-- Performans raporu yazdır
	PrintPerformanceReport = function(self: any)
		local stats: any = self.stats
		print("=== TERRAIN GENERATOR PERFORMANS RAPORU ===")
		print(string.format("Toplam İterasyon: %d", stats.totalIterations))
		print(string.format("Son %d İterasyon İstatistikleri:", stats.updateInterval))
		print(string.format("  - Ortalama Çalışma Süresi: %.4f ms", stats.averageExecutionTime * 1000))
		print(string.format("  - En Hızlı İterasyon: %.4f ms", stats.minExecutionTime * 1000))
		print(string.format("  - En Yavaş İterasyon: %.4f ms", stats.maxExecutionTime * 1000))
		print(string.format("  - Toplam Çalışma Süresi: %.2f saniye", stats.totalExecutionTime))
		print(string.format("  - Saniye Başına İterasyon: %.2f", stats.iterationCount / stats.updateInterval))
		print("==========================================")
	end,
	
	-- Performans istatistiklerini sıfırla
	ResetStats = function(self: any)
		self.stats = {
			totalIterations = 0,
			averageExecutionTime = 0,
			minExecutionTime = math.huge,
			maxExecutionTime = 0,
			totalExecutionTime = 0,
			lastUpdateTime = tick(),
			updateInterval = 10,
			iterationCount = 0
		}
		print("Performans istatistikleri sıfırlandı!")
	end
}



--Main Loop
--Gets player location every 1 second

if tryOld then
	-- Oyun kapanırken temizlik yap
	game:BindToClose(function()
		TerrainGeneratorOld.ClearAllChunks()
		print("TerrainGeneratorOld durduruldu ve temizlendi!")
	end)
else
	-- Oyun kapanırken temizlik yap
	game:BindToClose(function()
		TerrainGenerator.ClearAllChunks()
		print("TerrainGenerator durduruldu ve temizlendi!")
	end)
end

-- Performans takibini başlat
PerformanceMonitor:ResetStats()

while true do
	-- Performans ölçümü başlat
	PerformanceMonitor:StartMeasurement()
	
	if tryOld then
		local chunks: {TerrainGeneratorOld.ChunkRequest} = {}
		
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
					
					local velocity: Vector3 = primaryPart.AssemblyLinearVelocity * TerrainGeneratorOld.HORIZONTAL_MASK
					local playerSpeed: number = velocity.Magnitude
					
					local predictedPosition: Vector3? = TerrainGeneratorOld.predictPlayerPosition(player.Character)
					
					if predictedPosition and predictedPosition ~= currentPosition then
						chunks = TerrainGeneratorOld.combine(chunks, TerrainGeneratorOld.generatePathBetweenPoints(currentPosition, predictedPosition, playerSpeed))
					else
						chunks = TerrainGeneratorOld.combine(chunks, TerrainGeneratorOld.checkSurroundings(currentPosition, playerSpeed))
					end
				end
			end
		end
		
		chunks = TerrainGeneratorOld.mergeDuplicateChunks(chunks)
		
		table.sort(chunks, function(a: TerrainGeneratorOld.ChunkRequest, b: TerrainGeneratorOld.ChunkRequest): boolean return a.priority > b.priority end)
		
		for _, chunk: TerrainGeneratorOld.ChunkRequest in ipairs(chunks) do
			TerrainGeneratorOld.makeChunk(chunk.x, chunk.z)
		end
		
		TerrainGeneratorOld.removeTimeoutChunk()

		local function checkPlayerHeight()
			for _, player: Player in pairs(Players:GetPlayers()) do
				if player.Character then
					local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
					if humanoidRootPart and (humanoidRootPart :: BasePart) then
						local humanoidRootPartTyped = humanoidRootPart :: BasePart
						local terrainHeight: number = TerrainGeneratorOld.getTerrainHeightAtPosition(humanoidRootPartTyped.Position)
						
						if humanoidRootPartTyped.Position.Y < terrainHeight then
							TerrainGeneratorOld.teleportPlayerToSurface(player)
						end
					end
				end
			end
		end

		checkPlayerHeight()
		
		
	else
		local players: {Player} = Players:GetPlayers()

		local playerChunks: {TerrainGenerator.Chunks} = {}
		
		for i: number = 1, #players do
			local player: Player = players[i]
			if player.Character then
				local humanoidRootPart: BasePart? = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoidRootPart then
					local humanoid: Humanoid? = player.Character:FindFirstChild("Humanoid") :: Humanoid?
					if humanoid then
						humanoid.WalkSpeed = 100
						table.insert(playerChunks, TerrainGenerator.GenerateChunks(humanoidRootPart, 1.0))
					end
				end
			end
		end
		local chunks: TerrainGenerator.Chunks = TerrainGenerator.MergeChunks(table.unpack(playerChunks))
		
		if visualize then
			TerrainGenerator.visualizeChunks(chunks)
		else
			TerrainGenerator.generateGround(chunks)
		end

		TerrainGenerator.RemoveTimeoutChunks()
	end
	
	-- Performans ölçümü bitir
	PerformanceMonitor:EndMeasurement()
	
	task.wait(1)
end