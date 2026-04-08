--[[
	LobbyQueue
	Blue/red waiting queues, countdown, arena send with team assignments.
]]

local Players = game:GetService("Players")
local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)

local function maxQueueTeamDiff()
	return LobbyConfig.LOBBY_MAX_WAITING_QUEUE_TEAM_DIFF or 1
end

--[[
	True if one new player (not in either queue) joining `team` would stay within max imbalance.
]]
local function balanceAllowsNewJoinToTeam(state, team)
	local b = #state.waitingQueueBlue
	local r = #state.waitingQueueRed
	local maxDiff = maxQueueTeamDiff()
	if team == "Blue" then
		return math.abs((b + 1) - r) <= maxDiff
	end
	if team == "Red" then
		return math.abs(b - (r + 1)) <= maxDiff
	end
	return false
end

--[[
	Team with strictly more queued players, and the other team; nil if tied.
]]
local function strictFullerTeam(state)
	local b = #state.waitingQueueBlue
	local r = #state.waitingQueueRed
	if b > r then
		return "Blue", "Red"
	end
	if r > b then
		return "Red", "Blue"
	end
	return nil, nil
end

local function totalWaiting(state)
	return #state.waitingQueueBlue + #state.waitingQueueRed
end

local function canStartCountdown(state)
	local b, r = #state.waitingQueueBlue, #state.waitingQueueRed
	local minTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM or 2
	if b < minTeam or r < minTeam then
		return false
	end
	-- Match starts only when teams are equal (e.g. 2v2, 3v3); imbalance blocks countdown until the smaller team catches up.
	if b ~= r then
		return false
	end
	return true
end

local function playerQueuedTeam(state, player)
	for _, p in ipairs(state.waitingQueueBlue) do
		if p == player then
			return "Blue"
		end
	end
	for _, p in ipairs(state.waitingQueueRed) do
		if p == player then
			return "Red"
		end
	end
	return nil
end

--[[
	Queue counts after `player` leaves their current queue (if any) and joins `team`.
]]
local function projectedCountsIfPlayerMovesToTeam(state, player, team)
	local b = #state.waitingQueueBlue
	local r = #state.waitingQueueRed
	local q = playerQueuedTeam(state, player)
	if q == "Blue" then
		b = b - 1
	elseif q == "Red" then
		r = r - 1
	end
	if team == "Blue" then
		b = b + 1
	else
		r = r + 1
	end
	return b, r
end

--[[
	True if `player` may end up on `team` without exceeding max queue imbalance (same team is always ok).
]]
local function balanceAllowsPlayerJoinTeam(state, player, team)
	if team ~= "Blue" and team ~= "Red" then
		return false
	end
	if playerQueuedTeam(state, player) == team then
		return true
	end
	local b, r = projectedCountsIfPlayerMovesToTeam(state, player, team)
	return math.abs(b - r) <= maxQueueTeamDiff()
end

local function buildStateForPlayer(state, _remotes, player)
	local userId = player.UserId
	local phase = state.playerPhase[userId] or LobbyConfig.PHASE.SHOP_LOBBY
	local b, r = #state.waitingQueueBlue, #state.waitingQueueRed
	local result = {
		phase = phase,
		waitingCount = b + r,
		waitingCountBlue = b,
		waitingCountRed = r,
		queuedTeam = playerQueuedTeam(state, player),
		minPlayers = LobbyConfig.MIN_PLAYERS,
		minPlayersPerTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM,
		maxPlayers = LobbyConfig.MAX_PLAYERS,
		matchStarting = state.matchStartingAt ~= nil,
		countdownEndTime = state.countdownEndTime,
		secondsRemaining = nil,
	}
	if state.countdownEndTime then
		result.secondsRemaining = math.max(0, math.ceil(state.countdownEndTime - os.clock()))
	end
	return result
end

