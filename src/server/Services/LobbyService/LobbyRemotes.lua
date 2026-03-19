--[[
	LobbyRemotes
	Remote creation for client-server lobby communication.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(LobbyConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LobbyConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local function remote(name, className)
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	return {
		JoinWaitingLobby = remote(LobbyConfig.REMOTES.JOIN_WAITING_LOBBY, "RemoteFunction"),
		LeaveWaitingLobby = remote(LobbyConfig.REMOTES.LEAVE_WAITING_LOBBY, "RemoteEvent"),
		GetLobbyState = remote(LobbyConfig.REMOTES.GET_LOBBY_STATE, "RemoteFunction"),
		LobbyState = remote(LobbyConfig.REMOTES.LOBBY_STATE, "RemoteEvent"),
		TeleportToWaiting = remote(LobbyConfig.REMOTES.TELEPORT_TO_WAITING, "RemoteEvent"),
		TeleportToArena = remote(LobbyConfig.REMOTES.TELEPORT_TO_ARENA, "RemoteEvent"),
		TeleportToShop = remote(LobbyConfig.REMOTES.TELEPORT_TO_SHOP, "RemoteEvent"),
	}
end

return {
	ensureRemotes = ensureRemotes,
}
