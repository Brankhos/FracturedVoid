--!strict

local runService = game:GetService("RunService")

local ModuleGlobals = {
    Version = "1.0.0",
    Loaded = false,
    Debug = false,
    Production = false,
    isStudio = runService:IsStudio(),
    Verbose = false,
    VerboseLevel = 0,
    VerboseLevelMax = 10,
    VerboseLevelMin = 0,
}

return ModuleGlobals