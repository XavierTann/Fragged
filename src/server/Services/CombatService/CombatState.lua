--[[
	CombatState
	Shared mutable state for the CombatService.
	Created and reset by CombatServiceServer per round.
]]

return function()
	return {
		currentRoundPlayers = {},
		onRoundEndCallback = nil,
		diedConnections = {},
		matchEnded = false,
		playerTeams = {},
		teamKills = { Blue = 0, Red = 0 },
		playerKills = {},
		playerDeaths = {},
		lastFiredAt = {},
		lastGrenadeThrownAt = {},
		ammoInMagazine = {},
		reloadEndAt = {},
		-- Remotes (set by CombatRemotes)
		fireGunRE = nil,
		ammoStateRE = nil,
		throwGrenadeRE = nil,
		matchEndedRE = nil,
		teamScoreUpdateRE = nil,
	}
end
