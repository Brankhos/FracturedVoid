--!strict

local TerrainGenerator = require(script.Parent)

-- Test fonksiyonunu çalıştır
local function runTest()
    print("TerrainGenerator Performans Testi Başlatılıyor...")
    
    -- Test başlat
    local results = TerrainGenerator.runPerformanceTest()
    
    print("\n=== TEST TAMAMLANDI ===")

end

-- Testi çalıştır
runTest() 