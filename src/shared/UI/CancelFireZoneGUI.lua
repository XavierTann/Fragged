--[[
	CancelFireZoneGUI
	Non-interactive decal strip above the aim joystick for release-to-fire weapons.
	Visible only when release mode is on, the joystick touch is active, and aim is off-axis.
	RotationJoystickGUI calls UpdateFromJoystick / IsReleaseInsideCancelZone / SetReleaseModeEnabled.
]]

local DECAL_TEXTURE = "rbxassetid://12449337505"
local AIM_OFF_AXIS_EPS = 0.01

local rootFrame = nil
local releaseModeEnabled = false
local lastJoystickActive = false
local lastDirectionMagnitude = 0

local function screenPointInGuiObject(screenPoint, guiObject)
	if not guiObject or not guiObject.Parent then
		return false
	end
	local ap = guiObject.AbsolutePosition
	local sz = guiObject.AbsoluteSize
	return screenPoint.X >= ap.X
		and screenPoint.X <= ap.X + sz.X
		and screenPoint.Y >= ap.Y
		and screenPoint.Y <= ap.Y + sz.Y
end

local function applyVisibility()
	if not rootFrame then
		return
	end
	rootFrame.Visible = releaseModeEnabled
		and lastJoystickActive
		and lastDirectionMagnitude > AIM_OFF_AXIS_EPS
end

local function mount(parent)
	if rootFrame then
		return
	end
	rootFrame = Instance.new("Frame")
	rootFrame.Name = "CancelFireZone"
	rootFrame.AnchorPoint = Vector2.new(1, 1)
	rootFrame.Size = UDim2.fromOffset(116, 42)
	rootFrame.Position = UDim2.new(1, -44, 1, -300)
	rootFrame.BackgroundTransparency = 1
	rootFrame.BorderSizePixel = 0
	rootFrame.Visible = false
	rootFrame.Active = false
	rootFrame.ZIndex = 2
	rootFrame.Parent = parent

	local cancelIcon = Instance.new("ImageLabel")
	cancelIcon.Name = "Decal"
	cancelIcon.BackgroundTransparency = 1
	cancelIcon.Size = UDim2.fromScale(1, 1)
	cancelIcon.Image = DECAL_TEXTURE
	cancelIcon.ScaleType = Enum.ScaleType.Fit
	cancelIcon.Parent = rootFrame

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 10)
	iconCorner.Parent = cancelIcon
end

return {
	Mount = mount,

	SetReleaseModeEnabled = function(active)
		releaseModeEnabled = active == true
		applyVisibility()
	end,

	--- Call whenever joystick drag state or aim direction changes.
	UpdateFromJoystick = function(isJoystickActive, aimDirectionVector2)
		lastJoystickActive = isJoystickActive == true
		lastDirectionMagnitude = aimDirectionVector2 and aimDirectionVector2.Magnitude or 0
		applyVisibility()
	end,

	--- Hit test for touch release (screen pixels). Ignores visibility; geometric test only.
	IsReleaseInsideCancelZone = function(screenPoint)
		if not releaseModeEnabled or not rootFrame then
			return false
		end
		return screenPointInGuiObject(screenPoint, rootFrame)
	end,
}
