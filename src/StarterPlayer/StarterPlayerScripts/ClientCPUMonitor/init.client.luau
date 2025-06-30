local LocalPlayer = game:GetService("Players").LocalPlayer
local CPUMonitor = require(game:GetService("ReplicatedStorage").Components.CPUMonitor)

-- İstemci tarafı izlemeyi başlat
CPUMonitor.StartMonitoring(LocalPlayer)