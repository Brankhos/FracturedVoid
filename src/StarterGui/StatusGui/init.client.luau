
local oLocalPlayer = game:GetService("Players").LocalPlayer -- Get The Player

local StatusFrame = script:WaitForChild("StatusGui"):WaitForChild("StatusFrame")
local PingFrame = StatusFrame:WaitForChild("PingFrame")
local PingLabel = PingFrame:WaitForChild("PingLabel")
local ClientFrame = StatusFrame:WaitForChild("ClientFrame")
local ClientLabel = ClientFrame:WaitForChild("ClientLabel")

local iCPULoad
local iPing



local signals = {
	tooth1 = "http://www.roblox.com/asset/?id=95246268190861",
	tooth2 = "http://www.roblox.com/asset/?id=70547817423774",
	tooth3 = "http://www.roblox.com/asset/?id=76177833351105",
	tooth4 = "http://www.roblox.com/asset/?id=73710223601391",
	tooth5 = "http://www.roblox.com/asset/?id=135867379093967",

}


while true do
	iCPULoad = oLocalPlayer:GetAttribute("LocalClientCPULoad") or 0
    iPing = oLocalPlayer:GetAttribute("LocalClientPing") or 0
	ClientLabel.Text = string.format("%.0f%%", iCPULoad)
	PingLabel.Text = string.format("%.0fms", iPing)
	task.wait(5)
end