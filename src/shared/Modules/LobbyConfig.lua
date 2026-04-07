--[[
	Lobby configuration: Shop Lobby -> stand on team pad in Lobby -> Waiting -> Arena.
	Workspace.Lobby.SpawnPads: Models named BluePad (x6) and RedPad (x6).
]]

return {
	-- Waiting lobby: min total queued players before countdown; max sent to one arena match
	MIN_PLAYERS = 2,
	MAX_PLAYERS = 8,
	-- True = need at least one on blue pads and one on red pads before countdown (TDM).
	REQUIRE_BOTH_TEAMS_TO_START = true,
	-- Max players per team in the waiting queues (matches 6 blue + 6 red pads).
	MAX_PLAYERS_PER_TEAM = 6,

	-- Countdown (seconds) in waiting lobby before teleporting to arena
	ARENA_COUNTDOWN_SECONDS = 3,

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

	-- Workspace/Lobby/SpawnPads — direct child Models with these exact names
	LOBBY_PADS_FOLDER_PATH = { "Lobby", "SpawnPads" },
	LOBBY_BLUE_PAD_MODEL_NAME = "BluePad",
	LOBBY_RED_PAD_MODEL_NAME = "RedPad",
	LOBBY_LIGHTBEAM_PART_NAME = "LightBeam",
	-- Client-only pulse on LightBeam transparency under each pad model
	LOBBY_LIGHTBEAM_PULSE_SPEED = 1.5,
	LOBBY_LIGHTBEAM_TRANSPARENCY_MIN = 0.4,
	LOBBY_LIGHTBEAM_TRANSPARENCY_MAX = 0.88,
	-- How often to test HRP vs pad model bounds (seconds)
	LOBBY_PAD_POLL_INTERVAL = 0.2,
}
