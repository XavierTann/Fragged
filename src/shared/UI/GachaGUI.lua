--[[
	GachaGUI: Full-screen gacha overlay with slot-machine rolling animation.
	A vertical reel of weapon icons spins, decelerates, and lands on the result.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local GachaConfig = require(Shared.Modules.GachaConfig)
local ShopEconomyClient = require(Shared.Services.ShopEconomyClient)
local GunsConfig = require(Shared.Modules.GunsConfig)
local WeaponIconsConfig = require(Shared.Modules.WeaponIconsConfig)

local LocalPlayer = Players.LocalPlayer

local gui = nil
local visible = false
local rolling = false

local rollBtn = nil
local reelViewport = nil
local reelStrip = nil
local selectorLine = nil
local resultFrame = nil
local resultIcon = nil
local resultName = nil
local resultRarity = nil
local resultRounds = nil
local resultFlash = nil
local tempListFrame = nil
local closeBtn = nil

local savedWalkSpeed = nil
local savedJumpHeight = nil

local reelConnection = nil
local freeSpinRequester = nil

local GachaGUI = {}

local RARITY_COLORS = {}
for _, r in ipairs(GachaConfig.RARITIES) do
	RARITY_COLORS[r.name] = r.color
end
RARITY_COLORS["Legendary"] = RARITY_COLORS["Legendary"] or Color3.fromRGB(255, 200, 40)

local REEL_CELL_SIZE = 64
local REEL_GAP = 6
local REEL_CELL_STRIDE = REEL_CELL_SIZE + REEL_GAP
local REEL_VISIBLE_CELLS = 3
local REEL_SPIN_CELLS = 60
local REEL_TOTAL_CELLS = REEL_SPIN_CELLS + REEL_VISIBLE_CELLS
local REEL_WIDTH = 280
local REEL_HEIGHT = REEL_CELL_STRIDE * REEL_VISIBLE_CELLS
local SPIN_DURATION = 6.0

local ALL_WEAPON_IDS = {}
do
	local seen = {}
	for _, entry in ipairs(GachaConfig.POOL) do
		if not seen[entry.weaponId] then
			seen[entry.weaponId] = true
			table.insert(ALL_WEAPON_IDS, entry.weaponId)
		end
	end
end

local function getIconImage(weaponId)
	local assetId = WeaponIconsConfig[weaponId]
	if not assetId or assetId == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(assetId)
end

local function getWeaponDisplayName(weaponId)
	local cfg = GunsConfig[weaponId]
	if cfg then
		return cfg.name or weaponId
	end
	return weaponId
end

local function randomWeaponId(): string
	return ALL_WEAPON_IDS[math.random(1, #ALL_WEAPON_IDS)]
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	c.Parent = parent
	return c
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
	end
end

local function refreshTempWeapons()
	if not tempListFrame then
		return
	end
	for _, child in ipairs(tempListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local snap = ShopEconomyClient.GetSnapshot()
	local tw = snap.tempWeapons or {}
	if #tw == 0 then
		return
	end
	for i, entry in ipairs(tw) do
		local row = Instance.new("Frame")
		row.Name = "Temp_" .. entry.id
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Position = UDim2.fromOffset(0, (i - 1) * 36)
		row.BackgroundColor3 = Theme.Card
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = tempListFrame
		corner(row, 6)

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.fromOffset(24, 24)
		icon.Position = UDim2.fromOffset(4, 4)
		icon.BackgroundTransparency = 1
		icon.Image = getIconImage(entry.id)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = row

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(1, -80, 1, 0)
		nameL.Position = UDim2.fromOffset(32, 0)
		nameL.BackgroundTransparency = 1
		nameL.Text = getWeaponDisplayName(entry.id)
		nameL.TextSize = 11
		nameL.Font = Theme.FontBody
		nameL.TextColor3 = Theme.TextBright
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.Parent = row

		local roundsL = Instance.new("TextLabel")
		roundsL.Size = UDim2.fromOffset(44, 32)
		roundsL.Position = UDim2.new(1, -48, 0, 0)
		roundsL.BackgroundTransparency = 1
		roundsL.Text = entry.roundsLeft .. "R"
		roundsL.TextSize = 12
		roundsL.Font = Enum.Font.GothamBold
		roundsL.TextColor3 = Theme.NeonAmber
		roundsL.TextXAlignment = Enum.TextXAlignment.Right
		roundsL.Parent = row
	end
end

local function updateRollButton()
	if not rollBtn then
		return
	end
	if rolling then
		rollBtn.Text = "SPINNING..."
		rollBtn.AutoButtonColor = false
		return
	end
	local snap = ShopEconomyClient.GetSnapshot()
	if snap.freeSpinAvailable then
		rollBtn.Text = "FREE SPIN!"
		rollBtn.BackgroundColor3 = Theme.NeonLime
		rollBtn.TextColor3 = Theme.BgVoid
	else
		rollBtn.Text = "ROLL (R$ " .. GachaConfig.ROLL_ROBUX_PRICE .. ")"
		rollBtn.BackgroundColor3 = Theme.NeonCyan
		rollBtn.TextColor3 = Theme.BgVoid
	end
	rollBtn.AutoButtonColor = true
end

local function hideResult()
	if resultFrame then
		resultFrame.Visible = false
	end
	if resultFlash then
		resultFlash.Visible = false
	end
	if reelViewport then
		reelViewport.Size = UDim2.fromOffset(REEL_WIDTH, REEL_HEIGHT)
	end
end

local function buildReelCell(parent, weaponId, index)
	local cell = Instance.new("Frame")
	cell.Name = "Cell_" .. index
	cell.Size = UDim2.fromOffset(REEL_CELL_SIZE, REEL_CELL_SIZE)
	cell.Position = UDim2.fromOffset(
		(REEL_WIDTH - REEL_CELL_SIZE) / 2,
		(index - 1) * REEL_CELL_STRIDE
	)
	cell.BackgroundColor3 = Theme.Card
	cell.BackgroundTransparency = 0.2
	cell.BorderSizePixel = 0
	cell.Parent = parent
	corner(cell, 10)

	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.Size = UDim2.new(1, -12, 1, -12)
	img.Position = UDim2.fromOffset(6, 6)
	img.BackgroundTransparency = 1
	img.Image = getIconImage(weaponId)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = cell

	local nameTag = Instance.new("TextLabel")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(1, 0, 0, 14)
	nameTag.Position = UDim2.new(0, 0, 1, 2)
	nameTag.BackgroundTransparency = 1
	nameTag.Text = getWeaponDisplayName(weaponId)
	nameTag.TextSize = 9
	nameTag.Font = Theme.FontBody
	nameTag.TextColor3 = Theme.TextMuted
	nameTag.TextXAlignment = Enum.TextXAlignment.Center
	nameTag.Parent = cell

	return cell
end

local function populateReel(winWeaponId)
	if reelStrip then
		for _, child in ipairs(reelStrip:GetChildren()) do
			child:Destroy()
		end
	end

	local centerSlot = math.floor(REEL_VISIBLE_CELLS / 2) + 1
	local winIndex = REEL_SPIN_CELLS + centerSlot

	for i = 1, REEL_TOTAL_CELLS do
		local wid
		if i == winIndex then
			wid = winWeaponId
		else
			wid = randomWeaponId()
		end
		buildReelCell(reelStrip, wid, i)
	end

	local totalH = REEL_TOTAL_CELLS * REEL_CELL_STRIDE
	reelStrip.Size = UDim2.fromOffset(REEL_WIDTH, totalH)
	reelStrip.Position = UDim2.fromOffset(0, 0)

	return winIndex
end

local function stopReelConnection()
	if reelConnection then
		reelConnection:Disconnect()
		reelConnection = nil
	end
end

local function animateReel(winWeaponId, onFinished)
	stopReelConnection()

	local winIndex = populateReel(winWeaponId)

	local centerSlot = math.floor(REEL_VISIBLE_CELLS / 2) + 1
	local targetY = -((winIndex - centerSlot) * REEL_CELL_STRIDE)

	reelStrip.Position = UDim2.fromOffset(0, 0)

	if selectorLine then
		selectorLine.Visible = true
	end

	local elapsed = 0

	reelConnection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / SPIN_DURATION, 0, 1)

		-- High-exponent ease-out: starts very fast, then has a long, gradual tail.
		-- Power of 5 keeps it smooth and continuous while spending most of the
		-- time crawling through the last few cells.
		local eased = 1 - (1 - t) ^ 7
		local currentY = eased * targetY
		reelStrip.Position = UDim2.fromOffset(0, currentY)

		if t >= 1 then
			stopReelConnection()
			reelStrip.Position = UDim2.fromOffset(0, targetY)

			task.delay(0.15, function()
				if selectorLine then
					local glow = TweenService:Create(selectorLine, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 2, true), {
						BackgroundTransparency = 0,
					})
					glow:Play()
				end

				task.delay(0.6, function()
					if onFinished then
						onFinished()
					end
				end)
			end)
		end
	end)
end

local function showResultPanel(payload)
	if not resultFrame then
		return
	end

	local rarityColor = RARITY_COLORS[payload.rarity] or Theme.TextBright
	local weaponName = getWeaponDisplayName(payload.weaponId)

	resultIcon.Image = getIconImage(payload.weaponId)
	resultRarity.Text = string.upper(payload.rarity)
	resultRarity.TextColor3 = rarityColor
	resultName.Text = string.upper(weaponName)

	if payload.permanent then
		resultRounds.Text = "PERMANENT UNLOCK!"
		resultRounds.TextColor3 = Theme.NeonLime
	elseif payload.rounds then
		resultRounds.Text = payload.rounds .. " rounds"
		resultRounds.TextColor3 = Theme.NeonAmber
	else
		resultRounds.Text = ""
	end

	if payload.isFree then
		resultRounds.Text = "WELCOME GIFT -- " .. (resultRounds.Text or "")
	end

	-- Shrink the reel to make room for the result panel
	if reelViewport then
		local shrink = TweenService:Create(reelViewport, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(REEL_WIDTH, 0),
		})
		shrink:Play()
	end

	if resultFlash then
		resultFlash.BackgroundColor3 = rarityColor
		resultFlash.BackgroundTransparency = 0.15
		resultFlash.Visible = true
		local fadeOut = TweenService:Create(resultFlash, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			resultFlash.Visible = false
		end)
	end

	-- Slide result panel up into the space the reel vacated
	resultFrame.Position = UDim2.fromOffset(20, 56)
	resultFrame.Visible = true
	resultFrame.Size = UDim2.new(1, -40, 0, 10)
	resultFrame.BackgroundTransparency = 0
	local expandTween = TweenService:Create(resultFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, -40, 0, 160),
	})
	expandTween:Play()

	local resultStroke = resultFrame:FindFirstChildOfClass("UIStroke")
	if not resultStroke then
		resultStroke = Instance.new("UIStroke")
		resultStroke.Thickness = 2
		resultStroke.Parent = resultFrame
	end
	resultStroke.Color = rarityColor
	resultStroke.Transparency = 0
	local strokeFade = TweenService:Create(resultStroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Transparency = 0.6,
	})
	strokeFade:Play()

	-- Move roll button below the result panel so player can roll again
	if rollBtn then
		local btnTween = TweenService:Create(rollBtn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(20, 224),
		})
		btnTween:Play()
	end

	rolling = false
	updateRollButton()
	refreshTempWeapons()
