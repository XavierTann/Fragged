--[[
	WeaponSelectGUI
	Top-right bar with weapon buttons. Click to switch weapons.
	Uses raw asset IDs from WeaponIconsConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
local WeaponIconsConfig = require(ReplicatedStorage.Shared.Modules.WeaponIconsConfig)
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local gui = nil
local weaponBar = nil
local weaponBarContainer = nil
local buttonMap = {} -- gunId -> ImageButton
local ammoLabelMap = {} -- gunId -> TextLabel
local BAR_HEIGHT = 55
local BUTTON_WIDTH = 60
local BUTTON_GAP = 4
local BACKGROUND_TRANSPARENCY = 0.45
local ICON_TRANSPARENCY = 0.35

local function getIconImage(weaponId)
	local assetId = WeaponIconsConfig[weaponId]
	if not assetId or assetId == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(assetId)
end

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponSelectGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function updateSelection(gunId)
	for id, btn in pairs(buttonMap) do
		local selected = (id == gunId)
		if selected then
			btn.BackgroundColor3 = Color3.fromRGB(70, 90, 120)
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
			btn.ImageColor3 = Color3.fromRGB(200, 200, 200)
		end
		local fallback = btn:FindFirstChild("Fallback")
		if fallback then
			fallback.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
		end
		local ammoLabel = ammoLabelMap[id]
		if ammoLabel then
			ammoLabel.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
		end
	end
end

local function updateAmmoLabels()
	local weapons = CombatServiceClient.GetAvailableWeapons()
	for _, itemId in ipairs(weapons) do
		local label = ammoLabelMap[itemId]
		if label then
			if itemId == "Grenade" then
				local state = CombatServiceClient.GetGrenadeState()
				label.Text = string.format("%d/%d", state.count, state.max)
				label.Visible = true
			elseif itemId == "RocketLauncher" then
				local state = CombatServiceClient.GetRocketState()
				label.Text = string.format("%d/%d", state.count, state.max)
				label.Visible = true
			else
				local state = CombatServiceClient.GetAmmoState(itemId)
				label.Text = string.format("%d/%d", state.ammo, state.maxAmmo)
				label.Visible = true
			end
		end
	end
end

local function createWeaponBar(parent)
	local weapons = CombatServiceClient.GetAvailableWeapons()
	buttonMap = {}
	ammoLabelMap = {}
	if weaponBar then
		weaponBar:Destroy()
	end
	local totalWidth = #weapons * BUTTON_WIDTH + (#weapons - 1) * BUTTON_GAP
	local bar = Instance.new("Frame")
	bar.Name = "WeaponBar"
	bar.Size = UDim2.fromOffset(totalWidth + 16, BAR_HEIGHT + 12)
	bar.Position = UDim2.fromScale(1, 0)
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	bar.BackgroundTransparency = BACKGROUND_TRANSPARENCY
	bar.BorderSizePixel = 0
	bar.Parent = parent
	weaponBar = bar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bar

	for i, itemId in ipairs(weapons) do
		local accentColor = GunsConfig[itemId] and GunsConfig[itemId].bulletColor or nil
		if itemId == "Grenade" then
			accentColor = GrenadeConfig.color
		elseif itemId == "RocketLauncher" then
			accentColor = RocketLauncherConfig.color
		end

		local iconImage = getIconImage(itemId)

		local btn = Instance.new("ImageButton")
		btn.Name = itemId
		btn.Size = UDim2.fromOffset(BUTTON_WIDTH, BAR_HEIGHT)
		btn.Position = UDim2.fromOffset(8 + (i - 1) * (BUTTON_WIDTH + BUTTON_GAP), 6)
		btn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
		btn.BackgroundTransparency = BACKGROUND_TRANSPARENCY
		btn.Image = iconImage
		btn.ImageColor3 = Color3.fromRGB(200, 200, 200)
		btn.ImageTransparency = ICON_TRANSPARENCY
		btn.ScaleType = Enum.ScaleType.Fit
		btn.BorderSizePixel = 0
		btn.Parent = bar

		local fallbackLabel = Instance.new("TextLabel")
		fallbackLabel.Name = "Fallback"
		fallbackLabel.Size = UDim2.new(1, -6, 1, 0)
		fallbackLabel.Position = UDim2.fromOffset(3, 0)
		fallbackLabel.BackgroundTransparency = 1
		fallbackLabel.Text = itemId
		fallbackLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		fallbackLabel.TextSize = 10
		fallbackLabel.Font = Enum.Font.GothamMedium
		fallbackLabel.Visible = (iconImage == "")
		fallbackLabel.Parent = btn

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		local accent = Instance.new("Frame")
		accent.Size = UDim2.new(0, 3, 1, 0)
		accent.Position = UDim2.fromOffset(0, 0)
		accent.BackgroundColor3 = accentColor or Color3.fromRGB(150, 150, 150)
		accent.BorderSizePixel = 0
		accent.Parent = btn
		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(0, 8)
		accentCorner.Parent = accent

		local ammoLabel = Instance.new("TextLabel")
		ammoLabel.Name = "AmmoLabel"
		ammoLabel.Size = UDim2.new(1, -6, 0, 12)
		ammoLabel.Position = UDim2.new(0, 6, 1, 0)
		ammoLabel.AnchorPoint = Vector2.new(0, 1)
		ammoLabel.BackgroundTransparency = 1
		ammoLabel.Text = "0/0"
		ammoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		ammoLabel.TextSize = 9
		ammoLabel.Font = Enum.Font.GothamMedium
		ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
		ammoLabel.Parent = btn

		btn.MouseButton1Click:Connect(function()
			CombatServiceClient.SetCurrentWeapon(itemId)
			updateSelection(itemId)
		end)

		buttonMap[itemId] = btn
		ammoLabelMap[itemId] = ammoLabel
	end

	updateAmmoLabels()
	updateSelection(CombatServiceClient.GetCurrentWeapon())
	return bar
end

local function refreshWeaponBar()
	if weaponBarContainer then
		createWeaponBar(weaponBarContainer)
		updateAmmoLabels()
		updateSelection(CombatServiceClient.GetCurrentWeapon())
	end
end

local function init()
	createGui()
	local container = Instance.new("Frame")
	container.Name = "WeaponSelectContainer"
	container.Size = UDim2.fromScale(1, 1)
	container.Position = UDim2.fromScale(0, 0)
	container.BackgroundTransparency = 1
	container.Parent = gui
	weaponBarContainer = container
	createWeaponBar(container)
	CombatServiceClient.SubscribeAmmoState(updateAmmoLabels)
	CombatServiceClient.SubscribeWeaponChanged(function()
		updateAmmoLabels()
		updateSelection(CombatServiceClient.GetCurrentWeapon())
	end)
	CombatServiceClient.SubscribeWeaponInventory(refreshWeaponBar)
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateAmmoLabels()
			updateSelection(CombatServiceClient.GetCurrentWeapon())
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
