--[[
	CombatServiceClient
	Firing input and FireGun remote. Only active when in arena (enabled by startup).
	Mobile: fire when aiming joystick is pulled off-axis (direction = player facing).
	Desktop: fire on mouse click (mouse aim).
	Respects ammo and reload state from server to prevent spamming.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)

local FireGunRE = nil
local AmmoStateRE = nil
local shootingEnabled = false
local currentWeapon = "Pistol"
local inputConnection = nil
local renderSteppedConnection = nil

-- [gunId] = { ammo = number, isReloading = boolean, reloadStartedAt = number? }
local ammoState = {}
local ammoStateSubscribers = {}

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

local function getAmmoStateForWeapon(gunId)
	local s = ammoState[gunId]
	if s then
		return s.ammo, s.isReloading, s.reloadStartedAt
	end
	local gun = GunsConfig[gunId or "Pistol"] or GunsConfig.Pistol
	return gun.magazineSize or 6, false, nil
end

local function canFire()
	local ammo, isReloading = getAmmoStateForWeapon(currentWeapon)
	return ammo > 0 and not isReloading
end

local function notifyAmmoSubscribers()
	for _, cb in ipairs(ammoStateSubscribers) do
		task.defer(cb)
	end
end

local function fireInDirection(dir)
	if not shootingEnabled or not FireGunRE or not dir then
		return
	end
	if not canFire() then
		return
	end
	FireGunRE:FireServer(dir, currentWeapon)
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
		AmmoStateRE = folder:WaitForChild(CombatConfig.REMOTES.AMMO_STATE)
		AmmoStateRE.OnClientEvent:Connect(function(gunId, ammoCount, isReloading)
			ammoState[gunId] = ammoState[gunId] or {}
			ammoState[gunId].ammo = ammoCount
			ammoState[gunId].isReloading = isReloading
			if isReloading then
				ammoState[gunId].reloadStartedAt = os.clock()
			else
				ammoState[gunId].reloadStartedAt = nil
			end
			notifyAmmoSubscribers()
		end)
	end,

	SubscribeAmmoState = function(callback)
		table.insert(ammoStateSubscribers, callback)
	end,

	GetAmmoState = function(gunId)
		gunId = gunId or currentWeapon
		local ammo, isReloading, reloadStartedAt = getAmmoStateForWeapon(gunId)
		local gun = GunsConfig[gunId] or GunsConfig.Pistol
		return {
			ammo = ammo,
			maxAmmo = gun.magazineSize or 6,
			isReloading = isReloading,
			reloadStartedAt = reloadStartedAt,
			reloadTime = gun.reloadTime or 1.5,
		}
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

	SetCurrentWeapon = function(gunId)
		currentWeapon = gunId or "Pistol"
	end,

	GetCurrentWeapon = function()
		return currentWeapon
	end,
}