--[[
	Push LobbyState to every player in shop or waiting lobby (not arena).
	Queue counts / "players needed" must stay in sync for shoppers on pads and off.
	LobbyMatchCountdown only goes to players actually in a queue (toast + teleport flow).
]]
local function broadcastStateToWaiting(state, remotes)
	local seen = {}
	local function sendToLobbyClient(p)
		if not p or not p.Parent or seen[p] then
			return
		end
		local phase = state.playerPhase[p.UserId]
		if phase == LobbyConfig.PHASE.ARENA then
			return
		end
		seen[p] = true
		remotes.LobbyState:FireClient(p, buildStateForPlayer(state, remotes, p))
		if state.matchStartingAt and state.countdownEndTime and remotes.LobbyMatchCountdown and playerQueuedTeam(state, p) then
			local sec = math.max(0, math.ceil(state.countdownEndTime - os.clock()))
			remotes.LobbyMatchCountdown:FireClient(p, sec)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		sendToLobbyClient(p)
	end
end

local function removeFromWaitingQueue(state, player)
	for i = #state.waitingQueueBlue, 1, -1 do
		if state.waitingQueueBlue[i] == player then
			table.remove(state.waitingQueueBlue, i)
			break
		end
	end
	for i = #state.waitingQueueRed, 1, -1 do
		if state.waitingQueueRed[i] == player then
			table.remove(state.waitingQueueRed, i)
			break
		end
	end
	state.playerPhase[player.UserId] = LobbyConfig.PHASE.SHOP_LOBBY
end

local function cancelCountdown(state, remotes)
	if state.countdownTickConnection then
		task.cancel(state.countdownTickConnection)
		state.countdownTickConnection = nil
	end
	state.matchStartingAt = nil
	state.countdownEndTime = nil
	broadcastStateToWaiting(state, remotes)
end

local function startCountdownTick(state, remotes)
	if state.countdownTickConnection then
		return
	end
	state.countdownTickConnection = task.spawn(function()
		while state.matchStartingAt and state.countdownEndTime and os.clock() < state.countdownEndTime do
			task.wait(1)
			if not state.matchStartingAt then
				break
			end
			broadcastStateToWaiting(state, remotes)
		end
		state.countdownTickConnection = nil
	end)
end

local function isInLeaveCooldown(state, userId)
	local t = state.lastLeftWaitingAt[userId]
	if not t then
		return false
	end
	if os.clock() - t < (LobbyConfig.LEAVE_WAITING_COOLDOWN_SECONDS or 2) then
		return true
	end
	state.lastLeftWaitingAt[userId] = nil
	return false
end

-- Pop up to MAX_PLAYERS alternating blue/red; drain remainder from whichever queue has players.
local function takePlayersForArena(state)
	local players = {}
	local teamByUserId = {}
	local preferBlue = true
	local maxP = LobbyConfig.MAX_PLAYERS or 8

	local function popNext()
		if preferBlue and #state.waitingQueueBlue > 0 then
			return table.remove(state.waitingQueueBlue, 1), "Blue"
		end
		if not preferBlue and #state.waitingQueueRed > 0 then
			return table.remove(state.waitingQueueRed, 1), "Red"
		end
		if #state.waitingQueueBlue > 0 then
			return table.remove(state.waitingQueueBlue, 1), "Blue"
		end
		if #state.waitingQueueRed > 0 then
			return table.remove(state.waitingQueueRed, 1), "Red"
		end
		return nil, nil
	end

	while #players < maxP do
		local p, team = popNext()
		if not p then
			break
		end
		if p.Parent then
			players[#players + 1] = p
			teamByUserId[p.UserId] = team
		end
		preferBlue = not preferBlue
	end
	return players, teamByUserId
end

local function sendToArena(state, remotes, teleportPlayerTo)
	if not canStartCountdown(state) then
		cancelCountdown(state, remotes)
		return
	end
	if state.countdownEndTime and os.clock() < state.countdownEndTime - 0.05 then
		local waitTime = state.countdownEndTime - os.clock()
		task.delay(waitTime, function()
			sendToArena(state, remotes, teleportPlayerTo)
		end)
		return
	end
	local players, teamByUserId = takePlayersForArena(state)
	if #players == 0 then
		cancelCountdown(state, remotes)
		return
	end
	for _, p in ipairs(players) do
		state.playerPhase[p.UserId] = LobbyConfig.PHASE.ARENA
		remotes.LobbyState:FireClient(p, {
			phase = LobbyConfig.PHASE.ARENA,
			waitingCount = 0,
			waitingCountBlue = 0,
			waitingCountRed = 0,
			queuedTeam = nil,
			minPlayers = LobbyConfig.MIN_PLAYERS,
			minPlayersPerTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM,
			maxPlayers = LobbyConfig.MAX_PLAYERS,
			matchStarting = false,
			countdownEndTime = nil,
		})
		remotes.TeleportToArena:FireClient(p)
	end
	state.matchStartingAt = nil
	state.countdownEndTime = nil
	broadcastStateToWaiting(state, remotes)
	if state.onArenaRoundStarted then
		state.onArenaRoundStarted(players, teamByUserId)
	end
end

local function tryBeginCountdown(state, remotes)
	if state.matchStartingAt then
		return
	end
	if not canStartCountdown(state) then
		return
	end
	state.matchStartingAt = os.clock()
	state.countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
	broadcastStateToWaiting(state, remotes)
	startCountdownTick(state, remotes)
	task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, function()
		sendToArena(state, remotes, state.teleportPlayerToForArena)
	end)
