--[[
	UI Labs story for LoadoutGUI.
	Point UI Labs at this module to preview the loadout screen without running the game.
	All weapons show as owned for easy iteration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local LoadoutGUI = require(Shared.UI.LoadoutGUI)

return function(target: Instance)
	local bg = Instance.new("Frame")
	bg.Name = "LoadoutStoryBg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Theme.BgVoid
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = target

	LoadoutGUI.BuildPreview(bg)

	return function()
		bg:Destroy()
	end
end
