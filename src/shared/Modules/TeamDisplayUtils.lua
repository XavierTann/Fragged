--[[
	TeamDisplayUtils
	Server and networking use internal team keys "Blue" and "Red".
	Player-facing labels use the same display names.
]]

local TeamDisplayUtils = {}

function TeamDisplayUtils.displayName(internalTeam)
	if internalTeam == "Red" then
		return "Red"
	end
	if internalTeam == "Blue" then
		return "Blue"
	end
	return type(internalTeam) == "string" and internalTeam or ""
end

function TeamDisplayUtils.youAreOnTeamPhrase(internalTeam)
	local name = TeamDisplayUtils.displayName(internalTeam)
	if name == "" then
		return ""
	end
	return "You are on the " .. name .. " Team"
end

function TeamDisplayUtils.teamVictoryPhrase(internalTeam)
	local name = TeamDisplayUtils.displayName(internalTeam)
	if name == "" then
		return ""
	end
	return name .. " Team Victory!"
end

return TeamDisplayUtils
