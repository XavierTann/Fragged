--[[
	CombatService (server)
	Shooting (visible bullets), health, round end. Server-authoritative.
	Init() sets up remotes and handlers. StartRound(players, onRoundEnd) is called when arena round starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)

local fireGunRE = nil
local ammoStateRE = nil
local throwGrenadeRE = nil
local matchEndedRE = nil
local teamScoreUpdateRE = nil
local currentRoundPlayers = {}
local onRoundEndCallback = nil
local diedConnections = {}
local matchEnded = false
local playerTeams = {}
local teamKills = {}
local playerKills = {}
local playerDeaths = {}
local lastFiredAt = {}
local lastGrenadeThrownAt = {}
local ammoInMagazine = {} -- [userId][gunId] = count
local reloadEndAt = {} -- [userId][gunId] = os.clock() when reload finishes
local BULLETS_FOLDER_NAME = "CombatBullets"
local GRENADES_FOLDER_NAME = "CombatGrenades"
local COLLISION_GROUP_WALLS = "CombatWalls"
local COLLISION_GROUP_GRENADES = "Grenades"

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

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local fireR = folder:FindFirstChild(CombatConfig.REMOTES.FIRE_GUN)
	if not fireR then
		fireR = Instance.new("RemoteEvent")
		fireR.Name = CombatConfig.REMOTES.FIRE_GUN
		fireR.Parent = folder
	end
	local ammoR = folder:FindFirstChild(CombatConfig.REMOTES.AMMO_STATE)
	if not ammoR then
		ammoR = Instance.new("RemoteEvent")
		ammoR.Name = CombatConfig.REMOTES.AMMO_STATE
		ammoR.Parent = folder
	end
	local grenadeR = folder:FindFirstChild(CombatConfig.REMOTES.THROW_GRENADE)
	if not grenadeR then
		grenadeR = Instance.new("RemoteEvent")
		grenadeR.Name = CombatConfig.REMOTES.THROW_GRENADE
		grenadeR.Parent = folder
	end
	local matchEndedR = folder:FindFirstChild(CombatConfig.REMOTES.MATCH_ENDED)
	if not matchEndedR then
		matchEndedR = Instance.new("RemoteEvent")
		matchEndedR.Name = CombatConfig.REMOTES.MATCH_ENDED
		matchEndedR.Parent = folder
	end
	local teamScoreR = folder:FindFirstChild(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
	if not teamScoreR then
		teamScoreR = Instance.new("RemoteEvent")
		teamScoreR.Name = CombatConfig.REMOTES.TEAM_SCORE_UPDATE
		teamScoreR.Parent = folder
	end
	return fireR, ammoR, grenadeR, matchEndedR, teamScoreR
end

local function sendAmmoState(player, gunId, ammoCount, isReloading)
	if ammoStateRE then
		ammoStateRE:FireClient(player, gunId, ammoCount, isReloading)
	end
end

local function broadcastTeamScore()
	if not teamScoreUpdateRE then
		return
	end
	local blueKills = teamKills.Blue or 0
	local redKills = teamKills.Red or 0
	for _, p in ipairs(currentRoundPlayers) do
		if p and p.Parent then
			teamScoreUpdateRE:FireClient(p, blueKills, redKills)
		end
	end
end

local function initPlayerAmmo(userId)
	ammoInMagazine[userId] = {}
	reloadEndAt[userId] = {}
	for gunId, gun in pairs(GunsConfig) do
		local mag = gun.magazineSize or 6
		ammoInMagazine[userId][gunId] = mag
		reloadEndAt[userId][gunId] = nil
	end
end

local function processReloads()
	local now = os.clock()
	for userId, gunReloads in pairs(reloadEndAt) do
		for gunId, endTime in pairs(gunReloads) do
			if endTime and now >= endTime then
				local gun = GunsConfig[gunId]
				if gun then
					ammoInMagazine[userId][gunId] = gun.magazineSize or 6
					reloadEndAt[userId][gunId] = nil
					local player = Players:GetPlayerByUserId(userId)
					if player then
						sendAmmoState(player, gunId, ammoInMagazine[userId][gunId], false)
					end
				end
			end
		end
	end
end

local function getBulletsFolder()
	local folder = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = BULLETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function getGrenadesFolder()
	local folder = Workspace:FindFirstChild(GRENADES_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = GRENADES_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local onPlayerDied
local function getSpawnCFrame(spawnName)
	local folder = Workspace:FindFirstChild(LobbyConfig.SPAWNS_FOLDER_NAME)
	if not folder then
		return CFrame.new(0, 10, 0)
	end
	local spawn = folder:FindFirstChild(spawnName)
	if not spawn then
		spawn = folder:FindFirstChild(LobbyConfig.SPAWN_NAMES.BLUE_TEAM)
	end
	if not spawn then
		return CFrame.new(0, 10, 0)
	end
	local cf, part
	if spawn:IsA("BasePart") then
		part = spawn
		cf = spawn.CFrame
	elseif spawn:IsA("Model") and spawn.PrimaryPart then
		part = spawn.PrimaryPart
		cf = spawn.PrimaryPart.CFrame
	else
		return CFrame.new(0, 10, 0)
	end
	-- Offset upward so player stands ON TOP of the spawn, not inside it
	local offset = part and part:IsA("BasePart") and (part.Size.Y / 2 + 2.5) or 3
	return cf + Vector3.new(0, offset, 0)
end

local function respawnPlayer(player)
	local team = playerTeams[player.UserId]
	local spawnName = (team == "Blue" and LobbyConfig.SPAWN_NAMES.BLUE_TEAM) or LobbyConfig.SPAWN_NAMES.RED_TEAM
	player:LoadCharacter()
	task.defer(function()
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = getSpawnCFrame(spawnName)
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
				humanoid.Health = CombatConfig.DEFAULT_HEALTH
				local conn = humanoid.Died:Connect(function()
					onPlayerDied(player)
				end)
				diedConnections[player.UserId] = conn
			end
		end
	end)
end

local function buildLeaderboardData()
	local bluePlayers = {}
	local redPlayers = {}
	for _, p in ipairs(currentRoundPlayers) do
		if p and p.Parent then
			local team = playerTeams[p.UserId] or "Blue"
			local entry = {
				name = p.Name,
				kills = playerKills[p.UserId] or 0,
				deaths = playerDeaths[p.UserId] or 0,
			}
			if team == "Blue" then
				table.insert(bluePlayers, entry)
			else
				table.insert(redPlayers, entry)
			end
		end
	end
	table.sort(bluePlayers, function(a, b)
		return a.kills > b.kills
	end)
	table.sort(redPlayers, function(a, b)
		return a.kills > b.kills
	end)
	return bluePlayers, redPlayers
end

local function endMatch(winningTeam)
	if matchEnded then
		return
	end
	matchEnded = true
	print("[Combat] TDM match ended. Winning team: " .. tostring(winningTeam))
	for _, conn in pairs(diedConnections) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	diedConnections = {}
	local bluePlayers, redPlayers = buildLeaderboardData()
	for _, p in ipairs(currentRoundPlayers) do
		if p and p.Parent and matchEndedRE then
			local payload = {
				winningTeam = winningTeam,
				myTeam = playerTeams[p.UserId] or "Blue",
				bluePlayers = bluePlayers,
				redPlayers = redPlayers,
			}
			matchEndedRE:FireClient(p, payload)
		end
	end
	task.delay(TDMConfig.LEADERBOARD_DURATION, function()
		currentRoundPlayers = {}
		if onRoundEndCallback then
			local cb = onRoundEndCallback
			onRoundEndCallback = nil
			cb()
		end
	end)
end

onPlayerDied = function(deadPlayer)
	if matchEnded then
		return
	end
	local uid = deadPlayer.UserId
	playerDeaths[uid] = (playerDeaths[uid] or 0) + 1
	local humanoid = deadPlayer.Character and deadPlayer.Character:FindFirstChildOfClass("Humanoid")
	local killerUserId = humanoid and humanoid:GetAttribute("LastDamagerUserId")
	if killerUserId and killerUserId ~= uid then
		local killerTeam = playerTeams[killerUserId]
		local deadTeam = playerTeams[uid]
		if killerTeam and deadTeam and killerTeam ~= deadTeam then
			playerKills[killerUserId] = (playerKills[killerUserId] or 0) + 1
			teamKills[killerTeam] = (teamKills[killerTeam] or 0) + 1
			broadcastTeamScore()
			if teamKills[killerTeam] >= TDMConfig.KILL_LIMIT then
				endMatch(killerTeam)
				return
			end
		end
	end
	diedConnections[uid] = nil
	task.delay(TDMConfig.RESPAWN_DELAY, function()
		if matchEnded then
			return
		end
		for _, p in ipairs(currentRoundPlayers) do
			if p.UserId == uid and p.Parent then
				respawnPlayer(p)
				break
			end
		end
	end)
end

local function spawnBullet(shooter, startPos, direction, gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
	local dir = direction.Unit
	local bullet = Instance.new("Part")
	bullet.Name = "Bullet"
	bullet.Size = gun.bulletSize
	bullet.Color = gun.bulletColor
	bullet.Material = Enum.Material.Neon
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CFrame = CFrame.lookAt(startPos, startPos + dir)
	bullet.Parent = getBulletsFolder()
	local shooterUserId = shooter.UserId
	local speed = gun.bulletSpeed
	local lastPos = startPos
	local params = RaycastParams.new()
	local filter = { bullet, getBulletsFolder() }
	if shooter.Character then
		filter[#filter + 1] = shooter.Character
	end
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not bullet.Parent then
			conn:Disconnect()
			return
		end
		local move = dir * speed * dt
		local newPos = lastPos + move
		local result = Workspace:Raycast(lastPos, move, params)
		if result and result.Instance then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			if model then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local hitPlayer = humanoid and Players:GetPlayerFromCharacter(model)
				if hitPlayer and hitPlayer.UserId ~= shooterUserId then
					local shooterTeam = playerTeams[shooterUserId]
					local hitTeam = playerTeams[hitPlayer.UserId]
					if shooterTeam and hitTeam and shooterTeam ~= hitTeam then
						conn:Disconnect()
						humanoid:SetAttribute("LastDamagerUserId", shooterUserId)
						humanoid:TakeDamage(gun.damage)
						bullet:Destroy()
						return
					end
				end
			end
			-- Hit wall or other solid: block bullet (do not pass through)
			conn:Disconnect()
			bullet:Destroy()
			return
		end
		lastPos = newPos
		bullet.CFrame = CFrame.lookAt(newPos, newPos + dir)
	end)
	task.delay(5, function()
		if bullet and bullet.Parent then
			conn:Disconnect()
			bullet:Destroy()
		end
	end)
end

local function doExplosionDamage(center, radius, damage, throwerUserId)
	local radiusSq = radius * radius
	local throwerTeam = throwerUserId and playerTeams[throwerUserId]
	for _, p in ipairs(currentRoundPlayers) do
		if p and p.Parent and p.Character then
			if not (throwerTeam and throwerTeam == (playerTeams[p.UserId] or "")) then
				local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
				local root = p.Character:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and root then
					local offset = root.Position - center
					local distSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
					if distSq <= radiusSq then
						local dist = math.sqrt(distSq)
						local falloff = dist > 0 and math.max(0, 1 - dist / radius) or 1
						local dmg = math.ceil(damage * falloff)
						if dmg > 0 then
							humanoid:SetAttribute("LastDamagerUserId", throwerUserId or 0)
							humanoid:TakeDamage(dmg)
						end
					end
				end
			end
		end
	end
end

local function spawnGrenade(_thrower, startPos, direction)
	local cfg = GrenadeConfig
	local dir = direction.Unit
	-- Add upward arc
	local throwDir = (Vector3.new(dir.X, 0, dir.Z) * (1 - cfg.throwArcUp) + Vector3.new(0, cfg.throwArcUp, 0)).Unit
	local velocity = throwDir * cfg.throwSpeed

	local grenade = Instance.new("Part")
	grenade.Name = "Grenade"
	grenade.Size = cfg.size
	grenade.Color = cfg.color
	grenade.Material = cfg.material
	grenade.Shape = Enum.PartType.Ball
	grenade.Anchored = false
	grenade.CanCollide = true
	grenade.CFrame = CFrame.new(startPos)
	grenade.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, cfg.restitution, 1, 1)
	grenade.AssemblyLinearVelocity = velocity
	grenade.CollisionGroup = COLLISION_GROUP_GRENADES
	grenade.Parent = getGrenadesFolder()

	task.delay(cfg.fuseTime, function()
		if not grenade or not grenade.Parent then
			return
		end
		local center = grenade.Position
		grenade:Destroy()

		-- Explosion visual: expanding sphere
		local explosionPart = Instance.new("Part")
		explosionPart.Name = "Explosion"
		explosionPart.Shape = Enum.PartType.Ball
		explosionPart.Size = Vector3.new(1, 1, 1)
		explosionPart.Anchored = true
		explosionPart.CanCollide = false
		explosionPart.Material = Enum.Material.Neon
		explosionPart.Color = Color3.fromRGB(255, 120, 40)
		explosionPart.CFrame = CFrame.new(center)
		explosionPart.Transparency = 0.3
		explosionPart.Parent = getGrenadesFolder()
		local startSize = 1
		local endSize = cfg.radius * 2
		local duration = 0.2
		local elapsed = 0
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

		doExplosionDamage(center, cfg.radius, cfg.damage, _thrower and _thrower.UserId or nil)
	end)
end

local function bindHandlers()
	fireGunRE.OnServerEvent:Connect(function(player, aimDirection, gunId)
		if matchEnded then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" then
			return
		end
		if aimDirection.Magnitude < 0.01 then
			return
		end
		gunId = gunId or "Pistol"
		local gun = GunsConfig[gunId] or GunsConfig.Pistol
		local now = os.clock()
		local uid = player.UserId

		-- Fire rate check
		local last = lastFiredAt[uid] or 0
		if now - last < gun.fireRate then
			return
		end

		-- Ammo check: ensure player has ammo state for this weapon
		ammoInMagazine[uid] = ammoInMagazine[uid] or {}
		reloadEndAt[uid] = reloadEndAt[uid] or {}
		local ammo = ammoInMagazine[uid][gunId]
		if ammo == nil then
			ammoInMagazine[uid][gunId] = gun.magazineSize or 6
			ammo = ammoInMagazine[uid][gunId]
		end

		-- Reloading check
		if reloadEndAt[uid][gunId] and now < reloadEndAt[uid][gunId] then
			sendAmmoState(player, gunId, ammo, true)
			return
		end

		-- Ammo check
		if ammo <= 0 then
			-- Auto-start reload (if not already)
			if not reloadEndAt[uid][gunId] then
				local reloadTime = gun.reloadTime or 1.5
				reloadEndAt[uid][gunId] = now + reloadTime
			end
			sendAmmoState(player, gunId, 0, true)
			return
		end

		lastFiredAt[uid] = now
		ammoInMagazine[uid][gunId] = ammo - 1
		local newAmmo = ammoInMagazine[uid][gunId]

		local character = player.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local startPos = root.Position + aimDirection.Unit * 2
		local pelletCount = gun.pelletCount or 1
		local spreadDeg = gun.spreadDegrees or 0
		for _ = 1, pelletCount do
			local dir = aimDirection.Unit
			if spreadDeg > 0 and pelletCount > 1 then
				local angle = math.rad(spreadDeg * (math.random() * 2 - 1))
				local perp = Vector3.new(-dir.Z, 0, dir.X)
				dir = (dir * math.cos(angle) + perp * math.sin(angle)).Unit
				-- add vertical spread
				local up = Vector3.new(0, 1, 0)
				local angle2 = math.rad(spreadDeg * 0.5 * (math.random() * 2 - 1))
				dir = (dir * math.cos(angle2) + up * math.sin(angle2)).Unit
			end
			spawnBullet(player, startPos, dir, gunId)
		end

		-- If magazine empty after shot, auto-start reload
		if newAmmo <= 0 then
			local reloadTime = gun.reloadTime or 1.5
			reloadEndAt[uid][gunId] = now + reloadTime
			sendAmmoState(player, gunId, 0, true)
		else
			sendAmmoState(player, gunId, newAmmo, false)
		end
	end)

	throwGrenadeRE.OnServerEvent:Connect(function(player, aimDirection)
		if matchEnded then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" then
			return
		end
		if aimDirection.Magnitude < 0.01 then
			return
		end
		local now = os.clock()
		local uid = player.UserId
		local last = lastGrenadeThrownAt[uid] or 0
		if now - last < GrenadeConfig.cooldown then
			return
		end
		lastGrenadeThrownAt[uid] = now
		local character = player.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local startPos = root.Position + aimDirection.Unit * 2
		spawnGrenade(player, startPos, aimDirection)
	end)
end

return {
	Init = function()
		setupWallCollisionGroups()
		setupBulletBlockerWalls()
		fireGunRE, ammoStateRE, throwGrenadeRE, matchEndedRE, teamScoreUpdateRE = ensureRemotes()
		bindHandlers()
		RunService.Heartbeat:Connect(processReloads)
	end,

	StartRound = function(players, onRoundEnd)
		onRoundEndCallback = onRoundEnd
		matchEnded = false
		currentRoundPlayers = {}
		playerTeams = {}
		teamKills = { Blue = 0, Red = 0 }
		playerKills = {}
		playerDeaths = {}
		for i, p in ipairs(players) do
			currentRoundPlayers[#currentRoundPlayers + 1] = p
			playerTeams[p.UserId] = (i % 2 == 1) and "Blue" or "Red"
			playerKills[p.UserId] = 0
			playerDeaths[p.UserId] = 0
			initPlayerAmmo(p.UserId)
			local team = playerTeams[p.UserId]
			local spawnName = (team == "Blue" and LobbyConfig.SPAWN_NAMES.BLUE_TEAM) or LobbyConfig.SPAWN_NAMES.RED_TEAM
			local cf = getSpawnCFrame(spawnName)
			local character = p.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				character.HumanoidRootPart.CFrame = cf
			end
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
					humanoid.Health = CombatConfig.DEFAULT_HEALTH
					local conn = humanoid.Died:Connect(function()
						onPlayerDied(p)
					end)
					diedConnections[p.UserId] = conn
				end
			end
			for gunId, ammo in pairs(ammoInMagazine[p.UserId] or {}) do
				sendAmmoState(p, gunId, ammo, false)
			end
		end
		broadcastTeamScore()
	end,
}
