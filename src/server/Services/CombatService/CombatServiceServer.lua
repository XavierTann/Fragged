--[[
	CombatService (server)
	Shooting (visible bullets), health, round end. Server-authoritative.
	FireGun: validate round membership, weapon inventory, equipped Tool, ammo/cooldown/reload,
	client shot origin vs HRP+aim*2, then spawn bullets at authoritative muzzle (HRP + aim * 2).
	Init() sets up remotes and handlers. StartRound(players, onRoundEnd) is called when arena round starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local TDMSpawnStrategy = require(script.Parent.TDMSpawnStrategy)

local CombatState = require(script.Parent.CombatState)
local CombatRemotes = require(script.Parent.CombatRemotes)
local CombatAmmo = require(script.Parent.CombatAmmo)
local CombatBullets = require(script.Parent.CombatBullets)
local CombatGrenades = require(script.Parent.CombatGrenades)
local CombatRockets = require(script.Parent.CombatRockets)
local CombatTDM = require(script.Parent.CombatTDM)
local WeaponInventoryServer = require(script.Parent.WeaponInventoryServer)

local COLLISION_GROUP_WALLS = "CombatWalls"
local COLLISION_GROUP_GRENADES = "Grenades"

-- Client-reported muzzle must be near server-expected point (root + aim * 2).
local FIRE_ORIGIN_MAX_ERROR_STUDS = 6
local FIRE_ORIGIN_MAX_DISTANCE_FROM_ROOT_STUDS = 14
-- Aim must be a valid horizontal-ish world direction (matches client XZ aim, blocks degenerate axes).
local FIRE_AIM_MIN_HORIZONTAL = 0.08
local FIRE_AIM_MAX_VERTICAL_ABS = 0.95

local state = CombatState()

local function playerInActiveRound(player)
	for _, p in ipairs(state.currentRoundPlayers) do
		if p == player then
			return true
		end
	end
	return false
end

local function sendAuthoritativeAmmoForGun(player, gunId)
	local uid = player.UserId
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
	state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
	state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
	local ammo = state.ammoInMagazine[uid][gunId]
	if ammo == nil then
		ammo = gun.magazineSize or 6
		state.ammoInMagazine[uid][gunId] = ammo
	end
	local isReloading = state.reloadEndAt[uid][gunId] ~= nil and os.clock() < state.reloadEndAt[uid][gunId]
	CombatRemotes.sendAmmoState(state, player, gunId, ammo, isReloading)
end

local function isFiniteVector3(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
end

local function parseFireGunArgs(a, b, c)
	-- FireServer(shotOrigin, aimDirection, gunId) — required for validation and prediction sync.
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" and typeof(c) == "string" then
		return a, b, c
	end
	return nil, nil, nil
end

local function validateClientShotOrigin(rootPos, shotOrigin, aimUnit)
	if not shotOrigin or not isFiniteVector3(shotOrigin) then
		return false
	end
	if (shotOrigin - rootPos).Magnitude > FIRE_ORIGIN_MAX_DISTANCE_FROM_ROOT_STUDS then
		return false
	end
	local expected = rootPos + aimUnit * 2
	return (shotOrigin - expected).Magnitude <= FIRE_ORIGIN_MAX_ERROR_STUDS
end

-- Returns unit direction or nil if out of bounds / non-finite.
local function validateFireAimDirection(aimDirection)
	if typeof(aimDirection) ~= "Vector3" or not isFiniteVector3(aimDirection) or aimDirection.Magnitude < 0.01 then
		return nil
	end
	local u = aimDirection.Unit
	if not isFiniteVector3(u) or u.Magnitude < 0.99 then
		return nil
	end
	if Vector3.new(u.X, 0, u.Z).Magnitude < FIRE_AIM_MIN_HORIZONTAL then
		return nil
	end
	if math.abs(u.Y) > FIRE_AIM_MAX_VERTICAL_ABS then
		return nil
	end
	return u
end

local function rejectFire(player, reason, gunId, resetClientFireRate, sendAmmo)
	CombatRemotes.sendFireGunRejected(state, player, reason, gunId, resetClientFireRate == true)
	if sendAmmo ~= false and gunId and GunsConfig[gunId] then
		sendAuthoritativeAmmoForGun(player, gunId)
	end
end

local function playerOwnsGun(player, gunId)
	for _, w in ipairs(WeaponInventoryServer.getWeapons(player)) do
		if w == gunId then
			return true
		end
	end
	return false
end

local function characterHasGunEquipped(character, gunId)
	local tool = character:FindFirstChild(gunId)
	return tool and tool:IsA("Tool")
end

local function giveRocketLauncherTool(player)
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local template = models3D and models3D:FindFirstChild("RocketLauncherTool")
	if template and template:IsA("Tool") and player:FindFirstChild("Backpack") then
		local tool = template:Clone()
		tool.Name = "RocketLauncher"
		tool.Parent = player.Backpack
	end
end

local function setupWallCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_WALLS)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_GRENADES)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_WALLS, COLLISION_GROUP_GRENADES, false)
end

