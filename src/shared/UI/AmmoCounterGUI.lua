--[[
	AmmoCounterGUI
	Simple ammo counter (current/max) at bottom right of screen.
	Hidden when Grenade is selected.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local BULLET_ICON_ID = 91340135

local gui = nil
local containerFrame = nil
local label = nil

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "AmmoCounterGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function updateCounter()
	if not label or not containerFrame then
		return
	end
	local weaponId = CombatServiceClient.GetCurrentWeapon()
	if weaponId == "Grenade" then
		containerFrame.Visible = false
		return
	end
	containerFrame.Visible = true
	local state = CombatServiceClient.GetAmmoState(weaponId)
	label.Text = string.format("%d/%d", state.ammo, state.maxAmmo)
end

local function init()
	createGui()
	local root = Instance.new("Frame")
	root.Name = "AmmoCounterRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundTransparency = 1
	root.Parent = gui

	containerFrame = Instance.new("Frame")
	containerFrame.Name = "AmmoCounterContainer"
	containerFrame.Size = UDim2.fromOffset(120, 32)
	containerFrame.Position = UDim2.new(1, -130, 1, -50)
	containerFrame.AnchorPoint = Vector2.new(1, 1)
	containerFrame.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	containerFrame.BackgroundTransparency = 0.2
	containerFrame.BorderSizePixel = 0
	containerFrame.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = containerFrame

	local icon = Instance.new("ImageLabel")
	icon.Name = "BulletIcon"
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Position = UDim2.fromOffset(6, 4)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://" .. tostring(BULLET_ICON_ID)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = containerFrame

	label = Instance.new("TextLabel")
	label.Name = "AmmoCounter"
	label.Size = UDim2.new(1, -40, 1, 0)
	label.Position = UDim2.fromOffset(36, 0)
	label.BackgroundTransparency = 1
	label.Text = "0/0"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 18
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = containerFrame

	CombatServiceClient.SubscribeAmmoState(updateCounter)
	CombatServiceClient.SubscribeWeaponChanged(updateCounter)
	updateCounter()
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateCounter()
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
