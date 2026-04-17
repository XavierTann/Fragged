--[[
	Server root startup script.
	Requires each server service module and calls its Init().
]]

print("Server starting.")

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local LobbyService = Services:WaitForChild("LobbyService"):WaitForChild("LobbyServiceServer")
local CombatService = Services:WaitForChild("CombatService"):WaitForChild("CombatServiceServer")
local EconomyService = Services:WaitForChild("EconomyService"):WaitForChild("EconomyServiceServer")
local DropService = Services:WaitForChild("DropService"):WaitForChild("DropServiceServer")
local CharacterService = Services:WaitForChild("CharacterService"):WaitForChild("CharacterServiceServer")
local LoadoutService = Services:WaitForChild("LoadoutService"):WaitForChild("LoadoutServiceServer")
local GachaService = Services:WaitForChild("GachaService"):WaitForChild("GachaServiceServer")
local ArenaService = Services:WaitForChild("ArenaService"):WaitForChild("ArenaServiceServer")
local MatchService = Services:WaitForChild("MatchService"):WaitForChild("MatchServiceServer")
local PadQueueService = Services:WaitForChild("PadQueueService"):WaitForChild("PadQueueServiceServer")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedModules = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules")
local CombatConfig = require(SharedModules:WaitForChild("CombatConfig"))
local LobbyConfig = require(SharedModules:WaitForChild("LobbyConfig"))

local LobbyServiceModule = require(LobbyService)
local CombatServiceModule = require(CombatService)
local EconomyServiceModule = require(EconomyService)
local DropServiceModule = require(DropService)
local CharacterServiceModule = require(CharacterService)
local LoadoutServiceModule = require(LoadoutService)
local GachaServiceModule = require(GachaService)
local WeaponInventoryServer = require(Services:WaitForChild("CombatService"):WaitForChild("WeaponInventoryServer"))
local ArenaServiceModule = require(ArenaService)
local MatchServiceModule = require(MatchService)
local PadQueueServiceModule = require(PadQueueService)

CharacterServiceModule.Init()
CombatServiceModule.Init()
EconomyServiceModule.Init()
GachaServiceModule.Init()
LoadoutServiceModule.Init()

DropServiceModule.SetPickupCallback(function(player, dropType, _drop)
	if dropType == "RocketLauncher" then
		local added = WeaponInventoryServer.addWeapon(player, "RocketLauncher")
		if added then
			CombatServiceModule.InitRocketsForPlayer(player)
			CombatServiceModule.GiveRocketLauncherTool(player)
			return true
		end
		return false
	elseif dropType == "HealthPack" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false
		end
		if humanoid.Health >= humanoid.MaxHealth then
			return false
		end
		humanoid.Health = humanoid.MaxHealth
		return true
	end
	return false
end)
DropServiceModule.Init()

LobbyServiceModule.Init(nil)

do
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local leaveRE = folder:FindFirstChild(CombatConfig.REMOTES.LEAVE_MATCH)
	if not leaveRE then
		leaveRE = Instance.new("RemoteEvent")
		leaveRE.Name = CombatConfig.REMOTES.LEAVE_MATCH
		leaveRE.Parent = folder
	end
	local leaveCooldowns = {}

	local function forfeitMatchIfNeeded(matchId, snapshotPlayers, excludeUserId)
		local counts = CombatServiceModule.GetMatchTeamCounts(matchId)
		if not counts or (counts.blue > 0 and counts.red > 0) then
			return
		end

		local remaining = {}
		for _, p in ipairs(snapshotPlayers) do
			if p and p.Parent and p.UserId ~= excludeUserId then
				table.insert(remaining, p)
			end
		end

		CombatServiceModule.ForfeitMatch(matchId)
		DropServiceModule.Stop(matchId)
		CombatServiceModule.CleanupMatchState(matchId)

		for _, p in ipairs(remaining) do
			PadQueueServiceModule.ClearPlayerArenaPhase(p)
			LobbyServiceModule.ReturnPlayerToLobby(p)
		end

		local forfeitRE = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
			and ReplicatedStorage[CombatConfig.REMOTE_FOLDER_NAME]:FindFirstChild(CombatConfig.REMOTES.MATCH_FORFEIT)
		if forfeitRE then
			for _, p in ipairs(remaining) do
				forfeitRE:FireClient(p)
			end
		end

		MatchServiceModule.CleanupMatch(matchId)
	end

	leaveRE.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if leaveCooldowns[player.UserId] and now - leaveCooldowns[player.UserId] < 2 then
			return
		end
		leaveCooldowns[player.UserId] = now

		local matchId = MatchServiceModule.GetPlayerMatchId(player)
		if not matchId then
			return
		end

		local match = MatchServiceModule.GetMatch(matchId)
		local snapshotPlayers = match and table.clone(match.players) or {}

		local removed = CombatServiceModule.RemovePlayerFromRound(player)
		if not removed then
			return
		end

		MatchServiceModule.RemovePlayerFromMatch(player)
		PadQueueServiceModule.ClearPlayerArenaPhase(player)
		LobbyServiceModule.ReturnPlayerToLobby(player)

		forfeitMatchIfNeeded(matchId, snapshotPlayers, player.UserId)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		leaveCooldowns[player.UserId] = nil

		local matchId = MatchServiceModule.GetPlayerMatchId(player)
		if not matchId then
			return
		end

		local match = MatchServiceModule.GetMatch(matchId)
		local snapshotPlayers = match and table.clone(match.players) or {}

		local removed = CombatServiceModule.RemovePlayerFromRound(player)
		MatchServiceModule.RemovePlayerFromMatch(player)
		PadQueueServiceModule.ClearPlayerArenaPhase(player)

		if removed then
			forfeitMatchIfNeeded(matchId, snapshotPlayers, player.UserId)
		end
	end)
end

-- ── Multi-arena instancing system (SpawnPads1, SpawnPads2, …) ──
ArenaServiceModule.Init()

MatchServiceModule.Init({
	onRoundStart = function(match)
		for _, p in ipairs(match.players) do
			LobbyServiceModule.SetPlayerPhase(p.UserId, LobbyConfig.PHASE.ARENA)
		end
		DropServiceModule.Start(match.matchId, match.arenaModel, match.modeConfig)
		CombatServiceModule.StartRound(match.players, function()
			DropServiceModule.Stop(match.matchId)
			CombatServiceModule.CleanupMatchState(match.matchId)
			PadQueueServiceModule.ClearMatchPlayers(match.players)
			MatchServiceModule.EndMatch(match.matchId)
		end, match.playerTeamsMap, match.matchId, match.arenaModel, match.modeConfig)
	end,
	onRoundEnd = function(_match)
	end,
})

PadQueueServiceModule.Init(function(padFolderName, players, playerTeamsMap, modeConfig)
	local match = MatchServiceModule.CreateMatch(padFolderName, players, playerTeamsMap, modeConfig)
	if match then
		MatchServiceModule.StartMatch(match.matchId)
	end
end)

print("Server startup complete.")
