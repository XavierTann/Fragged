--[[
	UI Labs story for GachaGUI.
	Point UI Labs at this module to preview the gacha screen without running the game.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local GachaGUI = require(Shared.UI.GachaGUI)

return function(target: Instance)
	local bg = Instance.new("Frame")
	bg.Name = "GachaStoryBg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Theme.BgVoid
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = target

	GachaGUI.BuildPreview(bg)

	return function()
		bg:Destroy()
	end
end
