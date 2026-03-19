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
local ContentProvider = game:GetService("ContentProvider")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)

local FireGunRE = nil
local AmmoStateRE = nil
local ThrowGrenadeRE = nil
local ThrowRocketRE = nil
local shootingEnabled = false
local currentWeapon = "Pistol"
local inputConnection = nil
local renderSteppedConnection = nil

-- [gunId] = { ammo = number, isReloading = boolean, reloadStartedAt = number? }
local ammoState = {}
local lastFiredAt = 0
local grenadeCount = 0
local rocketCount = 0
local availableWeapons = { "Pistol", "Rifle", "Shotgun", "Grenade" }
local weaponInventorySubscribers = {}
local ammoStateSubscribers = {}
local matchEndedSubscribers = {}
local weaponChangedSubscribers = {}

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

local function canFireByRate()
	local gun = GunsConfig[currentWeapon] or GunsConfig.Pistol
	local fireRate = gun.fireRate or 0.4
	return (os.clock() - lastFiredAt) >= fireRate
end

local function playGunshotSound(gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
	local soundId = gun.gunshotSoundId
	if not soundId then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local parent = rootPart or Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMaxDistance = 200
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function playReloadSound(gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
	local soundId = gun.reloadSoundId
	if not soundId then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local parent = rootPart or Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMaxDistance = 200
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function playGrenadeThrowSound()
	local soundId = GrenadeConfig.throwSoundId
	if not soundId then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local parent = rootPart or Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMaxDistance = 200
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function preloadCombatSounds()
	local ids = {}
	for _, gun in pairs(GunsConfig) do
		if gun.gunshotSoundId then
			table.insert(ids, gun.gunshotSoundId)
		end
		if gun.reloadSoundId then
			table.insert(ids, gun.reloadSoundId)
		end
	end
	if GrenadeConfig.throwSoundId then
		table.insert(ids, GrenadeConfig.throwSoundId)
	end
	if GrenadeConfig.explosionSoundId then
		table.insert(ids, GrenadeConfig.explosionSoundId)
	end
	local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
	if RocketLauncherConfig.throwSoundId then
		table.insert(ids, RocketLauncherConfig.throwSoundId)
	end
	if RocketLauncherConfig.explosionSoundId then
		table.insert(ids, RocketLauncherConfig.explosionSoundId)
	end
	if #ids > 0 then
		ContentProvider:PreloadAsync(ids)
	end
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
	if not canFireByRate() then
		return
	end
	lastFiredAt = os.clock()
	playGunshotSound(currentWeapon)
	FireGunRE:FireServer(dir, currentWeapon)
end

local function playRocketThrowSound()
	local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
	local soundId = RocketLauncherConfig.throwSoundId
	if not soundId then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local parent = rootPart or Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMaxDistance = 200
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function throwRocket(dir)
	if not shootingEnabled or not ThrowRocketRE or not dir then
		return
	end
	if currentWeapon ~= "RocketLauncher" then
		return
	end
	if rocketCount <= 0 then
		return
	end
	playRocketThrowSound()
	ThrowRocketRE:FireServer(dir)
end

-- Fire when aiming joystick is off-axis (mobile). No fire when Grenade selected.
local function throwGrenade(dir)
	if not shootingEnabled or not ThrowGrenadeRE or not dir then
		return
	end
	if currentWeapon ~= "Grenade" then
		return
	end
	if grenadeCount <= 0 then
		return
	end
	playGrenadeThrowSound()
	ThrowGrenadeRE:FireServer(dir)
end

local function onRenderStepped()
	if not shootingEnabled or not FireGunRE then
		return
	end
	if currentWeapon == "Grenade" or currentWeapon == "RocketLauncher" then
		return
	end
	local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
	local dir = RotationJoystickGUI.GetWorldDirectionXZ()
	if dir then
		fireInDirection(dir)
	end
end

-- Fire on click (desktop fallback), grenade on G key when Grenade selected
local function onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if currentWeapon ~= "Grenade" and currentWeapon ~= "RocketLauncher" then
			local dir = getAimDirectionFromMouse()
			if dir then
				fireInDirection(dir)
			end
		end
		return
	end
	-- Grenade/Rocket: G key (desktop only; mobile uses joystick release)
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.G then
		local dir = getAimDirectionFromMouse()
		if dir then
			if currentWeapon == "Grenade" then
				throwGrenade(dir)
			elseif currentWeapon == "RocketLauncher" then
				throwRocket(dir)
			end
		end
	end
end

local function setShootingEnabled(enabled)
	shootingEnabled = enabled
	lastFiredAt = 0
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	if renderSteppedConnection then
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end
	if enabled then
		preloadCombatSounds()
		renderSteppedConnection = RunService.RenderStepped:Connect(onRenderStepped)
		if not UserInputService.TouchEnabled then
			inputConnection = UserInputService.InputBegan:Connect(onInputBegan)
		end
	end
end

local function equipCurrentWeapon()
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = player.Backpack and player.Backpack:FindFirstChild(currentWeapon)
	if humanoid and tool then
		humanoid:EquipTool(tool)
		return true
	end
	return false
end

return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		FireGunRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN)
		AmmoStateRE = folder:WaitForChild(CombatConfig.REMOTES.AMMO_STATE)
		ThrowGrenadeRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_GRENADE)
		ThrowRocketRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_ROCKET)
		local matchEndedRE = folder:WaitForChild(CombatConfig.REMOTES.MATCH_ENDED)
		local grenadeStateRE = folder:WaitForChild(CombatConfig.REMOTES.GRENADE_STATE)
		local rocketStateRE = folder:WaitForChild(CombatConfig.REMOTES.ROCKET_STATE)
		local weaponInventoryRE = folder:WaitForChild(CombatConfig.REMOTES.WEAPON_INVENTORY)

		-- Equip weapon when character spawns (e.g. arena entry, respawn)
		local player = Players.LocalPlayer
		player.CharacterAdded:Connect(function()
			if shootingEnabled then
				task.defer(function()
					if not equipCurrentWeapon() then
						task.delay(0.2, function()
							equipCurrentWeapon()
						end)
					end
				end)
			end
		end)
		matchEndedRE.OnClientEvent:Connect(function(payload)
			setShootingEnabled(false)
			for _, cb in ipairs(matchEndedSubscribers) do
				task.defer(cb, payload)
			end
		end)
		-- Mobile: grenade/rocket thrown when right joystick released (last direction before lift)
		if UserInputService.TouchEnabled then
			local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
			RotationJoystickGUI.SubscribeOnRelease(function(worldDir)
				if currentWeapon == "Grenade" then
					throwGrenade(worldDir)
				elseif currentWeapon == "RocketLauncher" then
					throwRocket(worldDir)
				end
			end)
		end
		AmmoStateRE.OnClientEvent:Connect(function(gunId, ammoCount, isReloading)
			ammoState[gunId] = ammoState[gunId] or {}
			ammoState[gunId].ammo = ammoCount
			ammoState[gunId].isReloading = isReloading
			if isReloading then
				ammoState[gunId].reloadStartedAt = os.clock()
				playReloadSound(gunId)
			else
				ammoState[gunId].reloadStartedAt = nil
			end
			notifyAmmoSubscribers()
		end)
		grenadeStateRE.OnClientEvent:Connect(function(count)
			grenadeCount = count
			notifyAmmoSubscribers()
		end)
		rocketStateRE.OnClientEvent:Connect(function(count)
			rocketCount = count
			notifyAmmoSubscribers()
		end)
		weaponInventoryRE.OnClientEvent:Connect(function(weapons)
			availableWeapons = weapons or { "Pistol", "Rifle", "Shotgun", "Grenade" }
			local stillHas = false
			for _, w in ipairs(availableWeapons) do
				if w == currentWeapon then
					stillHas = true
					break
				end
			end
			if not stillHas and #availableWeapons > 0 then
				currentWeapon = availableWeapons[1]
				for _, w in ipairs(availableWeapons) do
					if w == "Rifle" then
						currentWeapon = "Rifle"
						break
					end
				end
				equipCurrentWeapon()
				for _, cb in ipairs(weaponChangedSubscribers) do
					task.defer(cb)
				end
			end
			for _, cb in ipairs(weaponInventorySubscribers) do
				task.defer(cb)
			end
		end)
	end,

	SubscribeAmmoState = function(callback)
		table.insert(ammoStateSubscribers, callback)
	end,

	SubscribeMatchEnded = function(callback)
		table.insert(matchEndedSubscribers, callback)
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

	SetShootingEnabled = setShootingEnabled,

	FireNow = fireInDirection,
	ThrowGrenade = throwGrenade,

	SetCurrentWeapon = function(gunId)
		currentWeapon = gunId or "Pistol"
		if not equipCurrentWeapon() then
			task.defer(function()
				if not equipCurrentWeapon() then
					task.delay(0.2, equipCurrentWeapon)
				end
			end)
		end
		for _, cb in ipairs(weaponChangedSubscribers) do
			task.defer(cb)
		end
	end,

	SubscribeWeaponChanged = function(callback)
		table.insert(weaponChangedSubscribers, callback)
	end,

	GetCurrentWeapon = function()
		return currentWeapon
	end,

	GetGrenadeState = function()
		local maxCap = GrenadeConfig.maxCapacity or 3
		return {
			count = grenadeCount,
			max = maxCap,
		}
	end,

	GetRocketState = function()
		local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
		local maxCap = RocketLauncherConfig.maxRockets or 3
		return {
			count = rocketCount,
			max = maxCap,
		}
	end,

	GetAvailableWeapons = function()
		return availableWeapons
	end,

	SubscribeWeaponInventory = function(callback)
		table.insert(weaponInventorySubscribers, callback)
	end,

	ThrowRocket = throwRocket,
}
