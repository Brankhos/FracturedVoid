--!strict

local Utils = {
    isCoreGuiDisabled = false,
    isControlsDisabled = false
}

-- Services
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

-- Constants
local MAX_WAIT_TIME = 5 -- Maksimum bekleme süresi (saniye)

-- Private Functions
local function waitForPlayerModule(player: Player): boolean
    local startTime = os.clock()
    while not player:FindFirstChild("PlayerModule") do
        if os.clock() - startTime > MAX_WAIT_TIME then
            warn("PlayerModule bulunamadı, zaman aşımı")
            return false
        end
        task.wait()
    end
    return true
end

local function getPlayerControls(player: Player)
    local playerModule = player:FindFirstChild("PlayerScripts") and 
                        player.PlayerScripts:FindFirstChild("PlayerModule")
    if not playerModule then return nil end
    
    local success, controls = pcall(function()
        return require(playerModule):GetControls()
    end)
    
    if not success then
        warn("Kontroller alınamadı:", controls)
        return nil
    end
    
    return controls
end

-- Public Functions
function Utils.DisableCoreGui()
    if not Utils.isCoreGuiDisabled then
        local success, err = pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        end)
        
        if success then
            Utils.isCoreGuiDisabled = true
        else
            warn("Core GUI devre dışı bırakılamadı:", err)
        end
    end
end

function Utils.DisableControls(force: boolean?)
    if not Utils.isControlsDisabled then
        local player = Players.LocalPlayer
        if not player then return end
        
        if force == nil then
            force = true
        end
        
        if force and not waitForPlayerModule(player) then
            return
        end
        
        if player.Character then
            local controls = getPlayerControls(player)
            if controls then
                controls:Enable(false)
                Utils.isControlsDisabled = true
            end
        end
    end
end

function Utils.EnableCoreGui()
    if Utils.isCoreGuiDisabled then
        local success, err = pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
        end)
        
        if success then
            Utils.isCoreGuiDisabled = false
        else
            warn("Core GUI etkinleştirilemedi:", err)
        end
    end
end

function Utils.EnableControls(force: boolean?)
    if Utils.isControlsDisabled then
        local player = Players.LocalPlayer
        if not player then return end
        
        if force == nil then
            force = true
        end
        
        if force and not waitForPlayerModule(player) then
            return
        end
        
        if player.Character then
            local controls = getPlayerControls(player)
            if controls then
                controls:Enable(true)
                Utils.isControlsDisabled = false
            end
        end
    end
end

return Utils 