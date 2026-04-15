--[[
	Team Deathmatch configuration.
	Arena layout: SpawnLocations.PlayerSpawnLocations (players) and SpawnLocations.ItemSpawnLocations (drops).
	Legacy: TDMSpawnLocations folder directly under Arena if the new layout is absent.
]]

local TDMConfig = {
	KILL_LIMIT = 1,
	TEAMS = { "Blue", "Red" },
	RESPAWN_DELAY = 2,
	LEADERBOARD_DURATION = 8,

	SPAWN_LOCATIONS_ROOT = "SpawnLocations",
	PLAYER_SPAWN_FOLDER = "PlayerSpawnLocations",
	ITEM_SPAWN_FOLDER = "ItemSpawnLocations",

	-- Legacy arena template: player spawns only
	LEGACY_TDM_SPAWN_FOLDER = "TDMSpawnLocations",

	TDM_SAFE_DISTANCE = 24,
	TDM_SPAWN_MAX_ATTEMPTS = 15,
}

function TDMConfig.getPlayerSpawnFolder(arenaModel)
	if not arenaModel then
		return nil
	end
	local root = arenaModel:FindFirstChild(TDMConfig.SPAWN_LOCATIONS_ROOT)
	if root then
		local f = root:FindFirstChild(TDMConfig.PLAYER_SPAWN_FOLDER)
		if f then
			return f
		end
	end
	return arenaModel:FindFirstChild(TDMConfig.LEGACY_TDM_SPAWN_FOLDER)
end

function TDMConfig.getItemSpawnFolder(arenaModel)
	if not arenaModel then
		return nil
	end
	local root = arenaModel:FindFirstChild(TDMConfig.SPAWN_LOCATIONS_ROOT)
	if root then
		return root:FindFirstChild(TDMConfig.ITEM_SPAWN_FOLDER)
	end
	return nil
end

return TDMConfig
