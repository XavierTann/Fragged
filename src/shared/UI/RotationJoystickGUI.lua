--[[
	RotationJoystickGUI
	Second joystick on the bottom-right for mobile. Rotates the player in the
	direction of joystick movement. Only shown when TouchEnabled.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local gui = nil
local backgroundFrame = nil
local thumbstick = nil
local joystickRadiusPx = 50
local thumbRadiusPx = 24
local currentDirection = Vector2.zero
local isActive = false
local touchStartPos = Vector2.zero
local onReleaseCallbacks = {}
local thumbStartPos = Vector2.zero
local lastProcessedTouchPos = nil -- reject InputChanged from other finger ( sudden jumps )

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "RotationJoystickGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Clamp thumb position to circle, return direction Vector2 (unit)
local function clampToCircle(center, pos, radius)
	local delta = pos - center
	local len = delta.Magnitude
	if len <= 0.001 then
		return Vector2.zero
	end
	if len > radius then
		delta = delta.Unit * radius
	end
	return delta.Unit
end

-- True if touch is within/near our joystick (right side). Ignores left-joystick touches.
local function isTouchInRightJoystickZone(posX, posY)
	if not backgroundFrame then
		return false
	end
	local pos = backgroundFrame.AbsolutePosition
	local size = backgroundFrame.AbsoluteSize
	local margin = 80 -- generous for drag; left joystick stays on left
	return posX >= pos.X - margin and posX <= pos.X + size.X + margin
		and posY >= pos.Y - margin and posY <= pos.Y + size.Y + margin
end

local function updateThumbPosition(direction)
	if not thumbstick or not backgroundFrame then
		return
	end
	local radius = joystickRadiusPx - thumbRadiusPx
	local offset = direction * radius
	thumbstick.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
end

local MAX_JUMP_PX = 80 -- if touch jumps more than this, treat as different finger (e.g. left joystick)

local function onInputChanged(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if not isActive or not backgroundFrame then
		return
	end
	local touchPos = Vector2.new(input.Position.X, input.Position.Y)
	-- Reject if this touch jumped too far from our last position = different finger (left joystick)
	if lastProcessedTouchPos and (touchPos - lastProcessedTouchPos).Magnitude > MAX_JUMP_PX then
		return
	end
	if not isTouchInRightJoystickZone(input.Position.X, input.Position.Y) then
		return
	end
	lastProcessedTouchPos = touchPos
	local centerX = backgroundFrame.AbsolutePosition.X + backgroundFrame.AbsoluteSize.X / 2
	local centerY = backgroundFrame.AbsolutePosition.Y + backgroundFrame.AbsoluteSize.Y / 2
	local center = Vector2.new(centerX, centerY)
	currentDirection = clampToCircle(center, touchPos, joystickRadiusPx)
	updateThumbPosition(currentDirection)
end

local function snapToCenter()
	isActive = false
	lastProcessedTouchPos = nil
	currentDirection = Vector2.zero
	updateThumbPosition(currentDirection)
end

local function onInputEnded(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	-- Only snap when the touch that ended was in our joystick zone
	if not isTouchInRightJoystickZone(input.Position.X, input.Position.Y) then
		return
	end
	if not isActive then
		return
	end
	-- Fire release callbacks with last direction BEFORE snapping to center
	-- (Throw direction = last joystick direction before finger lift)
	if currentDirection.Magnitude > 0.01 then
		local worldDir = Vector3.new(-currentDirection.Y, 0, currentDirection.X).Unit
		for _, cb in ipairs(onReleaseCallbacks) do
			task.defer(cb, worldDir)
		end
	end
	snapToCenter()
end

-- World XZ: joystick up -> face up (+X), joystick right -> face right (+Z)
local function getWorldDirectionXZ()
	if currentDirection.Magnitude < 0.01 then
		return nil
	end
	return Vector3.new(-currentDirection.Y, 0, currentDirection.X).Unit
end

local function updateCharacterRotation()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dir = getWorldDirectionXZ()
	if not dir then
		return
	end
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + dir)
end

local function initJoystick(parent)
	-- Background circle (Frame)
	backgroundFrame = Instance.new("Frame")
	backgroundFrame.Name = "RotationJoystickBackground"
	backgroundFrame.Size = UDim2.fromOffset(120, 120)
	backgroundFrame.Position = UDim2.new(1, -100, 1, -100)
	backgroundFrame.AnchorPoint = Vector2.new(1, 1)
	backgroundFrame.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	backgroundFrame.BackgroundTransparency = 0.3
	backgroundFrame.BorderSizePixel = 0
	backgroundFrame.Parent = parent

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.5, 0)
	bgCorner.Parent = backgroundFrame

	-- Thumbstick (ImageButton)
	thumbstick = Instance.new("ImageButton")
	thumbstick.Name = "Thumbstick"
	thumbstick.Size = UDim2.fromOffset(thumbRadiusPx * 2, thumbRadiusPx * 2)
	thumbstick.Position = UDim2.new(0.5, -thumbRadiusPx, 0.5, -thumbRadiusPx)
	thumbstick.AnchorPoint = Vector2.new(0.5, 0.5)
	thumbstick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	thumbstick.BackgroundTransparency = 0.2
	thumbstick.BorderSizePixel = 0
	thumbstick.Image = ""
	thumbstick.Parent = backgroundFrame

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(0.5, 0)
	thumbCorner.Parent = thumbstick

	-- Touch: start drag on background or thumb
	local function onBackgroundInputBegan(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		isActive = true
		lastProcessedTouchPos = Vector2.new(input.Position.X, input.Position.Y)
		touchStartPos = lastProcessedTouchPos
		local cx = backgroundFrame.AbsolutePosition.X + backgroundFrame.AbsoluteSize.X / 2
		local cy = backgroundFrame.AbsolutePosition.Y + backgroundFrame.AbsoluteSize.Y / 2
		thumbStartPos = Vector2.new(cx, cy)
		currentDirection = clampToCircle(thumbStartPos, touchStartPos, joystickRadiusPx)
		updateThumbPosition(currentDirection)
	end

	backgroundFrame.InputBegan:Connect(onBackgroundInputBegan)
	thumbstick.InputBegan:Connect(onBackgroundInputBegan)

	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Apply rotation every frame when joystick has input
	RunService.RenderStepped:Connect(updateCharacterRotation)

	snapToCenter()
end

local function init()
	if not UserInputService.TouchEnabled then
		return
	end
	createGui()
	local container = Instance.new("Frame")
	container.Name = "RotationJoystickContainer"
	container.Size = UDim2.fromScale(1, 1)
	container.Position = UDim2.fromScale(0, 0)
	container.BackgroundTransparency = 1
	container.Parent = gui
	initJoystick(container)
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
	-- For external use: current joystick direction (unit Vector2, or zero)
	GetDirection = function()
		return currentDirection
	end,
	GetWorldDirectionXZ = getWorldDirectionXZ,
	-- Called when joystick returns to center (finger lifted). Receives world direction Vector3.
	SubscribeOnRelease = function(callback)
		table.insert(onReleaseCallbacks, callback)
	end,
}
