--[[
	CombatRemotes
	Remote creation and client communication (ammo, team score).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local function ensureRemotes(state)
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
	state.fireGunRE = getOrCreate(CombatConfig.REMOTES.FIRE_GUN)
	state.requestReloadRE = getOrCreate(CombatConfig.REMOTES.REQUEST_RELOAD)
	state.ammoStateRE = getOrCreate(CombatConfig.REMOTES.AMMO_STATE)
	state.throwGrenadeRE = getOrCreate(CombatConfig.REMOTES.THROW_GRENADE)
	state.matchEndedRE = getOrCreate(CombatConfig.REMOTES.MATCH_ENDED)
	state.teamScoreUpdateRE = getOrCreate(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
	state.grenadeStateRE = getOrCreate(CombatConfig.REMOTES.GRENADE_STATE)
	state.rocketStateRE = getOrCreate(CombatConfig.REMOTES.ROCKET_STATE)
	state.throwRocketRE = getOrCreate(CombatConfig.REMOTES.THROW_ROCKET)
	state.weaponInventoryRE = getOrCreate(CombatConfig.REMOTES.WEAPON_INVENTORY)
	state.playerDiedRE = getOrCreate(CombatConfig.REMOTES.PLAYER_DIED)
	state.teamAssignmentRE = getOrCreate(CombatConfig.REMOTES.TEAM_ASSIGNMENT)
	state.fireGunRejectedRE = getOrCreate(CombatConfig.REMOTES.FIRE_GUN_REJECTED)
	state.getLiveLeaderboardRF = getOrCreateRemoteFunction(CombatConfig.REMOTES.GET_LIVE_LEADERBOARD)
	state.damageNumberRE = getOrCreate(CombatConfig.REMOTES.DAMAGE_NUMBER)
	state.killNotificationRE = getOrCreate(CombatConfig.REMOTES.KILL_NOTIFICATION)
end

local function sendAmmoState(state, player, gunId, ammoCount, isReloading)
	if state.ammoStateRE then
		state.ammoStateRE:FireClient(player, gunId, ammoCount, isReloading)
	end
end

-- reason: string (e.g. InvalidArgs, WeaponNotOwned, NotEquipped, BadOrigin, BadDirection, Cooldown, Reloading, EmptyMag).
-- resetClientFireRate: if true, client clears local lastFiredAt so mispredicted shots do not block the next press.
local function sendFireGunRejected(state, player, reason, gunId, resetClientFireRate)
	if state.fireGunRejectedRE then
		state.fireGunRejectedRE:FireClient(player, reason, gunId, resetClientFireRate == true)
	end
end

local function sendGrenadeState(state, player, grenadeCount)
	if state.grenadeStateRE then
		state.grenadeStateRE:FireClient(player, grenadeCount)
	end
end

local function sendRocketState(state, player, rocketCount)
	if state.rocketStateRE then
		state.rocketStateRE:FireClient(player, rocketCount)
	end
end

local function firePlayerDied(state, player, respawnDelaySeconds)
	if state.playerDiedRE then
		state.playerDiedRE:FireClient(player, respawnDelaySeconds)
	end
end

local function sendTeamAssignment(state, player, myTeam, playerTeams)
	if state.teamAssignmentRE then
		state.teamAssignmentRE:FireClient(player, myTeam, playerTeams)
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

-- Floating damage numbers for the attacker only (exact damage dealt).
local function notifyAttackerDamage(state, attackerUserId, victimCharacter, damage)
	if damage <= 0 or not attackerUserId then
		return
	end
	local attacker = Players:GetPlayerByUserId(attackerUserId)
	if not attacker or not attacker.Parent or not state.damageNumberRE then
		return
	end
	local pos = worldPositionAboveHead(victimCharacter)
	if not pos then
		return
	end
	state.damageNumberRE:FireClient(attacker, damage, pos)
end

local function sendEliminationNotice(state, killerUserId, victimPlayer)
	if not killerUserId or not victimPlayer or not victimPlayer.Parent then
		return
	end
	local killer = Players:GetPlayerByUserId(killerUserId)
	if not killer or not killer.Parent or not state.killNotificationRE then
		return
	end
	local name = victimPlayer.DisplayName
	if name == "" then
		name = victimPlayer.Name
	end
	state.killNotificationRE:FireClient(killer, name)
end

local function broadcastTeamScore(state)
	if not state.teamScoreUpdateRE then
		return
	end
	local blueKills = state.teamKills.Blue or 0
	local redKills = state.teamKills.Red or 0
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent then
			state.teamScoreUpdateRE:FireClient(p, blueKills, redKills)
		end
	end
end

return {
	ensureRemotes = ensureRemotes,
	sendAmmoState = sendAmmoState,
	sendFireGunRejected = sendFireGunRejected,
	sendGrenadeState = sendGrenadeState,
	sendRocketState = sendRocketState,
	broadcastTeamScore = broadcastTeamScore,
	firePlayerDied = firePlayerDied,
	sendTeamAssignment = sendTeamAssignment,
	notifyAttackerDamage = notifyAttackerDamage,
	sendEliminationNotice = sendEliminationNotice,
}
