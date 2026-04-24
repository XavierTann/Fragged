--[[
	LoadoutGUI
	Full-screen loadout configuration overlay. Two weapon slots (Primary + Secondary).
	Top: available weapons split by category. Right: detail panel. Bottom: equipped slots.
	Sci-fi neon aesthetic using ShopTheme.
	All sizing and positioning uses Scale (UDim2.fromScale) for cross-device responsiveness.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local LoadoutConfig = require(Shared.Modules.LoadoutConfig)
local UIConfig = require(Shared.Modules.LoadoutGUIConfig)
local WeaponIconsConfig = require(Shared.Modules.WeaponIconsConfig)
local ShopCatalog = require(Shared.Modules.ShopCatalog)
local CombatConfig = require(Shared.Modules.CombatConfig)
local SkinsConfig = require(Shared.Modules.SkinsConfig)

local LocalPlayer = Players.LocalPlayer
local ShopEconomyClient = nil

local gui = nil
local visible = false
local selectedWeaponId = nil
local equippedPrimary = LoadoutConfig.DEFAULT.primary
local equippedSecondary = LoadoutConfig.DEFAULT.secondary
local equippedSkins: { [string]: string? } = {}

local detailFrame = nil
local equippedPrimaryIcon = nil
local equippedSecondaryIcon = nil
local primaryButtons = {}
local secondaryButtons = {}

local savedWalkSpeed = nil
local savedJumpHeight = nil
local loadoutRE = nil

local LoadoutGUI = {}
local onCloseCallbacks = {}
local skinChangeCallbacks = {}

local CORNER_RADIUS    = UIConfig.CornerRadius

local MODAL_W          = UIConfig.Modal.Width
local MODAL_H          = UIConfig.Modal.Height
local PAD_X            = UIConfig.Layout.PadX
local HEADER_H         = UIConfig.Layout.HeaderH
local LEFT_COL_W       = UIConfig.Layout.LeftColW
local DETAIL_PANEL_W   = UIConfig.DetailPanel.Width
local DETAIL_PANEL_X   = UIConfig.DetailPanel.PosX
local ROW_LABEL_H      = UIConfig.Layout.RowLabelH
local ROW_GAP          = UIConfig.Layout.RowGap
local ICON_ROW_H       = UIConfig.Layout.IconRowH
local EQUIPPED_BAR_H   = UIConfig.Layout.EquippedBarH

local function getIconImage(weaponId)
	local assetId = WeaponIconsConfig[weaponId]
	if not assetId or assetId == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(assetId)
end

local function getTempWeaponRounds(weaponId): number?
	if not ShopEconomyClient then
		return nil
	end
	local snap = ShopEconomyClient.GetSnapshot()
	for _, tw in ipairs(snap.tempWeapons or {}) do
		if tw.id == weaponId and tw.roundsLeft > 0 then
			return tw.roundsLeft
		end
	end
	return nil
end

local function isWeaponOwned(weaponId)
	if not ShopCatalog.isShopGun(weaponId) then
		return true
	end
	if not ShopEconomyClient then
		return false
	end
	local snap = ShopEconomyClient.GetSnapshot()
	if snap.ownedShopGunIds[weaponId] == true then
		return true
	end
	if getTempWeaponRounds(weaponId) then
		return true
	end
	return false
end

local function getAccentColor(weaponId)
	local w = LoadoutConfig.WEAPONS[weaponId]
	if not w then
		return Theme.NeonCyan
	end
	if w.category == LoadoutConfig.CATEGORY.PRIMARY then
		return Theme.NeonCyan
	end
	return Theme.NeonMagenta
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or CORNER_RADIUS)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.NeonCyan
	s.Thickness = thickness or 1.5
	s.Transparency = 0.3
	s.Parent = parent
	return s
end

local function freezeMovement()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if savedWalkSpeed == nil then
		savedWalkSpeed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
		savedJumpHeight = hum.JumpHeight
	end
	hum.WalkSpeed = 0
	hum.JumpHeight = 0
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

local function restoreMovement()
	local walk = savedWalkSpeed
	local jump = savedJumpHeight
	savedWalkSpeed = nil
	savedJumpHeight = nil
	if walk == nil then
		return
	end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = walk
		hum.JumpHeight = jump or hum.JumpHeight
		return
	end
	local conn
	conn = LocalPlayer.CharacterAdded:Connect(function(newChar)
		conn:Disconnect()
		local newHum = newChar:WaitForChild("Humanoid", 5)
		if newHum then
			newHum.WalkSpeed = walk
			newHum.JumpHeight = jump or newHum.JumpHeight
		end
	end)
end

local function sendLoadoutToServer()
	if not loadoutRE then
		local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
		if folder then
			loadoutRE = folder:FindFirstChild(CombatConfig.REMOTES.LOADOUT_SELECT)
		end
	end
	if loadoutRE then
		loadoutRE:FireServer({ primary = equippedPrimary, secondary = equippedSecondary, skins = equippedSkins })
	end
	for _, cb in ipairs(skinChangeCallbacks) do
		task.spawn(cb, equippedSkins)
	end
end



local function updateButtonHighlights()
	for id, btn in pairs(primaryButtons) do
		local equipped = (id == equippedPrimary)
		local s = btn:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = equipped and Theme.NeonCyan or Theme.TextMuted
			s.Thickness = equipped and 2.5 or 1
			s.Transparency = equipped and 0 or 0.6
		end
	end
	for id, btn in pairs(secondaryButtons) do
		local equipped = (id == equippedSecondary)
		local s = btn:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = equipped and Theme.NeonMagenta or Theme.TextMuted
			s.Thickness = equipped and 2.5 or 1
			s.Transparency = equipped and 0 or 0.6
		end
	end
end

local function getSkinIconImage(skinDef)
	if not skinDef then
		return ""
	end
	local decalName = skinDef.iconDecalName
	if decalName then
		local imports = ReplicatedStorage:FindFirstChild("Imports")
		local decals = imports and imports:FindFirstChild("Decals")
		local decal = decals and decals:FindFirstChild(decalName)
		if decal and decal:IsA("Decal") then
			local tex = decal.Texture
			if tex and tex ~= "" then
				return tex
			end
		end
	end
	if skinDef.iconAssetId and skinDef.iconAssetId ~= 0 then
		return "rbxassetid://" .. tostring(skinDef.iconAssetId)
	end
	return ""
end

local function getEquippedWeaponIcon(weaponId)
	local skinId = equippedSkins[weaponId]
	if skinId then
		local skinDef = SkinsConfig.getSkin(skinId)
		local skinIcon = getSkinIconImage(skinDef)
		if skinIcon ~= "" then
			return skinIcon
		end
	end
	return getIconImage(weaponId)
end

local function updateWeaponButtonIcon(weaponId)
	local btn = primaryButtons[weaponId] or secondaryButtons[weaponId]
	if btn then
		btn.Image = getEquippedWeaponIcon(weaponId)
	end
end

local function updateEquippedSlots()
	if equippedPrimaryIcon then
		equippedPrimaryIcon.Image = getEquippedWeaponIcon(equippedPrimary)
	end
	if equippedSecondaryIcon then
		equippedSecondaryIcon.Image = getEquippedWeaponIcon(equippedSecondary)
	end
end

local function updateDetailWeaponIcon(weaponId)
	local iconImg = detailFrame and detailFrame:FindFirstChild("WeaponIcon")
	if not iconImg then
		return
	end
	local equippedSkinId = equippedSkins[weaponId]
	if equippedSkinId then
		local skinDef = SkinsConfig.getSkin(equippedSkinId)
		local skinIcon = getSkinIconImage(skinDef)
		if skinIcon ~= "" then
			iconImg.Image = skinIcon
			return
		end
	end
	iconImg.Image = getIconImage(weaponId)
end

local function refreshSkinsSection(weaponId)
	local skinsLabel = detailFrame and detailFrame:FindFirstChild("SkinsLabel")
	local skinsFrame = detailFrame and detailFrame:FindFirstChild("SkinsFrame")
	if not skinsFrame or not skinsLabel then
		return
	end

	for _, child in ipairs(skinsFrame:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local skinIds = SkinsConfig.getSkinsForWeapon(weaponId)
	if #skinIds == 0 then
		skinsLabel.Visible = false
		skinsFrame.Visible = false
		return
	end

	local snap = ShopEconomyClient and ShopEconomyClient.GetSnapshot() or nil
	local ownedSkinIds = (snap and snap.ownedSkinIds) or {}

	local lockLabel = detailFrame:FindFirstChild("LockLabel")
	local lockVisible = lockLabel and lockLabel.Visible
	local skinStartY = lockVisible and UIConfig.SkinsLabel.PosYLocked or UIConfig.SkinsLabel.PosYUnlocked
	skinsLabel.Position = UDim2.fromScale(UIConfig.SkinsLabel.PosX, skinStartY)

	local frameY = lockVisible and UIConfig.SkinsFrame.PosYLocked or UIConfig.SkinsFrame.PosYUnlocked
	local isDefault = equippedSkins[weaponId] == nil
	local layoutOrder = 0

	local function makeSkinBtn(parent, image, selected, owned, onClick)
		local btn = Instance.new("ImageButton")
		btn.Size = UDim2.fromScale(UIConfig.SkinBtn.Width, 1)
		btn.LayoutOrder = layoutOrder
		btn.BackgroundColor3 = Theme.Card
		btn.BackgroundTransparency = 0.15
		btn.Image = image
		btn.ScaleType = Enum.ScaleType.Fit
		btn.ImageColor3 = owned and Color3.new(1, 1, 1) or Color3.fromRGB(70, 70, 70)
		btn.ImageTransparency = owned and 0 or 0.55
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = owned
		btn.Parent = parent

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = btn

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, UIConfig.SkinBtn.CornerRadius)
		c.Parent = btn

		local s = Instance.new("UIStroke")
		s.Parent = btn
		if selected then
			s.Color = Theme.NeonMagenta
			s.Thickness = 2.5
			s.Transparency = 0
		else
			s.Color = Theme.TextMuted
			s.Thickness = 1
			s.Transparency = 0.6
		end

		if not owned then
			local lock = Instance.new("TextLabel")
			lock.Name = "LockOverlay"
			lock.Size = UDim2.fromScale(UIConfig.LockOverlay.Width, UIConfig.LockOverlay.Height)
			lock.Position = UDim2.fromScale(UIConfig.LockOverlay.PosX, UIConfig.LockOverlay.PosY)
			lock.AnchorPoint = Vector2.new(0.5, 0.5)
			lock.BackgroundTransparency = UIConfig.LockOverlay.BgTransparency
			lock.BackgroundColor3 = Theme.BgVoid
			lock.Text = UIConfig.LockOverlay.IconText
			lock.Font = Enum.Font.GothamBold
			lock.TextColor3 = Theme.TextMuted
			lock.TextScaled = true
			lock.Parent = btn
			local lc = Instance.new("UICorner")
			lc.CornerRadius = UDim.new(0, UIConfig.SkinBtn.CornerRadius)
			lc.Parent = lock
		end

		if owned and onClick then
			btn.MouseButton1Click:Connect(onClick)
		end

		layoutOrder += 1
		return btn
	end

	makeSkinBtn(skinsFrame, getIconImage(weaponId), isDefault, true, function()
		equippedSkins[weaponId] = nil
		sendLoadoutToServer()
		updateDetailWeaponIcon(weaponId)
		updateWeaponButtonIcon(weaponId)
		updateEquippedSlots()
		refreshSkinsSection(weaponId)
	end)

	for _, skinId in ipairs(skinIds) do
		local skinDef = SkinsConfig.getSkin(skinId)
		if not skinDef then
			continue
		end
		local owned = ownedSkinIds[skinId] == true
		local selected = equippedSkins[weaponId] == skinId

		makeSkinBtn(skinsFrame, getSkinIconImage(skinDef), selected, owned, function()
			equippedSkins[weaponId] = skinId
			sendLoadoutToServer()
			updateDetailWeaponIcon(weaponId)
			updateWeaponButtonIcon(weaponId)
			updateEquippedSlots()
			refreshSkinsSection(weaponId)
		end)
	end

	skinsFrame.Position = UDim2.fromScale(UIConfig.SkinsFrame.PosX, frameY)
	skinsFrame.Size = UDim2.fromScale(UIConfig.SkinsFrame.Width, UIConfig.SkinsFrame.Height)
	if skinsFrame:IsA("ScrollingFrame") then
		skinsFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
		skinsFrame.ScrollingDirection = Enum.ScrollingDirection.X
	end
	skinsLabel.Visible = true
	skinsFrame.Visible = true

	updateDetailWeaponIcon(weaponId)
end

local function showDetailPanel(weaponId)
	selectedWeaponId = weaponId
	if not detailFrame then
		return
	end
	local w = LoadoutConfig.WEAPONS[weaponId]
	if not w then
		detailFrame.Visible = false
		return
	end

	local nameLabel = detailFrame:FindFirstChild("WeaponName")
	local descLabel = detailFrame:FindFirstChild("WeaponDesc")
	local equipBtn = detailFrame:FindFirstChild("EquipBtn")
	local iconImg = detailFrame:FindFirstChild("WeaponIcon")
	local lockLabel = detailFrame:FindFirstChild("LockLabel")

	if nameLabel then
		nameLabel.Text = string.upper(w.name)
	end
	if descLabel then
		descLabel.Text = w.desc
	end
	if iconImg then
		local equippedSkinId = equippedSkins[weaponId]
		if equippedSkinId then
			local skinDef = SkinsConfig.getSkin(equippedSkinId)
			local skinIcon = getSkinIconImage(skinDef)
			if skinIcon ~= "" then
				iconImg.Image = skinIcon
			else
				iconImg.Image = getIconImage(weaponId)
			end
		else
			iconImg.Image = getIconImage(weaponId)
		end
	end

	local owned = isWeaponOwned(weaponId)
	local tempRounds = getTempWeaponRounds(weaponId)
	local alreadyEquipped = (w.category == LoadoutConfig.CATEGORY.PRIMARY and weaponId == equippedPrimary)
		or (w.category == LoadoutConfig.CATEGORY.SECONDARY and weaponId == equippedSecondary)

	if equipBtn then
		if not owned then
			equipBtn.Text = "LOCKED"
			equipBtn.BackgroundColor3 = Theme.PanelDeep
			equipBtn.TextColor3 = Theme.TextMuted
		elseif alreadyEquipped then
			equipBtn.Text = "EQUIPPED"
			equipBtn.BackgroundColor3 = Theme.PanelDeep
			equipBtn.TextColor3 = Theme.NeonLime
		else
			equipBtn.Text = "EQUIP"
			equipBtn.BackgroundColor3 = getAccentColor(weaponId)
			equipBtn.TextColor3 = Theme.BgVoid
		end
	end
	if lockLabel then
		if not owned then
			lockLabel.Text = "Purchase from shop to unlock"
			lockLabel.Visible = true
		elseif tempRounds then
			lockLabel.Text = tempRounds .. " rounds remaining"
			lockLabel.TextColor3 = Theme.NeonAmber
			lockLabel.Visible = true
		else
			lockLabel.Visible = false
		end
	end

	refreshSkinsSection(weaponId)
	detailFrame.Visible = true
end

local function syncWeaponButtonOwnership(btn, weaponId)
	local owned = isWeaponOwned(weaponId)
	local tempRounds = getTempWeaponRounds(weaponId)
	btn.ImageColor3 = owned and Color3.new(1, 1, 1) or Color3.fromRGB(80, 80, 80)
	btn.ImageTransparency = owned and 0 or 0.55

	local lock = btn:FindFirstChild("LockOverlay")
	local badge = btn:FindFirstChild("TempBadge")

	if owned then
		if lock then
			lock:Destroy()
		end
		if tempRounds then
			if not badge then
				badge = Instance.new("TextLabel")
				badge.Name = "TempBadge"
				badge.Size = UDim2.fromScale(UIConfig.TempBadge.Width, UIConfig.TempBadge.Height)
				badge.Position = UDim2.fromScale(UIConfig.TempBadge.PosX, UIConfig.TempBadge.PosY)
				badge.AnchorPoint = Vector2.new(1, 1)
				badge.BackgroundColor3 = Theme.NeonAmber
				badge.BackgroundTransparency = 0.1
				badge.Font = Enum.Font.GothamBold
				badge.TextColor3 = Theme.BgVoid
				badge.TextScaled = true
				badge.Parent = btn
				corner(badge, UIConfig.TempBadge.CornerRadius)
			end
			badge.Text = tempRounds .. "R"
			badge.Visible = true
		else
			if badge then
				badge.Visible = false
			end
		end
	else
		if badge then
			badge.Visible = false
		end
		if not lock then
			local lockLabel = Instance.new("TextLabel")
			lockLabel.Name = "LockOverlay"
			lockLabel.Size = UDim2.fromScale(UIConfig.LockOverlay.Width, UIConfig.LockOverlay.Height)
			lockLabel.Position = UDim2.fromScale(UIConfig.LockOverlay.PosX, UIConfig.LockOverlay.PosY)
			lockLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			lockLabel.BackgroundTransparency = UIConfig.LockOverlay.BgTransparency
			lockLabel.BackgroundColor3 = Theme.BgVoid
			lockLabel.Text = UIConfig.LockOverlay.IconText
			lockLabel.Font = Enum.Font.GothamBold
			lockLabel.TextColor3 = Theme.TextMuted
			lockLabel.TextScaled = true
			lockLabel.Parent = btn
			corner(lockLabel, UIConfig.WeaponBtn.CornerRadius)
		end
	end
end

local function refreshAllWeaponButtonLocks()
	for id, btn in pairs(primaryButtons) do
		syncWeaponButtonOwnership(btn, id)
	end
	for id, btn in pairs(secondaryButtons) do
		syncWeaponButtonOwnership(btn, id)
	end
end

local function equipSelected()
	if not selectedWeaponId then
		return
	end
	if not isWeaponOwned(selectedWeaponId) then
		return
	end
	local w = LoadoutConfig.WEAPONS[selectedWeaponId]
	if not w then
		return
	end
	if w.category == LoadoutConfig.CATEGORY.PRIMARY then
		equippedPrimary = selectedWeaponId
	elseif w.category == LoadoutConfig.CATEGORY.SECONDARY then
		equippedSecondary = selectedWeaponId
	end
	updateEquippedSlots()
	updateButtonHighlights()
	showDetailPanel(selectedWeaponId)
	sendLoadoutToServer()
end

local function createWeaponButton(parent, weaponId, layoutOrder)
	local w = LoadoutConfig.WEAPONS[weaponId]
	if not w then
		return nil
	end
	local btn = Instance.new("ImageButton")
	btn.Name = weaponId
	btn.Size = UDim2.fromScale(UIConfig.WeaponBtn.Width, 1)
	btn.LayoutOrder = layoutOrder
	btn.BackgroundColor3 = Theme.Card
	btn.BackgroundTransparency = 0.15
	btn.Image = getEquippedWeaponIcon(weaponId)
	btn.ScaleType = Enum.ScaleType.Fit
	btn.BorderSizePixel = 0
	btn.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = btn

	corner(btn, UIConfig.WeaponBtn.CornerRadius)
	stroke(btn, Theme.TextMuted, 1)
	syncWeaponButtonOwnership(btn, weaponId)

	btn.MouseButton1Click:Connect(function()
		showDetailPanel(weaponId)
		updateButtonHighlights()
	end)

	return btn
end

local function buildModal(parent)
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromScale(MODAL_W, MODAL_H)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Theme.Panel
	modal.BackgroundTransparency = 0
	modal.BorderSizePixel = 0
	modal.ClipsDescendants = true
	modal.Parent = parent

	corner(modal, CORNER_RADIUS)
	stroke(modal, Theme.NeonCyan, 2)

	local modalBg = Instance.new("ImageLabel")
	modalBg.Name = "Background"
	modalBg.Size = UDim2.fromScale(1, 1)
	modalBg.BackgroundTransparency = 1
	modalBg.Image = "rbxassetid://95341433832521"
	modalBg.ScaleType = Enum.ScaleType.Crop
	modalBg.ImageTransparency = 0.3
	modalBg.ZIndex = 0
	modalBg.Parent = modal
	corner(modalBg, CORNER_RADIUS)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromScale(UIConfig.CloseBtn.Width, UIConfig.CloseBtn.Height)
	closeBtn.Position = UDim2.fromScale(UIConfig.CloseBtn.PosX, UIConfig.CloseBtn.PosY)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Theme.PanelDeep
	closeBtn.BackgroundTransparency = 0
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "X"

	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextColor3 = Theme.TextBright
	closeBtn.TextScaled = true
	closeBtn.Parent = modal
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.Parent = closeBtn
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Theme.NeonMagenta
	closeStroke.Thickness = 1
	closeStroke.Transparency = 0.2
	closeStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		LoadoutGUI.Hide()
	end)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(UIConfig.Title.Width, UIConfig.Title.Height)
	title.Position = UDim2.fromScale(UIConfig.Title.PosX, UIConfig.Title.PosY)
	title.BackgroundTransparency = 1
	title.Text = "LOADOUT"

	title.Font = Theme.FontDisplay
	title.TextColor3 = Theme.NeonCyan
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = modal

	local cursorY = HEADER_H

	local primaryLabel = Instance.new("TextLabel")
	primaryLabel.Size = UDim2.fromScale(LEFT_COL_W, ROW_LABEL_H)
	primaryLabel.Position = UDim2.fromScale(PAD_X, cursorY)
	primaryLabel.BackgroundTransparency = 1
	primaryLabel.Text = "PRIMARY"

	primaryLabel.Font = Theme.FontBody
	primaryLabel.TextColor3 = Theme.NeonCyan
	primaryLabel.TextScaled = true
	primaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	primaryLabel.Parent = modal

	cursorY = cursorY + ROW_LABEL_H

	local primaryFrame = Instance.new("Frame")
	primaryFrame.Name = "PrimaryWeapons"
	primaryFrame.Size = UDim2.fromScale(LEFT_COL_W, ICON_ROW_H)
	primaryFrame.Position = UDim2.fromScale(PAD_X, cursorY + UIConfig.PrimaryRow.FrameOffsetY)
	primaryFrame.BackgroundTransparency = 1
	primaryFrame.Parent = modal

	local primaryLayout = Instance.new("UIListLayout")
	primaryLayout.FillDirection = Enum.FillDirection.Horizontal
	primaryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	primaryLayout.Padding = UDim.new(UIConfig.PrimaryRow.ListPadding, 0)
	primaryLayout.Parent = primaryFrame

	cursorY = cursorY + ICON_ROW_H + ROW_GAP

	local secondaryLabel = Instance.new("TextLabel")
	secondaryLabel.Size = UDim2.fromScale(LEFT_COL_W, ROW_LABEL_H)
	secondaryLabel.Position = UDim2.fromScale(PAD_X, cursorY + UIConfig.SecondaryRow.LabelOffsetY)
	secondaryLabel.BackgroundTransparency = 1
	secondaryLabel.Text = "SECONDARY"

	secondaryLabel.Font = Theme.FontBody
	secondaryLabel.TextColor3 = Theme.NeonMagenta
	secondaryLabel.TextScaled = true
	secondaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	secondaryLabel.Parent = modal

	cursorY = cursorY + ROW_LABEL_H

	local secondaryFrame = Instance.new("Frame")
	secondaryFrame.Name = "SecondaryWeapons"
	secondaryFrame.Size = UDim2.fromScale(LEFT_COL_W, ICON_ROW_H)
	secondaryFrame.Position = UDim2.fromScale(PAD_X, cursorY + UIConfig.SecondaryRow.FrameOffsetY)
	secondaryFrame.BackgroundTransparency = 1
	secondaryFrame.Parent = modal

	local secondaryLayout = Instance.new("UIListLayout")
	secondaryLayout.FillDirection = Enum.FillDirection.Horizontal
	secondaryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	secondaryLayout.Padding = UDim.new(UIConfig.SecondaryRow.ListPadding, 0)
	secondaryLayout.Parent = secondaryFrame

	cursorY = cursorY + ICON_ROW_H + ROW_GAP

	local primWeapons = LoadoutConfig:getByCategory(LoadoutConfig.CATEGORY.PRIMARY)
	local secWeapons = LoadoutConfig:getByCategory(LoadoutConfig.CATEGORY.SECONDARY)

	primaryButtons = {}
	for i, entry in ipairs(primWeapons) do
		local btn = createWeaponButton(primaryFrame, entry.id, i)
		if btn then
			primaryButtons[entry.id] = btn
		end
	end

	secondaryButtons = {}
	for i, entry in ipairs(secWeapons) do
		local btn = createWeaponButton(secondaryFrame, entry.id, i)
		if btn then
			secondaryButtons[entry.id] = btn
		end
	end

	local detailH = 1 - HEADER_H - UIConfig.DetailPanel.BottomPad

	detailFrame = Instance.new("Frame")
	detailFrame.Name = "DetailPanel"
	detailFrame.Size = UDim2.fromScale(DETAIL_PANEL_W , detailH)
	detailFrame.Position = UDim2.fromScale(DETAIL_PANEL_X, HEADER_H)
	detailFrame.BackgroundColor3 = Theme.PanelDeep
	detailFrame.BackgroundTransparency = 0.15
	detailFrame.BorderSizePixel = 0
	detailFrame.Visible = false
	detailFrame.Parent = modal

	corner(detailFrame, UIConfig.DetailPanel.CornerRadius)
	stroke(detailFrame, Theme.TextMuted, 1)

	local dIcon = Instance.new("ImageLabel")
	dIcon.Name = "WeaponIcon"
	dIcon.Size = UDim2.fromScale(UIConfig.DetailIcon.Width, UIConfig.DetailIcon.Height)
	dIcon.Position = UDim2.fromScale(0.5, UIConfig.DetailIcon.PosY)
	dIcon.AnchorPoint = Vector2.new(0.5, 0)
	dIcon.BackgroundTransparency = 1
	dIcon.ScaleType = Enum.ScaleType.Fit
	dIcon.Parent = detailFrame

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = dIcon

	local dName = Instance.new("TextLabel")
	dName.Name = "WeaponName"
	dName.Size = UDim2.fromScale(UIConfig.DetailName.Width, UIConfig.DetailName.Height)
	dName.Position = UDim2.fromScale(UIConfig.DetailName.PosX, UIConfig.DetailName.PosY)
	dName.BackgroundTransparency = 1
	dName.Text = ""

	dName.Font = Theme.FontDisplay
	dName.TextColor3 = Theme.TextBright
	dName.TextScaled = true
	dName.TextXAlignment = Enum.TextXAlignment.Center
	dName.TextWrapped = true
	dName.Parent = detailFrame

	local dDesc = Instance.new("TextLabel")
	dDesc.Name = "WeaponDesc"
	dDesc.Size = UDim2.fromScale(UIConfig.DetailDesc.Width, UIConfig.DetailDesc.Height)
	dDesc.Position = UDim2.fromScale(UIConfig.DetailDesc.PosX, UIConfig.DetailDesc.PosY)
	dDesc.BackgroundTransparency = 1
	dDesc.Text = ""

	dDesc.Font = Theme.FontBody
	dDesc.TextColor3 = Theme.TextMuted
	dDesc.TextScaled = true
	dDesc.TextXAlignment = Enum.TextXAlignment.Center
	dDesc.TextWrapped = true
	dDesc.Parent = detailFrame

	local dLock = Instance.new("TextLabel")
	dLock.Name = "LockLabel"
	dLock.Size = UDim2.fromScale(UIConfig.DetailLock.Width, UIConfig.DetailLock.Height)
	dLock.Position = UDim2.fromScale(UIConfig.DetailLock.PosX, UIConfig.DetailLock.PosY)
	dLock.BackgroundTransparency = 1
	dLock.Text = "Purchase from shop to unlock"

	dLock.Font = Theme.FontBody
	dLock.TextColor3 = Theme.NeonAmber
	dLock.TextScaled = true
	dLock.TextXAlignment = Enum.TextXAlignment.Center
	dLock.Visible = false
	dLock.Parent = detailFrame

	local dEquip = Instance.new("TextButton")
	dEquip.Name = "EquipBtn"
	dEquip.Size = UDim2.fromScale(UIConfig.DetailEquipBtn.Width, UIConfig.DetailEquipBtn.Height)
	dEquip.Position = UDim2.fromScale(UIConfig.DetailEquipBtn.PosX, UIConfig.DetailEquipBtn.PosY)
	dEquip.BackgroundColor3 = Theme.NeonCyan
	dEquip.Text = "EQUIP"

	dEquip.Font = Theme.FontDisplay
	dEquip.TextColor3 = Theme.BgVoid
	dEquip.TextScaled = true
	dEquip.BorderSizePixel = 0
	dEquip.Parent = detailFrame
	corner(dEquip, UIConfig.DetailEquipBtn.CornerRadius)
	dEquip.MouseButton1Click:Connect(equipSelected)

	local skinsLabel = Instance.new("TextLabel")
	skinsLabel.Name = "SkinsLabel"
	skinsLabel.Size = UDim2.fromScale(UIConfig.SkinsLabel.Width, UIConfig.SkinsLabel.Height)
	skinsLabel.BackgroundTransparency = 1
	skinsLabel.Text = "SKINS"

	skinsLabel.Font = Enum.Font.GothamBold
	skinsLabel.TextColor3 = Theme.NeonMagenta
	skinsLabel.TextScaled = true
	skinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	skinsLabel.Visible = false
	skinsLabel.Parent = detailFrame

	local skinsScroll = Instance.new("ScrollingFrame")
	skinsScroll.Name = "SkinsFrame"
	skinsScroll.Size = UDim2.fromScale(UIConfig.SkinsFrame.Width, UIConfig.SkinsFrame.DisplayH)
	skinsScroll.BackgroundTransparency = 1
	skinsScroll.BorderSizePixel = 0
	skinsScroll.ScrollBarThickness = UIConfig.SkinsFrame.ScrollBarThickness
	skinsScroll.ScrollBarImageColor3 = Theme.NeonMagenta
	skinsScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	skinsScroll.CanvasSize = UDim2.fromScale(0, 0)
	skinsScroll.Visible = false
	skinsScroll.Parent = detailFrame

	local skinsListLayout = Instance.new("UIListLayout")
	skinsListLayout.FillDirection = Enum.FillDirection.Horizontal
	skinsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	skinsListLayout.Padding = UDim.new(UIConfig.SkinsFrame.ListPadding, 0)
	skinsListLayout.Parent = skinsScroll

	local equippedBar = Instance.new("Frame")
	equippedBar.Name = "EquippedBar"
	equippedBar.Size = UDim2.fromScale(1 - PAD_X * 2, EQUIPPED_BAR_H + UIConfig.EquippedBar.HeightExtra)
	equippedBar.Position = UDim2.fromScale(PAD_X, cursorY + UIConfig.EquippedBar.PosYOffset)
	equippedBar.BackgroundTransparency = 1
	equippedBar.Parent = modal

	local eqTitle = Instance.new("TextLabel")
	eqTitle.Size = UDim2.fromScale(1, UIConfig.EquippedTitle.Height)
	eqTitle.Position = UDim2.fromScale(0, UIConfig.EquippedTitle.PosY)
	eqTitle.BackgroundTransparency = 1
	eqTitle.Text = "EQUIPPED"
	eqTitle.Font = Theme.FontBody
	eqTitle.TextColor3 = Theme.TextMuted
	eqTitle.TextScaled = true
	eqTitle.TextXAlignment = Enum.TextXAlignment.Left
	eqTitle.Parent = equippedBar

	local pSlotLabel = Instance.new("TextLabel")
	pSlotLabel.Size = UDim2.fromScale(UIConfig.SlotLabel.Width, UIConfig.SlotLabel.Height)
	pSlotLabel.Position = UDim2.fromScale(0, UIConfig.SlotLabel.PosY)
	pSlotLabel.BackgroundTransparency = 1
	pSlotLabel.Text = "PRI"

	pSlotLabel.Font = Theme.FontBody
	pSlotLabel.TextColor3 = Theme.NeonCyan
	pSlotLabel.TextScaled = true
	pSlotLabel.Parent = equippedBar

	local pSlot = Instance.new("Frame")
	pSlot.Size = UDim2.fromScale(UIConfig.Slot.Width, UIConfig.Slot.Height)
	pSlot.Position = UDim2.fromScale(0, UIConfig.Slot.PosY)
	pSlot.BackgroundColor3 = Theme.Card
	pSlot.BackgroundTransparency = 0.2
	pSlot.BorderSizePixel = 0
	pSlot.Parent = equippedBar
	local pSlotAspect = Instance.new("UIAspectRatioConstraint")
	pSlotAspect.AspectRatio = 1
	pSlotAspect.Parent = pSlot
	corner(pSlot, UIConfig.Slot.CornerRadius)
	stroke(pSlot, Theme.NeonCyan, 2)

	equippedPrimaryIcon = Instance.new("ImageLabel")
	equippedPrimaryIcon.Size = UDim2.fromScale(UIConfig.Slot.IconScale, UIConfig.Slot.IconScale)
	equippedPrimaryIcon.Position = UDim2.fromScale(0.5, 0.5)
	equippedPrimaryIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	equippedPrimaryIcon.BackgroundTransparency = 1
	equippedPrimaryIcon.ScaleType = Enum.ScaleType.Fit
	equippedPrimaryIcon.Image = getEquippedWeaponIcon(equippedPrimary)
	equippedPrimaryIcon.Parent = pSlot

	local sSlotLabel = Instance.new("TextLabel")
	sSlotLabel.Size = UDim2.fromScale(UIConfig.SlotLabel.Width, UIConfig.SlotLabel.Height)
	sSlotLabel.Position = UDim2.fromScale(UIConfig.SecondarySlotX, UIConfig.SlotLabel.PosY)
	sSlotLabel.BackgroundTransparency = 1
	sSlotLabel.Text = "SEC"

	sSlotLabel.Font = Theme.FontBody
	sSlotLabel.TextColor3 = Theme.NeonMagenta
	sSlotLabel.TextScaled = true
	sSlotLabel.Parent = equippedBar

	local sSlot = Instance.new("Frame")
	sSlot.Size = UDim2.fromScale(UIConfig.Slot.Width, UIConfig.Slot.Height)
	sSlot.Position = UDim2.fromScale(UIConfig.SecondarySlotX, UIConfig.Slot.PosY)
	sSlot.BackgroundColor3 = Theme.Card
	sSlot.BackgroundTransparency = 0.2
	sSlot.BorderSizePixel = 0
	sSlot.Parent = equippedBar
	local sSlotAspect = Instance.new("UIAspectRatioConstraint")
	sSlotAspect.AspectRatio = 1
	sSlotAspect.Parent = sSlot
	corner(sSlot, UIConfig.Slot.CornerRadius)
	stroke(sSlot, Theme.NeonMagenta, 2)

	equippedSecondaryIcon = Instance.new("ImageLabel")
	equippedSecondaryIcon.Size = UDim2.fromScale(UIConfig.Slot.IconScale, UIConfig.Slot.IconScale)
	equippedSecondaryIcon.Position = UDim2.fromScale(0.5, 0.5)
	equippedSecondaryIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	equippedSecondaryIcon.BackgroundTransparency = 1
	equippedSecondaryIcon.ScaleType = Enum.ScaleType.Fit
	equippedSecondaryIcon.Image = getEquippedWeaponIcon(equippedSecondary)
	equippedSecondaryIcon.Parent = sSlot

	updateButtonHighlights()
	return modal
