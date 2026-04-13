--[[
	LowHealthDecalGUI
	Full-screen decal that fades in as the local player's health drops and fades out when healthy.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local DECAL_IMAGE = "rbxassetid://10556220377"
-- Health ratio (0–1): above high = decal fully hidden; at/below low = strongest vignette.
local FADE_START_RATIO = 0.5
local FADE_END_RATIO = 0.10
-- ImageTransparency at full low-health intensity (higher = subtler; 1 = invisible).
local MIN_TRANSPARENCY = 0.68
local TWEEN_TIME = 0.45
local TWEEN_STYLE = Enum.EasingStyle.Quad
local TWEEN_DIR = Enum.EasingDirection.Out

local gui = nil
local imageLabel = nil
local healthConnection = nil
local diedConnection = nil
local maxHealthConnection = nil
local activeTween = nil

local function transparencyForHealthRatio(ratio)
	ratio = math.clamp(ratio, 0, 1)
	if ratio >= FADE_START_RATIO then
		return 1
	end
	if ratio <= FADE_END_RATIO then
		return MIN_TRANSPARENCY
	end
	local t = (FADE_START_RATIO - ratio) / (FADE_START_RATIO - FADE_END_RATIO)
	return 1 - (1 - MIN_TRANSPARENCY) * t
end

local function setDecalTargetTransparency(target)
	if not imageLabel then
		return
	end
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	local tween = TweenService:Create(
		imageLabel,
		TweenInfo.new(TWEEN_TIME, TWEEN_STYLE, TWEEN_DIR),
		{ ImageTransparency = target }
	)
	activeTween = tween
	tween.Completed:Connect(function()
		if activeTween == tween then
			activeTween = nil
		end
	end)
	tween:Play()
end

local function updateFromHumanoid(humanoid)
	if not humanoid or not imageLabel or not gui or not gui.Enabled then
		return
	end
	local maxHealth = humanoid.MaxHealth
	local ratio = maxHealth > 0 and (humanoid.Health / maxHealth) or 0
	setDecalTargetTransparency(transparencyForHealthRatio(ratio))
end

local function disconnectHumanoid()
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if diedConnection then
		diedConnection:Disconnect()
		diedConnection = nil
	end
	if maxHealthConnection then
		maxHealthConnection:Disconnect()
		maxHealthConnection = nil
	end
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "LowHealthDecalGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "LowHealthDecal"
	imageLabel.BackgroundTransparency = 1
	imageLabel.BorderSizePixel = 0
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.Position = UDim2.fromScale(0, 0)
	imageLabel.Image = DECAL_IMAGE
	imageLabel.ImageTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Stretch
	imageLabel.ZIndex = 1
	imageLabel.Parent = gui

	return gui
end

local function bindToCharacter(character)
	disconnectHumanoid()
	if not character or not character.Parent then
		if imageLabel then
			setDecalTargetTransparency(1)
		end
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5)
	end
	if not humanoid then
		return
	end
	updateFromHumanoid(humanoid)
	healthConnection = humanoid.HealthChanged:Connect(function()
		updateFromHumanoid(humanoid)
	end)
	maxHealthConnection = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateFromHumanoid(humanoid)
	end)
	diedConnection = humanoid.Died:Connect(function()
		updateFromHumanoid(humanoid)
	end)
end

local function init()
	createGui()
	LocalPlayer.CharacterAdded:Connect(function(character)
		if gui and gui.Enabled then
			bindToCharacter(character)
		end
	end)
	if LocalPlayer.Character and gui and gui.Enabled then
		bindToCharacter(LocalPlayer.Character)
	end
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			bindToCharacter(LocalPlayer.Character)
		end
	end,
	Hide = function()
		disconnectHumanoid()
		if imageLabel then
			imageLabel.ImageTransparency = 1
		end
		if gui then
			gui.Enabled = false
		end
	end,
}
