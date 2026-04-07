--[[
	LobbyServiceClient
	Flow: Shop Lobby -> stand on team pad -> Waiting Lobby -> Arena -> Shop Lobby.
	Module returns a table with Init and public API. Remote bindings run in Init().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local LobbyMatchStartToastClient = require(ReplicatedStorage.Shared.Services.LobbyMatchStartToastClient)

-- State and refs (remotes set in Init)
local currentState = nil
local callbacks = {}
local JoinWaitingRF = nil
local LeaveWaitingRE = nil
local GetStateRF = nil
local LobbyStateRE = nil
local TeleportToWaitingRE = nil
local TeleportToArenaRE = nil
local TeleportToShopRE = nil

-- Public API
return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(LobbyConfig.REMOTE_FOLDER_NAME)
		JoinWaitingRF = folder:WaitForChild(LobbyConfig.REMOTES.JOIN_WAITING_LOBBY)
		LeaveWaitingRE = folder:WaitForChild(LobbyConfig.REMOTES.LEAVE_WAITING_LOBBY)
		GetStateRF = folder:WaitForChild(LobbyConfig.REMOTES.GET_LOBBY_STATE)
		LobbyStateRE = folder:WaitForChild(LobbyConfig.REMOTES.LOBBY_STATE)
		local lobbyMatchCountdownRE = folder:WaitForChild(LobbyConfig.REMOTES.LOBBY_MATCH_COUNTDOWN)
		if lobbyMatchCountdownRE:IsA("RemoteEvent") then
			lobbyMatchCountdownRE.OnClientEvent:Connect(function(sec)
				LobbyMatchStartToastClient.OnMatchCountdown(sec)
			end)
		end
		TeleportToWaitingRE = folder:WaitForChild(LobbyConfig.REMOTES.TELEPORT_TO_WAITING)
		TeleportToArenaRE = folder:WaitForChild(LobbyConfig.REMOTES.TELEPORT_TO_ARENA)
		TeleportToShopRE = folder:WaitForChild(LobbyConfig.REMOTES.TELEPORT_TO_SHOP)

		LobbyStateRE.OnClientEvent:Connect(function(state)
			currentState = state
			LobbyMatchStartToastClient.ApplyLobbyState(state)
			for _, cb in ipairs(callbacks) do
				task.spawn(cb, state)
			end
		end)
	end,

	GetState = function()
		if currentState then
			return currentState
		end
		if not GetStateRF then
			return nil
		end
		local ok, state = pcall(function()
			return GetStateRF:InvokeServer()
		end)
		if ok and state then
			currentState = state
		end
		return currentState
	end,

	Subscribe = function(cb)
		callbacks[#callbacks + 1] = cb
		if currentState then
			task.spawn(cb, currentState)
		end
	end,

	JoinWaitingLobby = function()
		if not JoinWaitingRF then
			return { success = false, error = LobbyConfig.TEXT.CLIENT_LOBBY_NOT_INITIALIZED }
		end
		return JoinWaitingRF:InvokeServer()
	end,

	LeaveWaitingLobby = function()
		if LeaveWaitingRE then
			LeaveWaitingRE:FireServer()
		end
	end,

	OnTeleportToWaiting = function(cb)
		if TeleportToWaitingRE then
			TeleportToWaitingRE.OnClientEvent:Connect(cb)
		end
	end,

	OnTeleportToArena = function(cb)
		if TeleportToArenaRE then
			TeleportToArenaRE.OnClientEvent:Connect(cb)
		end
	end,

	OnTeleportToShop = function(cb)
		if TeleportToShopRE then
			TeleportToShopRE.OnClientEvent:Connect(cb)
		end
	end,

	PHASE = LobbyConfig.PHASE,
	MIN_PLAYERS = LobbyConfig.MIN_PLAYERS,
	MAX_PLAYERS = LobbyConfig.MAX_PLAYERS,
	ARENA_COUNTDOWN_SECONDS = LobbyConfig.ARENA_COUNTDOWN_SECONDS,
}
