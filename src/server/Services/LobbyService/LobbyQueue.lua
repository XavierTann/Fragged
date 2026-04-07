--[[
	LobbyQueue
	Blue/red waiting queues, countdown, arena send with team assignments.
]]

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)

local function totalWaiting(state)
	return #state.waitingQueueBlue + #state.waitingQueueRed
end

local function requiresBothTeamsForStart()
	if LobbyConfig.REQUIRE_BOTH_TEAMS_TO_START == false then
		return false
	end
	return true
end

local function canStartCountdown(state)
	local b, r = #state.waitingQueueBlue, #state.waitingQueueRed
	local t = b + r
	if t < (LobbyConfig.MIN_PLAYERS or 2) then
		return false
	end
	if requiresBothTeamsForStart() then
		if b < 1 or r < 1 then
			return false
		end
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

local function broadcastStateToWaiting(state, remotes)
	local seen = {}
	for _, p in ipairs(state.waitingQueueBlue) do
		if p and p.Parent and not seen[p] then
			seen[p] = true
			remotes.LobbyState:FireClient(p, buildStateForPlayer(state, remotes, p))
		end
	end
	for _, p in ipairs(state.waitingQueueRed) do
		if p and p.Parent and not seen[p] then
			seen[p] = true
			remotes.LobbyState:FireClient(p, buildStateForPlayer(state, remotes, p))
		end
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
	if onBlue or onRed then
		if (team == "Blue" and onBlue) or (team == "Red" and onRed) then
			return true
		end
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
}
