--[[
	CombatServiceClient
	Firing input and FireGun remote. Only active when in arena (enabled by startup).
	Mobile: fire when aiming joystick is pulled off-axis (direction = player facing).
	Desktop: fire on mouse click (mouse aim).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local FireGunRE = nil
local shootingEnabled = false
local inputConnection = nil
local renderSteppedConnection = nil

local function getAimDirectionFromMouse()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local mouse = player:GetMouse()
	local origin = camera.CFrame.Position
	local direction = camera:ScreenPointToRay(mouse.X, mouse.Y).Direction
	local rootY = root.Position.Y
	local dy = direction.Y
	if math.abs(dy) < 0.001 then
		return Vector3.new(direction.X, 0, direction.Z).Unit
	end
	local t = (rootY - origin.Y) / dy
	if t < 0 then
		t = 0
	end
	local hitPoint = origin + direction * t
	local aim = (hitPoint - root.Position)
	if aim.Magnitude < 0.01 then
		return nil
	end
	return aim.Unit
end

local function fireInDirection(dir)
	if not shootingEnabled or not FireGunRE or not dir then
		return
	end
	FireGunRE:FireServer(dir, "Pistol")
end

-- Fire when aiming joystick is off-axis (mobile)
local function onRenderStepped()
	if not shootingEnabled or not FireGunRE then
		return
	end
	local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
	local dir = RotationJoystickGUI.GetWorldDirectionXZ()
	if dir then
		fireInDirection(dir)
	end
end

-- Fire on click (desktop fallback)
local function onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local dir = getAimDirectionFromMouse()
	if dir then
		fireInDirection(dir)
	end
end

return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		FireGunRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN)
	end,

	SetShootingEnabled = function(enabled)
		shootingEnabled = enabled
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if renderSteppedConnection then
			renderSteppedConnection:Disconnect()
			renderSteppedConnection = nil
		end
		if enabled then
			-- Mobile: fire continuously when joystick is pulled off-axis
			renderSteppedConnection = RunService.RenderStepped:Connect(onRenderStepped)
			-- Desktop: fire on mouse click (joystick not available)
			if not UserInputService.TouchEnabled then
				inputConnection = UserInputService.InputBegan:Connect(onInputBegan)
			end
		end
	end,

	FireNow = fireInDirection,
}
