--[[
	MovementDirectionIndicatorClient
	Blue: movement from Humanoid.MoveDirection (WASD, move thumbstick, gamepad left).
	Weapon aim (off-axis only):
	- Rifle: red Beam toward aim (short range preview).
	- RocketLauncher: white flat rectangle, width ≈ rocket cross-section, length = max range.
	- Grenade: white Beams — polyline for first flight, one straight segment for rebound direction.
	Other weapons: no aim overlay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local RotationJoystickGUI = require(Shared.UI.RotationJoystickGUI)
local RocketLauncherConfig = require(Shared.Modules.RocketLauncherConfig)
local GrenadeTrajectoryUtils = require(Shared.Modules.GrenadeTrajectoryUtils)

local LocalPlayer = Players.LocalPlayer

-- Studs from HumanoidRootPart position on XZ; Y is raised slightly for visibility
local OFFSET_RADIUS = 3.25
-- Rifle beam length (studs from root toward aim on XZ)
local AIM_LINE_LENGTH = 8.5
local Y_ABOVE_ROOT = 0.2
local AIM_Y_ABOVE_ROOT = 0.34
local DOT_DIAMETER = 0.38
-- Beam width (studs); FaceCamera helps readability in top-down view
local AIM_BEAM_WIDTH = 0.28
-- Rocket preview: vertical thickness of the white slab (world Y)
local ROCKET_RECT_THICKNESS = 0.14
-- Grenade: pre-bounce samples + one rebound endpoint (+ small buffer for attachments)
local GRENADE_MAX_VERTS = GrenadeTrajectoryUtils.DEFAULT_MAX_PRE_BOUNCE_POINTS + 2
local GRENADE_BEAM_WIDTH = 0.065

local MIN_INPUT_MAGNITUDE = 0.04
-- Hide aim when the cursor’s ground aim is near the character (still on-axis)
local AIM_MIN_CURSOR_GROUND_DIST = 1.15
local SMOOTH_RATE = 14
local AIM_SMOOTH_RATE = 16

local renderConnection = nil
local dotPart = nil
local aimBeamHost = nil
local aimRocketRect = nil
local grenadeAimHost = nil
local grenadeChainAttachments = {}
local grenadeChainBeams = {}
local smoothedOffsetXZ = Vector3.zero
local smoothedAimOffsetXZ = Vector3.zero

local function getRocketAimRange()
	local c = RocketLauncherConfig
	return c.aimMaxRangeStuds or (c.speed * c.fuseTime)
end

local function getRocketAimWidth()
	local c = RocketLauncherConfig
	if c.aimIndicatorWidthStuds then
		return c.aimIndicatorWidthStuds
	end
	return math.max(c.size.X, c.size.Y) * (c.scale or 1)
end

local function destroyGrenadeAimChain()
	if grenadeAimHost then
		grenadeAimHost:Destroy()
		grenadeAimHost = nil
	end
	grenadeChainAttachments = {}
	grenadeChainBeams = {}
end

local function destroyAimVisuals()
	if aimBeamHost then
		aimBeamHost:Destroy()
		aimBeamHost = nil
	end
	if aimRocketRect then
		aimRocketRect:Destroy()
		aimRocketRect = nil
	end
	destroyGrenadeAimChain()
end

local function destroyDots()
	if dotPart then
		dotPart:Destroy()
		dotPart = nil
	end
	destroyAimVisuals()
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

local function ensureAimBeamHost(character)
	if aimBeamHost and aimBeamHost.Parent == character then
		return aimBeamHost
	end
	if aimBeamHost then
		aimBeamHost:Destroy()
		aimBeamHost = nil
	end
	local p = Instance.new("Part")
	p.Name = "AimDirectionBeamHost"
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

	aimBeamHost = p
	return p
end

local function ensureAimRocketRect(character)
	if aimRocketRect and aimRocketRect.Parent == character then
		return aimRocketRect
	end
	if aimRocketRect then
		aimRocketRect:Destroy()
		aimRocketRect = nil
	end
	local p = Instance.new("Part")
	p.Name = "AimRocketPathIndicator"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.new(1, 1, 1)
	p.Transparency = 1
	p.Parent = character
	aimRocketRect = p
	return p
end

local function ensureGrenadeAimChain(character)
	if grenadeAimHost and grenadeAimHost.Parent == character then
		return
	end
	destroyGrenadeAimChain()
	local p = Instance.new("Part")
	p.Name = "GrenadeAimChainHost"
	p.Size = Vector3.one * 0.05
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = character

	for i = 1, GRENADE_MAX_VERTS do
		local a = Instance.new("Attachment")
		a.Name = "GrenadeAimAtt_" .. i
		a.Parent = p
		grenadeChainAttachments[i] = a
	end
	for seg = 1, GRENADE_MAX_VERTS - 1 do
		local b = Instance.new("Beam")
		b.Name = "GrenadeAimBeam_" .. seg
		b.Attachment0 = grenadeChainAttachments[seg]
		b.Attachment1 = grenadeChainAttachments[seg + 1]
		b.Width0 = GRENADE_BEAM_WIDTH
		b.Width1 = GRENADE_BEAM_WIDTH
		b.Color = ColorSequence.new(Color3.new(1, 1, 1))
		b.Transparency = NumberSequence.new(0.12)
		b.LightEmission = 0.2
		b.FaceCamera = true
		b.Segments = 1
		b.Enabled = false
		b.Parent = p
		grenadeChainBeams[seg] = b
	end
	grenadeAimHost = p
end

local function hideGrenadeAimChain()
	for _, b in ipairs(grenadeChainBeams) do
		if b then
			b.Enabled = false
		end
	end
end

local function applyGrenadeTrajectoryPoints(points, enabled)
	if #grenadeChainBeams == 0 or #grenadeChainAttachments == 0 then
		return
	end
	local n = #points
	if not enabled or n < 2 or not grenadeAimHost then
		hideGrenadeAimChain()
		return
	end
	local origin = points[1]
	grenadeAimHost.CFrame = CFrame.new(origin)
	for i = 1, GRENADE_MAX_VERTS do
		local worldPt = (i <= n and points[i] or points[n])
		grenadeChainAttachments[i].Position = worldPt - origin
	end
	local maxSeg = math.min(n - 1, #grenadeChainBeams)
	for i = 1, #grenadeChainBeams do
		grenadeChainBeams[i].Enabled = i <= maxSeg
	end
end

local function aimOffsetTargetXZ(weapon)
	if weapon ~= "Rifle" and weapon ~= "RocketLauncher" and weapon ~= "Grenade" then
		return Vector3.zero
	end
	local spanLength = weapon == "RocketLauncher" and getRocketAimRange() or AIM_LINE_LENGTH

	if UserInputService.TouchEnabled then
		local joyDir = RotationJoystickGUI.GetWorldDirectionXZ()
		if joyDir then
			return joyDir * spanLength
		end
		return Vector3.zero
	end

	local dir = CombatServiceClient.GetAimDirectionXZ(AIM_MIN_CURSOR_GROUND_DIST)
	if dir then
		return dir * spanLength
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

	local weapon = CombatServiceClient.GetCurrentWeapon()
	local targetAim = aimOffsetTargetXZ(weapon)
	local aimAlpha = 1 - math.exp(-AIM_SMOOTH_RATE * dt)
	smoothedAimOffsetXZ = smoothedAimOffsetXZ:Lerp(targetAim, aimAlpha)

	local showAim = smoothedAimOffsetXZ.Magnitude > 0.08
	local yLift = Vector3.new(0, AIM_Y_ABOVE_ROOT, 0)
	local startPos = root.Position + yLift

	if weapon == "Rifle" then
		destroyGrenadeAimChain()
		local beamHost = ensureAimBeamHost(character)
		local beam = beamHost:FindFirstChild("AimDirectionBeam")
		local att0 = beamHost:FindFirstChild("AimLineStart")
		local att1 = beamHost:FindFirstChild("AimLineEnd")
		if aimRocketRect then
			aimRocketRect.Transparency = 1
		end
		if beam then
			beam.Enabled = showAim
		end
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
			beamHost.CFrame = CFrame.fromMatrix(mid, right, dir)
			att0.Position = Vector3.new(0, -length * 0.5, 0)
			att1.Position = Vector3.new(0, length * 0.5, 0)
		elseif att0 and att1 then
			beamHost.CFrame = CFrame.new(startPos)
			att0.Position = Vector3.zero
			att1.Position = Vector3.zero
		end
	elseif weapon == "RocketLauncher" then
		destroyGrenadeAimChain()
		local rect = ensureAimRocketRect(character)
		local beam = aimBeamHost and aimBeamHost:FindFirstChild("AimDirectionBeam")
		if beam then
			beam.Enabled = false
		end
		local range = getRocketAimRange()
		local width = getRocketAimWidth()
		if showAim and smoothedAimOffsetXZ.Magnitude > 0.12 then
			local flat = Vector3.new(smoothedAimOffsetXZ.X, 0, smoothedAimOffsetXZ.Z)
			local dir = flat.Unit
			local right = Vector3.new(-dir.Z, 0, dir.X)
			if right.Magnitude < 0.001 then
				right = Vector3.new(1, 0, 0)
			else
				right = right.Unit
			end
			local mid = startPos + dir * (range * 0.5)
			rect.Size = Vector3.new(width, ROCKET_RECT_THICKNESS, range)
			rect.CFrame = CFrame.fromMatrix(mid, right, Vector3.yAxis)
			rect.Transparency = 0.42
		else
			rect.Transparency = 1
		end
	elseif weapon == "Grenade" then
		local beam = aimBeamHost and aimBeamHost:FindFirstChild("AimDirectionBeam")
		if beam then
			beam.Enabled = false
		end
		if aimRocketRect then
			aimRocketRect.Transparency = 1
		end
		ensureGrenadeAimChain(character)
		if showAim and smoothedAimOffsetXZ.Magnitude > 0.12 then
			local flat = Vector3.new(smoothedAimOffsetXZ.X, 0, smoothedAimOffsetXZ.Z)
			local simplified = GrenadeTrajectoryUtils.computeSimplifiedGrenadePath(character, flat.Unit)
			local pts = GrenadeTrajectoryUtils.mergeGrenadePreviewPoints(
				simplified,
				GrenadeTrajectoryUtils.DEFAULT_MAX_PRE_BOUNCE_POINTS
			)
			applyGrenadeTrajectoryPoints(pts, true)
		else
			applyGrenadeTrajectoryPoints({}, false)
		end
	else
		if aimBeamHost then
			local b = aimBeamHost:FindFirstChild("AimDirectionBeam")
			if b then
				b.Enabled = false
			end
		end
		if aimRocketRect then
			aimRocketRect.Transparency = 1
		end
		destroyGrenadeAimChain()
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
