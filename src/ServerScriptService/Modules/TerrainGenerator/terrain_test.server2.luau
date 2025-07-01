--[[
TERRAIN GENERATOR PARAMETRE AÇIKLAMALARI
==========================================

GLOBAL PARAMETRELER:
-------------------
SIZE: Grid boyutu (x,z ekseni)
  ↑ INCREASE: Daha büyük arazi, daha fazla blok, daha yavaş performans
  ↓ DECREASE: Daha küçük arazi, daha az blok, daha hızlı performans
  ⚠️ ETKİLEŞİM: HEIGHT_SCALE ile birlikte toplam arazi boyutunu belirler

HEIGHT_SCALE: Yükseklik ölçeği (potansiyel yükseklik aralığı)
  ↑ INCREASE: Daha yüksek tepeler, daha dramatik arazi
  ↓ DECREASE: Daha alçak tepeler, daha düz arazi
  ⚠️ ETKİLEŞİM: CLAMP_MIN/MAX ile çakışabilir, gerçek yükseklik sınırını belirler

BLOCK_SIZE: Her bloğun boyutu (Vector3)
  ↑ INCREASE: Daha büyük bloklar, daha az detay, daha hızlı performans
  ↓ DECREASE: Daha küçük bloklar, daha fazla detay, daha yavaş performans
  ⚠️ ETKİLEŞİM: SIZE ile birlikte toplam arazi boyutunu belirler

NOISE SCALE PARAMETRELERİ:
-------------------------
SCALE_BASE: Büyük ölçek noise frekansı
  ↑ INCREASE: Daha hızlı değişim, daha küçük tepeler
  ↓ DECREASE: Daha yavaş değişim, daha büyük tepeler
  ⚠️ ETKİLEŞİM: SCALE_DETAIL ile birlikte arazi detayını belirler

SCALE_DETAIL: Küçük ölçek noise frekansı
  ↑ INCREASE: Daha fazla detay, daha engebeli arazi
  ↓ DECREASE: Daha az detay, daha yumuşak arazi
  ⚠️ ETKİLEŞİM: SCALE_BASE ile birlikte arazi detayını belirler

PLATEAU SİSTEMİ:
----------------
PLATEAU_THRESHOLD: Plateau başlangıç noktası (0-1 arası)
  ↑ INCREASE: Daha geç plateau başlar, daha az düz üst
  ↓ DECREASE: Daha erken plateau başlar, daha fazla düz üst
  ⚠️ ETKİLEŞİM: CLAMP_THRESHOLD ile birlikte düz alan miktarını belirler

PLATEAU_WIDTH: Plateau genişliği (0-1 arası)
  ↑ INCREASE: Daha geniş düz üstler, daha fazla oynanabilir alan
  ↓ DECREASE: Daha dar düz üstler, daha az oynanabilir alan
  ⚠️ ETKİLEŞİM: PLATEAU_THRESHOLD ile birlikte düz alan kalitesini belirler

CLAMP SİSTEMİ:
--------------
CLAMP_MIN/MAX: Yükseklik sınırları
  ↑ INCREASE: Daha yüksek tepeler, daha dramatik arazi
  ↓ DECREASE: Daha alçak tepeler, daha düz arazi
  ⚠️ ETKİLEŞİM: HEIGHT_SCALE ile çakışabilir, gerçek yükseklik sınırını belirler

CLAMP_THRESHOLD: Ekstrem düzleştirme başlangıcı (0-1 arası)
  ↑ INCREASE: Daha geç düzleştirme, daha fazla keskin tepeler
  ↓ DECREASE: Daha erken düzleştirme, daha fazla düz üstler
  ⚠️ ETKİLEŞİM: PLATEAU_THRESHOLD ile birlikte düz alan stratejisini belirler

SİGMOİD FONKSİYONU:
-------------------
k (steepness factor): Sigmoid geçiş hızı
  ↑ INCREASE: Daha keskin geçişler, daha dramatik tepeler
  ↓ DECREASE: Daha yumuşak geçişler, daha doğal tepeler
  ⚠️ ETKİLEŞİM: PLATEAU_THRESHOLD ile birlikte tepe karakterini belirler

ETKİLEŞİMLİ PARAMETRE GRUPLARI:
-------------------------------
1. BOYUT GRUBU: SIZE, BLOCK_SIZE → Toplam arazi boyutu
2. YÜKSEKLİK GRUBU: HEIGHT_SCALE, CLAMP_MIN/MAX → Yükseklik aralığı
3. DETAY GRUBU: SCALE_BASE, SCALE_DETAIL → Arazi detayı
4. DÜZLEŞTİRME GRUBU: PLATEAU_THRESHOLD, CLAMP_THRESHOLD → Düz alan stratejisi
5. GEÇİŞ GRUBU: k (steepness), PLATEAU_WIDTH → Geçiş kalitesi

PERFORMANS ETKİLERİ:
-------------------
- SIZE ↑ = Performans ↓ (doğrusal)
- BLOCK_SIZE ↑ = Performans ↑ (ters orantılı)
- HEIGHT_SCALE = Performans etkisi yok
- Noise hesaplamaları = Performans etkisi minimal
]]

