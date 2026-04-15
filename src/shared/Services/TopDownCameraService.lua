--[[
	TopDownCameraService (client)
	Locks the camera to a top-down view above the local player's character.
	Call Init() from the client startup script.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Config: height above character (studs), optional angle (0 = straight down)
local HEIGHT_ABOVE = 28
local ANGLE_FROM_VERTICAL = 0 -- 0 = straight down; increase for slight tilt

-- Snap for leaving top-down: typical over-shoulder distance behind horizontal facing.
local DEFAULT_CAMERA_DISTANCE = 12
local DEFAULT_CAMERA_LOOK_Y = 1.5 -- look target above root (chest)
local DEFAULT_CAMERA_RAISE = 2.5 -- camera height above root

local camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local connection = nil
local characterAddedConnection = nil
local topDownEnabled = false
-- When true, camera stays Scriptable at the last frame but does not follow the character (post-match leaderboard).
local followFrozen = false

local function updateCamera()
	local character = localPlayer.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local pos = root.Position
	-- Camera above the character, looking down (with optional tilt)
	local angleRad = math.rad(ANGLE_FROM_VERTICAL)
	local offset = Vector3.new(0, HEIGHT_ABOVE, 0)
	local camPos = pos + Vector3.new(offset.X, offset.Y * math.cos(angleRad), offset.Z)
	local lookAt = pos - Vector3.new(0, HEIGHT_ABOVE * math.sin(angleRad), 0)
	camera.CFrame = CFrame.lookAt(camPos, lookAt)
end

local function horizontalForwardFromRoot(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Puts the camera behind the character (Roblox third-person style), then hands control to the default Custom camera.
local function applyDefaultCamera()
	local character = localPlayer.Character
	if not character then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = nil
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
	if humanoid and root and root:IsA("BasePart") then
		local forward = horizontalForwardFromRoot(root)
		local focus = root.Position + Vector3.new(0, DEFAULT_CAMERA_LOOK_Y, 0)
		local camPos = focus - forward * DEFAULT_CAMERA_DISTANCE + Vector3.new(0, DEFAULT_CAMERA_RAISE, 0)
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(camPos, focus)
	end
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function onCharacterAdded()
	if topDownEnabled and not followFrozen then
		task.defer(updateCamera)
	end
end

return {
	-- Wires CharacterAdded only; lobby uses default camera until SetEnabled(true) (arena / active round).
	Init = function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		topDownEnabled = false
		followFrozen = false
		if characterAddedConnection then
			characterAddedConnection:Disconnect()
			characterAddedConnection = nil
		end
		characterAddedConnection = localPlayer.CharacterAdded:Connect(onCharacterAdded)
	end,

	SetEnabled = function(enabled)
		enabled = enabled == true
		if enabled == topDownEnabled then
			if enabled and not followFrozen then
				task.defer(updateCamera)
			end
			return
		end
		topDownEnabled = enabled
		if enabled then
			camera.CameraType = Enum.CameraType.Scriptable
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if not followFrozen then
				connection = RunService.RenderStepped:Connect(updateCamera)
				if localPlayer.Character then
					task.defer(updateCamera)
				end
			end
		else
			followFrozen = false
			if connection then
				connection:Disconnect()
				connection = nil
			end
			applyDefaultCamera()
		end
	end,

	-- Freeze or resume top-down follow while remaining in Scriptable mode (arena + post-match overlay).
	SetFollowFrozen = function(frozen)
		frozen = frozen == true
		if frozen == followFrozen then
			return
		end
		followFrozen = frozen
		if not topDownEnabled then
			return
		end
		if followFrozen then
			if connection then
				connection:Disconnect()
				connection = nil
			end
		else
			camera.CameraType = Enum.CameraType.Scriptable
			updateCamera()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			connection = RunService.RenderStepped:Connect(updateCamera)
		end
	end,

	-- One Roblox-tick reset to Custom camera, then resume scriptable top-down if enabled (waiting room -> arena).
	ArenaEntranceCameraReset = function()
		if not topDownEnabled then
			return
		end
		if connection then
			connection:Disconnect()
			connection = nil
		end
		applyDefaultCamera()
		task.defer(function()
			if not topDownEnabled or followFrozen then
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			updateCamera()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			connection = RunService.RenderStepped:Connect(updateCamera)
		end)
	end,

	-- Optional: set height at runtime (studs above character)
	SetHeight = function(height)
		HEIGHT_ABOVE = math.max(10, height)
	end,
}
