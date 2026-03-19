--[[
	Combat configuration: health, remotes, etc.
	Tag parts with BULLET_BLOCKER_TAG to create walls that block bullets but not grenades.
]]

return {
	BULLET_BLOCKER_TAG = "BulletBlocker",
	DEFAULT_HEALTH = 100,
	REMOTE_FOLDER_NAME = "CombatRemotes",
	REMOTES = {
		FIRE_GUN = "FireGun",
		AMMO_STATE = "AmmoState", -- Server -> Client: ammo count, isReloading, gunId
		THROW_GRENADE = "ThrowGrenade",
		THROW_ROCKET = "ThrowRocket",
		MATCH_ENDED = "MatchEnded", -- Server -> Client: { winningTeam, bluePlayers, redPlayers }
		TEAM_SCORE_UPDATE = "TeamScoreUpdate", -- Server -> Client: blueKills, redKills (real-time)
		GRENADE_STATE = "GrenadeState", -- Server -> Client: grenadeCount (current)
		ROCKET_STATE = "RocketState", -- Server -> Client: rocketCount (current)
		WEAPON_INVENTORY = "WeaponInventory", -- Server -> Client: { "Pistol", "Rifle", ... }
		PLAYER_DIED = "PlayerDied", -- Server -> Client: respawnDelaySeconds (local player died in TDM)
	},
}