local Terrain = workspace.Terrain

local SIZE = 1000
local HEIGHT_SCALE = 150
local BLOCK_SIZE = Vector3.new(4, 4, 4)
local MATERIAL = Enum.Material.Sand

local SCALE_BASE = 0.05
local SCALE_DETAIL = 0.2

-- Plateau parametreleri
local PLATEAU_THRESHOLD = 0.4  -- Bu değerin üstündeki tepeler düzleşir
local PLATEAU_WIDTH = 0.2      -- Plateau genişliği (0-1 arası)

-- Clamp parametreleri
local CLAMP_MIN = -50
local CLAMP_MAX = 50
local CLAMP_THRESHOLD = 0.75   -- Bu değerin üstündeki ekstrem tepeler düzleşir

-- Terrain'i temizle
Terrain:Clear()

for x = 0, SIZE - 1 do
	for z = 0, SIZE - 1 do
		local height

		local nx = x * SCALE_BASE
		local nz = z * SCALE_BASE
		local base = math.noise(nx, nz)

		local dx = x * SCALE_DETAIL
		local dz = z * SCALE_DETAIL
		local detail = math.noise(dx, dz)

		local combined = (base * 0.7 + detail * 0.3 + 1) / 2
		local centered = combined - 0.5
		local abs_centered = math.abs(centered)
		local sign_centered = math.sign(centered)
		
		-- Sigmoid fonksiyonu: Doğal geçişler
		local k = 22  -- Steepness factor
		local sigmoid = 1 / (1 + math.exp(-k * (abs_centered - 0.3)))
		local final = sign_centered * sigmoid
		
		-- Plateau sistemi: Yüksek tepeleri düzleştir
		if abs_centered > PLATEAU_THRESHOLD then
			-- Smooth plateau geçişi
			local plateau_progress = (abs_centered - PLATEAU_THRESHOLD) / (1 - PLATEAU_THRESHOLD)
			local smooth_plateau = 3 * plateau_progress^2 - 2 * plateau_progress^3  -- Smoothstep
			
			-- Plateau yüksekliği: Threshold + ek yükseklik
			local plateau_height = PLATEAU_THRESHOLD + (1 - PLATEAU_THRESHOLD) * PLATEAU_WIDTH
			
			-- Yumuşak geçiş: Sigmoid'den plateau'a
			final = sign_centered * (PLATEAU_THRESHOLD + (plateau_height - PLATEAU_THRESHOLD) * smooth_plateau)
		end
		
		-- Yüksekliği hesapla (-75 ile +75 arası)
		height = final * HEIGHT_SCALE
		
		-- Clamp sistemi: -50 ile +50 arasına sınırla
		height = math.clamp(height, CLAMP_MIN, CLAMP_MAX)
		
		-- Ekstrem değerlerin üstünü düzleştir
		if math.abs(height) > CLAMP_MAX * CLAMP_THRESHOLD then
			-- Ekstrem tepelerin üstünü düz yap
			local extreme_progress = (math.abs(height) - CLAMP_MAX * CLAMP_THRESHOLD) / (CLAMP_MAX - CLAMP_MAX * CLAMP_THRESHOLD)
			local smooth_extreme = 3 * extreme_progress^2 - 2 * extreme_progress^3
			
			-- Düz üst yüksekliği
			local flat_top_height = CLAMP_MAX * CLAMP_THRESHOLD + (CLAMP_MAX - CLAMP_MAX * CLAMP_THRESHOLD) * 0.8
			height = math.sign(height) * (CLAMP_MAX * CLAMP_THRESHOLD + (flat_top_height - CLAMP_MAX * CLAMP_THRESHOLD) * smooth_extreme)
		end

		-- KÖŞE BAZLI pozisyon
		local posX = x * BLOCK_SIZE.X
		local posZ = z * BLOCK_SIZE.Z
		local position = Vector3.new(posX, height, posZ)

		Terrain:FillBlock(CFrame.new(position), BLOCK_SIZE, MATERIAL)
	end
end
