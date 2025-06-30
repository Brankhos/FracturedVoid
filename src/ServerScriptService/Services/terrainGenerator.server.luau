--!optimize 2
--!strict
--!native

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

------------------------------------------------------------------------------------------------------------------------------------------------
-- Performans Takip Sistemi
------------------------------------------------------------------------------------------------------------------------------------------------


--Main Loop
--Gets player location every 1 second

if tryOld then
	TerrainGeneratorOld.Start()

	-- Oyun kapanırken temizlik yap
	game:BindToClose(function()
		TerrainGeneratorOld.Stop()
		TerrainGeneratorOld.ClearAllChunks()
		print("TerrainGeneratorOld durduruldu ve temizlendi!")
	end)
else
	TerrainGenerator.Start()

	-- Oyun kapanırken temizlik yap
	game:BindToClose(function()
		TerrainGenerator.Stop()
		TerrainGenerator.ClearAllChunks()
		print("TerrainGenerator durduruldu ve temizlendi!")
	end)
end