end

local function maybeCancelCountdown(state, remotes)
	if state.matchStartingAt and not canStartCountdown(state) then
		cancelCountdown(state, remotes)
	end
end

--[[
	Add player to blue or red queue. skipTeleport: do not move character (pad join).
]]
local function addPlayerToTeamQueue(state, remotes, teleportPlayerTo, player, team, skipTeleport)
	local userId = player.UserId
	local blockUntil = state.joinQueueBlockedUntil[userId]
	if blockUntil and os.clock() < blockUntil then
		return false
	end
	if isInLeaveCooldown(state, userId) then
		return false
	end
	local phase = state.playerPhase[userId]
	if phase == LobbyConfig.PHASE.ARENA then
		return false
	end
	if team ~= "Blue" and team ~= "Red" then
		return false
	end
	local cap = LobbyConfig.MAX_PLAYERS_PER_TEAM or 6
	local onBlue = playerQueuedTeam(state, player) == "Blue"
	local onRed = playerQueuedTeam(state, player) == "Red"
	if (team == "Blue" and onBlue) or (team == "Red" and onRed) then
		return true
	end
	if not balanceAllowsPlayerJoinTeam(state, player, team) then
		return false
	end
	if onBlue or onRed then
		removeFromWaitingQueue(state, player)
	end
	local q = team == "Blue" and state.waitingQueueBlue or state.waitingQueueRed
	if #q >= cap then
		return false
	end
	q[#q + 1] = player
	state.playerPhase[userId] = LobbyConfig.PHASE.WAITING_LOBBY
	if not skipTeleport then
		remotes.TeleportToWaiting:FireClient(player)
		if teleportPlayerTo then
			teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.LOBBY)
		end
	end
	remotes.LobbyState:FireClient(player, buildStateForPlayer(state, remotes, player))
	broadcastStateToWaiting(state, remotes)
	tryBeginCountdown(state, remotes)
	return true
end

local function addPlayerToWaitingLobby(state, remotes, teleportPlayerTo, player)
	return addPlayerToTeamQueue(state, remotes, teleportPlayerTo, player, "Blue", false)
end

return {
	buildStateForPlayer = buildStateForPlayer,
	broadcastStateToWaiting = broadcastStateToWaiting,
	removeFromWaitingQueue = removeFromWaitingQueue,
	cancelCountdown = cancelCountdown,
	startCountdownTick = startCountdownTick,
	isInLeaveCooldown = isInLeaveCooldown,
	sendToArena = sendToArena,
	addPlayerToWaitingLobby = addPlayerToWaitingLobby,
	addPlayerToTeamQueue = addPlayerToTeamQueue,
	playerQueuedTeam = playerQueuedTeam,
	totalWaiting = totalWaiting,
	canStartCountdown = canStartCountdown,
	maybeCancelCountdown = maybeCancelCountdown,
	tryBeginCountdown = tryBeginCountdown,
	balanceAllowsNewJoinToTeam = balanceAllowsNewJoinToTeam,
	balanceAllowsPlayerJoinTeam = balanceAllowsPlayerJoinTeam,
	strictFullerTeam = strictFullerTeam,
	maxQueueTeamDiff = maxQueueTeamDiff,
}
