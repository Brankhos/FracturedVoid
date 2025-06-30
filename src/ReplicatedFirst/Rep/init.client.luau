--!strict

local ReplicatedFirst = game:GetService("ReplicatedFirst")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local Utils = require(ReplicatedFirst:WaitForChild("Rep"):WaitForChild("Shared"):WaitForChild("utils"))
Utils.DisableCoreGui()

local Players = game:GetService("Players")
local SkeletonLoader = require(ReplicatedFirst:WaitForChild("Rep"):WaitForChild("SkeletonLoader"))

local skeletonLoader = SkeletonLoader.new()

skeletonLoader:start(Players.LocalPlayer)


local LoadingScreen = require(ReplicatedFirst:WaitForChild("Rep"):WaitForChild("LoadingScreen"))
local ModuleGlobals = require(ReplicatedFirst:WaitForChild("ModuleGlobals"))

-- LoadingScreen'i başlat
local loadingScreen = LoadingScreen.init()

-- Yükleme işlemini başlat
loadingScreen:startLoading()

-- Yükleme işlemini bitir
Utils.EnableCoreGui()
loadingScreen:finishLoading()

ModuleGlobals.Loaded = true