end

local function buildGUI()
	if gui then
		gui:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 11
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BackgroundColor3 = Theme.BgVoid
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	buildModal(overlay)
end

function LoadoutGUI.Init()
	ShopEconomyClient = require(Shared.Services.ShopEconomyClient)
	buildGUI()
	ShopEconomyClient.Subscribe(function()
		if not gui then
			return
		end
		refreshAllWeaponButtonLocks()
		if selectedWeaponId then
			showDetailPanel(selectedWeaponId)
		end
	end)
end

function LoadoutGUI.Show()
	if not gui then
		return
	end
	visible = true
	gui.Enabled = true
	freezeMovement()
	selectedWeaponId = nil
	if detailFrame then
		detailFrame.Visible = false
	end
	updateEquippedSlots()
	updateButtonHighlights()
	refreshAllWeaponButtonLocks()
end

function LoadoutGUI.Hide()
	if not gui then
		return
	end
	local wasVisible = visible
	visible = false
	gui.Enabled = false
	restoreMovement()
	if wasVisible then
		for _, cb in ipairs(onCloseCallbacks) do
			task.spawn(cb)
		end
	end
end

function LoadoutGUI.GetEquippedSkins(): { [string]: string? }
	return equippedSkins
end

function LoadoutGUI.SubscribeSkinsChanged(cb: ({ [string]: string? }) -> ())
	table.insert(skinChangeCallbacks, cb)
end

function LoadoutGUI.SubscribeOnClose(cb)
	table.insert(onCloseCallbacks, cb)
end

function LoadoutGUI.IsVisible()
	return visible
end

function LoadoutGUI.Toggle()
	if visible then
		LoadoutGUI.Hide()
	else
		LoadoutGUI.Show()
	end
end

function LoadoutGUI.BuildPreview(parent)
	ShopEconomyClient = ShopEconomyClient or {
		GetSnapshot = function()
			return { credits = 9999, matchesPlayed = 0, ownedShopGunIds = {} }
		end,
	}
	equippedPrimary = LoadoutConfig.DEFAULT.primary
	equippedSecondary = LoadoutConfig.DEFAULT.secondary
	selectedWeaponId = nil
	return buildModal(parent)
end

return LoadoutGUI
