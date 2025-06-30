--!strict

local LoadingScreen = {}
LoadingScreen.__index = LoadingScreen

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ModuleGlobals = require(game:GetService("ReplicatedFirst"):WaitForChild("ModuleGlobals"))

-- Event oluştur
local OnLoadingAsset = Instance.new("BindableEvent")
LoadingScreen.OnLoadingAsset = OnLoadingAsset.Event

-- Sabit değerleri önbelleğe al
local BAR_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BASE_SIZE = UDim2.new(1, 0, 0, 20)
local ACTIVE_SIZE = UDim2.new(1, 0, 0, 30)
local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PADDING = UDim.new(0, 4)
local BASE_COLOR = Color3.fromRGB(30, 30, 30)
local ACTIVE_COLOR = Color3.fromRGB(60, 90, 160)
local BATCH_SIZE = 50
local UPDATE_SCHEDULED = false



-- Yardımcı fonksiyonlar
local function formatPercent(value: number): string
	return string.format("%.0f%%", value)
end

local function formatCount(current: number, total: number): string
	return string.format("%d/%d", current, total)
end

local function createLabel(index: number, parent: Instance, text: string)
	local container = Instance.new("Frame")
	container.Name = "Item_" .. index
	container.Size = BASE_SIZE
	container.BackgroundColor3 = Color3.fromRGB(36, 37, 38) -- Sade koyu bir renk
	container.BorderSizePixel = 0
	container.LayoutOrder = index
	container.Parent = parent

	-- Sağdan ve soldan 10px padding
	local containerPadding = Instance.new("UIPadding")
	containerPadding.PaddingLeft = UDim.new(0, 10)
	containerPadding.PaddingRight = UDim.new(0, 10)
	containerPadding.Parent = container

	-- Köşe yuvarlatma
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = container

	-- Sadece isim
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = text
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 11
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = container

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(0.2, 0, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = ""
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextSize = 11
	countLabel.TextXAlignment = Enum.TextXAlignment.Center
	countLabel.LayoutOrder = 2
	countLabel.Parent = container

	local percentLabel = Instance.new("TextLabel")
	percentLabel.Name = "PercentLabel"
	percentLabel.Size = UDim2.new(0.2, 0, 1, 0)
	percentLabel.Text = ""
	percentLabel.BackgroundTransparency = 1
	percentLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	percentLabel.Font = Enum.Font.Gotham
	percentLabel.TextSize = 11
	percentLabel.TextXAlignment = Enum.TextXAlignment.Right
	percentLabel.LayoutOrder = 3
	percentLabel.Parent = container

	return container
end

local function handleAssetError(assetId: string, assetFetchStatus: Enum.AssetFetchStatus)
	if assetFetchStatus == Enum.AssetFetchStatus.Failure or assetFetchStatus == Enum.AssetFetchStatus.TimedOut then
		if ModuleGlobals.Debug then
			warn("Asset yüklenemedi:", assetId, "Durum:", assetFetchStatus)
		end
        if assetFetchStatus == Enum.AssetFetchStatus.TimedOut then
            -- Yeniden deneme mekanizması
            task.delay(1, function()
                pcall(function()
                    ContentProvider:PreloadAsync({game:GetService("ContentProvider"):GetAsset(assetId)})
                end)
            end)
        end
		
	end
end


function LoadingScreen:necessaryAssetsLoaded()
	for _, asset in ipairs(self.necessaryAssets) do
		if not asset.loaded then
			return false
		end
	end
	return true
end

function LoadingScreen.init()
	local self = setmetatable({}, LoadingScreen)
	self.skipped = false
    self.necessaryAssetsName = {"ReplicatedFirst", "ReplicatedStorage"}


	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	self.loadingScreenGui = script:WaitForChild("LoadingScreenGui")
	self.loadingScreenGui.Parent = playerGui
	self.loadingScreenGui.ResetOnSpawn = false
	self.loadingScreenGui.IgnoreGuiInset = true
	self.loadingScreenGui.DisplayOrder = 100

	local background = self.loadingScreenGui:WaitForChild("Background")
	self.barProcessFrame = background:WaitForChild("BarBackgroundFrame"):WaitForChild("BarProcessFrame")
	local rightFrame = background:WaitForChild("RightFrame")
	local rightBottomFrame = rightFrame:WaitForChild("RightBottomFrame")

	self.skipButton = rightFrame:WaitForChild("SkipButton")
	self.progressPercentText = rightBottomFrame:WaitForChild("ProgressPercentText")
	self.progressStateText = rightBottomFrame:WaitForChild("ProgressStateText")
	self.scrollFrame = rightFrame:WaitForChild("RightCenterFrame"):WaitForChild("ScrollFrame")

	local layout = self.scrollFrame:WaitForChild("UIListLayout")
	layout.Padding = PADDING
    layout.SortOrder = Enum.SortOrder.LayoutOrder 

	self.scrollFrame.ScrollingEnabled = false
	self.scrollFrame.ScrollBarThickness = 0

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not UPDATE_SCHEDULED then
			UPDATE_SCHEDULED = true
			task.defer(function()
				self.scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
				UPDATE_SCHEDULED = false
			end)
		end
	end)

	self.skipButton.Visible = false
	self.skipButton.Activated:Connect(function()
		self.skipped = true
	end)

	-- Ana klasörleri al ve allAssets'e ekle
	local mainFolders = game:GetChildren(true)

	-- Other kategorisini ekle
	local otherAssets = game:GetDescendants()
	local processedAssets = {}

    self.labels = table.create(#mainFolders)
	self.allAssets = table.create(#mainFolders)

    local idx
    local loadedNecessaryAssets = 0
    local necessaryIndex = 1
	-- Önce ana klasörleri ve içeriklerini işaretle
	for i = #mainFolders, 1, -1 do
		local folder = mainFolders[i]
		processedAssets[folder] = true
		local folderAssets = folder:GetDescendants()
		for _, asset in ipairs(folderAssets) do
			processedAssets[asset] = true
		end

        necessaryIndex = table.find(self.necessaryAssetsName, folder.Name)
        if necessaryIndex then
            loadedNecessaryAssets += 1
            idx = necessaryIndex
        else
            idx = i + loadedNecessaryAssets
        end

		self.allAssets[idx] = {
			name = folder.Name,
			instance = folder,
			assets = folderAssets,
			loaded = false
		}
        self.labels[idx] = createLabel(idx, self.scrollFrame, folder.Name)
	end

	-- Other kategorisi için işaretlenmemiş assetleri topla
	local otherAssetsList = {}
	for _, asset in ipairs(otherAssets) do
		if not processedAssets[asset] then
			table.insert(otherAssetsList, asset)
		end
	end

	table.insert(self.allAssets, {
		name = "Other",
		assets = otherAssetsList,
		loaded = false
	})


	self.labels[#self.allAssets] = createLabel(#self.allAssets, self.scrollFrame, "Other")


	self.totalGameAssets = 0
	for _, folderData in ipairs(self.allAssets) do
		self.totalGameAssets += #folderData.assets + 1
	end

	self.barProcessFrame.Size = UDim2.new(1, 0, 0, 0)
	self.progressStateText.Text = formatCount(0, self.totalGameAssets)
	self.progressPercentText.Text = formatPercent(0)


	self.necessaryAssets = {}


	for _, folderData in ipairs(self.allAssets) do
		if table.find(self.necessaryAssetsName, folderData.name) then
			table.insert(self.necessaryAssets, folderData)
		end
	end

-- Debug için sıralama kontrolü
if ModuleGlobals.Debug then
    print("Asset Sıralaması:")
    for i, asset in ipairs(self.allAssets) do
        print(i, asset.name, table.find(self.necessaryAssetsName, asset.name) and "Öncelikli" or "Normal")
    end
end

	return self
end

function LoadingScreen:updateLoadingProgress(currentProgress: number, folderIndex: number, loadedAssets: number, totalAssets: number)
	local percent = (currentProgress / self.totalGameAssets) * 100
	self.progressStateText.Text = formatCount(currentProgress, self.totalGameAssets)
	self.progressPercentText.Text = formatPercent(percent)

	local targetSize = UDim2.new(1, 0, currentProgress / self.totalGameAssets, 0)

	if self.tween then
		self.tween:Cancel()
	end

	self.tween = TweenService:Create(self.barProcessFrame, BAR_TWEEN_INFO, {
		Size = targetSize
	})
	self.tween:Play()

	if folderIndex and self.labels[folderIndex] then
		local folderData = self.allAssets[folderIndex]
		if folderData then
			loadedAssets += 1
			totalAssets += 1

			local percentLabel = self.labels[folderIndex]:FindFirstChild("PercentLabel")
			local countLabel = self.labels[folderIndex]:FindFirstChild("CountLabel")

			if percentLabel then
				percentLabel.Text = formatPercent((loadedAssets / totalAssets) * 100)
			end
			if countLabel then
				countLabel.Text = formatCount(loadedAssets, totalAssets)
			end
		end
	end

	if not self.skipButton.Visible and game:IsLoaded() and self:necessaryAssetsLoaded() then
		self.skipButton.Visible = true
	end
end

function LoadingScreen:updateActiveItem()
	-- Önceki aktif öğeyi sıfırla
	if self.activeLabel then
		local Tween = self.activeLabel:FindFirstChild("Tween")
		if Tween then
			Tween:Cancel()
			Tween.Parent = nil
		end
		Tween = TweenService:Create(self.activeLabel, TWEEN_INFO, {
			Size = BASE_SIZE,
			BackgroundColor3 = BASE_COLOR
		})
		Tween.Name = "Tween"
		Tween.Parent = self.activeLabel
		Tween:Play()
	end

	-- Yeni aktif öğeyi ayarla
	self.activeLabel = self.labels[self.activeIndex]
	if self.activeLabel then
		local Tween = self.activeLabel:FindFirstChild("Tween")
		if Tween then
			Tween:Cancel()
			Tween.Parent = nil
		end
		Tween = TweenService:Create(self.activeLabel, TWEEN_INFO, {
			Size = ACTIVE_SIZE,
			BackgroundColor3 = ACTIVE_COLOR
		})
		Tween.Name = "Tween"
		Tween.Parent = self.activeLabel
		Tween:Play()
	end

	if ModuleGlobals.Debug then
		task.wait(0.05)
	end

	-- Scroll pozisyonunu güncelle
	if not self.activeLabel then return end

	local viewportHeight: number = self.scrollFrame.AbsoluteSize.Y
	local activeLabelHeight: number = self.activeLabel.AbsoluteSize.Y
	local itemPosition: number = 0

	for i = 1, self.activeIndex - 1 do
		itemPosition += self.labels[i].AbsoluteSize.Y + PADDING.Offset
	end

	local targetScroll: number = itemPosition - (viewportHeight / 2) + (activeLabelHeight / 2)
	local maxScroll: number = math.max(0, self.scrollFrame.CanvasSize.Y.Offset - viewportHeight)
	targetScroll = math.clamp(targetScroll, 0, maxScroll)

	if self.scrollTween then
		self.scrollTween:Cancel()
	end

	self.scrollTween = TweenService:Create(self.scrollFrame, TWEEN_INFO, {
		CanvasPosition = Vector2.new(0, targetScroll)
	})
	self.scrollTween:Play()
end

function LoadingScreen:startLoading()
	if not self.allAssets then return end

	local currentProgress = 0
	local batch = {}

	for idx, folderData in ipairs(self.allAssets) do
		if self.skipped then break end
		self.activeIndex = idx
		self:updateActiveItem()
		local count = #folderData.assets

		currentProgress += 1
		if folderData.instance then
			ContentProvider:PreloadAsync({folderData.instance}, handleAssetError)
		end

		if count > 0 then
			for idx2, asset in ipairs(folderData.assets) do
				if self.skipped then break end
				table.insert(batch, asset)

				if #batch >= BATCH_SIZE or idx2 == #folderData.assets then
					ContentProvider:PreloadAsync(batch, handleAssetError)
					batch = {}
				end

				OnLoadingAsset:Fire(asset)

				currentProgress += 1
				self:updateLoadingProgress(currentProgress, self.activeIndex, idx2, count)

				if ModuleGlobals.Debug then
					task.wait(0.01)
				end
			end

			if #batch > 0 then
				ContentProvider:PreloadAsync(batch, handleAssetError)
				batch = {} 
			end

		else
			self:updateLoadingProgress(currentProgress, self.activeIndex, 0, 0)
		end

		folderData.loaded = true
	end
end

function LoadingScreen:finishLoading()
	if self.loadingScreenGui and self.loadingScreenGui.Parent then
		self.loadingScreenGui.Enabled = false
		self.loadingScreenGui:Destroy()
	end
	script:Destroy()
end

return LoadingScreen

