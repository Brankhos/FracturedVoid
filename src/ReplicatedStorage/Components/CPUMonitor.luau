--!native

local CPUMonitor = {}

-- Servisler
local runService = game:GetService("RunService")
local Players = game:GetService("Players")

local isClient = runService:IsClient()

local iFrameTicks = 0
local iMaxFrames = 1
local iSampleInterval = 5

local function getPing(): number
    if isClient then
        local oLocalPlayer = Players.LocalPlayer
        local success, ping = pcall(function()
            return oLocalPlayer:GetNetworkPing()
        end)
        if success then
            return ping
        else
            return 9999
        end
    else
        return 9999
    end
end


local function getStats(): table
    local success, result = pcall(function()

        local iCPULoad = math.round((1 - (iFrameTicks / iMaxFrames)) * 100)
        local iPhysicsLoad = math.round((1 - (workspace:GetRealPhysicsFPS() / 60)) * 100)

        local iTotalLoad = iCPULoad + iPhysicsLoad
        iTotalLoad = math.clamp(iTotalLoad, 0, 100)

        return {
            iCPULoad = iCPULoad,
            iPhysicsLoad = iPhysicsLoad,
            iTotalLoad = iTotalLoad,
        }
    end)
    
    if not success then
        warn("Performans istatistikleri alınamadı:", result)
        result = {
            iCPULoad = 0,
            iPhysicsLoad = 0,
            iTotalLoad = 0,
        }
    end

    if isClient then
        result.ping = getPing()
    end

    return result
end




-- Özellik güncelleme fonksiyonu
local function updateAttributes(target: Instance, stats: table)
    local prefix = isClient and "LocalClient" or "Server"
    
    -- Temel metrikler
    target:SetAttribute(prefix .. "CPULoad", stats.iCPULoad)
    print(prefix .."CPULoad: " .. stats.iCPULoad)
    
    -- Render metrikleri
    if isClient then
        target:SetAttribute(prefix .. "Ping", stats.ping)
        print(prefix .. "Ping: " .. stats.ping)
    end
end

-- Ana izleme fonksiyonu
function CPUMonitor.StartMonitoring(target: Instance)


    -- Ana izleme döngüsü
    task.spawn(function()
        local iFrameStartTime
        while true do
            iFrameTicks = 0
            iFrameStartTime = os.clock()

            while os.clock() - iFrameStartTime < iSampleInterval do
                runService.Heartbeat:Wait()
                iFrameTicks += 1
            end

            if iFrameTicks > iMaxFrames then
                iMaxFrames = iFrameTicks
            elseif iFrameTicks < iMaxFrames - 2 then
                iMaxFrames -= 1
            end
            

            updateAttributes(target, getStats())
        end
    end)
end

return CPUMonitor 