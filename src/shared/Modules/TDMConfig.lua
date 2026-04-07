--[[
	Team Deathmatch configuration.
]]

return {
	KILL_LIMIT = 5,
	-- Internal keys "Blue" / "Red"; UI labels match.
	TEAMS = { "Blue", "Red" },
	RESPAWN_DELAY = 2,
	LEADERBOARD_DURATION = 8,

	-- TDM spawn system: SpawnLocations.TDMSpawnLocations, avoids enemies
	TDM_SPAWN_PARENT = "SpawnLocations",
	TDM_SPAWN_FOLDER = "TDMSpawnLocations",
	TDM_SAFE_DISTANCE = 24, -- studs; no enemies within this radius
	TDM_SPAWN_MAX_ATTEMPTS = 15, -- retries before fallback to any spawn
}
