--[[
	Creates a ScreenGui, React root, and renders Shared.UI.RootUI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local RootUI = require(ReplicatedStorage.Shared.UI.RootUI)

local MountUI = {}

local reactRoot = nil
local screenGui: ScreenGui? = nil

function MountUI.Init()
	if reactRoot ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "ReactMount"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	gui.Parent = playerGui
	screenGui = gui

	reactRoot = ReactRoblox.createRoot(gui)
	reactRoot:render(React.createElement(RootUI.App))
end

function MountUI.Unmount()
	if reactRoot ~= nil then
		reactRoot:unmount()
		reactRoot = nil
	end
	if screenGui ~= nil then
		screenGui:Destroy()
		screenGui = nil
	end
end

return MountUI