end

local function buildGUI()
	if gui then
		gui:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "GachaGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 11
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.BgVoid
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromOffset(340, 460)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Theme.Panel
	modal.BorderSizePixel = 0
	modal.ClipsDescendants = true
	modal.Parent = overlay
	corner(modal, 16)

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Theme.NeonCyan
	modalStroke.Thickness = 2
	modalStroke.Transparency = 0.2
	modalStroke.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 0, 36)
	title.Position = UDim2.fromOffset(16, 12)
	title.BackgroundTransparency = 1
	title.Text = "GACHA MACHINE"
	title.TextSize = 18
	title.Font = Theme.FontDisplay
	title.TextColor3 = Theme.NeonCyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = modal

	closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.Position = UDim2.new(1, -10, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Theme.PanelDeep
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
		if not rolling then
			GachaGUI.Hide()
		end
	end)

	-- Reel viewport (clipping window for the spinning strip)
	reelViewport = Instance.new("Frame")
	reelViewport.Name = "ReelViewport"
	reelViewport.Size = UDim2.fromOffset(REEL_WIDTH, REEL_HEIGHT)
	reelViewport.Position = UDim2.new(0.5, 0, 0, 50)
	reelViewport.AnchorPoint = Vector2.new(0.5, 0)
	reelViewport.BackgroundColor3 = Theme.PanelDeep
	reelViewport.BackgroundTransparency = 0.3
	reelViewport.BorderSizePixel = 0
	reelViewport.ClipsDescendants = true
	reelViewport.Parent = modal
	corner(reelViewport, 12)

	local viewportStroke = Instance.new("UIStroke")
	viewportStroke.Color = Theme.TextMuted
	viewportStroke.Thickness = 1
	viewportStroke.Transparency = 0.5
	viewportStroke.Parent = reelViewport

	-- Top/bottom gradient fades
	local topGrad = Instance.new("Frame")
	topGrad.Name = "TopFade"
	topGrad.Size = UDim2.new(1, 0, 0, 60)
	topGrad.Position = UDim2.fromOffset(0, 0)
	topGrad.BackgroundColor3 = Theme.Panel
	topGrad.BorderSizePixel = 0
	topGrad.ZIndex = 3
	topGrad.Parent = reelViewport
	local tg = Instance.new("UIGradient")
	tg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	tg.Rotation = 90
	tg.Parent = topGrad

	local bottomGrad = Instance.new("Frame")
	bottomGrad.Name = "BottomFade"
	bottomGrad.Size = UDim2.new(1, 0, 0, 60)
	bottomGrad.Position = UDim2.new(0, 0, 1, -60)
	bottomGrad.BackgroundColor3 = Theme.Panel
	bottomGrad.BorderSizePixel = 0
	bottomGrad.ZIndex = 3
	bottomGrad.Parent = reelViewport
	local bg = Instance.new("UIGradient")
	bg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	bg.Rotation = 90
	bg.Parent = bottomGrad

	-- Center selector line
	selectorLine = Instance.new("Frame")
	selectorLine.Name = "Selector"
	selectorLine.Size = UDim2.new(1, 10, 0, REEL_CELL_SIZE + 8)
	selectorLine.Position = UDim2.new(0, -5, 0.5, -(REEL_CELL_SIZE + 8) / 2)
	selectorLine.BackgroundColor3 = Theme.NeonCyan
	selectorLine.BackgroundTransparency = 0.85
	selectorLine.BorderSizePixel = 0
	selectorLine.ZIndex = 4
	selectorLine.Parent = reelViewport
	corner(selectorLine, 8)

	local selStroke = Instance.new("UIStroke")
	selStroke.Color = Theme.NeonCyan
	selStroke.Thickness = 2
	selStroke.Transparency = 0.2
	selStroke.Parent = selectorLine

	-- The moving strip that holds all reel cells
	reelStrip = Instance.new("Frame")
	reelStrip.Name = "ReelStrip"
	reelStrip.Size = UDim2.fromOffset(REEL_WIDTH, 0)
	reelStrip.Position = UDim2.fromOffset(0, 0)
	reelStrip.BackgroundTransparency = 1
	reelStrip.Parent = reelViewport

	-- Populate idle state with a few random icons
	for i = 1, REEL_VISIBLE_CELLS do
		buildReelCell(reelStrip, randomWeaponId(), i)
	end
	reelStrip.Size = UDim2.fromOffset(REEL_WIDTH, REEL_VISIBLE_CELLS * REEL_CELL_STRIDE)

	-- Roll button
	rollBtn = Instance.new("TextButton")
	rollBtn.Name = "RollBtn"
	rollBtn.Size = UDim2.new(1, -40, 0, 50)
	rollBtn.Position = UDim2.fromOffset(20, REEL_HEIGHT + 56)
	rollBtn.BackgroundColor3 = Theme.NeonCyan
	rollBtn.Text = "ROLL"
	rollBtn.TextSize = 18
	rollBtn.Font = Theme.FontDisplay
	rollBtn.TextColor3 = Theme.BgVoid
	rollBtn.BorderSizePixel = 0
	rollBtn.AutoButtonColor = true
	rollBtn.Parent = modal
	corner(rollBtn, 10)

	rollBtn.MouseButton1Click:Connect(function()
		if rolling then
			return
		end
		hideResult()

		local snap = ShopEconomyClient.GetSnapshot()
		if snap.freeSpinAvailable then
			rolling = true
			updateRollButton()
			if freeSpinRequester then
				freeSpinRequester()
			end
		else
			local productId = GachaConfig.DEVELOPER_PRODUCT_ID
			if productId and productId > 0 then
				rolling = true
				updateRollButton()
				MarketplaceService:PromptProductPurchase(LocalPlayer, productId)
			end
		end
	end)

	-- Result flash (full modal overlay)
	resultFlash = Instance.new("Frame")
	resultFlash.Name = "Flash"
	resultFlash.Size = UDim2.fromScale(1, 1)
	resultFlash.BackgroundColor3 = Color3.new(1, 1, 1)
	resultFlash.BackgroundTransparency = 1
	resultFlash.BorderSizePixel = 0
	resultFlash.ZIndex = 10
	resultFlash.Visible = false
	resultFlash.Parent = modal

	-- Result panel (appears after reel stops)
	local resultY = REEL_HEIGHT + 56 + 54
	resultFrame = Instance.new("Frame")
	resultFrame.Name = "ResultPanel"
	resultFrame.Size = UDim2.new(1, -40, 0, 140)
	resultFrame.Position = UDim2.fromOffset(20, resultY)
	resultFrame.BackgroundColor3 = Theme.PanelDeep
	resultFrame.BackgroundTransparency = 0.1
	resultFrame.BorderSizePixel = 0
	resultFrame.Visible = false
	resultFrame.Parent = modal
	corner(resultFrame, 12)

	resultIcon = Instance.new("ImageLabel")
	resultIcon.Size = UDim2.fromOffset(44, 44)
	resultIcon.Position = UDim2.new(0.5, 0, 0, 6)
	resultIcon.AnchorPoint = Vector2.new(0.5, 0)
	resultIcon.BackgroundTransparency = 1
	resultIcon.ScaleType = Enum.ScaleType.Fit
	resultIcon.Parent = resultFrame

	resultRarity = Instance.new("TextLabel")
	resultRarity.Name = "Rarity"
	resultRarity.Size = UDim2.new(1, -16, 0, 18)
	resultRarity.Position = UDim2.fromOffset(8, 54)
	resultRarity.BackgroundTransparency = 1
	resultRarity.TextSize = 12
	resultRarity.Font = Enum.Font.GothamBold
	resultRarity.TextColor3 = Theme.NeonAmber
	resultRarity.TextXAlignment = Enum.TextXAlignment.Center
	resultRarity.Parent = resultFrame

	resultName = Instance.new("TextLabel")
	resultName.Name = "WeaponName"
	resultName.Size = UDim2.new(1, -16, 0, 24)
	resultName.Position = UDim2.fromOffset(8, 74)
	resultName.BackgroundTransparency = 1
	resultName.TextSize = 14
	resultName.Font = Theme.FontDisplay
	resultName.TextColor3 = Theme.TextBright
	resultName.TextXAlignment = Enum.TextXAlignment.Center
	resultName.TextWrapped = true
	resultName.Parent = resultFrame

	resultRounds = Instance.new("TextLabel")
	resultRounds.Name = "Rounds"
	resultRounds.Size = UDim2.new(1, -16, 0, 20)
	resultRounds.Position = UDim2.fromOffset(8, 102)
	resultRounds.BackgroundTransparency = 1
	resultRounds.TextSize = 12
	resultRounds.Font = Theme.FontBody
	resultRounds.TextColor3 = Theme.NeonLime
	resultRounds.TextXAlignment = Enum.TextXAlignment.Center
	resultRounds.Parent = resultFrame

	tempListFrame = nil
