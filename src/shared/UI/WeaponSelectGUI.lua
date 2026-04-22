--[[
	WeaponSelectGUI
	Top-right bar with weapon buttons. Click to switch weapons.
	Uses raw asset IDs from WeaponIconsConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
local WeaponIconsConfig = require(ReplicatedStorage.Shared.Modules.WeaponIconsConfig)
local SkinsConfig = require(ReplicatedStorage.Shared.Modules.SkinsConfig)
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)
local CenterScreenToast = require(ReplicatedStorage.Shared.UI.CenterScreenToast)
local LoadoutGUI = require(ReplicatedStorage.Shared.UI.LoadoutGUI)

local gui = nil
local weaponBar = nil
local weaponBarContainer = nil
local buttonMap = {} -- gunId -> ImageButton
local ammoLabelMap = {} -- gunId -> TextLabel
local fireHintLabel = nil
local hintFlashTween = nil
local hasFlashedHint = false

local function stopHintFlash()
	if hintFlashTween then
		hintFlashTween:Cancel()
		hintFlashTween = nil
	end
	if fireHintLabel then
		fireHintLabel.TextTransparency = 0
	end
end

local HINT_FLASH_CYCLES = 6
local HINT_FLASH_HALF = 0.35

local function startHintFlash()
	if not fireHintLabel then
		return
	end
	stopHintFlash()

	local cyclesLeft = HINT_FLASH_CYCLES * 2
	local tweenFade = TweenService:Create(fireHintLabel, TweenInfo.new(HINT_FLASH_HALF, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0.7 })
	local tweenShow = TweenService:Create(fireHintLabel, TweenInfo.new(HINT_FLASH_HALF, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0 })

	local fadingOut = true
	local function step()
		cyclesLeft -= 1
		if cyclesLeft <= 0 or not fireHintLabel or not fireHintLabel.Parent then
			stopHintFlash()
			return
		end
		fadingOut = not fadingOut
		if fadingOut then
			hintFlashTween = tweenFade
			tweenFade:Play()
			tweenFade.Completed:Once(step)
		else
			hintFlashTween = tweenShow
			tweenShow:Play()
			tweenShow.Completed:Once(step)
		end
	end

	hintFlashTween = tweenFade
	tweenFade:Play()
	tweenFade.Completed:Once(step)
end

local RELEASE_TO_FIRE_WEAPONS = {
	Shotgun = true,
	Grenade = true,
	RocketLauncher = true,
	HeliosThread = true,
}

local weaponEquipCount = {} -- weaponId -> number of times equipped

local function getFireModeText(weaponId)
	if weaponId == "HeliosThread" then
		return "Release to charge — locked, then beam", Color3.fromRGB(200, 170, 0)
	end
	if RELEASE_TO_FIRE_WEAPONS[weaponId] then
		return "Release to Fire", Color3.fromRGB(200, 170, 0)
	end
	return "Hold to Fire", Color3.fromRGB(255, 80, 80)
end

local function showFireModeToast(weaponId)
	if not weaponId then
		return
	end
	weaponEquipCount[weaponId] = (weaponEquipCount[weaponId] or 0) + 1
	local count = weaponEquipCount[weaponId]
	local isRelease = RELEASE_TO_FIRE_WEAPONS[weaponId]

	-- Release-to-fire: toast on first equip; Hold-to-fire: toast on second equip
	if isRelease and count ~= 1 then
		return
	end
	if not isRelease and count ~= 2 then
		return
	end

	local text, color = getFireModeText(weaponId)
	local displayName = weaponId
	local gun = GunsConfig[weaponId]
	if gun and gun.name then
		displayName = gun.name
	end
	CenterScreenToast.Show({
		text = displayName .. ": " .. text,
		textColor = color,
		holdSeconds = 2.5,
		fadeSeconds = 0.5,
		textSize = 18,
	})
end
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

local function getSkinIcon(skinDef)
	if not skinDef then
		return ""
	end
	local decalName = skinDef.iconDecalName
	if decalName then
		local imports = ReplicatedStorage:FindFirstChild("Imports")
		local decals = imports and imports:FindFirstChild("Decals")
		local decal = decals and decals:FindFirstChild(decalName)
		if decal and decal:IsA("Decal") and decal.Texture ~= "" then
			return decal.Texture
		end
	end
	if skinDef.iconAssetId and skinDef.iconAssetId ~= 0 then
		return "rbxassetid://" .. tostring(skinDef.iconAssetId)
	end
	return ""
end

local function getWeaponIcon(weaponId)
	local skins = LoadoutGUI.GetEquippedSkins()
	local skinId = skins[weaponId]
	if skinId then
		local skinDef = SkinsConfig.getSkin(skinId)
		local icon = getSkinIcon(skinDef)
		if icon ~= "" then
			return icon
		end
	end
	return getIconImage(weaponId)
end

local function refreshButtonIcons()
	for weaponId, btn in pairs(buttonMap) do
		btn.Image = getWeaponIcon(weaponId)
	end
end

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponSelectGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
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
	if fireHintLabel then
		local text, color = getFireModeText(gunId)
		fireHintLabel.Text = text
		fireHintLabel.TextColor3 = color
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

		local iconImage = getWeaponIcon(itemId)

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

	fireHintLabel = Instance.new("TextLabel")
	fireHintLabel.Name = "FireHintLabel"
	fireHintLabel.Size = UDim2.new(0, 0, 0, 18)
	fireHintLabel.AutomaticSize = Enum.AutomaticSize.X
	fireHintLabel.Position = UDim2.new(1, 0, 1, 4)
	fireHintLabel.AnchorPoint = Vector2.new(1, 0)
	fireHintLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fireHintLabel.BackgroundTransparency = 0.4
	fireHintLabel.BorderSizePixel = 0
	local hintText, hintColor = getFireModeText(CombatServiceClient.GetCurrentWeapon())
	fireHintLabel.Text = hintText
	fireHintLabel.TextColor3 = hintColor
	fireHintLabel.TextSize = 10
	fireHintLabel.Font = Enum.Font.GothamBold
	fireHintLabel.TextXAlignment = Enum.TextXAlignment.Center
	fireHintLabel.Parent = bar

	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 6)
	hintCorner.Parent = fireHintLabel

	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 6)
	hintPad.PaddingRight = UDim.new(0, 6)
	hintPad.Parent = fireHintLabel

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
		local currentWeapon = CombatServiceClient.GetCurrentWeapon()
		updateAmmoLabels()
		updateSelection(currentWeapon)
		showFireModeToast(currentWeapon)
	end)
	CombatServiceClient.SubscribeWeaponInventory(refreshWeaponBar)
	LoadoutGUI.SubscribeSkinsChanged(refreshButtonIcons)
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateAmmoLabels()
			updateSelection(CombatServiceClient.GetCurrentWeapon())
			if not hasFlashedHint then
				hasFlashedHint = true
				task.delay(1, startHintFlash)
			end
		end
	end,
	Hide = function()
		stopHintFlash()
		if gui then
			gui.Enabled = false
		end
	end,
}
