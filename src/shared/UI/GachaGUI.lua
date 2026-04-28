--[[
	GachaGUI: Full-screen gacha overlay with slot-machine rolling animation.
	A vertical reel of weapon icons spins, decelerates, and lands on the result.
	All static layout uses Scale for cross-device responsiveness.
	Reel strip/cell X positions remain offset-based for pixel-precise scroll animation.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.UI.Shop.ShopTheme)
local GachaConfig = require(Shared.Modules.GachaConfig)
local UIConfig = require(Shared.Modules.GachaGUIConfig)
local ShopEconomyClient = require(Shared.Services.ShopEconomyClient)
local SkinsConfig = require(Shared.Modules.SkinsConfig)

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
local closeBtn = nil

local savedWalkSpeed = nil
local savedJumpHeight = nil

local reelConnection = nil
local freeSpinRequester = nil

local GachaGUI = {}
local onCloseCallbacks = {}

local RARITY_COLORS = {}
for _, r in ipairs(GachaConfig.RARITIES) do
	RARITY_COLORS[r.name] = r.color
end
RARITY_COLORS["Legendary"] = RARITY_COLORS["Legendary"] or Color3.fromRGB(255, 200, 40)

-- Shorthand references into config
local RA            = UIConfig.ReelAnim
local REEL_CELL_SIZE    = RA.CellSize
local REEL_CELL_STRIDE  = RA.CellStride
local REEL_VISIBLE_CELLS = RA.VisibleCells
local REEL_SPIN_CELLS   = RA.SpinCells
local REEL_TOTAL_CELLS  = RA.TotalCells
local SPIN_DURATION     = RA.SpinDuration
local SETTLE_DURATION   = RA.SettleDuration
local SPIN_POWER        = RA.SpinPower
local REEL_OVERSHOOT    = RA.Overshoot
local LAND_PAUSE        = RA.LandPause
local RESULT_DELAY      = RA.ResultDelay

local MODAL_W     = UIConfig.Modal.Width
local MODAL_H     = UIConfig.Modal.Height
local PAD_X       = UIConfig.Layout.PadX
local CONTENT_W   = UIConfig.Layout.ContentW
local REEL_SCALE_H = UIConfig.Reel.Height
local REEL_SCALE_Y = UIConfig.Reel.PosY
local ROLL_BTN_W  = UIConfig.RollBtn.Width
local ROLL_BTN_H  = UIConfig.RollBtn.Height
local ROLL_BTN_X  = UIConfig.RollBtn.PosX
local ROLL_BTN_Y  = UIConfig.RollBtn.PosY
local RESULT_W    = UIConfig.Result.Width
local RESULT_H    = UIConfig.Result.Height
local RESULT_X    = UIConfig.Result.PosX
local RESULT_Y    = UIConfig.Result.PosY

local ALL_SKIN_IDS = {}
do
	local seen = {}
	for _, entry in ipairs(GachaConfig.POOL) do
		if not seen[entry.skinId] then
			seen[entry.skinId] = true
			table.insert(ALL_SKIN_IDS, entry.skinId)
		end
	end
end

local function getSkinIconImage(skinId)
	local skin = SkinsConfig.getSkin(skinId)
	if not skin then
		return ""
	end
	if skin.iconDecalName then
		local imports = ReplicatedStorage:FindFirstChild("Imports")
		local decals = imports and imports:FindFirstChild("Decals")
		local decal = decals and decals:FindFirstChild(skin.iconDecalName)
		if decal and decal:IsA("Decal") then
			local tex = decal.Texture
			if tex and tex ~= "" then
				return tex
			end
		end
	end
	if skin.iconAssetId and skin.iconAssetId ~= 0 then
		return "rbxassetid://" .. tostring(skin.iconAssetId)
	end
	return ""
end

local function getSkinDisplayName(skinId)
	local skin = SkinsConfig.getSkin(skinId)
	if skin then
		return skin.name or skinId
	end
	return skinId
end

local function randomPoolEntry()
	local pool = GachaConfig.POOL
	return pool[math.random(1, #pool)]
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

local function updateRollButton()
	if not rollBtn then
		return
	end
	if rolling then
		rollBtn.Text = "SPINNING..."
		rollBtn.AutoButtonColor = false
		return
	end
	local isFree = GachaConfig.DEV_FREE_ROLLS or ShopEconomyClient.GetSnapshot().freeSpinAvailable
	if isFree then
		rollBtn.Text = "FREE SPIN!"
		rollBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 255)
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
		reelViewport.Size = UDim2.fromScale(CONTENT_W, REEL_SCALE_H)
	end
end

local function buildReelCell(parent, skinId, index, rarity)
	local rarityColor = RARITY_COLORS[rarity or "Common"] or RARITY_COLORS["Common"]

	local cell = Instance.new("Frame")
	cell.Name = "Cell_" .. index
	cell.Size = UDim2.fromOffset(REEL_CELL_SIZE, REEL_CELL_SIZE)
	cell.Position = UDim2.new(0, (index - 1) * REEL_CELL_STRIDE, 0.5, 0)
	cell.AnchorPoint = Vector2.new(0, 0.5)
	cell.BackgroundColor3 = Theme.Card
	cell.BackgroundTransparency = 0.2
	cell.BorderSizePixel = 0
	cell.Parent = parent
	corner(cell, UIConfig.ReelCell.CornerRadius)

	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = rarity == "Legendary" and 2.5 or rarity == "Epic" and 2 or rarity == "Rare" and 1.5 or 1
	stroke.Transparency = rarity == "Common" and 0.5 or 0.1
	stroke.Parent = cell

	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.Size = UDim2.fromScale(UIConfig.ReelCell.IconScale, UIConfig.ReelCell.IconScale)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.BackgroundTransparency = 1
	img.Image = getSkinIconImage(skinId)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = cell

	local nameTag = Instance.new("TextLabel")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.fromScale(1, UIConfig.ReelCell.NameTagH)
	nameTag.Position = UDim2.fromScale(0, UIConfig.ReelCell.NameTagY)
	nameTag.BackgroundTransparency = 1
	nameTag.Text = getSkinDisplayName(skinId)

	nameTag.Font = Theme.FontBody
	nameTag.TextColor3 = rarityColor
	nameTag.TextScaled = true
	nameTag.TextXAlignment = Enum.TextXAlignment.Center
	nameTag.Parent = cell

	return cell
end

local function populateReel(winSkinId, winRarity)
	if reelStrip then
		for _, child in ipairs(reelStrip:GetChildren()) do
			child:Destroy()
		end
	end

	local centerSlot = math.floor(REEL_VISIBLE_CELLS / 2) + 1
	local winIndex = REEL_SPIN_CELLS + centerSlot

	for i = 1, REEL_TOTAL_CELLS do
		if i == winIndex then
			buildReelCell(reelStrip, winSkinId, i, winRarity)
		else
			local entry = randomPoolEntry()
			buildReelCell(reelStrip, entry.skinId, i, entry.rarity)
		end
	end

	local totalW = REEL_TOTAL_CELLS * REEL_CELL_STRIDE
	reelStrip.Size = UDim2.new(0, totalW, 1, 0)
	reelStrip.Position = UDim2.fromOffset(0, 0)

	return winIndex
end

local function stopReelConnection()
	if reelConnection then
		reelConnection:Disconnect()
		reelConnection = nil
	end
end

local function animateReel(winSkinId, winRarity, onFinished)
	stopReelConnection()

	local winIndex = populateReel(winSkinId, winRarity)

	local viewportWidth = reelViewport and reelViewport.AbsoluteSize.X or 300
	local winCellCenter = (winIndex - 1) * REEL_CELL_STRIDE + REEL_CELL_SIZE / 2
	local targetX = -(winCellCenter - viewportWidth / 2)

	reelStrip.Position = UDim2.fromOffset(0, 0)

	if selectorLine then
		selectorLine.Visible = true
	end

	local overshootX = targetX * (1 + REEL_OVERSHOOT)
	local spinElapsed = 0
	local settling = false
	local settleElapsed = 0

	reelConnection = RunService.RenderStepped:Connect(function(dt)
		if not settling then
			spinElapsed += dt
			local t = math.clamp(spinElapsed / SPIN_DURATION, 0, 1)
			local eased = 1 - (1 - t) ^ SPIN_POWER
			reelStrip.Position = UDim2.fromOffset(eased * overshootX, 0)

			if t >= 1 then
				settling = true
			end
		else
			settleElapsed += dt
			local t = math.clamp(settleElapsed / SETTLE_DURATION, 0, 1)
			local eased = t * t * (3 - 2 * t)
			reelStrip.Position = UDim2.fromOffset(overshootX + (targetX - overshootX) * eased, 0)

			if t >= 1 then
				stopReelConnection()
				reelStrip.Position = UDim2.fromOffset(targetX, 0)

				task.delay(LAND_PAUSE, function()
					if selectorLine then
						local glow = TweenService:Create(selectorLine, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 2, true), {
							BackgroundTransparency = 0,
						})
						glow:Play()
					end

					task.delay(RESULT_DELAY, function()
						if onFinished then
							onFinished()
						end
					end)
				end)
			end
		end
	end)
end

local function showResultPanel(payload)
	if not resultFrame then
		return
	end

	local rarityColor = RARITY_COLORS[payload.rarity] or Theme.TextBright
	local skinName = payload.skinName or getSkinDisplayName(payload.skinId)
	local iconId = payload.iconAssetId
	local iconImage = (iconId and iconId ~= 0) and ("rbxassetid://" .. tostring(iconId)) or getSkinIconImage(payload.skinId)

	resultIcon.Image = iconImage
	resultRarity.Text = string.upper(payload.rarity)
	resultRarity.TextColor3 = rarityColor
	resultName.Text = string.upper(skinName)

	if payload.duplicate then
		local credits = payload.consolationCredits or 300
		resultRounds.Text = "ALREADY OWNED  +" .. credits .. " CREDITS"
		resultRounds.TextColor3 = Theme.NeonAmber
	else
		resultRounds.Text = "SKIN UNLOCKED!"
		resultRounds.TextColor3 = Theme.NeonLime
	end


	if reelViewport then
		local shrink = TweenService:Create(reelViewport, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(CONTENT_W, 0),
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

	resultFrame.Position = UDim2.fromScale(RESULT_X, RESULT_Y)
	resultFrame.Visible = true
	resultFrame.Size = UDim2.fromScale(RESULT_W, 0.026)
	resultFrame.BackgroundTransparency = 0
	local expandTween = TweenService:Create(resultFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(RESULT_W, RESULT_H),
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

	if rollBtn then
		local btnTween = TweenService:Create(rollBtn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(ROLL_BTN_X, UIConfig.ResultBtnPosY),
		})
		btnTween:Play()
	end

	rolling = false
	updateRollButton()
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
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("TextButton")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.BgVoid
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Active = true
	overlay.Parent = gui

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromScale(MODAL_W, MODAL_H)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = Theme.Panel
	modal.BorderSizePixel = 0
	modal.ClipsDescendants = true
	modal.Parent = overlay
	corner(modal, UIConfig.Modal.CornerRadius)

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Theme.NeonCyan
	modalStroke.Thickness = 2
	modalStroke.Transparency = 0.2
	modalStroke.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(UIConfig.Title.Width, UIConfig.Title.Height)
	title.Position = UDim2.fromScale(UIConfig.Title.PosX, UIConfig.Title.PosY)
	title.BackgroundTransparency = 1
	title.Text = "WEAPON FABRICATOR"

	title.Font = Theme.FontDisplay
	title.TextColor3 = Theme.NeonCyan
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = modal

	closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromScale(UIConfig.CloseBtn.Width, UIConfig.CloseBtn.Height)
	closeBtn.Position = UDim2.fromScale(UIConfig.CloseBtn.PosX, UIConfig.CloseBtn.PosY)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Theme.PanelDeep
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "X"

	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextColor3 = Theme.TextBright
	closeBtn.TextScaled = true
	closeBtn.Parent = modal
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.DominantAxis = Enum.DominantAxis.Height
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
		if not rolling then
			GachaGUI.Hide()
		end
	end)

	reelViewport = Instance.new("Frame")
	reelViewport.Name = "ReelViewport"
	reelViewport.Size = UDim2.fromScale(CONTENT_W, REEL_SCALE_H)
	reelViewport.Position = UDim2.fromScale(PAD_X, REEL_SCALE_Y)
	reelViewport.BackgroundColor3 = Theme.PanelDeep
	reelViewport.BackgroundTransparency = 0.3
	reelViewport.BorderSizePixel = 0
	reelViewport.ClipsDescendants = true
	reelViewport.Parent = modal
	corner(reelViewport, UIConfig.Reel.CornerRadius)

	local viewportStroke = Instance.new("UIStroke")
	viewportStroke.Color = Theme.TextMuted
	viewportStroke.Thickness = 1
	viewportStroke.Transparency = 0.5
	viewportStroke.Parent = reelViewport

	local leftGrad = Instance.new("Frame")
	leftGrad.Name = "LeftFade"
	leftGrad.Size = UDim2.fromScale(UIConfig.GradientFade.Width, 1)
	leftGrad.Position = UDim2.fromScale(0, 0)
	leftGrad.BackgroundColor3 = Theme.Panel
	leftGrad.BorderSizePixel = 0
	leftGrad.ZIndex = 3
	leftGrad.Parent = reelViewport
	local lg = Instance.new("UIGradient")
	lg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	lg.Rotation = 0
	lg.Parent = leftGrad

	local rightGrad = Instance.new("Frame")
	rightGrad.Name = "RightFade"
	rightGrad.Size = UDim2.fromScale(UIConfig.GradientFade.Width, 1)
	rightGrad.Position = UDim2.fromScale(1 - UIConfig.GradientFade.Width, 0)
	rightGrad.BackgroundColor3 = Theme.Panel
	rightGrad.BorderSizePixel = 0
	rightGrad.ZIndex = 3
	rightGrad.Parent = reelViewport
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	rg.Rotation = 0
	rg.Parent = rightGrad

	selectorLine = Instance.new("Frame")
	selectorLine.Name = "Selector"
	selectorLine.Size = UDim2.fromScale(UIConfig.Selector.Width, UIConfig.Selector.Height)
	selectorLine.Position = UDim2.fromScale(0.5, 0.5)
	selectorLine.AnchorPoint = Vector2.new(0.5, 0.5)
	selectorLine.BackgroundColor3 = Theme.NeonCyan
	selectorLine.BackgroundTransparency = 0.85
	selectorLine.BorderSizePixel = 0
	selectorLine.ZIndex = 4
	selectorLine.Parent = reelViewport
	corner(selectorLine, UIConfig.Selector.CornerRadius)

	local selStroke = Instance.new("UIStroke")
	selStroke.Color = Theme.NeonCyan
	selStroke.Thickness = 2
	selStroke.Transparency = 0.2
	selStroke.Parent = selectorLine

	-- Reel strip: X offset for scroll animation, Y scale to fill viewport
	reelStrip = Instance.new("Frame")
	reelStrip.Name = "ReelStrip"
	reelStrip.Size = UDim2.new(0, 0, 1, 0)
	reelStrip.Position = UDim2.fromOffset(0, 0)
	reelStrip.BackgroundTransparency = 1
	reelStrip.Parent = reelViewport

	for i = 1, REEL_VISIBLE_CELLS do
		local entry = randomPoolEntry()
		buildReelCell(reelStrip, entry.skinId, i, entry.rarity)
	end
	local idleStripW = REEL_VISIBLE_CELLS * REEL_CELL_STRIDE
	reelStrip.Size = UDim2.new(0, idleStripW, 1, 0)
	local viewW = reelViewport.AbsoluteSize.X
	if viewW <= 0 then
		viewW = 300
	end
	local centerCellCenter = math.floor(REEL_VISIBLE_CELLS / 2) * REEL_CELL_STRIDE + REEL_CELL_SIZE / 2
	reelStrip.Position = UDim2.fromOffset(viewW / 2 - centerCellCenter, 0)

	rollBtn = Instance.new("TextButton")
	rollBtn.Name = "RollBtn"
	rollBtn.Size = UDim2.fromScale(ROLL_BTN_W, ROLL_BTN_H)
	rollBtn.Position = UDim2.fromScale(ROLL_BTN_X, ROLL_BTN_Y)
	rollBtn.BackgroundColor3 = Theme.NeonCyan
	rollBtn.Text = "ROLL"

	rollBtn.Font = Theme.FontDisplay
	rollBtn.TextColor3 = Theme.BgVoid
	rollBtn.TextScaled = true
	rollBtn.BorderSizePixel = 0
	rollBtn.AutoButtonColor = true
	rollBtn.Parent = modal
	corner(rollBtn, UIConfig.RollBtn.CornerRadius)

	rollBtn.MouseButton1Click:Connect(function()
		if rolling then
			return
		end
		hideResult()

		local isFree = GachaConfig.DEV_FREE_ROLLS or ShopEconomyClient.GetSnapshot().freeSpinAvailable
		if isFree then
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

	resultFlash = Instance.new("Frame")
	resultFlash.Name = "Flash"
	resultFlash.Size = UDim2.fromScale(1, 1)
	resultFlash.BackgroundColor3 = Color3.new(1, 1, 1)
	resultFlash.BackgroundTransparency = 1
	resultFlash.BorderSizePixel = 0
	resultFlash.ZIndex = 10
	resultFlash.Visible = false
	resultFlash.Parent = modal

	resultFrame = Instance.new("Frame")
	resultFrame.Name = "ResultPanel"
	resultFrame.Size = UDim2.fromScale(RESULT_W, RESULT_H)
	resultFrame.Position = UDim2.fromScale(RESULT_X, RESULT_Y)
	resultFrame.BackgroundColor3 = Theme.PanelDeep
	resultFrame.BackgroundTransparency = 0.1
	resultFrame.BorderSizePixel = 0
	resultFrame.Visible = false
	resultFrame.Parent = modal
	corner(resultFrame, UIConfig.Result.CornerRadius)

	resultIcon = Instance.new("ImageLabel")
	resultIcon.Size = UDim2.fromScale(UIConfig.ResultIcon.Width, UIConfig.ResultIcon.Height)
	resultIcon.Position = UDim2.fromScale(0.5, UIConfig.ResultIcon.PosY)
	resultIcon.AnchorPoint = Vector2.new(0.5, 0)
	resultIcon.BackgroundTransparency = 1
	resultIcon.ScaleType = Enum.ScaleType.Fit
	resultIcon.Parent = resultFrame
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = resultIcon

	resultRarity = Instance.new("TextLabel")
	resultRarity.Name = "Rarity"
	resultRarity.Size = UDim2.fromScale(UIConfig.ResultRarity.Width, UIConfig.ResultRarity.Height)
	resultRarity.Position = UDim2.fromScale(UIConfig.ResultRarity.PosX, UIConfig.ResultRarity.PosY)
	resultRarity.BackgroundTransparency = 1

	resultRarity.Font = Enum.Font.GothamBold
	resultRarity.TextColor3 = Theme.NeonAmber
	resultRarity.TextScaled = true
	resultRarity.TextXAlignment = Enum.TextXAlignment.Center
	resultRarity.Parent = resultFrame

	resultName = Instance.new("TextLabel")
	resultName.Name = "WeaponName"
	resultName.Size = UDim2.fromScale(UIConfig.ResultName.Width, UIConfig.ResultName.Height)
	resultName.Position = UDim2.fromScale(UIConfig.ResultName.PosX, UIConfig.ResultName.PosY)
	resultName.BackgroundTransparency = 1

	resultName.Font = Theme.FontDisplay
	resultName.TextColor3 = Theme.TextBright
	resultName.TextScaled = true
	resultName.TextXAlignment = Enum.TextXAlignment.Center
	resultName.TextWrapped = true
	resultName.Parent = resultFrame

	resultRounds = Instance.new("TextLabel")
	resultRounds.Name = "Rounds"
	resultRounds.Size = UDim2.fromScale(UIConfig.ResultRounds.Width, UIConfig.ResultRounds.Height)
	resultRounds.Position = UDim2.fromScale(UIConfig.ResultRounds.PosX, UIConfig.ResultRounds.PosY)
	resultRounds.BackgroundTransparency = 1

	resultRounds.Font = Theme.FontBody
	resultRounds.TextColor3 = Theme.NeonLime
	resultRounds.TextScaled = true
	resultRounds.TextXAlignment = Enum.TextXAlignment.Center
	resultRounds.Parent = resultFrame

	local obtainBtn = Instance.new("TextButton")
	obtainBtn.Name = "ObtainBtn"
	obtainBtn.Size = UDim2.fromScale(UIConfig.ObtainBtn.Width, UIConfig.ObtainBtn.Height)
	obtainBtn.Position = UDim2.fromScale(UIConfig.ObtainBtn.PosX, UIConfig.ObtainBtn.PosY)
	obtainBtn.AnchorPoint = Vector2.new(0, 0)
	obtainBtn.BackgroundColor3 = Theme.NeonCyan
	obtainBtn.BorderSizePixel = 0
	obtainBtn.Text = "OBTAIN"
	obtainBtn.Font = Theme.FontDisplay
	obtainBtn.TextColor3 = Theme.BgVoid
	obtainBtn.TextScaled = true
	obtainBtn.AutoButtonColor = true
	obtainBtn.Parent = resultFrame
	corner(obtainBtn, UIConfig.ObtainBtn.CornerRadius)

	obtainBtn.MouseButton1Click:Connect(function()
		hideResult()
		if rollBtn then
			rollBtn.Position = UDim2.fromScale(ROLL_BTN_X, ROLL_BTN_Y)
		end
		updateRollButton()
	end)

end

function GachaGUI.Init()
	buildGUI()
	ShopEconomyClient.Subscribe(function()
		updateRollButton()
	end)
	updateRollButton()
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

	if rollBtn then
		rollBtn.Position = UDim2.fromScale(ROLL_BTN_X, ROLL_BTN_Y)
	end

	stopReelConnection()
	if reelStrip then
		for _, child in ipairs(reelStrip:GetChildren()) do
			child:Destroy()
		end
		for i = 1, REEL_VISIBLE_CELLS do
			local entry = randomPoolEntry()
			buildReelCell(reelStrip, entry.skinId, i, entry.rarity)
		end
		local idleW = REEL_VISIBLE_CELLS * REEL_CELL_STRIDE
		reelStrip.Size = UDim2.new(0, idleW, 1, 0)
		local vw = reelViewport and reelViewport.AbsoluteSize.X or 300
		if vw <= 0 then
			vw = 300
		end
		local ccCenter = math.floor(REEL_VISIBLE_CELLS / 2) * REEL_CELL_STRIDE + REEL_CELL_SIZE / 2
		reelStrip.Position = UDim2.fromOffset(vw / 2 - ccCenter, 0)
	end
end

function GachaGUI.Hide()
	if not gui then
		return
	end
	local wasVisible = visible
	visible = false
	rolling = false
	gui.Enabled = false
	stopReelConnection()
	restoreMovement()
	if wasVisible then
		for _, cb in ipairs(onCloseCallbacks) do
			task.spawn(cb)
		end
	end
end

function GachaGUI.SubscribeOnClose(cb)
	table.insert(onCloseCallbacks, cb)
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

	animateReel(payload.skinId, payload.rarity, function()
		showResultPanel(payload)
	end)
end

function GachaGUI.BuildPreview(parent)
	local previewGui = Instance.new("Frame")
	previewGui.Name = "GachaPreview"
	previewGui.Size = UDim2.fromScale(1, 1)
	previewGui.BackgroundTransparency = 1
	previewGui.Parent = parent

	local prevOverlay = Instance.new("Frame")
	prevOverlay.Name = "Overlay"
	prevOverlay.Size = UDim2.fromScale(1, 1)
	prevOverlay.BackgroundColor3 = Theme.BgVoid
	prevOverlay.BackgroundTransparency = 1
	prevOverlay.BorderSizePixel = 0
	prevOverlay.Parent = previewGui

	local prevModal = Instance.new("Frame")
	prevModal.Name = "Modal"
	prevModal.Size = UDim2.fromScale(MODAL_W, MODAL_H)
	prevModal.Position = UDim2.fromScale(0.5, 0.5)
	prevModal.AnchorPoint = Vector2.new(0.5, 0.5)
	prevModal.BackgroundColor3 = Theme.Panel
	prevModal.BorderSizePixel = 0
	prevModal.BackgroundTransparency = 1
	prevModal.ClipsDescendants = true
	prevModal.Parent = prevOverlay
	corner(prevModal, UIConfig.Modal.CornerRadius)

	local prevStroke = Instance.new("UIStroke")
	prevStroke.Color = Theme.NeonCyan
	prevStroke.Thickness = 2
	prevStroke.Transparency = 0.2
	prevStroke.Parent = prevModal

	local prevTitle = Instance.new("TextLabel")
	prevTitle.Size = UDim2.fromScale(UIConfig.Title.Width, UIConfig.Title.Height)
	prevTitle.Position = UDim2.fromScale(UIConfig.Title.PosX, UIConfig.Title.PosY)
	prevTitle.BackgroundTransparency = 1
	prevTitle.Text = "WEAPON FABRICATOR"

	prevTitle.Font = Theme.FontDisplay
	prevTitle.TextColor3 = Theme.NeonCyan
	prevTitle.TextScaled = true
	prevTitle.TextXAlignment = Enum.TextXAlignment.Left
	prevTitle.Parent = prevModal

	local prevClose = Instance.new("TextButton")
	prevClose.Size = UDim2.fromScale(UIConfig.CloseBtn.Width, UIConfig.CloseBtn.Height)
	prevClose.Position = UDim2.fromScale(UIConfig.CloseBtn.PosX, UIConfig.CloseBtn.PosY)
	prevClose.AnchorPoint = Vector2.new(1, 0)
	prevClose.BackgroundColor3 = Theme.PanelDeep
	prevClose.BorderSizePixel = 0
	prevClose.Text = "X"

	prevClose.Font = Enum.Font.GothamBold
	prevClose.TextColor3 = Theme.TextBright
	prevClose.TextScaled = true
	prevClose.Parent = prevModal
	local prevCloseAspect = Instance.new("UIAspectRatioConstraint")
	prevCloseAspect.AspectRatio = 1
	prevCloseAspect.DominantAxis = Enum.DominantAxis.Height
	prevCloseAspect.Parent = prevClose
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(1, 0)
	cc.Parent = prevClose

	local prevReel = Instance.new("Frame")
	prevReel.Name = "ReelViewport"
	prevReel.Size = UDim2.fromScale(CONTENT_W, REEL_SCALE_H)
	prevReel.Position = UDim2.fromScale(PAD_X, REEL_SCALE_Y)
	prevReel.BackgroundColor3 = Theme.PanelDeep
	prevReel.BackgroundTransparency = 0.3
	prevReel.BorderSizePixel = 0
	prevReel.ClipsDescendants = true
	prevReel.Parent = prevModal
	corner(prevReel, UIConfig.Reel.CornerRadius)

	local prevStrip = Instance.new("Frame")
	prevStrip.Name = "ReelStrip"
	prevStrip.BackgroundTransparency = 1
	prevStrip.Parent = prevReel
	local previewRarities = {"Common", "Epic", "Legendary"}
	for i = 1, REEL_VISIBLE_CELLS do
		local sid = ALL_SKIN_IDS[(i - 1) % math.max(#ALL_SKIN_IDS, 1) + 1]
		local rar = previewRarities[(i - 1) % #previewRarities + 1]
		buildReelCell(prevStrip, sid, i, rar)
	end
	prevStrip.Size = UDim2.new(0, REEL_VISIBLE_CELLS * REEL_CELL_STRIDE, 1, 0)

	local prevSel = Instance.new("Frame")
	prevSel.Name = "Selector"
	prevSel.Size = UDim2.fromScale(UIConfig.Selector.Width, UIConfig.Selector.Height)
	prevSel.Position = UDim2.fromScale(0.5, 0.5)
	prevSel.AnchorPoint = Vector2.new(0.5, 0.5)
	prevSel.BackgroundColor3 = Theme.NeonCyan
	prevSel.BackgroundTransparency = 0.85
	prevSel.BorderSizePixel = 0
	prevSel.ZIndex = 4
	prevSel.Parent = prevReel
	corner(prevSel, UIConfig.Selector.CornerRadius)
	local prevSelStroke = Instance.new("UIStroke")
	prevSelStroke.Color = Theme.NeonCyan
	prevSelStroke.Thickness = 2
	prevSelStroke.Transparency = 0.2
	prevSelStroke.Parent = prevSel

	local prevRollBtn = Instance.new("TextButton")
	prevRollBtn.Name = "RollBtn"
	prevRollBtn.Size = UDim2.fromScale(ROLL_BTN_W, ROLL_BTN_H)
	prevRollBtn.Position = UDim2.fromScale(ROLL_BTN_X, ROLL_BTN_Y)
	prevRollBtn.BackgroundColor3 = Theme.NeonLime
	prevRollBtn.Text = "FREE SPIN!"
	prevRollBtn.TextScaled = true
	prevRollBtn.Font = Theme.FontDisplay
	prevRollBtn.TextColor3 = Theme.BgVoid
	prevRollBtn.BorderSizePixel = 0
	prevRollBtn.Parent = prevModal
	corner(prevRollBtn, UIConfig.RollBtn.CornerRadius)

	return previewGui
end

return GachaGUI
