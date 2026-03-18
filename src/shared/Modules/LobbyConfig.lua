--[[
	Lobby configuration: Shop Lobby -> (portal) -> Waiting Lobby -> (enough players) -> Arena.
]]

return {
	-- Waiting lobby: min players before match can start, max per match
	MIN_PLAYERS = 2,
	MAX_PLAYERS = 8,

	-- Countdown (seconds) in waiting lobby before teleporting to arena
	ARENA_COUNTDOWN_SECONDS = 5,

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

	-- Workspace folder name for spawn points (create LobbySpawns.WaitingLobby, LobbySpawns.Arena, LobbySpawns.Shop in workspace)
	SPAWNS_FOLDER_NAME = "LobbySpawns",
	SPAWN_NAMES = {
		SHOP = "Shop",
		WAITING = "WaitingLobby",
		ARENA = "Arena",
		ARENA_BLUE = "ArenaBlue",
		ARENA_RED = "ArenaRed",
	},
}
