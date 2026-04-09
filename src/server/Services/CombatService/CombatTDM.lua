--[[
	CombatTDM
	Death handling, respawn, leaderboard, match end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)
local TDMSpawnStrategy = require(script.Parent.TDMSpawnStrategy)
local CombatRemotes = require(script.Parent.CombatRemotes)
local EconomyServiceServer = require(script.Parent.Parent.EconomyService.EconomyServiceServer)

local function getTDMContext(state)
	return {
		playerTeams = state.playerTeams,
		currentRoundPlayers = state.currentRoundPlayers,
	}
end

-- Roblox adds ForceField on spawn (SpawnLocation.Duration / default respawn protection).
-- TakeDamage is blocked while it exists — strip it in TDM so combat works immediately.
local SPAWN_FF_STRIP_SECONDS = 5

local function stripRobloxSpawnForceFields(character)
	if not character then
		return
	end
	local function removeForceFields()
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("ForceField") then
				child:Destroy()
			end
		end
	end
	removeForceFields()
	local conn
	conn = character.ChildAdded:Connect(function(child)
		if child:IsA("ForceField") then
			child:Destroy()
		end
	end)
	task.delay(SPAWN_FF_STRIP_SECONDS, function()
		if conn then
			conn:Disconnect()
		end
	end)
end

local function buildLeaderboardData(state)
	local bluePlayers = {}
	local redPlayers = {}
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent then
			local team = state.playerTeams[p.UserId] or "Blue"
			local entry = {
				playerName = p.Name,
				name = p.Name,
				displayName = p.DisplayName,
				kills = state.playerKills[p.UserId] or 0,
				deaths = state.playerDeaths[p.UserId] or 0,
				assists = (state.playerAssists and state.playerAssists[p.UserId]) or 0,
			}
			if team == "Blue" then
				table.insert(bluePlayers, entry)
			else
				table.insert(redPlayers, entry)
			end
		end
	end
	table.sort(bluePlayers, function(a, b)
		return a.kills > b.kills
	end)
	table.sort(redPlayers, function(a, b)
		return a.kills > b.kills
	end)
	return bluePlayers, redPlayers
end

local function endMatch(state, winningTeam)
	if state.matchEnded then
		return
	end
	state.matchEnded = true
	print("[Combat] TDM match ended. Winning team: " .. TeamDisplayUtils.displayName(winningTeam))
	for _, conn in pairs(state.diedConnections) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	state.diedConnections = {}
	for _, conn in pairs(state.characterAddedConnections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	state.characterAddedConnections = {}
	EconomyServiceServer.ApplyMatchEndRewards(state.currentRoundPlayers, winningTeam, state.playerTeams)
	local bluePlayers, redPlayers = buildLeaderboardData(state)
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent and state.matchEndedRE then
			local payload = {
				winningTeam = winningTeam,
				myTeam = state.playerTeams[p.UserId] or "Blue",
				bluePlayers = bluePlayers,
				redPlayers = redPlayers,
			}
			state.matchEndedRE:FireClient(p, payload)
		end
	end
	task.delay(TDMConfig.LEADERBOARD_DURATION, function()
		state.currentRoundPlayers = {}
		if state.onRoundEndCallback then
			local cb = state.onRoundEndCallback
			state.onRoundEndCallback = nil
			cb()
		end
	end)
end

local function respawnPlayer(state, onPlayerDiedFn, player)
	player:LoadCharacter()
	task.defer(function()
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			stripRobloxSpawnForceFields(char)
			local cf = TDMSpawnStrategy.getSpawnCFrame(player, getTDMContext(state))
			char.HumanoidRootPart.CFrame = cf
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
				humanoid.Health = CombatConfig.DEFAULT_HEALTH
				local conn = humanoid.Died:Connect(function()
					onPlayerDiedFn(player)
				end)
				state.diedConnections[player.UserId] = conn
			end
		end
	end)
end

local function onPlayerDied(state, deadPlayer)
	if state.matchEnded then
		return
	end
	local uid = deadPlayer.UserId
	state.playerDeaths[uid] = (state.playerDeaths[uid] or 0) + 1
	local humanoid = deadPlayer.Character and deadPlayer.Character:FindFirstChildOfClass("Humanoid")
	local killerUserId = humanoid and humanoid:GetAttribute("LastDamagerUserId")
	if killerUserId and killerUserId ~= uid then
		local killerTeam = state.playerTeams[killerUserId]
		local deadTeam = state.playerTeams[uid]
		if killerTeam and deadTeam and killerTeam ~= deadTeam then
			state.playerKills[killerUserId] = (state.playerKills[killerUserId] or 0) + 1
			state.teamKills[killerTeam] = (state.teamKills[killerTeam] or 0) + 1
			CombatRemotes.sendEliminationNotice(state, killerUserId, deadPlayer)
			CombatRemotes.broadcastTeamScore(state)
			if state.teamKills[killerTeam] >= TDMConfig.KILL_LIMIT then
				endMatch(state, killerTeam)
				return
			end
		end
	end
	state.diedConnections[uid] = nil
	CombatRemotes.firePlayerDied(state, deadPlayer, TDMConfig.RESPAWN_DELAY)
	task.delay(TDMConfig.RESPAWN_DELAY, function()
		if state.matchEnded then
			return
		end
		for _, p in ipairs(state.currentRoundPlayers) do
			if p.UserId == uid and p.Parent then
				respawnPlayer(state, function(plr)
					onPlayerDied(state, plr)
				end, p)
				break
			end
		end
	end)
end

return {
	getTDMContext = getTDMContext,
	buildLeaderboardData = buildLeaderboardData,
	endMatch = endMatch,
	respawnPlayer = respawnPlayer,
	onPlayerDied = onPlayerDied,
	stripRobloxSpawnForceFields = stripRobloxSpawnForceFields,
}
