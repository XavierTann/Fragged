--[[
	CombatRemotes
	Remote creation and client communication (ammo, team score).
]]

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
	state.fireGunRE = getOrCreate(CombatConfig.REMOTES.FIRE_GUN)
	state.ammoStateRE = getOrCreate(CombatConfig.REMOTES.AMMO_STATE)
	state.throwGrenadeRE = getOrCreate(CombatConfig.REMOTES.THROW_GRENADE)
	state.matchEndedRE = getOrCreate(CombatConfig.REMOTES.MATCH_ENDED)
	state.teamScoreUpdateRE = getOrCreate(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
end

local function sendAmmoState(state, player, gunId, ammoCount, isReloading)
	if state.ammoStateRE then
		state.ammoStateRE:FireClient(player, gunId, ammoCount, isReloading)
	end
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
	broadcastTeamScore = broadcastTeamScore,
}
