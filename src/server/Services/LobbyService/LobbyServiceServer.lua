--[[
	LobbyService (server)
	Flow: Lobby -> stand on blue/red pad -> Waiting -> Arena -> Lobby.
	Module returns a table with Init and public API. All event/remote setup runs in Init().
]]

local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local LobbySpawns = require(script.Parent.LobbySpawns)
local LobbyRemotes = require(script.Parent.LobbyRemotes)
local LobbyState = require(script.Parent.LobbyState)
local LobbyQueue = require(script.Parent.LobbyQueue)
local LobbyPadZones = require(script.Parent.LobbyPadZones)

local state = nil
local remotes = nil

local function bindRemoteHandlers()
	remotes.JoinWaitingLobby.OnServerInvoke = function(player)
		return {
			success = false,
			error = LobbyConfig.TEXT.JOIN_WAITING_STAND_ON_PAD_ERROR,
			state = LobbyQueue.buildStateForPlayer(state, remotes, player),
		}
	end

	remotes.LeaveWaitingLobby.OnServerEvent:Connect(function(player)
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.WAITING_LOBBY then
			return
		end
		state.lastLeftWaitingAt[player.UserId] = os.clock()
		state.joinQueueBlockedUntil[player.UserId] = os.clock() + (LobbyConfig.LEAVE_WAITING_COOLDOWN_SECONDS or 2)
		LobbyQueue.removeFromWaitingQueue(state, player)
		LobbyPadZones.clearPadOccupantForUser(player.UserId)
		LobbyQueue.maybeCancelCountdown(state, remotes)
		remotes.TeleportToLobby:FireClient(player)
		LobbySpawns.teleportPlayerTo(player, LobbyConfig.LOBBY_SPAWN_NAME)
		remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
		LobbyQueue.broadcastStateToWaiting(state, remotes)
	end)

	remotes.GetLobbyState.OnServerInvoke = function(player)
		return LobbyQueue.buildStateForPlayer(state, remotes, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		LobbyQueue.removeFromWaitingQueue(state, player)
		LobbyPadZones.clearPadOccupantForUser(player.UserId)
		state.playerPhase[player.UserId] = nil
		state.joinQueueBlockedUntil[player.UserId] = nil
		state.teamQueueBalanceToastCooldown[player.UserId] = nil
		LobbyQueue.maybeCancelCountdown(state, remotes)
		LobbyQueue.broadcastStateToWaiting(state, remotes)
	end)
end

local function setupPlayerSpawn()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local phase = state.playerPhase[player.UserId] or LobbyConfig.PHASE.LOBBY
			if phase == LobbyConfig.PHASE.LOBBY then
				task.defer(function()
					LobbySpawns.teleportPlayerTo(player, LobbyConfig.LOBBY_SPAWN_NAME)
				end)
			end
		end)
		if player.Character then
			local phase = state.playerPhase[player.UserId] or LobbyConfig.PHASE.LOBBY
			if phase == LobbyConfig.PHASE.LOBBY then
				task.defer(function()
					LobbySpawns.teleportPlayerTo(player, LobbyConfig.LOBBY_SPAWN_NAME)
				end)
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			if player.Character and (not state.playerPhase[player.UserId] or state.playerPhase[player.UserId] == LobbyConfig.PHASE.LOBBY) then
				LobbySpawns.teleportPlayerTo(player, LobbyConfig.LOBBY_SPAWN_NAME)
			end
		end)
	end
end

return {
	Init = function(onRoundStartedCallback)
		state = LobbyState()
		state.onArenaRoundStarted = onRoundStartedCallback
		state.teleportPlayerToForArena = LobbySpawns.teleportPlayerTo
		remotes = LobbyRemotes.ensureRemotes()
		LobbySpawns.configureSpawnLocations()
		bindRemoteHandlers()
		setupPlayerSpawn()
		LobbyPadZones.Init(state, remotes, LobbySpawns.teleportPlayerTo)
	end,

	AddPlayerToWaitingLobby = function(player)
		return LobbyQueue.addPlayerToWaitingLobby(state, remotes, LobbySpawns.teleportPlayerTo, player)
	end,

	ReturnPlayerToLobby = function(player)
		state.playerPhase[player.UserId] = LobbyConfig.PHASE.LOBBY
		remotes.TeleportToLobby:FireClient(player)
		LobbySpawns.teleportPlayerTo(player, LobbyConfig.LOBBY_SPAWN_NAME)
		remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
	end,

	GetPhase = function(userId)
		return state.playerPhase[userId] or LobbyConfig.PHASE.LOBBY
	end,

	SetPlayerPhase = function(userId, phase)
		state.playerPhase[userId] = phase
	end,
}
