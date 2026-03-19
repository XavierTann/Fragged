--[[
	LobbyQueue
	Queue operations, countdown, and state building for the lobby.
]]

local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)

local function buildStateForPlayer(state, remotes, player)
	local userId = player.UserId
	local phase = state.playerPhase[userId] or LobbyConfig.PHASE.SHOP_LOBBY
	local waitingCount = #state.waitingQueue
	local result = {
		phase = phase,
		waitingCount = waitingCount,
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
	local payload = {
		phase = LobbyConfig.PHASE.WAITING_LOBBY,
		waitingCount = #state.waitingQueue,
		minPlayers = LobbyConfig.MIN_PLAYERS,
		maxPlayers = LobbyConfig.MAX_PLAYERS,
		matchStarting = state.matchStartingAt ~= nil,
		countdownEndTime = state.countdownEndTime,
		secondsRemaining = nil,
	}
	if state.countdownEndTime then
		payload.secondsRemaining = math.max(0, math.ceil(state.countdownEndTime - os.clock()))
	end
	for i = 1, #state.waitingQueue do
		local p = state.waitingQueue[i]
		if p and p.Parent then
			remotes.LobbyState:FireClient(p, payload)
		end
	end
end

local function removeFromWaitingQueue(state, player)
	for i = #state.waitingQueue, 1, -1 do
		if state.waitingQueue[i] == player then
			table.remove(state.waitingQueue, i)
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

local function sendToArena(state, remotes, teleportPlayerTo)
	if #state.waitingQueue < LobbyConfig.MIN_PLAYERS then
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
	local toSend = math.min(#state.waitingQueue, LobbyConfig.MAX_PLAYERS)
	print("[Lobby] Game starting – sending " .. toSend .. " player(s) to arena.")
	local players = {}
	for i = 1, toSend do
		players[i] = state.waitingQueue[1]
		table.remove(state.waitingQueue, 1)
	end
	for _, p in ipairs(players) do
		state.playerPhase[p.UserId] = LobbyConfig.PHASE.ARENA
		remotes.LobbyState:FireClient(p, {
			phase = LobbyConfig.PHASE.ARENA,
			waitingCount = 0,
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
		state.onArenaRoundStarted(players)
	end
end

local function addPlayerToWaitingLobby(state, remotes, teleportPlayerTo, player)
	local userId = player.UserId
	if isInLeaveCooldown(state, userId) then
		return false
	end
	local phase = state.playerPhase[userId]
	if phase == LobbyConfig.PHASE.WAITING_LOBBY then
		return true
	end
	if phase == LobbyConfig.PHASE.ARENA then
		return false
	end
	state.waitingQueue[#state.waitingQueue + 1] = player
	state.playerPhase[userId] = LobbyConfig.PHASE.WAITING_LOBBY
	remotes.TeleportToWaiting:FireClient(player)
	teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.LOBBY)
	remotes.LobbyState:FireClient(player, buildStateForPlayer(state, remotes, player))
	broadcastStateToWaiting(state, remotes)
	if not state.matchStartingAt and #state.waitingQueue >= LobbyConfig.MIN_PLAYERS then
		state.matchStartingAt = os.clock()
		state.countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
		print("[Lobby] Countdown started – " .. #state.waitingQueue .. " player(s) in waiting lobby (" .. tostring(LobbyConfig.ARENA_COUNTDOWN_SECONDS) .. "s).")
		broadcastStateToWaiting(state, remotes)
		startCountdownTick(state, remotes)
		task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, function()
			sendToArena(state, remotes, teleportPlayerTo)
		end)
	end
	return true
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
}
