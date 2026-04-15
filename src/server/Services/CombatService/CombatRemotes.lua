--[[
	CombatRemotes
	Remote creation and client communication (ammo, team score).
	Remotes are stored at module level (shared across all matches).
	Functions still receive per-match state for player lists / game data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local remotes = {}

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local function getOrCreate(name)
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	local function getOrCreateRemoteFunction(name)
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	remotes.fireGunRE = getOrCreate(CombatConfig.REMOTES.FIRE_GUN)
	remotes.requestReloadRE = getOrCreate(CombatConfig.REMOTES.REQUEST_RELOAD)
	remotes.ammoStateRE = getOrCreate(CombatConfig.REMOTES.AMMO_STATE)
	remotes.throwGrenadeRE = getOrCreate(CombatConfig.REMOTES.THROW_GRENADE)
	remotes.matchEndedRE = getOrCreate(CombatConfig.REMOTES.MATCH_ENDED)
	remotes.teamScoreUpdateRE = getOrCreate(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
	remotes.grenadeStateRE = getOrCreate(CombatConfig.REMOTES.GRENADE_STATE)
	remotes.rocketStateRE = getOrCreate(CombatConfig.REMOTES.ROCKET_STATE)
	remotes.throwRocketRE = getOrCreate(CombatConfig.REMOTES.THROW_ROCKET)
	remotes.weaponInventoryRE = getOrCreate(CombatConfig.REMOTES.WEAPON_INVENTORY)
	remotes.playerDiedRE = getOrCreate(CombatConfig.REMOTES.PLAYER_DIED)
	remotes.teamAssignmentRE = getOrCreate(CombatConfig.REMOTES.TEAM_ASSIGNMENT)
	remotes.fireGunRejectedRE = getOrCreate(CombatConfig.REMOTES.FIRE_GUN_REJECTED)
	remotes.getLiveLeaderboardRF = getOrCreateRemoteFunction(CombatConfig.REMOTES.GET_LIVE_LEADERBOARD)
	remotes.damageNumberRE = getOrCreate(CombatConfig.REMOTES.DAMAGE_NUMBER)
	remotes.killNotificationRE = getOrCreate(CombatConfig.REMOTES.KILL_NOTIFICATION)
	remotes.gunshotSpatialRE = getOrCreate(CombatConfig.REMOTES.GUNSHOT_SPATIAL)
	remotes.grenadeExplosionFXRE = getOrCreate(CombatConfig.REMOTES.GRENADE_EXPLOSION_FX)
	return remotes
end

local function getRemotes()
	return remotes
end

local function sendAmmoState(_state, player, gunId, ammoCount, isReloading)
	if remotes.ammoStateRE then
		remotes.ammoStateRE:FireClient(player, gunId, ammoCount, isReloading)
	end
end

local function sendFireGunRejected(_state, player, reason, gunId, resetClientFireRate)
	if remotes.fireGunRejectedRE then
		remotes.fireGunRejectedRE:FireClient(player, reason, gunId, resetClientFireRate == true)
	end
end

local function sendGrenadeState(_state, player, grenadeCount)
	if remotes.grenadeStateRE then
		remotes.grenadeStateRE:FireClient(player, grenadeCount)
	end
end

local function sendRocketState(_state, player, rocketCount)
	if remotes.rocketStateRE then
		remotes.rocketStateRE:FireClient(player, rocketCount)
	end
end

local function firePlayerDied(_state, player, respawnDelaySeconds)
	if remotes.playerDiedRE then
		remotes.playerDiedRE:FireClient(player, respawnDelaySeconds)
	end
end

local function sendTeamAssignment(_state, player, myTeam, playerTeams)
	if remotes.teamAssignmentRE then
		remotes.teamAssignmentRE:FireClient(player, myTeam, playerTeams)
	end
end

local function worldPositionAboveHead(character)
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	local base = head and head.Position or (root and root.Position)
	if not base then
		return nil
	end
	return base + Vector3.new(0, 0.75, 0)
end

local function notifyAttackerDamage(_state, attackerUserId, victimCharacter, damage)
	if damage <= 0 or not attackerUserId then
		return
	end
	local attacker = Players:GetPlayerByUserId(attackerUserId)
	if not attacker or not attacker.Parent or not remotes.damageNumberRE then
		return
	end
	local pos = worldPositionAboveHead(victimCharacter)
	if not pos then
		return
	end
	remotes.damageNumberRE:FireClient(attacker, damage, pos)
end

local function sendEliminationNotice(_state, killerUserId, victimPlayer)
	if not killerUserId or not victimPlayer or not victimPlayer.Parent then
		return
	end
	local killer = Players:GetPlayerByUserId(killerUserId)
	if not killer or not killer.Parent or not remotes.killNotificationRE then
		return
	end
	local name = victimPlayer.DisplayName
	if name == "" then
		name = victimPlayer.Name
	end
	remotes.killNotificationRE:FireClient(killer, name)
end

local function broadcastTeamScore(state)
	if not remotes.teamScoreUpdateRE then
		return
	end
	local blueKills = state.teamKills.Blue or 0
	local redKills = state.teamKills.Red or 0
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent then
			remotes.teamScoreUpdateRE:FireClient(p, blueKills, redKills)
		end
	end
end

local function broadcastGunshotSpatial(state, shooterUserId, gunId)
	if not remotes.gunshotSpatialRE or not shooterUserId or typeof(gunId) ~= "string" then
		return
	end
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent and p.UserId ~= shooterUserId then
			remotes.gunshotSpatialRE:FireClient(p, shooterUserId, gunId)
		end
	end
end

local function broadcastGrenadeExplosionFX(state, worldPosition, radius, explosionSoundId, throwerUserId)
	if not remotes.grenadeExplosionFXRE then
		return
	end
	if typeof(worldPosition) ~= "Vector3" or typeof(radius) ~= "number" then
		return
	end
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent then
			remotes.grenadeExplosionFXRE:FireClient(p, worldPosition, radius, explosionSoundId, throwerUserId)
		end
	end
end

return {
	ensureRemotes = ensureRemotes,
	getRemotes = getRemotes,
	sendAmmoState = sendAmmoState,
	sendFireGunRejected = sendFireGunRejected,
	sendGrenadeState = sendGrenadeState,
	sendRocketState = sendRocketState,
	broadcastTeamScore = broadcastTeamScore,
	firePlayerDied = firePlayerDied,
	sendTeamAssignment = sendTeamAssignment,
	notifyAttackerDamage = notifyAttackerDamage,
	sendEliminationNotice = sendEliminationNotice,
	broadcastGunshotSpatial = broadcastGunshotSpatial,
	broadcastGrenadeExplosionFX = broadcastGrenadeExplosionFX,
}
