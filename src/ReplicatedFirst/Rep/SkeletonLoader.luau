local SkeletonLoader = {}
SkeletonLoader.__index = SkeletonLoader

-- StarterPlayer > StarterPlayerScripts içine LocalScript olarak yerleştir

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Sabitler
local CONSTANTS = {
    OFFSET = {
        DEFAULT = 2,
        TAG = 1.5,
        EXTENTS = 5
    },
    ASSETS = {
        LOADING = "rbxassetid://92821871588070",
        BONE = "rbxassetid://8132813933"
    },
    ANIMATION = {
        DURATION = 1.5,
        FADE_DURATION = 2,
        ROTATION_SPEED = 180
    }
}

-- Tween bilgileri
local tweenInfo = TweenInfo.new(
    CONSTANTS.ANIMATION.DURATION,
    Enum.EasingStyle.Sine,
    Enum.EasingDirection.InOut,
    -1,
    true
)

local fadeTweenInfo = TweenInfo.new(
    CONSTANTS.ANIMATION.FADE_DURATION,
    Enum.EasingStyle.Linear
)

function SkeletonLoader.new()
    local self = setmetatable({}, SkeletonLoader)
    return self
end

function SkeletonLoader:createBeamShimmer(part: BasePart)
    local attachment0 = Instance.new("Attachment", part)
    local attachment1 = Instance.new("Attachment", part)

    attachment0.Position = Vector3.new(0, part.Size.Y / 2, 0)
    attachment1.Position = Vector3.new(0, -part.Size.Y / 2, 0)

    local beam = Instance.new("Beam")
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Texture = CONSTANTS.ASSETS.BONE
    beam.TextureLength = 1
    beam.TextureSpeed = 2
    beam.Width0 = 0.2
    beam.Width1 = 0.2
    beam.Color = ColorSequence.new(Color3.fromRGB(180, 180, 180), Color3.fromRGB(220, 220, 220))
    beam.LightEmission = 1
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    beam.FaceCamera = true
    beam.Parent = part
end

function SkeletonLoader:createLoadingAnimation(character: Model)
    local head = character:FindFirstChild("Head")
    if not head then return end

    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "LoadingBillboard"
    billboardGui.Size = UDim2.new(1, 0, 1, 0)
    
    local extentsSize = character:GetExtentsSize()
    local excess = extentsSize.Y - CONSTANTS.OFFSET.EXTENTS
    billboardGui.StudsOffsetWorldSpace = Vector3.new(0, CONSTANTS.OFFSET.DEFAULT + excess + CONSTANTS.OFFSET.TAG, 0)
    
    billboardGui.Parent = head
    billboardGui.Adornee = head

    local loadingImage = Instance.new("ImageLabel")
    loadingImage.Name = "LoadingCircle"
    loadingImage.Size = UDim2.new(1, 0, 1, 0)
    loadingImage.BackgroundTransparency = 1
    loadingImage.Image = CONSTANTS.ASSETS.LOADING
    loadingImage.ImageTransparency = 0.5
    loadingImage.Parent = billboardGui

    local rotation = 0
    RunService.RenderStepped:Connect(function(deltaTime)
        rotation = (rotation + deltaTime * CONSTANTS.ANIMATION.ROTATION_SPEED) % 360
        loadingImage.Rotation = rotation
    end)
end

function SkeletonLoader:createSkeletonLoader(character: Model): Model
    local loaderModel = Instance.new("Model")
    loaderModel.Name = "SkeletonLoader"

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            local clone = Instance.new("Part")
            clone.Name = part.Name
            clone.Size = part.Size
            clone.CFrame = part.CFrame
            clone.Anchored = true
            clone.CanCollide = false
            clone.Material = Enum.Material.SmoothPlastic
            clone.BrickColor = BrickColor.Gray()
            clone.Transparency = 0.4

            local tween = TweenService:Create(clone, tweenInfo, {
                Transparency = 0.05,
                Size = part.Size * 1.05
            })
            tween.Name = "LoadingTween"
            tween.Parent = clone
            tween:Play()

            clone.Parent = loaderModel
            self:createBeamShimmer(clone)
        end
    end

    self:createLoadingAnimation(loaderModel)
    loaderModel.Parent = workspace
    return loaderModel
end

function SkeletonLoader:fadeOutModel(model: Model): {[number]: Tween}
    local tweens = {}
    
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local tween = part:FindFirstChild("LoadingTween")
            if tween then
                tween:Cancel()
                tween:Destroy()
            end
            tween = TweenService:Create(part, fadeTweenInfo, {Transparency = 0})
            tween.Name = "FadeOutTween"
            tween.Parent = part
            tween:Play()
            table.insert(tweens, tween)
        elseif part:IsA("Beam") then
            part.Transparency = NumberSequence.new(1)
        end
    end

    return tweens
end

function SkeletonLoader:start(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    character.Parent = nil
    local loader = self:createSkeletonLoader(character)

    task.delay(7, function()
        local fadeTweens = self:fadeOutModel(loader)
        
        local completedCount = 0
        local totalTweens = #fadeTweens
        
        for _, tween in ipairs(fadeTweens) do
            tween.Completed:Connect(function()
                completedCount += 1
                if completedCount == totalTweens then
                    loader:Destroy()
                    character.Parent = workspace
                end
            end)
        end
        
        if loader and loader.Parent then
            loader:Destroy()
            character.Parent = workspace
        end
    end)
end

return SkeletonLoader


