--[[
	MovementDirectionIndicatorClient
	Blue: movement from Humanoid.MoveDirection (WASD, move thumbstick, gamepad left).
	Red: line along shooting direction when off-axis — touch: rotation joystick pulled
	from center; desktop: mouse ground point farther than AIM_MIN_CURSOR_GROUND_DIST on XZ.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local RotationJoystickGUI = require(Shared.UI.RotationJoystickGUI)

local LocalPlayer = Players.LocalPlayer

-- Studs from HumanoidRootPart position on XZ; Y is raised slightly for visibility
local OFFSET_RADIUS = 3.25
-- World length of the red aim line (studs from root to tip on XZ)
local AIM_LINE_LENGTH = 8.5
local Y_ABOVE_ROOT = 0.2
local AIM_Y_ABOVE_ROOT = 0.34
local DOT_DIAMETER = 0.38
-- Beam width (studs); FaceCamera helps readability in top-down view
local AIM_BEAM_WIDTH = 0.28

local MIN_INPUT_MAGNITUDE = 0.04
-- Hide aim line when the cursor’s ground aim is near the character (still on-axis)
local AIM_MIN_CURSOR_GROUND_DIST = 1.15
local SMOOTH_RATE = 14
local AIM_SMOOTH_RATE = 16

local renderConnection = nil
local dotPart = nil
local aimLinePart = nil
local smoothedOffsetXZ = Vector3.zero
local smoothedAimOffsetXZ = Vector3.zero

local function destroyDots()
	if dotPart then
		dotPart:Destroy()
		dotPart = nil
	end
	if aimLinePart then
		aimLinePart:Destroy()
		aimLinePart = nil
	end
end

local function ensureDot(character)
	if dotPart and dotPart.Parent == character then
		return dotPart
	end
	if dotPart then
		dotPart:Destroy()
		dotPart = nil
	end
	local p = Instance.new("Part")
	p.Name = "MovementDirectionIndicator"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * DOT_DIAMETER
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(130, 210, 255)
	p.Transparency = 1
	p.Parent = character
	dotPart = p
	return p
end

local function ensureAimLine(character)
	if aimLinePart and aimLinePart.Parent == character then
		return aimLinePart
	end
	if aimLinePart then
		aimLinePart:Destroy()
		aimLinePart = nil
	end
	-- Invisible carrier; visible segment is a Beam (cylinders read as dots from straight above)
	local p = Instance.new("Part")
	p.Name = "AimDirectionIndicator"
	p.Size = Vector3.one * 0.05
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = character

	local att0 = Instance.new("Attachment")
	att0.Name = "AimLineStart"
	att0.Parent = p
	local att1 = Instance.new("Attachment")
	att1.Name = "AimLineEnd"
	att1.Parent = p

	local beam = Instance.new("Beam")
	beam.Name = "AimDirectionBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = AIM_BEAM_WIDTH
	beam.Width1 = AIM_BEAM_WIDTH
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 85, 95))
	beam.Transparency = NumberSequence.new(0.08)
	beam.LightEmission = 0.35
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = p

	aimLinePart = p
	return p
end

local function aimDirectionToOffsetXZ()
	if UserInputService.TouchEnabled then
		local joyDir = RotationJoystickGUI.GetWorldDirectionXZ()
		if joyDir then
			return joyDir * AIM_LINE_LENGTH
		end
		return Vector3.zero
	end

	local dir = CombatServiceClient.GetAimDirectionXZ(AIM_MIN_CURSOR_GROUND_DIST)
	if dir then
		return dir * AIM_LINE_LENGTH
	end
	return Vector3.zero
end

local function flattenMoveXZ(moveDirection)
	local v = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if v.Magnitude < MIN_INPUT_MAGNITUDE then
		return Vector3.zero
	end
	return v.Unit * OFFSET_RADIUS
end

local function onRenderStep(dt)
	local character = LocalPlayer.Character
	if not character or not character.Parent then
		destroyDots()
		smoothedOffsetXZ = Vector3.zero
		smoothedAimOffsetXZ = Vector3.zero
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	local targetOffset = flattenMoveXZ(humanoid.MoveDirection)
	local alpha = 1 - math.exp(-SMOOTH_RATE * dt)
	smoothedOffsetXZ = smoothedOffsetXZ:Lerp(targetOffset, alpha)

	local part = ensureDot(character)
	local showMove = smoothedOffsetXZ.Magnitude > 0.08
	part.Transparency = showMove and 0.12 or 1
	local pos = root.Position + Vector3.new(smoothedOffsetXZ.X, Y_ABOVE_ROOT, smoothedOffsetXZ.Z)
	part.CFrame = CFrame.new(pos)

	local targetAim = aimDirectionToOffsetXZ()
	local aimAlpha = 1 - math.exp(-AIM_SMOOTH_RATE * dt)
	smoothedAimOffsetXZ = smoothedAimOffsetXZ:Lerp(targetAim, aimAlpha)

	local aimPart = ensureAimLine(character)
	local beam = aimPart:FindFirstChild("AimDirectionBeam")
	local att0 = aimPart:FindFirstChild("AimLineStart")
	local att1 = aimPart:FindFirstChild("AimLineEnd")
	local showAim = smoothedAimOffsetXZ.Magnitude > 0.08
	if beam then
		beam.Enabled = showAim
	end
	local yLift = Vector3.new(0, AIM_Y_ABOVE_ROOT, 0)
	local startPos = root.Position + yLift
	local endPos = root.Position + Vector3.new(smoothedAimOffsetXZ.X, AIM_Y_ABOVE_ROOT, smoothedAimOffsetXZ.Z)
	local span = endPos - startPos
	local length = span.Magnitude
	if length > 0.001 and att0 and att1 then
		local dir = span.Unit
		local mid = startPos + dir * (length * 0.5)
		local aux = math.abs(dir.Y) < 0.95 and Vector3.yAxis or Vector3.zAxis
		local right = dir:Cross(aux)
		if right.Magnitude < 0.001 then
			aux = Vector3.xAxis
			right = dir:Cross(aux)
		end
		right = right.Unit
		aimPart.CFrame = CFrame.fromMatrix(mid, right, dir)
		att0.Position = Vector3.new(0, -length * 0.5, 0)
		att1.Position = Vector3.new(0, length * 0.5, 0)
	elseif att0 and att1 then
		aimPart.CFrame = CFrame.new(startPos)
		att0.Position = Vector3.zero
		att1.Position = Vector3.zero
	end
end

return {
	Init = function()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		destroyDots()
		smoothedOffsetXZ = Vector3.zero
		smoothedAimOffsetXZ = Vector3.zero

		LocalPlayer.CharacterRemoving:Connect(function()
			destroyDots()
			smoothedOffsetXZ = Vector3.zero
			smoothedAimOffsetXZ = Vector3.zero
		end)

		renderConnection = RunService.RenderStepped:Connect(onRenderStep)
	end,
}