local function assignToWallGroup(instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = COLLISION_GROUP_WALLS
	elseif instance:IsA("Model") then
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = COLLISION_GROUP_WALLS
			end
		end
	end
end

local function setupBulletBlockerWalls()
	for _, instance in ipairs(CollectionService:GetTagged(CombatConfig.BULLET_BLOCKER_TAG)) do
		assignToWallGroup(instance)
	end
	CollectionService:GetInstanceAddedSignal(CombatConfig.BULLET_BLOCKER_TAG):Connect(assignToWallGroup)
end

local function bindHandlers()
	state.fireGunRE.OnServerEvent:Connect(function(player, a, b, c)
		if state.matchEnded then
			return
		end
		if not playerInActiveRound(player) then
			return
		end

		local shotOrigin, aimDirection, gunId = parseFireGunArgs(a, b, c)
		if not shotOrigin or not aimDirection or not gunId then
			CombatRemotes.sendFireGunRejected(state, player, "InvalidArgs", nil, true)
			return
		end

		if not GunsConfig[gunId] then
			CombatRemotes.sendFireGunRejected(state, player, "InvalidWeapon", nil, true)
			return
		end

		local aimUnit = validateFireAimDirection(aimDirection)
		if not aimUnit then
			rejectFire(player, "BadDirection", gunId, true)
			return
		end

		if not playerOwnsGun(player, gunId) then
			rejectFire(player, "WeaponNotOwned", gunId, true)
			return
		end

		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			rejectFire(player, "NoCharacter", gunId, true)
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			rejectFire(player, "Dead", gunId, true)
			return
		end
		if not characterHasGunEquipped(character, gunId) then
			rejectFire(player, "NotEquipped", gunId, true)
			return
		end

		local root = character.HumanoidRootPart
		if not validateClientShotOrigin(root.Position, shotOrigin, aimUnit) then
			rejectFire(player, "BadOrigin", gunId, true)
			return
		end

		local gun = GunsConfig[gunId]
		local now = os.clock()
		local uid = player.UserId

		local last = state.lastFiredAt[uid] or 0
		if now - last < gun.fireRate then
			rejectFire(player, "Cooldown", gunId, false)
			return
		end

		state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
		state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
		local ammo = state.ammoInMagazine[uid][gunId]
		if ammo == nil then
			state.ammoInMagazine[uid][gunId] = gun.magazineSize or 6
			ammo = state.ammoInMagazine[uid][gunId]
		end

		if state.reloadEndAt[uid][gunId] and now < state.reloadEndAt[uid][gunId] then
			rejectFire(player, "Reloading", gunId, false)
			return
		end

		if ammo <= 0 then
			if not state.reloadEndAt[uid][gunId] then
				state.reloadEndAt[uid][gunId] = now + (gun.reloadTime or 1.5)
			end
			rejectFire(player, "EmptyMag", gunId, false)
			return
		end

		state.lastFiredAt[uid] = now
		state.ammoInMagazine[uid][gunId] = ammo - 1
		local newAmmo = state.ammoInMagazine[uid][gunId]

		local startPos = root.Position + aimUnit * 2
		local pelletCount = gun.pelletCount or 1
		local spreadDeg = gun.spreadDegrees or 0
		for _ = 1, pelletCount do
			local dir = aimUnit
			if spreadDeg > 0 and pelletCount > 1 then
				local angle = math.rad(spreadDeg * (math.random() * 2 - 1))
				local perp = Vector3.new(-dir.Z, 0, dir.X)
				dir = (dir * math.cos(angle) + perp * math.sin(angle)).Unit
				local angle2 = math.rad(spreadDeg * 0.5 * (math.random() * 2 - 1))
				dir = (dir * math.cos(angle2) + Vector3.new(0, 1, 0) * math.sin(angle2)).Unit
			end
			CombatBullets.spawnBullet(state, player, startPos, dir, gunId)
		end

		if newAmmo <= 0 then
			state.reloadEndAt[uid][gunId] = now + (gun.reloadTime or 1.5)
			CombatRemotes.sendAmmoState(state, player, gunId, 0, true)
		else
			CombatRemotes.sendAmmoState(state, player, gunId, newAmmo, false)
		end
	end)

	state.requestReloadRE.OnServerEvent:Connect(function(player, gunId)
		if state.matchEnded then
			return
		end
		if not playerInActiveRound(player) then
			return
		end
		if typeof(gunId) ~= "string" then
			return
		end
		local gun = GunsConfig[gunId]
		if not gun then
			return
		end
		if not playerOwnsGun(player, gunId) then
			return
		end
		local character = player.Character
		if not character or not characterHasGunEquipped(character, gunId) then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local uid = player.UserId
		local now = os.clock()
		state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
		state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
		local ammo = state.ammoInMagazine[uid][gunId]
		if ammo == nil then
			ammo = gun.magazineSize or 6
			state.ammoInMagazine[uid][gunId] = ammo
		end
		local maxMag = gun.magazineSize or 6
		if ammo >= maxMag then
			return
		end
		if state.reloadEndAt[uid][gunId] and now < state.reloadEndAt[uid][gunId] then
			return
		end
		state.reloadEndAt[uid][gunId] = now + (gun.reloadTime or 1.5)
		CombatRemotes.sendAmmoState(state, player, gunId, ammo, true)
	end)

	state.throwGrenadeRE.OnServerEvent:Connect(function(player, aimDirection)
		if state.matchEnded then
			return
		end
		if not playerInActiveRound(player) then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude < 0.01 then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root then
			return
		end
		local uid = player.UserId
		local count = state.grenadeCount[uid] or 0
		if count <= 0 then
			return
		end
		state.grenadeCount[uid] = count - 1
		local regenTimes = state.grenadeRegenTimes[uid]
		if not regenTimes then
			regenTimes = {}
			state.grenadeRegenTimes[uid] = regenTimes
		end
		table.insert(regenTimes, os.clock() + (GrenadeConfig.regenerationTime or 5))
		table.sort(regenTimes)
		CombatRemotes.sendGrenadeState(state, player, state.grenadeCount[uid])
		local startPos = root.Position + aimDirection.Unit * 2
		CombatGrenades.spawnGrenade(state, player, startPos, aimDirection)
	end)

	state.throwRocketRE.OnServerEvent:Connect(function(player, aimDirection)
		if state.matchEnded then
			return
		end
		if not playerInActiveRound(player) then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude < 0.01 then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root then
			return
		end
		local uid = player.UserId
		local count = state.rocketCount[uid] or 0
		if count <= 0 then
			return
		end
		state.rocketCount[uid] = count - 1
		local newCount = state.rocketCount[uid]
		CombatRemotes.sendRocketState(state, player, newCount)
		if newCount <= 0 then
			WeaponInventoryServer.removeWeapon(player, "RocketLauncher")
			local rl = player.Backpack and player.Backpack:FindFirstChild("RocketLauncher")
			if rl then
				rl:Destroy()
			end
			if player.Character then
				rl = player.Character:FindFirstChild("RocketLauncher")
				if rl then
					rl:Destroy()
				end
			end
		end
		local startPos = root.Position + aimDirection.Unit * 2
		CombatRockets.spawnRocket(state, player, startPos, aimDirection)
	end)

	state.getLiveLeaderboardRF.OnServerInvoke = function(player)
		if state.matchEnded or not playerInActiveRound(player) then
			return nil
		end
		local bluePlayers, redPlayers = CombatTDM.buildLeaderboardData(state)
		return {
			bluePlayers = bluePlayers,
			redPlayers = redPlayers,
			isLiveLeaderboard = true,
		}
	end
end

return {
	Init = function()
		state = CombatState()
		setupWallCollisionGroups()
		setupBulletBlockerWalls()
		CombatRemotes.ensureRemotes(state)
		bindHandlers()
		CombatAmmo.startReloadLoop(state)
	end,

	StartRound = function(players, onRoundEnd)
		state.onRoundEndCallback = onRoundEnd
		state.matchEnded = false
		state.currentRoundPlayers = {}
		state.playerTeams = {}
		state.teamKills = { Blue = 0, Red = 0 }
		state.playerKills = {}
		state.playerDeaths = {}
		state.playerAssists = {}
		for i, p in ipairs(players) do
			state.currentRoundPlayers[#state.currentRoundPlayers + 1] = p
			state.playerTeams[p.UserId] = (i % 2 == 1) and "Blue" or "Red"
			state.playerKills[p.UserId] = 0
			state.playerDeaths[p.UserId] = 0
			state.playerAssists[p.UserId] = 0
			CombatAmmo.initPlayerAmmo(state, p.UserId)
			CombatAmmo.initPlayerGrenades(state, p.UserId)
			local weapons = WeaponInventoryServer.getWeapons(p)
			for _, w in ipairs(weapons) do
				if w == "RocketLauncher" then
					CombatAmmo.initPlayerRockets(state, p.UserId)
					giveRocketLauncherTool(p)
					break
				end
			end
			WeaponInventoryServer.sendToPlayer(p)
			local cf = TDMSpawnStrategy.getSpawnCFrame(p, CombatTDM.getTDMContext(state))
			local character = p.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				character.HumanoidRootPart.CFrame = cf
			end
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
					humanoid.Health = CombatConfig.DEFAULT_HEALTH
					state.diedConnections[p.UserId] = humanoid.Died:Connect(function()
						CombatTDM.onPlayerDied(state, p)
					end)
				end
			end
			local conn = p.CharacterAdded:Connect(function()
				local inv = WeaponInventoryServer.getWeapons(p)
				for _, w in ipairs(inv) do
					if w == "RocketLauncher" then
						task.defer(function()
							giveRocketLauncherTool(p)
						end)
						break
					end
				end
			end)
			state.characterAddedConnections[p.UserId] = conn
			for gunId, ammo in pairs(state.ammoInMagazine[p.UserId] or {}) do
				CombatRemotes.sendAmmoState(state, p, gunId, ammo, false)
			end
			CombatRemotes.sendGrenadeState(state, p, state.grenadeCount[p.UserId] or 0)
			if state.rocketCount[p.UserId] then
				CombatRemotes.sendRocketState(state, p, state.rocketCount[p.UserId])
			end
		end
		CombatRemotes.broadcastTeamScore(state)
		for _, p in ipairs(players) do
			CombatRemotes.sendTeamAssignment(state, p, state.playerTeams[p.UserId] or "Blue", state.playerTeams)
		end
	end,

	InitRocketsForPlayer = function(player)
		CombatAmmo.initPlayerRockets(state, player.UserId)
		CombatRemotes.sendRocketState(state, player, state.rocketCount[player.UserId] or 0)
	end,

	GiveRocketLauncherTool = giveRocketLauncherTool,
}
