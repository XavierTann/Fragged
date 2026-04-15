--[[
	CombatState
	Per-match mutable state for the CombatService.
	One instance is created per active match. Remote event references
	are stored at module level in CombatRemotes, not per-match.
]]

return function()
	return {
		matchId = nil,
		arenaModel = nil,
		currentRoundPlayers = {},
		onRoundEndCallback = nil,
		diedConnections = {},
		characterAddedConnections = {},
		matchEnded = false,
		playerTeams = {},
		teamKills = { Blue = 0, Red = 0 },
		playerKills = {},
		playerDeaths = {},
		playerAssists = {},
		lastFiredAt = {},
		ammoInMagazine = {},
		grenadeCount = {},
		grenadeRegenTimes = {},
		rocketCount = {},
		rocketRegenTimes = {},
		reloadEndAt = {},
	}
end
