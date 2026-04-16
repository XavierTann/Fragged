--[[
	ArenaModeConfig
	Per-arena-mode settings. The mode name (e.g. "1v1", "6v6") maps to a config
	table with team size, kill limit, and drop weight overrides.
	PadQueueService parses the mode from the workspace folder name (e.g. "3v3ArenaPad" -> "3v3").
]]

local ArenaModeConfig = {}

ArenaModeConfig.MODES = {
	["1v1"] = {
		teamSize = 1,
		killLimit = 3,
		dropWeights = {
			RocketLauncher = 0.5,
			HealthPack = 0.5,
		},
	},
	["2v2"] = {
		teamSize = 2,
		killLimit = 5,
		dropWeights = {
			RocketLauncher = 0.8,
			HealthPack = 0.8,
		},
	},
	["3v3"] = {
		teamSize = 3,
		killLimit = 8,
		dropWeights = {
			RocketLauncher = 1,
			HealthPack = 1,
		},
	},
	["4v4"] = {
		teamSize = 4,
		killLimit = 12,
		dropWeights = {
			RocketLauncher = 1,
			HealthPack = 1,
		},
	},
	["5v5"] = {
		teamSize = 5,
		killLimit = 15,
		dropWeights = {
			RocketLauncher = 1.2,
			HealthPack = 1.2,
		},
	},
	["6v6"] = {
		teamSize = 6,
		killLimit = 20,
		dropWeights = {
			RocketLauncher = 1.5,
			HealthPack = 1.5,
		},
	},
}

function ArenaModeConfig.getMode(modeName)
	return ArenaModeConfig.MODES[modeName]
end

function ArenaModeConfig.getTeamSize(modeName)
	local mode = ArenaModeConfig.MODES[modeName]
	return mode and mode.teamSize or 1
end

return ArenaModeConfig
