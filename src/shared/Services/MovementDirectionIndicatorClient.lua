--[[
	MovementDirectionIndicatorClient
	Small world-space dot offset from the local player in the direction of movement
	input. Uses Humanoid.MoveDirection so keyboard, touch move stick, and gamepad
	left stick all share the same vector. Smoothly interpolates position when
	input changes or stops.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Studs from HumanoidRootPart position on XZ; Y is raised slightly for visibility
local OFFSET_RADIUS = 3.25
local Y_ABOVE_ROOT = 0.2
local DOT_DIAMETER = 0.38

local MIN_INPUT_MAGNITUDE = 0.04
local SMOOTH_RATE = 14

local renderConnection = nil
local dotPart = nil
local smoothedOffsetXZ = Vector3.zero

local function destroyDot()
	if dotPart then
		dotPart:Destroy()
		dotPart = nil
	end
end

local function ensureDot(character)
	if dotPart and dotPart.Parent == character then
		return dotPart
	end
	destroyDot()
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
		destroyDot()
		smoothedOffsetXZ = Vector3.zero
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
	local show = smoothedOffsetXZ.Magnitude > 0.08
	part.Transparency = show and 0.12 or 1
	local pos = root.Position + Vector3.new(smoothedOffsetXZ.X, Y_ABOVE_ROOT, smoothedOffsetXZ.Z)
	part.CFrame = CFrame.new(pos)
end

return {
	Init = function()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		destroyDot()
		smoothedOffsetXZ = Vector3.zero

		LocalPlayer.CharacterRemoving:Connect(function()
			destroyDot()
			smoothedOffsetXZ = Vector3.zero
		end)

		renderConnection = RunService.RenderStepped:Connect(onRenderStep)
	end,
}