end

function GachaGUI.Init()
	buildGUI()
	ShopEconomyClient.Subscribe(function()
		updateRollButton()
		refreshTempWeapons()
	end)
	updateRollButton()
	refreshTempWeapons()
end

function GachaGUI.Show()
	if not gui then
		return
	end
	visible = true
	rolling = false
	gui.Enabled = true
	freezeMovement()
	hideResult()
	updateRollButton()
	refreshTempWeapons()

	if rollBtn then
		rollBtn.Position = UDim2.fromOffset(20, REEL_HEIGHT + 56)
	end

	stopReelConnection()
	if reelStrip then
		for _, child in ipairs(reelStrip:GetChildren()) do
			child:Destroy()
		end
		for i = 1, REEL_VISIBLE_CELLS do
			buildReelCell(reelStrip, randomWeaponId(), i)
		end
		reelStrip.Size = UDim2.fromOffset(REEL_WIDTH, REEL_VISIBLE_CELLS * REEL_CELL_STRIDE)
		reelStrip.Position = UDim2.fromOffset(0, 0)
	end
end

function GachaGUI.Hide()
	if not gui then
		return
	end
	visible = false
	rolling = false
	gui.Enabled = false
	stopReelConnection()
	restoreMovement()
end

function GachaGUI.IsVisible()
	return visible
end

function GachaGUI.SetFreeSpinRequester(fn: () -> ())
	freeSpinRequester = fn
end

function GachaGUI.ShowResult(payload)
	if not gui or not reelStrip then
		return
	end

	if not visible then
		return
	end

	animateReel(payload.weaponId, function()
		showResultPanel(payload)
	end)
end

return GachaGUI
