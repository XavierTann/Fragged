--[[
	Move-direction dot from Humanoid.MoveDirection (WASD, move stick, gamepad left).
]]

local Config = require(script.Parent.Config)

local dotPart = nil
local smoothedOffsetXZ = Vector3.zero

local function flattenMoveXZ(moveDirection)
	local v = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if v.Magnitude < Config.MIN_INPUT_MAGNITUDE then
		return Vector3.zero
	end
	return v.Unit * Config.OFFSET_RADIUS
end

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
	if dotPart then
		dotPart:Destroy()
		dotPart = nil
	end
	local p = Instance.new("Part")
	p.Name = "DirectionIndicator_MoveDot"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * Config.DOT_DIAMETER
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

return {
	update = function(dt, character, humanoid, root)
		local targetOffset = flattenMoveXZ(humanoid.MoveDirection)
		local alpha = 1 - math.exp(-Config.SMOOTH_RATE * dt)
		smoothedOffsetXZ = smoothedOffsetXZ:Lerp(targetOffset, alpha)

		local part = ensureDot(character)
		local showMove = smoothedOffsetXZ.Magnitude > 0.08
		part.Transparency = showMove and 0.12 or 1
		local pos = root.Position
			+ Vector3.new(smoothedOffsetXZ.X, Config.Y_ABOVE_ROOT, smoothedOffsetXZ.Z)
		part.CFrame = CFrame.new(pos)
	end,

	destroy = function()
		destroyDot()
		smoothedOffsetXZ = Vector3.zero
	end,

	resetSmoothed = function()
		smoothedOffsetXZ = Vector3.zero
	end,
}
