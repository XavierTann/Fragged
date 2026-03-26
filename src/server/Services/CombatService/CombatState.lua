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
		characterAddedConnections = {},
		matchEnded = false,
		playerTeams = {},
		teamKills = { Blue = 0, Red = 0 },
		playerKills = {},
		playerDeaths = {},
		playerAssists = {},
		lastFiredAt = {},
		ammoInMagazine = {},
		grenadeCount = {}, -- uid -> current grenades (0 to maxCapacity)
		grenadeRegenTimes = {}, -- uid -> { t1, t2, ... } when each pending grenade will be ready
		rocketCount = {}, -- uid -> current rockets (0 to maxRockets)
		rocketRegenTimes = {}, -- uid -> { t1, t2, ... }
		reloadEndAt = {},
		-- Remotes (set by CombatRemotes)
		fireGunRE = nil,
		ammoStateRE = nil,
		throwGrenadeRE = nil,
		matchEndedRE = nil,
		teamScoreUpdateRE = nil,
		fireGunRejectedRE = nil,
	}
end
