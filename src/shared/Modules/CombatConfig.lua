--[[
	Combat configuration: health, remotes, etc.
	Tag parts with BULLET_BLOCKER_TAG to create walls that block bullets but not grenades.
]]

return {
	BULLET_BLOCKER_TAG = "BulletBlocker",
	-- Studs along aim from HumanoidRootPart for guns, predicted tracers, rockets (0 = at root).
	SHOT_ORIGIN_FORWARD_STUDS = 0,
	-- Grenades only: spawn slightly in front of the player along aim.
	GRENADE_SHOT_ORIGIN_FORWARD_STUDS = 5,
	DEFAULT_HEALTH = 100,
	REMOTE_FOLDER_NAME = "CombatRemotes",
	REMOTES = {
		-- Client -> Server: (shotOrigin: Vector3, aimDirection: Vector3, gunId: string).
		-- Server -> Client: FireGunRejected(reason, gunId, resetClientFireRate) when a shot is rejected
		-- after the client may have shown predicted feedback; resetClientFireRate clears local fire-rate gate.
		FIRE_GUN = "FireGun",
		FIRE_GUN_REJECTED = "FireGunRejected",
		REQUEST_RELOAD = "RequestReload", -- Client -> Server: manual magazine reload (gunId string)
		AMMO_STATE = "AmmoState", -- Server -> Client: ammo count, isReloading, gunId
		THROW_GRENADE = "ThrowGrenade",
		THROW_ROCKET = "ThrowRocket",
		MATCH_ENDED = "MatchEnded", -- Server -> Client: { winningTeam, bluePlayers, redPlayers } (redPlayers = Orange team, internal key Red)
		-- Client -> Server Invoke: live K/D table during an active TDM round only; returns nil if not in round
		GET_LIVE_LEADERBOARD = "GetLiveLeaderboard",
		TEAM_SCORE_UPDATE = "TeamScoreUpdate", -- Server -> Client: blueKills, redKills (real-time)
		GRENADE_STATE = "GrenadeState", -- Server -> Client: grenadeCount (current)
		ROCKET_STATE = "RocketState", -- Server -> Client: rocketCount (current)
		WEAPON_INVENTORY = "WeaponInventory", -- Server -> Client: { "Pistol", "Rifle", ... }
		PLAYER_DIED = "PlayerDied", -- Server -> Client: respawnDelaySeconds (local player died in TDM)
		TEAM_ASSIGNMENT = "TeamAssignment", -- Server -> Client: myTeam, playerTeams table
		-- Server -> attacking client only: damage dealt (number), worldPosition (Vector3 above head)
		DAMAGE_NUMBER = "DamageNumber",
		-- Server -> killer client only: victim display name (string) for center-screen elimination toast
		KILL_NOTIFICATION = "KillNotification",
		-- Server -> other clients in round: (shooterUserId: number, gunId: string) for 3D gunshot at shooter
		GUNSHOT_SPATIAL = "GunshotSpatial",
	},
}
