--[[
	Lobby configuration: Shop Lobby -> (portal) -> Waiting Lobby -> (enough players) -> Arena.
]]

return {
	-- Waiting lobby: min players before match can start, max per match
	-- MIN_PLAYERS = 2,
	-- DEBUG
	MIN_PLAYERS = 1,
	MAX_PLAYERS = 8,

	-- Countdown (seconds) in waiting lobby before teleporting to arena
	-- ARENA_COUNTDOWN_SECONDS = 5,
	-- DEBUG
	ARENA_COUNTDOWN_SECONDS = 1,

	-- Seconds to ignore portal/join after leaving waiting lobby (prevents instant re-enter when teleporting to shop)
	LEAVE_WAITING_COOLDOWN_SECONDS = 2,

	-- Remote folder and event names
	REMOTE_FOLDER_NAME = "LobbyRemotes",
	REMOTES = {
		JOIN_WAITING_LOBBY = "JoinWaitingLobby",
		LEAVE_WAITING_LOBBY = "LeaveWaitingLobby",
		GET_LOBBY_STATE = "GetLobbyState",
		LOBBY_STATE = "LobbyState",
		TELEPORT_TO_WAITING = "TeleportToWaiting",
		TELEPORT_TO_ARENA = "TeleportToArena",
		TELEPORT_TO_SHOP = "TeleportToShop",
	},

	-- Phases for UI/state
	PHASE = {
		SHOP_LOBBY = "ShopLobby",
		WAITING_LOBBY = "WaitingLobby",
		ARENA = "Arena",
	},

	-- Workspace folder: SpawnLocations (ShopSpawnLocation, LobbySpawnLocation, BlueTeamSpawnLocation, RedTeamSpawnLocation for orange team)
	SPAWNS_FOLDER_NAME = "SpawnLocations",
	SPAWN_NAMES = {
		SHOP = "ShopSpawnLocation",
		LOBBY = "LobbySpawnLocation",
		RED_TEAM = "RedTeamSpawnLocation",
		BLUE_TEAM = "BlueTeamSpawnLocation",
	},
}
