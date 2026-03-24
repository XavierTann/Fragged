--[[
	CombatServiceClient
	Firing input and FireGun remote. Only active when in arena (enabled by startup).
	Grenade: immediate throw sound + local clone with same root setup as CombatGrenades (physics); server grenade hidden for thrower.
	Predicted feedback (muzzle flash, recoil, sound, local-only tracers) runs immediately, then FireGun
	sends shotOrigin, aim direction, and gunId. The server is authoritative: validates origin/direction
	bounds, inventory, equipped tool, ammo, cooldown, and reload; on reject it may fire FireGunRejected
	(resetClientFireRate) and AmmoState to resync.
	Mobile: Pistol/Rifle fire while aim joystick is off-axis; Shotgun matches Grenade/Rocket
	(fire on joystick release with last aim direction).
	Desktop: Pistol/Rifle on LMB; Shotgun matches Grenade/Rocket (G key + mouse aim, no LMB).
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
local GrenadeAngularResistance = require(ReplicatedStorage.Shared.Modules.GrenadeAngularResistance)

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
	local gun = GunsConfig[gunId or "Pistol"] or GunsConfig.Pistol
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

-- Matches server muzzle offset (HumanoidRootPart + aim * 2).
local function getShotOriginForDirection(character, dir)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not dir or dir.Magnitude < 0.01 then
		return nil
	end
	return root.Position + dir.Unit * 2
end

local PREDICTED_TRACER_TRAIL = 4
local PREDICTED_TRACER_MAX_TIME = 0.35

local RECOIL_PITCH_DEG = {
	Pistol = 0.65,
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

local GRENADES_FOLDER_NAME = "CombatGrenades"

local function hideOwnServerGrenadeReplica(inst)
	if inst:GetAttribute("ThrowerUserId") ~= Players.LocalPlayer.UserId then
		return
	end
	local function touchVisual(d)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Fire") then
			d.Enabled = false
		end
	end
	touchVisual(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		touchVisual(d)
	end
end

local function wireHideOwnReplicatedGrenades()
	local function bind(folder)
		for _, c in ipairs(folder:GetChildren()) do
			hideOwnServerGrenadeReplica(c)
		end
		folder.ChildAdded:Connect(hideOwnServerGrenadeReplica)
	end
	local folder = Workspace:FindFirstChild(GRENADES_FOLDER_NAME)
	if folder then
		bind(folder)
	else
		Workspace.ChildAdded:Connect(function(child)
			if child.Name == GRENADES_FOLDER_NAME then
				bind(child)
			end
		end)
	end
end

local GRENADE_VISUAL_TEMPLATE_NAME = "GrenadeVisual"
local COLLISION_GROUP_GRENADES = "Grenades"

local function getGrenadeVisualTemplate()
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	return models3D and models3D:FindFirstChild(GRENADE_VISUAL_TEMPLATE_NAME)
end

-- Same root resolution as CombatGrenades.getGrenadeRootPart.
local function getGrenadeRootPart(instance)
	if instance:IsA("Tool") then
		return instance:FindFirstChild("Handle") or instance:FindFirstChildWhichIsA("BasePart")
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	elseif instance:IsA("BasePart") then
		return instance
	end
	return nil
end

-- Matches CombatGrenades.spawnGrenade velocity (throwDir * throwSpeed).
local function getGrenadeThrowVelocity(aimDirection)
	local cfg = GrenadeConfig
	local d = aimDirection.Unit
	local throwDir = (Vector3.new(d.X, 0, d.Z) * (1 - cfg.throwArcUp) + Vector3.new(0, cfg.throwArcUp, 0)).Unit
	return throwDir * cfg.throwSpeed
end

-- Same root configuration as CombatGrenades.spawnGrenade (template path).
local function configurePredictedGrenadeRootLikeServer(rootPart, startPos, velocity, cfg)
	rootPart.CFrame = CFrame.new(startPos)
	rootPart.AssemblyLinearVelocity = velocity
	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.CollisionGroup = COLLISION_GROUP_GRENADES
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, cfg.restitution, 1, 1)
end

-- Local physics clone: identical setup to server grenade; destroyed at fuseTime (no local explosion).
local function spawnPredictedGrenade(startPos, aimDirection)
	local cfg = GrenadeConfig
	local velocity = getGrenadeThrowVelocity(aimDirection)
	local template = getGrenadeVisualTemplate()
	local grenade
	local rootPart

	if template then
		grenade = template:Clone()
		grenade.Name = "PredictedGrenade"
		rootPart = getGrenadeRootPart(grenade)
		if rootPart then
			if grenade:IsA("Model") and not grenade.PrimaryPart then
				grenade.PrimaryPart = rootPart
			end
			grenade.Parent = getPredictedShotsFolder()
			configurePredictedGrenadeRootLikeServer(rootPart, startPos, velocity, cfg)
			GrenadeAngularResistance.attach(rootPart, cfg)
		else
			grenade:Destroy()
			grenade = nil
		end
	end

	if not grenade or not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "PredictedGrenade"
		rootPart.Size = cfg.size
		rootPart.Color = cfg.color
		rootPart.Material = cfg.material
		rootPart.Shape = Enum.PartType.Ball
		rootPart.Anchored = false
		rootPart.CanCollide = true
		rootPart.CFrame = CFrame.new(startPos)
		rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, cfg.restitution, 1, 1)
		rootPart.AssemblyLinearVelocity = velocity
		rootPart.CollisionGroup = COLLISION_GROUP_GRENADES
		rootPart.Parent = getPredictedShotsFolder()
		grenade = rootPart
		GrenadeAngularResistance.attach(rootPart, cfg)
	end

	local fuseTime = cfg.fuseTime
	task.delay(fuseTime, function()
		if grenade and grenade.Parent then
			grenade:Destroy()
		end
	end)
end

-- Cosmetic only; does not deal damage. Stops at geometry (local raycast).
local function spawnPredictedTracer(startPos, direction, gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
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
	playGunshotSound(gunId)

	local gun = GunsConfig[gunId] or GunsConfig.Pistol
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
	FireGunRE:FireServer(shotOrigin, dir, currentWeapon)
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
	playRocketThrowSound()
	ThrowRocketRE:FireServer(dir)
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
	local startPos = getShotOriginForDirection(character, dir)
	if not startPos then
		return
	end
	playGrenadeThrowSound()
	spawnPredictedGrenade(startPos, dir)
	ThrowGrenadeRE:FireServer(dir)
end

local function onRenderStepped()
	if not shootingEnabled or not FireGunRE then
		return
	end
	if currentWeapon == "Grenade" or currentWeapon == "RocketLauncher" or currentWeapon == "Shotgun" then
		return
	end
	local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
	local dir = RotationJoystickGUI.GetWorldDirectionXZ()
	if dir then
		fireInDirection(dir)
	end
end

-- Fire on click (desktop) for hold-fire guns; Grenade/Rocket/Shotgun use G (desktop) or joystick release (mobile)
local function onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if currentWeapon ~= "Grenade" and currentWeapon ~= "RocketLauncher" and currentWeapon ~= "Shotgun" then
			local dir = getAimDirectionFromMouse()
			if dir then
				fireInDirection(dir)
			end
		end
		return
	end
	-- Grenade/Rocket/Shotgun: G key (desktop only; mobile uses joystick release)
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.G then
		local dir = getAimDirectionFromMouse()
		if dir then
			if currentWeapon == "Grenade" then
				throwGrenade(dir)
			elseif currentWeapon == "RocketLauncher" then
				throwRocket(dir)
			elseif currentWeapon == "Shotgun" then
				fireInDirection(dir)
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
		wireHideOwnReplicatedBullets()
		wireHideOwnReplicatedGrenades()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		FireGunRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN)
		local fireGunRejectedRE = folder:WaitForChild(CombatConfig.REMOTES.FIRE_GUN_REJECTED)
		AmmoStateRE = folder:WaitForChild(CombatConfig.REMOTES.AMMO_STATE)
		ThrowGrenadeRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_GRENADE)
		ThrowRocketRE = folder:WaitForChild(CombatConfig.REMOTES.THROW_ROCKET)
		local matchEndedRE = folder:WaitForChild(CombatConfig.REMOTES.MATCH_ENDED)
		local grenadeStateRE = folder:WaitForChild(CombatConfig.REMOTES.GRENADE_STATE)
		local rocketStateRE = folder:WaitForChild(CombatConfig.REMOTES.ROCKET_STATE)
		local weaponInventoryRE = folder:WaitForChild(CombatConfig.REMOTES.WEAPON_INVENTORY)
		local teamAssignmentRE = folder:WaitForChild(CombatConfig.REMOTES.TEAM_ASSIGNMENT)

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
			print("[TeamAssignment] myTeam:", myTeam)
			for userId, team in pairs(fixedTeams) do
				print("[TeamAssignment]  userId:", userId, "-> team:", team)
			end
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
		-- Mobile: grenade/rocket/shotgun fire when right joystick released (last direction before lift)
		if UserInputService.TouchEnabled then
			local RotationJoystickGUI = require(ReplicatedStorage.Shared.UI.RotationJoystickGUI)
			RotationJoystickGUI.SubscribeOnRelease(function(worldDir)
				if currentWeapon == "Grenade" then
					throwGrenade(worldDir)
				elseif currentWeapon == "RocketLauncher" then
					throwRocket(worldDir)
				elseif currentWeapon == "Shotgun" then
					fireInDirection(worldDir)
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

	SubscribeTeamAssignment = function(callback)
		table.insert(teamAssignmentSubscribers, callback)
	end,

	GetTeamAssignment = function()
		return currentTeamAssignment
	end,

	-- World-space unit direction on XZ from mouse vs character; optional minGroundSeparation (studs on XZ)
	GetAimDirectionXZ = getAimDirectionFromMouse,
}
