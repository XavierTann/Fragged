--[[
	TopDownCameraService (client)
	Locks the camera to a top-down view above the local player's character.
	Call Init() from the client startup script.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Config: height above character (studs), optional angle (0 = straight down)
local HEIGHT_ABOVE = 20
local ANGLE_FROM_VERTICAL = 0 -- 0 = straight down; increase for slight tilt

local camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local connection = nil

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

return {
	Init = function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		camera.CameraType = Enum.CameraType.Scriptable
		connection = RunService.RenderStepped:Connect(updateCamera)
		-- Initial position when character exists
		local function onCharacterAdded()
			task.defer(updateCamera)
		end
		if localPlayer.Character then
			onCharacterAdded()
		end
		localPlayer.CharacterAdded:Connect(onCharacterAdded)
	end,

	-- Optional: set height at runtime (studs above character)
	SetHeight = function(height)
		HEIGHT_ABOVE = math.max(10, height)
	end,
}
