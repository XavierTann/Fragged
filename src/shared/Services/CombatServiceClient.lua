--[[
	CombatServiceClient
	Firing input and FireGun remote. Only active when in arena (enabled by startup).
	Grenade: throw sound + FireServer; in-flight mesh is server-replicated (CombatGrenades) so it matches physics.
	GrenadeExplosionFX plays burst at server position for all clients (including thrower).
	Predicted feedback (muzzle flash, recoil, sound, local-only tracers) runs immediately, then FireGun
	sends shotOrigin, aim direction, and gunId. The server is authoritative: validates origin/direction
	bounds, inventory, equipped tool, ammo, cooldown, and reload; on reject it may fire FireGunRejected
	(resetClientFireRate) and AmmoState to resync.
	Gunshots: local predicted sound + GunshotSpatial to other round players; all use 3D Sound on HRP or tool Handle.
	Mobile: Primary weapons fire while aim joystick is off-axis; Secondary weapons match Grenade/Rocket
	(fire on joystick release with last aim direction). Releasing inside the cancel zone
	skips the shot for those weapons only.
	Desktop: Primary weapons on LMB; Secondary weapons match Grenade/Rocket (G key + mouse aim, no LMB).
	Respects ammo and reload state from server to prevent spamming.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local LoadoutConfig = require(ReplicatedStorage.Shared.Modules.LoadoutConfig)
local LagCompConfig = require(ReplicatedStorage.Shared.Modules.LagCompensationConfig)

local FireGunRE = nil
local RequestReloadRE = nil
local AmmoStateRE = nil
local ThrowGrenadeRE = nil
local ThrowRocketRE = nil
local GetLiveLeaderboardRF = nil
local shootingEnabled = false
local serverTimeOffset = 0
local currentWeapon = "Rifle"
local inputConnection = nil
local renderSteppedConnection = nil

-- [gunId] = { ammo = number, isReloading = boolean, reloadStartedAt = number? }
local ammoState = {}
local lastFiredAt = 0
local grenadeCount = 0
local rocketCount = 0
local availableWeapons = { "Rifle", "Shotgun", "Grenade", "RocketLauncher" }
local weaponInventorySubscribers = {}
local ammoStateSubscribers = {}
local matchEndedSubscribers = {}
local weaponChangedSubscribers = {}
local teamAssignmentSubscribers = {}
local currentTeamAssignment = nil

-- minGroundSeparation: XZ distance from root to mouse hit on ground plane; below = nil (forgiving for firing)
local function getAimDirectionFromMouse(minGroundSeparation)
	minGroundSeparation = minGroundSeparation or 0.01
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
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < minGroundSeparation then
		return nil
	end
	return flat.Unit
end

local function getAmmoStateForWeapon(gunId)
	local s = ammoState[gunId]
	if s then
		return s.ammo, s.isReloading, s.reloadStartedAt
	end
	local gun = GunsConfig[gunId or "Rifle"] or GunsConfig.Rifle
	return gun.magazineSize or 6, false, nil
end

local function isLocalPlayerAlive()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function canFire()
	if not isLocalPlayerAlive() then
		return false
	end
	local ammo, isReloading = getAmmoStateForWeapon(currentWeapon)
	return ammo > 0 and not isReloading
end

local function canFireByRate()
	local gun = GunsConfig[currentWeapon] or GunsConfig.Rifle
	local fireRate = gun.fireRate or 0.12
	return (os.clock() - lastFiredAt) >= fireRate
end

-- 3D world audio: parent must be a BasePart on the character (replicated for other players’ shots).
local GUNSHOT_ROLLOFF_MIN = 6
local GUNSHOT_ROLLOFF_MAX = 150
local GUNSHOT_EMITTER_SIZE = 3

local function getGunshotAttachPart(character, gunId)
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if gunId then
		local tool = character:FindFirstChild(gunId)
		local handle = tool and tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle
		end
	end
	return root
end

local function playSpatialGunshotOnPart(parentPart, gunId)
	if not parentPart or not parentPart:IsA("BasePart") then
		return
	end
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local soundId = gun.gunshotSoundId
	if not soundId then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Gunshot3D"
	sound.SoundId = soundId
	sound.Volume = 0.92
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = GUNSHOT_ROLLOFF_MIN
	sound.RollOffMaxDistance = GUNSHOT_ROLLOFF_MAX
	sound.EmitterSize = GUNSHOT_EMITTER_SIZE
	sound.TimePosition = 0
	sound.Parent = parentPart
	-- Playing before the instance is loaded queues start and feels like lag vs muzzle/tracer
	if not sound.IsLoaded then
		pcall(function()
			sound.Loaded:Wait()
		end)
	end
	sound:Play()
	local maxDur = gun.gunshotMaxDurationSeconds
	if typeof(maxDur) == "number" and maxDur > 0 then
		task.delay(maxDur, function()
			if not sound.Parent then
				return
			end
			sound:Stop()
			sound:Destroy()
		end)
	else
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
end

local function playGunshotSound(gunId)
	local character = Players.LocalPlayer.Character
	local part = getGunshotAttachPart(character, gunId)
	if part then
		playSpatialGunshotOnPart(part, gunId)
	end
end

local function playReloadSound(gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
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

-- Matches server: HumanoidRootPart + aim * forwardStuds (guns use SHOT_ORIGIN_FORWARD_STUDS; grenades override).
local function getShotOriginForDirection(character, dir, forwardStudsOverride)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not dir or dir.Magnitude < 0.01 then
		return nil
	end
	local forward = forwardStudsOverride
	if forward == nil then
		forward = CombatConfig.SHOT_ORIGIN_FORWARD_STUDS or 0
	end
	return root.Position + dir.Unit * forward
end

local PREDICTED_TRACER_TRAIL = 4
local PREDICTED_TRACER_MAX_TIME = 0.35

local RECOIL_PITCH_DEG = {
	Rifle = 0.38,
	Shotgun = 1.8,
}

local function applyLocalRecoil(gunId)
	local pitch = RECOIL_PITCH_DEG[gunId] or 0.5
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(-pitch), 0, 0)
	end
end

local function playMuzzleFlash(origin, dir)
	if not origin or not dir or dir.Magnitude < 0.01 then
		return
	end
	local look = dir.Unit
	local flash = Instance.new("Part")
	flash.Name = "PredictedMuzzleFlash"
	flash.Size = Vector3.new(0.15, 0.15, 0.15)
	flash.Transparency = 1
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.CFrame = CFrame.lookAt(origin, origin + look)
	flash.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Range = 10
	light.Color = Color3.fromRGB(255, 230, 180)
	light.Parent = flash
	Debris:AddItem(flash, 0.07)
end

local function getPredictedShotsFolder()
	local folder = Workspace:FindFirstChild("LocalPredictedShots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LocalPredictedShots"
		folder.Parent = Workspace
	end
	return folder
end

local BULLETS_FOLDER_NAME = "CombatBullets"

-- Server-replicated bullets duplicate predicted VFX for the shooter; hide ours locally only.
local function hideOwnServerBulletReplica(inst)
	if not inst:IsA("BasePart") or inst.Name ~= "Bullet" then
		return
	end
	if inst:GetAttribute("ShooterUserId") ~= Players.LocalPlayer.UserId then
		return
	end
	inst.LocalTransparencyModifier = 1
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Beam") then
			d.Enabled = false
		end
	end
end

local function wireHideOwnReplicatedBullets()
	local function bind(folder)
		for _, c in ipairs(folder:GetChildren()) do
			hideOwnServerBulletReplica(c)
		end
		folder.ChildAdded:Connect(hideOwnServerBulletReplica)
	end
	local folder = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if folder then
		bind(folder)
	else
		Workspace.ChildAdded:Connect(function(child)
			if child.Name == BULLETS_FOLDER_NAME then
				bind(child)
			end
		end)
	end
end

local function playLocalGrenadeExplosionVFX(worldPosition, radius, explosionSoundId)
	local explosionPart = Instance.new("Part")
	explosionPart.Name = "LocalGrenadeExplosionFX"
	explosionPart.Shape = Enum.PartType.Ball
	explosionPart.Size = Vector3.new(1, 1, 1)
	explosionPart.Anchored = true
	explosionPart.CanCollide = false
	explosionPart.CanQuery = false
	explosionPart.Material = Enum.Material.Neon
	explosionPart.Color = Color3.fromRGB(255, 120, 40)
	explosionPart.CFrame = CFrame.new(worldPosition)
	explosionPart.Transparency = 0.3
	explosionPart.Parent = Workspace
	local startSize = 1
	local endSize = radius * 2
	local duration = 0.2
	local elapsed = 0
	if typeof(explosionSoundId) == "string" and explosionSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = explosionSoundId
		sound.Volume = 1
		sound.RollOffMode = Enum.RollOffMode.Inverse
		sound.RollOffMaxDistance = 300
		sound.RollOffMinDistance = 10
		sound.Parent = explosionPart
		sound:Play()
	end
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed >= duration then
			conn:Disconnect()
			explosionPart:Destroy()
			return
		end
		local t = elapsed / duration
		local s = startSize + (endSize - startSize) * t
		explosionPart.Size = Vector3.new(s, s, s)
		explosionPart.Transparency = 0.3 + 0.6 * t
	end)
end

-- Cosmetic only; does not deal damage. Stops at geometry (local raycast).
local function spawnPredictedTracer(startPos, direction, gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local dir = direction.Unit
	local bullet = Instance.new("Part")
	bullet.Name = "PredictedTracer"
	bullet.Size = gun.bulletSize
	bullet.Color = gun.bulletColor
	bullet.Material = Enum.Material.Neon
	bullet.Transparency = 0.35
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CastShadow = false
	bullet.CFrame = CFrame.lookAt(startPos, startPos + dir)
	bullet.Parent = getPredictedShotsFolder()

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, -PREDICTED_TRACER_TRAIL)
	att0.Parent = bullet
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, gun.bulletSize.Z / 2)
	att1.Parent = bullet
	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(gun.bulletColor)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = gun.bulletSize.X * 1.5
	beam.Width1 = gun.bulletSize.X * 0.5
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = bullet

	local speed = gun.bulletSpeed
	local lastPos = startPos
	local params = RaycastParams.new()
	local filter = { bullet, getPredictedShotsFolder() }
	local character = Players.LocalPlayer.Character
	if character then
		filter[#filter + 1] = character
	end
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude

	local conn
	local t0 = os.clock()
	conn = RunService.RenderStepped:Connect(function(dt)
		if not bullet.Parent then
			conn:Disconnect()
			return
		end
		if os.clock() - t0 > PREDICTED_TRACER_MAX_TIME then
			conn:Disconnect()
			bullet:Destroy()
			return
		end
		local move = dir * speed * dt
		local newPos = lastPos + move
		local result = Workspace:Raycast(lastPos, move, params)
		if result then
			conn:Disconnect()
			bullet:Destroy()
			return
		end
		lastPos = newPos
		bullet.CFrame = CFrame.lookAt(newPos, newPos + dir)
	end)
end

local function playPredictedGunfire(gunId, shotOrigin, aimDir)
	playMuzzleFlash(shotOrigin, aimDir)
	applyLocalRecoil(gunId)

	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local pelletCount = gun.pelletCount or 1
	local spreadDeg = gun.spreadDegrees or 0
	for _ = 1, pelletCount do
		local d = aimDir.Unit
		if spreadDeg > 0 and pelletCount > 1 then
			local angle = math.rad(spreadDeg * (math.random() * 2 - 1))
			local perp = Vector3.new(-d.Z, 0, d.X)
			if perp.Magnitude < 0.001 then
				perp = Vector3.new(1, 0, 0)
			else
				perp = perp.Unit
			end
			d = (d * math.cos(angle) + perp * math.sin(angle)).Unit
			local angle2 = math.rad(spreadDeg * 0.5 * (math.random() * 2 - 1))
			d = (d * math.cos(angle2) + Vector3.new(0, 1, 0) * math.sin(angle2)).Unit
		end
		spawnPredictedTracer(shotOrigin, d, gunId)
	end

	-- After tracers so Sound.Loaded:Wait() in playGunshotSound never blocks bullet feedback
	playGunshotSound(gunId)
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
	local character = Players.LocalPlayer.Character
	local shotOrigin = getShotOriginForDirection(character, dir)
	if not shotOrigin then
		return
	end
	lastFiredAt = os.clock()
	playPredictedGunfire(currentWeapon, shotOrigin, dir)
	local estimatedServerTime = os.clock() + serverTimeOffset
	FireGunRE:FireServer(shotOrigin, dir, currentWeapon, estimatedServerTime)
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
	if not isLocalPlayerAlive() then
		return
	end
	if currentWeapon ~= "RocketLauncher" then
		return
	end
	if rocketCount <= 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local shotOrigin = getShotOriginForDirection(character, dir)
	if not shotOrigin then
		return
	end
	playRocketThrowSound()
	local estimatedServerTime = os.clock() + serverTimeOffset
	ThrowRocketRE:FireServer(shotOrigin, dir, estimatedServerTime)
end

-- Fire when aiming joystick is off-axis (mobile). No continuous fire for release-style weapons.
local function throwGrenade(dir)
	if not shootingEnabled or not ThrowGrenadeRE or not dir then
		return
	end
	if not isLocalPlayerAlive() then
		return
	end
	if currentWeapon ~= "Grenade" then
		return
	end
	if grenadeCount <= 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local startPos = getShotOriginForDirection(character, dir, CombatConfig.GRENADE_SHOT_ORIGIN_FORWARD_STUDS or 0)
	if not startPos then
		return
	end
	playGrenadeThrowSound()
	ThrowGrenadeRE:FireServer(dir)
end

local function isReleaseToFireWeapon(weaponId)
	return weaponId == "Grenade" or weaponId == "RocketLauncher"
		or LoadoutConfig:isSecondaryWeapon(weaponId)
end

local function onRenderStepped()
	if not shootingEnabled or not FireGunRE then
		return
	end
	if isReleaseToFireWeapon(currentWeapon) then
		return
	end
	local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
	local dir = RotationJoystickGUI.GetWorldDirectionXZ()
	if dir then
		fireInDirection(dir)
	end
end

-- Fire on click (desktop) for hold-fire guns; release-to-fire weapons use G (desktop) or joystick release (mobile)
local function onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not isReleaseToFireWeapon(currentWeapon) then
			local dir = getAimDirectionFromMouse()
			if dir then
				fireInDirection(dir)
			end
		end
		return
	end
	-- Release-to-fire weapons: G key (desktop only; mobile uses joystick release)
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.G then
		if isReleaseToFireWeapon(currentWeapon) then
			local dir = getAimDirectionFromMouse()
			if dir then
				if currentWeapon == "Grenade" then
					throwGrenade(dir)
				elseif currentWeapon == "RocketLauncher" then
					throwRocket(dir)
				else
					fireInDirection(dir)
				end
			end
		end
	end
end

local function requestReload()
	if not shootingEnabled or not RequestReloadRE then
		return
	end
	if not GunsConfig[currentWeapon] then
		return
	end
	RequestReloadRE:FireServer(currentWeapon)
end

local function syncRotationJoystickCancelZone()
	if not UserInputService.TouchEnabled then
		return
	end
	local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
	if RotationJoystickGUI.SetCancelFireZoneActive then
		RotationJoystickGUI.SetCancelFireZoneActive(shootingEnabled and isReleaseToFireWeapon(currentWeapon))
	end
end

local function unequipCombatTools()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
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
	else
		unequipCombatTools()
	end
	syncRotationJoystickCancelZone()
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
		wireHideOwnReplicatedBullets()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		FireGunRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN)
		RequestReloadRE = folder:WaitForChild(CombatConfig.REMOTES.REQUEST_RELOAD)
		local fireGunRejectedRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN_REJECTED)
		AmmoStateRE = folder:WaitForChild(CombatConfig.REMOTES.AMMO_STATE)
		ThrowGrenadeRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_GRENADE)
		ThrowRocketRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_ROCKET)
		local matchEndedRE = folder:WaitForChild(CombatConfig.REMOTES.MATCH_ENDED)
		local grenadeStateRE = folder:WaitForChild(CombatConfig.REMOTES.GRENADE_STATE)
		local rocketStateRE = folder:WaitForChild(CombatConfig.REMOTES.ROCKET_STATE)
		local weaponInventoryRE = folder:WaitForChild(CombatConfig.REMOTES.WEAPON_INVENTORY)
		local teamAssignmentRE = folder:WaitForChild(CombatConfig.REMOTES.TEAM_ASSIGNMENT)
		GetLiveLeaderboardRF = folder:WaitForChild(CombatConfig.REMOTES.GET_LIVE_LEADERBOARD)
		local gunshotSpatialRE = folder:WaitForChild(CombatConfig.REMOTES.GUNSHOT_SPATIAL)
		local grenadeExplosionFXRE = folder:WaitForChild(CombatConfig.REMOTES.GRENADE_EXPLOSION_FX)

		local timeSyncRF = folder:FindFirstChild(LagCompConfig.TIME_SYNC_REMOTE_NAME)
		if timeSyncRF and timeSyncRF:IsA("RemoteFunction") then
			task.spawn(function()
				local bestOffset = 0
				local bestRtt = math.huge
				for _ = 1, 5 do
					local t0 = os.clock()
					local ok, serverTime = pcall(function()
						return timeSyncRF:InvokeServer()
					end)
					if ok and typeof(serverTime) == "number" then
						local rtt = os.clock() - t0
						if rtt < bestRtt then
							bestRtt = rtt
							bestOffset = serverTime - (t0 + rtt / 2)
						end
					end
					task.wait(0.3)
				end
				serverTimeOffset = bestOffset
			end)
		end

		grenadeExplosionFXRE.OnClientEvent:Connect(function(serverCenter, radius, explosionSoundId, _throwerUserId)
			if typeof(serverCenter) ~= "Vector3" or typeof(radius) ~= "number" then
				return
			end
			playLocalGrenadeExplosionVFX(serverCenter, radius, explosionSoundId)
		end)

		gunshotSpatialRE.OnClientEvent:Connect(function(shooterUserId, gunId)
			if typeof(shooterUserId) ~= "number" or typeof(gunId) ~= "string" then
				return
			end
			if shooterUserId == Players.LocalPlayer.UserId then
				return
			end
			local shooter = Players:GetPlayerByUserId(shooterUserId)
			local character = shooter and shooter.Character
			if not character then
				return
			end
			local part = getGunshotAttachPart(character, gunId)
			if part then
				playSpatialGunshotOnPart(part, gunId)
			end
		end)

		fireGunRejectedRE.OnClientEvent:Connect(function(_reason, _gunId, resetClientFireRate)
			if resetClientFireRate then
				lastFiredAt = 0
			end
		end)

		teamAssignmentRE.OnClientEvent:Connect(function(myTeam, playerTeamsTable)
			-- RemoteEvent serializes non-sequential integer keys as strings;
			-- convert them back to numbers so UserId lookups work correctly.
			local fixedTeams = {}
			for id, team in pairs(playerTeamsTable or {}) do
				fixedTeams[tonumber(id)] = team
			end
			currentTeamAssignment = { myTeam = myTeam, playerTeams = fixedTeams }

			for _, cb in ipairs(teamAssignmentSubscribers) do
				task.defer(cb, currentTeamAssignment)
			end
		end)

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
		-- Mobile: release-to-fire weapons fire when right joystick released (last direction before lift)
		if UserInputService.TouchEnabled then
			local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
			RotationJoystickGUI.SubscribeOnRelease(function(worldDir, releaseInsideCancelZone)
				if releaseInsideCancelZone then
					return
				end
				if not isReleaseToFireWeapon(currentWeapon) then
					return
				end
				if currentWeapon == "Grenade" then
					throwGrenade(worldDir)
				elseif currentWeapon == "RocketLauncher" then
					throwRocket(worldDir)
				else
					fireInDirection(worldDir)
				end
			end)
			task.defer(syncRotationJoystickCancelZone)
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
			availableWeapons = weapons or { "Rifle", "Shotgun", "Grenade", "RocketLauncher" }
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
				if shootingEnabled then
					equipCurrentWeapon()
				end
				for _, cb in ipairs(weaponChangedSubscribers) do
					task.defer(cb)
				end
			end
			syncRotationJoystickCancelZone()
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
		local gun = GunsConfig[gunId] or GunsConfig.Rifle
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
	RequestReload = requestReload,

	SetCurrentWeapon = function(gunId)
		currentWeapon = gunId or "Rifle"
		if not equipCurrentWeapon() then
			task.defer(function()
				if not equipCurrentWeapon() then
					task.delay(0.2, equipCurrentWeapon)
				end
			end)
		end
		syncRotationJoystickCancelZone()
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

	SubscribeTeamAssignment = function(callback)
		table.insert(teamAssignmentSubscribers, callback)
	end,

	GetTeamAssignment = function()
		return currentTeamAssignment
	end,

	-- Active TDM round only; nil if match ended or not in round
	RequestLiveLeaderboard = function()
		if not GetLiveLeaderboardRF then
			return nil
		end
		local ok, result = pcall(function()
			return GetLiveLeaderboardRF:InvokeServer()
		end)
		if ok then
			return result
		end
		return nil
	end,

	-- World-space unit direction on XZ from mouse vs character; optional minGroundSeparation (studs on XZ)
	GetAimDirectionXZ = getAimDirectionFromMouse,
}
