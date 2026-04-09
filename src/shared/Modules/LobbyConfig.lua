--[[
	Lobby configuration: main lobby (pre-arena) -> stand on team pad -> waiting -> arena.
	Workspace.Lobby.SpawnPads: BluePad and RedPad (shared team pads).
]]

return {
	-- When > 1: both teams need ≥ MIN_PLAYERS_PER_TEAM and equal counts. When 1: one team may queue alone for solo playtests.
	MIN_PLAYERS = 1,
	-- Each team must have at least this many queued before a match can start (in addition to equal counts).
	MIN_PLAYERS_PER_TEAM = 1,
	MAX_PLAYERS = 8,
	-- Max players per team in the waiting queues (not tied to number of physical pads).
	MAX_PLAYERS_PER_TEAM = 6,
	-- One pad per team: many players can stand on the same pad to queue; no per-pad "slot" occupancy.
	LOBBY_SHARED_TEAM_PADS = true,
	-- Waiting queues: |blueCount - redCount| must never exceed this (after adding one player to a team).
	LOBBY_MAX_WAITING_QUEUE_TEAM_DIFF = 1,

	-- Countdown (seconds) in waiting lobby before teleporting to arena
	ARENA_COUNTDOWN_SECONDS = 3,

	-- Seconds to ignore portal/join after leaving waiting lobby (prevents instant re-enter when teleporting back to main lobby)
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
		TELEPORT_TO_LOBBY = "TeleportToLobby",
		-- Server -> client: otherTeam ("Blue"|"Red") — need someone on that team before more can queue on fuller pad
		TEAM_QUEUE_BALANCE_TOAST = "TeamQueueBalanceToast",
		-- Server -> client: arena lobby countdown seconds (3,2,1,0); plain number, no table replication issues
		LOBBY_MATCH_COUNTDOWN = "LobbyMatchCountdown",
	},

	-- Phases for UI/state (replicated to clients on LobbyState)
	PHASE = {
		LOBBY = "Lobby",
		WAITING_LOBBY = "WaitingLobby",
		ARENA = "Arena",
	},

	-- Workspace folder: SpawnLocations (LobbySpawnLocation, BlueTeamSpawnLocation, RedTeamSpawnLocation)
	SPAWNS_FOLDER_NAME = "SpawnLocations",
	SPAWN_NAMES = {
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
	-- Workspace/Lobby/SpawnPads — 3D SurfaceGui hosts (siblings of BluePad/RedPad models)
	LOBBY_BLUE_PAD_SCREEN_NAME = "BluePadScreen",
	LOBBY_RED_PAD_SCREEN_NAME = "RedPadScreen",
	LOBBY_PAD_SCREEN_FRAME_SEGMENTS = { "Glass", "SurfaceGui", "Frame" },
	-- Under Frame: name list slots Player1..PlayerN (N = MAX_PLAYERS_PER_TEAM)
	LOBBY_PAD_SCREEN_PLAYER_NAMES_SEGMENTS = { "PlayerNames", "List" },
	LOBBY_PAD_SCREEN_PLAYER_NAME_SLOT_PREFIX = "Player",
	LOBBY_PAD_SCREEN_PLAYER_COUNT_NAME = "PlayerCount",
	LOBBY_PAD_SCREEN_ALERT_NAME = "Alert",
	-- Min seconds between team-queue balance toasts per player (fuller-team pad)
	LOBBY_TEAM_QUEUE_BALANCE_TOAST_COOLDOWN = 5,

	-- Player-facing copy (UI, toasts, server join errors). Use string.format where noted.
	TEXT = {
		-- JoinWaitingLobby RemoteFunction when not on a pad
		JOIN_WAITING_STAND_ON_PAD_ERROR = "Stand on a blue or red pad in the lobby to join the match queue.",
		-- LobbyServiceClient when remotes are not ready
		CLIENT_LOBBY_NOT_INITIALIZED = "Not initialized",

		-- string.format(seconds)
		MATCH_STARTING_IN = "Match starting in %d...",
		MATCH_STARTING = "Match starting...",

		-- string.format(otherTeamDisplayName) — fuller pad is over capacity vs other team
		TEAM_QUEUE_BALANCE_TOAST = "One player needs to join the %s team before more can queue here.",

		-- Pad SurfaceGui PlayerCount (RichText: <b> wraps count). string.format(count, teamLower)
		PAD_SCREEN_PLAYER_COUNT_ONE = "<b>%d</b> player in %s",
		PAD_SCREEN_PLAYER_COUNT_MANY = "<b>%d</b> players in %s",
		-- Per-team pad Alert (RichText). string.format(TeamDisplayUtils.displayName(team))
		PAD_SCREEN_TEAM_HAS_ENOUGH = "%s has enough players",
		-- string.format(teamDisplayName) — count 1 uses "player", many uses "players"; number is <u> underlined
		PAD_SCREEN_TEAM_NEED_MORE_ONE = "Need <u>1</u> more player on %s",
		PAD_SCREEN_TEAM_NEED_MORE_MANY = "Need <u>%d</u> more players on %s",
	},
}
