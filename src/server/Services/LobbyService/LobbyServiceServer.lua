--[[
	LobbyService (server)
	Flow: Shop Lobby -> (Find match) -> Waiting Lobby -> Arena -> Shop Lobby.
	Module returns a table with Init and public API. All event/remote setup runs in Init().
]]

local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local LobbySpawns = require(script.Parent.LobbySpawns)
local LobbyRemotes = require(script.Parent.LobbyRemotes)
local LobbyState = require(script.Parent.LobbyState)
local LobbyQueue = require(script.Parent.LobbyQueue)

local state = nil
local remotes = nil

local function bindRemoteHandlers()
	remotes.JoinWaitingLobby.OnServerInvoke = function(player)
		if LobbyQueue.isInLeaveCooldown(state, player.UserId) then
			return { success = false, error = "Please wait a moment" }
		end
		local phase = state.playerPhase[player.UserId]
		if phase == LobbyConfig.PHASE.WAITING_LOBBY then
			return { success = true, state = LobbyQueue.buildStateForPlayer(state, remotes, player) }
		end
		if phase == LobbyConfig.PHASE.ARENA then
			return { success = false, error = "Already in a match" }
		end
		state.waitingQueue[#state.waitingQueue + 1] = player
		state.playerPhase[player.UserId] = LobbyConfig.PHASE.WAITING_LOBBY
		remotes.TeleportToWaiting:FireClient(player)
		LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.LOBBY)
		local lobbyState = LobbyQueue.buildStateForPlayer(state, remotes, player)
		remotes.LobbyState:FireClient(player, lobbyState)
		LobbyQueue.broadcastStateToWaiting(state, remotes)
		if not state.matchStartingAt and #state.waitingQueue >= LobbyConfig.MIN_PLAYERS then
			state.matchStartingAt = os.clock()
			state.countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
			print("[Lobby] Countdown started – " .. #state.waitingQueue .. " player(s) in waiting lobby (" .. tostring(LobbyConfig.ARENA_COUNTDOWN_SECONDS) .. "s).")
			LobbyQueue.broadcastStateToWaiting(state, remotes)
			LobbyQueue.startCountdownTick(state, remotes)
			task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, function()
				LobbyQueue.sendToArena(state, remotes, LobbySpawns.teleportPlayerTo)
			end)
		end
		return { success = true, state = lobbyState }
	end

	remotes.LeaveWaitingLobby.OnServerEvent:Connect(function(player)
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.WAITING_LOBBY then
			return
		end
		state.lastLeftWaitingAt[player.UserId] = os.clock()
		LobbyQueue.removeFromWaitingQueue(state, player)
		if state.matchStartingAt and #state.waitingQueue < LobbyConfig.MIN_PLAYERS then
			LobbyQueue.cancelCountdown(state, remotes)
		end
		remotes.TeleportToShop:FireClient(player)
		LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
		remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
		LobbyQueue.broadcastStateToWaiting(state, remotes)
	end)

	remotes.GetLobbyState.OnServerInvoke = function(player)
		return LobbyQueue.buildStateForPlayer(state, remotes, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		LobbyQueue.removeFromWaitingQueue(state, player)
		state.playerPhase[player.UserId] = nil
		if state.matchStartingAt and #state.waitingQueue < LobbyConfig.MIN_PLAYERS then
			LobbyQueue.cancelCountdown(state, remotes)
		end
		LobbyQueue.broadcastStateToWaiting(state, remotes)
	end)
end

local function setupPlayerSpawn()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local phase = state.playerPhase[player.UserId] or LobbyConfig.PHASE.SHOP_LOBBY
			if phase == LobbyConfig.PHASE.SHOP_LOBBY then
				task.defer(function()
					LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
				end)
			end
		end)
		if player.Character then
			local phase = state.playerPhase[player.UserId] or LobbyConfig.PHASE.SHOP_LOBBY
			if phase == LobbyConfig.PHASE.SHOP_LOBBY then
				task.defer(function()
					LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
				end)
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			if player.Character and (not state.playerPhase[player.UserId] or state.playerPhase[player.UserId] == LobbyConfig.PHASE.SHOP_LOBBY) then
				LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
			end
		end)
	end
end

return {
	Init = function(onRoundStartedCallback)
		state = LobbyState()
		state.onArenaRoundStarted = onRoundStartedCallback
		remotes = LobbyRemotes.ensureRemotes()
		LobbySpawns.configureSpawnLocations()
		bindRemoteHandlers()
		setupPlayerSpawn()
	end,

	AddPlayerToWaitingLobby = function(player)
		return LobbyQueue.addPlayerToWaitingLobby(state, remotes, LobbySpawns.teleportPlayerTo, player)
	end,

	ReturnPlayerToShop = function(player)
		state.playerPhase[player.UserId] = LobbyConfig.PHASE.SHOP_LOBBY
		remotes.TeleportToShop:FireClient(player)
		LobbySpawns.teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
		remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
	end,

	GetPhase = function(userId)
		return state.playerPhase[userId] or LobbyConfig.PHASE.SHOP_LOBBY
	end,
}
