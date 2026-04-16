--[[
	MatchService (server)
	Central match lifecycle manager. Matches are keyed by auto-incrementing
	matchId, allowing unlimited concurrent arenas from the same pad folder.

	Lifecycle: queue fills -> CreateMatch -> StartMatch (clone arena, teleport in,
	start combat) -> EndMatch (teleport out, destroy arena, clean up).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local ArenaServiceServer = require(Services:WaitForChild("ArenaService"):WaitForChild("ArenaServiceServer"))

local MatchServiceServer = {}

local function getLobbyRemotes()
	local folder = ReplicatedStorage:FindFirstChild(LobbyConfig.REMOTE_FOLDER_NAME)
	if not folder then
		return nil
	end
	return {
		TeleportToLobby = folder:FindFirstChild(LobbyConfig.REMOTES.TELEPORT_TO_LOBBY),
		LobbyState = folder:FindFirstChild(LobbyConfig.REMOTES.LOBBY_STATE),
	}
end

local MATCH_STATE = {
	WAITING = "waiting",
	ACTIVE  = "active",
	ENDED   = "ended",
}
MatchServiceServer.MATCH_STATE = MATCH_STATE

local nextMatchId = 0
local activeMatches = {}          -- matchId -> match table
local playerMatchAssignment = {}  -- userId -> matchId

local onRoundStartCallback = nil
local onRoundEndCallback = nil

local function generateMatchId()
	nextMatchId = nextMatchId + 1
	return "match_" .. tostring(nextMatchId)
end

local function collectSpawnCFrames(spawnFolder)
	local points = {}
	if not spawnFolder then
		return points
	end
	for _, child in ipairs(spawnFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local offset = child.Size.Y / 2 + 2.5
			table.insert(points, child.CFrame + Vector3.new(0, offset, 0))
		elseif child:IsA("Model") and child.PrimaryPart then
			local offset = child.PrimaryPart.Size.Y / 2 + 2.5
			table.insert(points, child.PrimaryPart.CFrame + Vector3.new(0, offset, 0))
		end
	end
	return points
end

local function getArenaSpawnCFrames(arenaModel)
	if not arenaModel then
		return {}
	end
	local spawnFolder = TDMConfig.getPlayerSpawnFolder(arenaModel)
	return collectSpawnCFrames(spawnFolder)
end

local function teleportPlayerToArena(player, spawnCFrames, index)
	local cf
	if #spawnCFrames > 0 then
		cf = spawnCFrames[((index - 1) % #spawnCFrames) + 1]
	else
		cf = CFrame.new(0, 50, 0)
	end
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char.HumanoidRootPart.CFrame = cf
	end
end

local function teleportPlayerToLobby(player)
	local lobbySpawn = Workspace:FindFirstChild(LobbyConfig.LOBBY_SPAWN_NAME)
	local cf = CFrame.new(0, 10, 0)
	if lobbySpawn and lobbySpawn:IsA("BasePart") then
		cf = lobbySpawn.CFrame + Vector3.new(0, lobbySpawn.Size.Y / 2 + 2.5, 0)
	elseif lobbySpawn and lobbySpawn:IsA("Model") and lobbySpawn.PrimaryPart then
		local part = lobbySpawn.PrimaryPart
		cf = part.CFrame + Vector3.new(0, part.Size.Y / 2 + 2.5, 0)
	end
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char.HumanoidRootPart.CFrame = cf
	end
end

function MatchServiceServer.CreateMatch(padFolderName, players, playerTeamsMap, modeConfig)
	local matchId = generateMatchId()

	local match = {
		matchId = matchId,
		padFolderName = padFolderName,
		players = players,
		playerTeamsMap = playerTeamsMap or {},
		modeConfig = modeConfig or {},
		state = MATCH_STATE.WAITING,
		arenaModel = nil,
	}

	for _, p in ipairs(players) do
		playerMatchAssignment[p.UserId] = matchId
	end

	activeMatches[matchId] = match
	return match
end

function MatchServiceServer.StartMatch(matchId)
	local match = activeMatches[matchId]
	if not match then
		warn("[MatchService] No match found for " .. matchId)
		return
	end
	if match.state ~= MATCH_STATE.WAITING then
		warn("[MatchService] Match not in waiting state for " .. matchId)
		return
	end

	local arenaModel = ArenaServiceServer.CreateArena(matchId)
	if not arenaModel then
		warn("[MatchService] Failed to create arena for " .. matchId)
		MatchServiceServer.CleanupMatch(matchId)
		return
	end

	match.arenaModel = arenaModel
	match.state = MATCH_STATE.ACTIVE

	local spawnCFrames = getArenaSpawnCFrames(arenaModel)

	for i, p in ipairs(match.players) do
		if p and p.Parent then
			teleportPlayerToArena(p, spawnCFrames, i)
		end
	end

	if onRoundStartCallback then
		onRoundStartCallback(match)
	end
end

function MatchServiceServer.EndMatch(matchId)
	local match = activeMatches[matchId]
	if not match then
		return
	end

	match.state = MATCH_STATE.ENDED

	if onRoundEndCallback then
		onRoundEndCallback(match)
	end

	local lobbyRemotes = getLobbyRemotes()
	for _, p in ipairs(match.players) do
		if p and p.Parent then
			teleportPlayerToLobby(p)
			if lobbyRemotes then
				if lobbyRemotes.TeleportToLobby then
					lobbyRemotes.TeleportToLobby:FireClient(p)
				end
				if lobbyRemotes.LobbyState then
					lobbyRemotes.LobbyState:FireClient(p, {
						phase = LobbyConfig.PHASE.LOBBY,
						waitingCount = 0,
						waitingCountBlue = 0,
						waitingCountRed = 0,
						queuedTeam = nil,
						minPlayers = LobbyConfig.MIN_PLAYERS,
						minPlayersPerTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM,
						maxPlayers = LobbyConfig.MAX_PLAYERS,
						matchStarting = false,
						countdownEndTime = nil,
					})
				end
			end
		end
		playerMatchAssignment[p.UserId] = nil
	end

	ArenaServiceServer.DestroyArena(matchId)
	activeMatches[matchId] = nil
end

function MatchServiceServer.CleanupMatch(matchId)
	local match = activeMatches[matchId]
	if not match then
		return
	end
	for _, p in ipairs(match.players) do
		playerMatchAssignment[p.UserId] = nil
	end
	ArenaServiceServer.DestroyArena(matchId)
	activeMatches[matchId] = nil
end

function MatchServiceServer.GetMatch(matchId)
	return activeMatches[matchId]
end

function MatchServiceServer.GetAllActiveMatches()
	return activeMatches
end

function MatchServiceServer.IsPlayerInMatch(player)
	return playerMatchAssignment[player.UserId] ~= nil
end

function MatchServiceServer.GetPlayerMatchId(player)
	return playerMatchAssignment[player.UserId]
end

function MatchServiceServer.RemovePlayerFromMatch(player)
	local matchId = playerMatchAssignment[player.UserId]
	if not matchId then
		return false
	end

	local match = activeMatches[matchId]
	if not match then
		playerMatchAssignment[player.UserId] = nil
		return false
	end

	local remaining = {}
	local found = false
	for _, p in ipairs(match.players) do
		if p.UserId == player.UserId then
			found = true
		else
			table.insert(remaining, p)
		end
	end
	if not found then
		playerMatchAssignment[player.UserId] = nil
		return false
	end

	match.players = remaining
	playerMatchAssignment[player.UserId] = nil

	if #remaining == 0 then
		MatchServiceServer.CleanupMatch(matchId)
	end

	return true
end

function MatchServiceServer.Init(config)
	config = config or {}
	onRoundStartCallback = config.onRoundStart
	onRoundEndCallback = config.onRoundEnd

	Players.PlayerRemoving:Connect(function(player)
		MatchServiceServer.RemovePlayerFromMatch(player)
	end)
end

return MatchServiceServer
