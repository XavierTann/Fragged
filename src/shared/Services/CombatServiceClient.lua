--[[
	CombatServiceClient
	Firing input and FireGun remote. Only active when in arena (enabled by startup).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local FireGunRE = nil
local shootingEnabled = false
local inputConnection = nil

local function getAimDirection()
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
	-- Intersect ray with horizontal plane at character height (top-down aim in XZ)
	local dy = direction.Y
	if math.abs(dy) < 0.001 then
		-- Ray nearly horizontal; use direction in XZ only
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

local function tryFire()
	if not shootingEnabled or not FireGunRE then
		return
	end
	local dir = getAimDirection()
	if not dir then
		return
	end
	FireGunRE:FireServer(dir, "Pistol")
end

	return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		FireGunRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN)
	end,

	-- Call when entering arena; disables when leaving
	SetShootingEnabled = function(enabled)
		shootingEnabled = enabled
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if enabled then
			inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
				if gameProcessed then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					tryFire()
				end
			end)
		end
	end,

	-- Optional: hold to fire (continuous) - not used by default; click fires once per press
	FireNow = tryFire,
}
