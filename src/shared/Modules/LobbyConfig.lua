--[[
	Lobby configuration: Shop Lobby -> stand on team pad in Lobby -> Waiting -> Arena.
	Workspace.Lobby.SpawnPads: one Model named BluePad and one named RedPad (shared team pads).
]]

return {
	-- Waiting lobby: min total queued players before countdown; max sent to one arena match
	MIN_PLAYERS = 2,
	MAX_PLAYERS = 8,
	-- True = need at least one on blue pads and one on red pads before countdown (TDM).
	REQUIRE_BOTH_TEAMS_TO_START = true,
	-- Max players per team in the waiting queues (not tied to number of physical pads).
	MAX_PLAYERS_PER_TEAM = 6,
	-- One pad per team: many players can stand on the same pad to queue; no per-pad "slot" occupancy.
	LOBBY_SHARED_TEAM_PADS = true,
	-- Waiting queues: |blueCount - redCount| must never exceed this (after adding one player to a team).
	LOBBY_MAX_WAITING_QUEUE_TEAM_DIFF = 1,

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
		-- Server -> client: otherTeam ("Blue"|"Red") — need someone on that team before more can queue on fuller pad
		TEAM_QUEUE_BALANCE_TOAST = "TeamQueueBalanceToast",
		-- Server -> client: arena lobby countdown seconds (3,2,1,0); plain number, no table replication issues
		LOBBY_MATCH_COUNTDOWN = "LobbyMatchCountdown",
	},

	-- Phases for UI/state
	PHASE = {
		SHOP_LOBBY = "ShopLobby",
		WAITING_LOBBY = "WaitingLobby",
		ARENA = "Arena",
	},

	-- Workspace folder: SpawnLocations (ShopSpawnLocation, LobbySpawnLocation, BlueTeamSpawnLocation, RedTeamSpawnLocation)
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
	-- When LOBBY_SHARED_TEAM_PADS is false: server sets queued player's UserId on that pad (one player per pad).
	LOBBY_PAD_OCCUPANT_USER_ID_ATTRIBUTE = "LobbyPadOccupantUserId",
	-- Client-only pulse on LightBeam transparency under each pad model
	LOBBY_LIGHTBEAM_PULSE_SPEED = 1.5,
	LOBBY_LIGHTBEAM_TRANSPARENCY_MIN = 0.4,
	LOBBY_LIGHTBEAM_TRANSPARENCY_MAX = 0.88,
	-- How often to test HRP vs pad model bounds (seconds)
	LOBBY_PAD_POLL_INTERVAL = 0.2,
	-- Min seconds between team-queue balance toasts per player (fuller-team pad)
	LOBBY_TEAM_QUEUE_BALANCE_TOAST_COOLDOWN = 5,

	-- Player-facing copy (UI, toasts, server join errors). Use string.format where noted.
	TEXT = {
		-- JoinWaitingLobby RemoteFunction when not on a pad
		JOIN_WAITING_STAND_ON_PAD_ERROR = "Stand on a blue or red pad in the lobby to join the match queue.",
		-- LobbyServiceClient when remotes are not ready
		CLIENT_LOBBY_NOT_INITIALIZED = "Not initialized",

		-- Single lobby UI (shop + queue share one panel; server still uses SHOP_LOBBY / WAITING_LOBBY phases).
		LOBBY_PANEL_TITLE = "Lobby",
		-- string.format(count, minPlayers) — queue block placeholder before first refresh
		LOBBY_QUEUE_COUNT_INITIAL = "Players: %d / %d\n",
		-- string.format(total, blue, red) — then status lines + LOBBY_QUEUE_YOU_SUFFIX
		LOBBY_QUEUE_HEADER = "Queued: %d (Blue %d · Red %d).\n",
		-- Below MIN_PLAYERS total in queue — %s = team phrase from LobbyGUI (smaller queue, or both if tied)
		LOBBY_QUEUE_STATUS_NEED_MORE_TOTAL_ONE = "1 more player needs to join the %s before the round can start!\n",
		LOBBY_QUEUE_STATUS_NEED_MORE_TOTAL_MANY = "%d more players need to join the %s before the round can start!\n",
		-- REQUIRE_BOTH_TEAMS_TO_START (string.format with TeamDisplayUtils.displayName)
		LOBBY_QUEUE_STATUS_NEED_ON_TEAM = "At least one player needs to join the %s team!\n",
		-- string.format(teamId) — teamId is "Blue" or "Red"
		LOBBY_QUEUE_YOU_SUFFIX = "You are on the %s team.\n",

		-- string.format(seconds)
		MATCH_STARTING_IN = "Match starting in %d...",
		MATCH_STARTING = "Match starting...",

		-- string.format(otherTeamDisplayName) — fuller pad is over capacity vs other team
		TEAM_QUEUE_BALANCE_TOAST = "One player needs to join the %s team before more can queue here.",
	},
}
