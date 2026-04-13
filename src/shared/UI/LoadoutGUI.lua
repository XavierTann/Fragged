--[[
	LoadoutGUI
	Full-screen loadout configuration overlay. Two weapon slots (Primary + Secondary).
	Top: available weapons split by category. Right: detail panel. Bottom: equipped slots.
	Sci-fi neon aesthetic using ShopTheme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local LoadoutConfig = require(Shared.Modules.LoadoutConfig)
local WeaponIconsConfig = require(Shared.Modules.WeaponIconsConfig)
local ShopCatalog = require(Shared.Modules.ShopCatalog)
local CombatConfig = require(Shared.Modules.CombatConfig)

local LocalPlayer = Players.LocalPlayer
local ShopEconomyClient = nil

local gui = nil
local visible = false
local selectedWeaponId = nil
local equippedPrimary = LoadoutConfig.DEFAULT.primary
local equippedSecondary = LoadoutConfig.DEFAULT.secondary

local detailFrame = nil
local equippedPrimaryIcon = nil
local equippedSecondaryIcon = nil
local primaryButtons = {}
local secondaryButtons = {}

local savedWalkSpeed = nil
local savedJumpHeight = nil
local loadoutRE = nil

local LoadoutGUI = {}

local ICON_SIZE = 56
local ICON_GAP = 8
local CORNER_RADIUS = 14
local EQUIPPED_SLOT_SIZE = 48
local DETAIL_WIDTH = 170
local CONTENT_PAD = 16
local ROW_LABEL_H = 18
local ROW_GAP = 10

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
		loadoutRE:FireServer({ primary = equippedPrimary, secondary = equippedSecondary })
	end
end

local function updateEquippedSlots()
	if equippedPrimaryIcon then
		equippedPrimaryIcon.Image = getIconImage(equippedPrimary)
	end
	if equippedSecondaryIcon then
		equippedSecondaryIcon.Image = getIconImage(equippedSecondary)
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
		iconImg.Image = getIconImage(weaponId)
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
				badge.Size = UDim2.fromOffset(40, 16)
				badge.Position = UDim2.new(1, -2, 1, -2)
				badge.AnchorPoint = Vector2.new(1, 1)
				badge.BackgroundColor3 = Theme.NeonAmber
				badge.BackgroundTransparency = 0.1
				badge.TextSize = 10
				badge.Font = Enum.Font.GothamBold
				badge.TextColor3 = Theme.BgVoid
				badge.Parent = btn
				corner(badge, 6)
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
			lockLabel.Size = UDim2.fromScale(1, 1)
			lockLabel.BackgroundTransparency = 0.7
			lockLabel.BackgroundColor3 = Theme.BgVoid
			lockLabel.Text = "\xF0\x9F\x94\x92"
			lockLabel.TextSize = 22
			lockLabel.Font = Enum.Font.GothamBold
			lockLabel.TextColor3 = Theme.TextMuted
			lockLabel.Parent = btn
			corner(lockLabel, 10)
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

local function createWeaponButton(parent, weaponId, index)
	local w = LoadoutConfig.WEAPONS[weaponId]
	if not w then
		return nil
	end
	local btn = Instance.new("ImageButton")
	btn.Name = weaponId
	btn.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	btn.Position = UDim2.fromOffset((index - 1) * (ICON_SIZE + ICON_GAP), 0)
	btn.BackgroundColor3 = Theme.Card
	btn.BackgroundTransparency = 0.15
	btn.Image = getIconImage(weaponId)
	btn.ScaleType = Enum.ScaleType.Fit
	btn.BorderSizePixel = 0
	btn.Parent = parent

	corner(btn, 10)
	stroke(btn, Theme.TextMuted, 1)
	syncWeaponButtonOwnership(btn, weaponId)

	btn.MouseButton1Click:Connect(function()
		showDetailPanel(weaponId)
		updateButtonHighlights()
	end)

	return btn
end

local function buildModal(parent)
	local primWeapons = LoadoutConfig:getByCategory(LoadoutConfig.CATEGORY.PRIMARY)
	local secWeapons = LoadoutConfig:getByCategory(LoadoutConfig.CATEGORY.SECONDARY)
	local primCount = #primWeapons
	local secCount = #secWeapons
	local maxIconRow = math.max(primCount, secCount)

	local leftColW = maxIconRow * (ICON_SIZE + ICON_GAP) - ICON_GAP + CONTENT_PAD * 2
	local modalW = leftColW + DETAIL_WIDTH + CONTENT_PAD * 2 + 16
	modalW = math.max(modalW, 480)
	local twoRowsH = (ROW_LABEL_H + ICON_SIZE + ROW_GAP) * 2
	local headerH = 44
	local equippedH = EQUIPPED_SLOT_SIZE + 40
	local modalH = headerH + twoRowsH + equippedH + CONTENT_PAD * 2
	modalH = math.max(modalH, 320)

	local screenH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 600
	modalH = math.min(modalH, math.floor(screenH * 0.85))

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromOffset(modalW, modalH)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Theme.Panel
	modal.BackgroundTransparency = 0
	modal.BorderSizePixel = 0
	modal.ClipsDescendants = true
	modal.Parent = parent

	corner(modal, CORNER_RADIUS)
	stroke(modal, Theme.NeonCyan, 2)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Theme.PanelDeep
	closeBtn.BackgroundTransparency = 0
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "X"
	closeBtn.TextSize = 16
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextColor3 = Theme.TextBright
	closeBtn.Parent = modal
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
	title.Size = UDim2.new(1, -80, 0, 32)
	title.Position = UDim2.fromOffset(CONTENT_PAD, 8)
	title.BackgroundTransparency = 1
	title.Text = "LOADOUT"
	title.TextSize = 17
	title.Font = Theme.FontDisplay
	title.TextColor3 = Theme.NeonCyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = modal

	local cursorY = headerH

	local primaryLabel = Instance.new("TextLabel")
	primaryLabel.Size = UDim2.fromOffset(leftColW, ROW_LABEL_H)
	primaryLabel.Position = UDim2.fromOffset(CONTENT_PAD, cursorY)
	primaryLabel.BackgroundTransparency = 1
	primaryLabel.Text = "PRIMARY"
	primaryLabel.TextSize = 13
	primaryLabel.Font = Theme.FontBody
	primaryLabel.TextColor3 = Theme.NeonCyan
	primaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	primaryLabel.Parent = modal

	cursorY = cursorY + ROW_LABEL_H

	local primaryFrame = Instance.new("Frame")
	primaryFrame.Name = "PrimaryWeapons"
	primaryFrame.Size = UDim2.fromOffset(leftColW, ICON_SIZE)
	primaryFrame.Position = UDim2.fromOffset(CONTENT_PAD, cursorY)
	primaryFrame.BackgroundTransparency = 1
	primaryFrame.Parent = modal

	cursorY = cursorY + ICON_SIZE + ROW_GAP

	local secondaryLabel = Instance.new("TextLabel")
	secondaryLabel.Size = UDim2.fromOffset(leftColW, ROW_LABEL_H)
	secondaryLabel.Position = UDim2.fromOffset(CONTENT_PAD, cursorY)
	secondaryLabel.BackgroundTransparency = 1
	secondaryLabel.Text = "SECONDARY"
	secondaryLabel.TextSize = 13
	secondaryLabel.Font = Theme.FontBody
	secondaryLabel.TextColor3 = Theme.NeonMagenta
	secondaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	secondaryLabel.Parent = modal

	cursorY = cursorY + ROW_LABEL_H

	local secondaryFrame = Instance.new("Frame")
	secondaryFrame.Name = "SecondaryWeapons"
	secondaryFrame.Size = UDim2.fromOffset(leftColW, ICON_SIZE)
	secondaryFrame.Position = UDim2.fromOffset(CONTENT_PAD, cursorY)
	secondaryFrame.BackgroundTransparency = 1
	secondaryFrame.Parent = modal

	cursorY = cursorY + ICON_SIZE + ROW_GAP

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

	local detailTop = headerH
	local detailH = modalH - detailTop - CONTENT_PAD
	local detailX = CONTENT_PAD + leftColW + 16

	detailFrame = Instance.new("Frame")
	detailFrame.Name = "DetailPanel"
	detailFrame.Size = UDim2.fromOffset(DETAIL_WIDTH, detailH)
	detailFrame.Position = UDim2.fromOffset(detailX, detailTop)
	detailFrame.BackgroundColor3 = Theme.PanelDeep
	detailFrame.BackgroundTransparency = 0.15
	detailFrame.BorderSizePixel = 0
	detailFrame.Visible = false
	detailFrame.Parent = modal

	corner(detailFrame, 10)
	stroke(detailFrame, Theme.TextMuted, 1)

	local dIcon = Instance.new("ImageLabel")
	dIcon.Name = "WeaponIcon"
	dIcon.Size = UDim2.fromOffset(72, 72)
	dIcon.Position = UDim2.new(0.5, 0, 0, 12)
	dIcon.AnchorPoint = Vector2.new(0.5, 0)
	dIcon.BackgroundTransparency = 1
	dIcon.ScaleType = Enum.ScaleType.Fit
	dIcon.Parent = detailFrame

	local dName = Instance.new("TextLabel")
	dName.Name = "WeaponName"
	dName.Size = UDim2.new(1, -16, 0, 30)
	dName.Position = UDim2.fromOffset(8, 90)
	dName.BackgroundTransparency = 1
	dName.Text = ""
	dName.TextSize = 14
	dName.Font = Theme.FontDisplay
	dName.TextColor3 = Theme.TextBright
	dName.TextXAlignment = Enum.TextXAlignment.Center
	dName.TextWrapped = true
	dName.Parent = detailFrame

	local dDesc = Instance.new("TextLabel")
	dDesc.Name = "WeaponDesc"
	dDesc.Size = UDim2.new(1, -16, 0, 80)
	dDesc.Position = UDim2.fromOffset(8, 126)
	dDesc.BackgroundTransparency = 1
	dDesc.Text = ""
	dDesc.TextSize = 12
	dDesc.Font = Theme.FontBody
	dDesc.TextColor3 = Theme.TextMuted
	dDesc.TextXAlignment = Enum.TextXAlignment.Center
	dDesc.TextWrapped = true
	dDesc.Parent = detailFrame

	local dLock = Instance.new("TextLabel")
	dLock.Name = "LockLabel"
	dLock.Size = UDim2.new(1, -16, 0, 18)
	dLock.Position = UDim2.fromOffset(8, 212)
	dLock.BackgroundTransparency = 1
	dLock.Text = "Purchase from shop to unlock"
	dLock.TextSize = 11
	dLock.Font = Theme.FontBody
	dLock.TextColor3 = Theme.NeonAmber
	dLock.TextXAlignment = Enum.TextXAlignment.Center
	dLock.Visible = false
	dLock.Parent = detailFrame

	local dEquip = Instance.new("TextButton")
	dEquip.Name = "EquipBtn"
	dEquip.Size = UDim2.new(1, -24, 0, 34)
	dEquip.Position = UDim2.new(0, 12, 1, -46)
	dEquip.BackgroundColor3 = Theme.NeonCyan
	dEquip.Text = "EQUIP"
	dEquip.TextSize = 14
	dEquip.Font = Theme.FontDisplay
	dEquip.TextColor3 = Theme.BgVoid
	dEquip.BorderSizePixel = 0
	dEquip.Parent = detailFrame
	corner(dEquip, 8)
	dEquip.MouseButton1Click:Connect(equipSelected)

	local equippedBar = Instance.new("Frame")
	equippedBar.Name = "EquippedBar"
	equippedBar.Size = UDim2.new(1, -CONTENT_PAD * 2, 0, equippedH)
	equippedBar.Position = UDim2.fromOffset(CONTENT_PAD, cursorY)
	equippedBar.BackgroundTransparency = 1
	equippedBar.Parent = modal

	local eqTitle = Instance.new("TextLabel")
	eqTitle.Size = UDim2.new(1, 0, 0, 16)
	eqTitle.Position = UDim2.fromOffset(0, 0)
	eqTitle.BackgroundTransparency = 1
	eqTitle.Text = "EQUIPPED"
	eqTitle.TextSize = 11
	eqTitle.Font = Theme.FontBody
	eqTitle.TextColor3 = Theme.TextMuted
	eqTitle.TextXAlignment = Enum.TextXAlignment.Left
	eqTitle.Parent = equippedBar

	local slotY = 22

	local pSlotLabel = Instance.new("TextLabel")
	pSlotLabel.Size = UDim2.fromOffset(EQUIPPED_SLOT_SIZE, 14)
	pSlotLabel.Position = UDim2.fromOffset(0, slotY - 16)
	pSlotLabel.BackgroundTransparency = 1
	pSlotLabel.Text = "PRI"
	pSlotLabel.TextSize = 10
	pSlotLabel.Font = Theme.FontBody
	pSlotLabel.TextColor3 = Theme.NeonCyan
	pSlotLabel.Parent = equippedBar

	local pSlot = Instance.new("Frame")
	pSlot.Size = UDim2.fromOffset(EQUIPPED_SLOT_SIZE, EQUIPPED_SLOT_SIZE)
	pSlot.Position = UDim2.fromOffset(0, slotY)
	pSlot.BackgroundColor3 = Theme.Card
	pSlot.BackgroundTransparency = 0.2
	pSlot.BorderSizePixel = 0
	pSlot.Parent = equippedBar
	corner(pSlot, 8)
	stroke(pSlot, Theme.NeonCyan, 2)

	equippedPrimaryIcon = Instance.new("ImageLabel")
	equippedPrimaryIcon.Size = UDim2.new(1, -8, 1, -8)
	equippedPrimaryIcon.Position = UDim2.fromOffset(4, 4)
	equippedPrimaryIcon.BackgroundTransparency = 1
	equippedPrimaryIcon.ScaleType = Enum.ScaleType.Fit
	equippedPrimaryIcon.Image = getIconImage(equippedPrimary)
	equippedPrimaryIcon.Parent = pSlot

	local sSlotLabel = Instance.new("TextLabel")
	sSlotLabel.Size = UDim2.fromOffset(EQUIPPED_SLOT_SIZE, 14)
	sSlotLabel.Position = UDim2.fromOffset(EQUIPPED_SLOT_SIZE + 16, slotY - 16)
	sSlotLabel.BackgroundTransparency = 1
	sSlotLabel.Text = "SEC"
	sSlotLabel.TextSize = 10
	sSlotLabel.Font = Theme.FontBody
	sSlotLabel.TextColor3 = Theme.NeonMagenta
	sSlotLabel.Parent = equippedBar

	local sSlot = Instance.new("Frame")
	sSlot.Size = UDim2.fromOffset(EQUIPPED_SLOT_SIZE, EQUIPPED_SLOT_SIZE)
	sSlot.Position = UDim2.fromOffset(EQUIPPED_SLOT_SIZE + 16, slotY)
	sSlot.BackgroundColor3 = Theme.Card
	sSlot.BackgroundTransparency = 0.2
	sSlot.BorderSizePixel = 0
	sSlot.Parent = equippedBar
	corner(sSlot, 8)
	stroke(sSlot, Theme.NeonMagenta, 2)

	equippedSecondaryIcon = Instance.new("ImageLabel")
	equippedSecondaryIcon.Size = UDim2.new(1, -8, 1, -8)
	equippedSecondaryIcon.Position = UDim2.fromOffset(4, 4)
	equippedSecondaryIcon.BackgroundTransparency = 1
	equippedSecondaryIcon.ScaleType = Enum.ScaleType.Fit
	equippedSecondaryIcon.Image = getIconImage(equippedSecondary)
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
	visible = false
	gui.Enabled = false
	restoreMovement()
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
