--[[
	LobbyService (server)
	Flow: Shop Lobby -> portal -> Waiting Lobby -> Arena.
	Module returns a table with Init and public API. All event/remote setup runs in Init().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)

-- State (initialized on require; mutated in Init and at runtime)
local remotes = nil
local waitingQueue = {}
local playerPhase = {}
local lastLeftWaitingAt = {}
local matchStartingAt = nil
local countdownEndTime = nil
local countdownTickConnection = nil
local onArenaRoundStarted = nil -- callback(players) when round starts; set via Init(callback)

-- Private helpers
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

local function ensureSpawnsFolder()
	local folder = Workspace:FindFirstChild(LobbyConfig.SPAWNS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LobbyConfig.SPAWNS_FOLDER_NAME
		folder.Parent = Workspace
		for name, offset in pairs({
			[LobbyConfig.SPAWN_NAMES.SHOP] = Vector3.new(-14, 5, 0),
			[LobbyConfig.SPAWN_NAMES.WAITING] = Vector3.new(20, 5, 0),
			[LobbyConfig.SPAWN_NAMES.ARENA] = Vector3.new(40, 5, 0),
			[LobbyConfig.SPAWN_NAMES.ARENA_BLUE] = Vector3.new(35, 5, -5),
			[LobbyConfig.SPAWN_NAMES.ARENA_RED] = Vector3.new(45, 5, 5),
		}) do
			local part = Instance.new("Part")
			part.Name = name
			part.Size = Vector3.new(1, 1, 1)
			part.Position = offset
			part.Anchored = true
			part.Transparency = 1
			part.CanCollide = false
			part.Parent = folder
		end
	end
	return folder
end

local function getSpawnCFrame(spawnName)
	local folder = Workspace:FindFirstChild(LobbyConfig.SPAWNS_FOLDER_NAME)
	if not folder then
		return CFrame.new(0, 10, 0)
	end
	local spawn = folder:FindFirstChild(spawnName)
	if not spawn then
		return CFrame.new(0, 10, 0)
	end
	if spawn:IsA("BasePart") then
		return spawn.CFrame
	end
	if spawn:IsA("SpawnLocation") then
		return spawn.CFrame
	end
	if spawn:IsA("Model") and spawn.PrimaryPart then
		return spawn.PrimaryPart.CFrame
	end
	return CFrame.new(0, 10, 0)
end

local function teleportPlayerTo(player, spawnName)
	local cf = getSpawnCFrame(spawnName)
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char.HumanoidRootPart.CFrame = cf
	end
end

local function buildStateForPlayer(player)
	local userId = player.UserId
	local phase = playerPhase[userId] or LobbyConfig.PHASE.SHOP_LOBBY
	local waitingCount = #waitingQueue
	local state = {
		phase = phase,
		waitingCount = waitingCount,
		minPlayers = LobbyConfig.MIN_PLAYERS,
		maxPlayers = LobbyConfig.MAX_PLAYERS,
		matchStarting = matchStartingAt ~= nil,
		countdownEndTime = countdownEndTime,
		secondsRemaining = nil,
	}
	if countdownEndTime then
		state.secondsRemaining = math.max(0, math.ceil(countdownEndTime - os.clock()))
	end
	return state
end

local function broadcastStateToWaiting()
	local payload = {
		phase = LobbyConfig.PHASE.WAITING_LOBBY,
		waitingCount = #waitingQueue,
		minPlayers = LobbyConfig.MIN_PLAYERS,
		maxPlayers = LobbyConfig.MAX_PLAYERS,
		matchStarting = matchStartingAt ~= nil,
		countdownEndTime = countdownEndTime,
		secondsRemaining = nil,
	}
	if countdownEndTime then
		payload.secondsRemaining = math.max(0, math.ceil(countdownEndTime - os.clock()))
	end
	for i = 1, #waitingQueue do
		local p = waitingQueue[i]
		if p and p.Parent then
			remotes.LobbyState:FireClient(p, payload)
		end
	end
end

local function removeFromWaitingQueue(player)
	for i = #waitingQueue, 1, -1 do
		if waitingQueue[i] == player then
			table.remove(waitingQueue, i)
			break
		end
	end
	playerPhase[player.UserId] = LobbyConfig.PHASE.SHOP_LOBBY
end

local function cancelCountdown()
	if countdownTickConnection then
		task.cancel(countdownTickConnection)
		countdownTickConnection = nil
	end
	matchStartingAt = nil
	countdownEndTime = nil
	broadcastStateToWaiting()
end

local function startCountdownTick()
	if countdownTickConnection then
		return
	end
	countdownTickConnection = task.spawn(function()
		while matchStartingAt and countdownEndTime and os.clock() < countdownEndTime do
			task.wait(1)
			if not matchStartingAt then
				break
			end
			broadcastStateToWaiting()
		end
		countdownTickConnection = nil
	end)
end

local function sendToArena()
	if #waitingQueue < LobbyConfig.MIN_PLAYERS then
		cancelCountdown()
		return
	end
	-- Ensure countdown has actually finished (guard against being called early)
	if countdownEndTime and os.clock() < countdownEndTime - 0.05 then
		local waitTime = countdownEndTime - os.clock()
		task.delay(waitTime, sendToArena)
		return
	end
	local toSend = math.min(#waitingQueue, LobbyConfig.MAX_PLAYERS)
	print("[Lobby] Game starting – sending " .. toSend .. " player(s) to arena.")
	local players = {}
	for i = 1, toSend do
		players[i] = waitingQueue[1]
		table.remove(waitingQueue, 1)
	end
	for _, p in ipairs(players) do
		playerPhase[p.UserId] = LobbyConfig.PHASE.ARENA
		remotes.LobbyState:FireClient(p, {
			phase = LobbyConfig.PHASE.ARENA,
			waitingCount = 0,
			minPlayers = LobbyConfig.MIN_PLAYERS,
			maxPlayers = LobbyConfig.MAX_PLAYERS,
			matchStarting = false,
			countdownEndTime = nil,
		})
		remotes.TeleportToArena:FireClient(p)
		teleportPlayerTo(p, LobbyConfig.SPAWN_NAMES.ARENA)
	end
	matchStartingAt = nil
	countdownEndTime = nil
	broadcastStateToWaiting()
	if onArenaRoundStarted then
		onArenaRoundStarted(players)
	end
end

local function isInLeaveCooldown(userId)
	local t = lastLeftWaitingAt[userId]
	if not t then
		return false
	end
	if os.clock() - t < (LobbyConfig.LEAVE_WAITING_COOLDOWN_SECONDS or 2) then
		return true
	end
	lastLeftWaitingAt[userId] = nil
	return false
end

local function addPlayerToWaitingLobby(player)
	local userId = player.UserId
	if isInLeaveCooldown(userId) then
		return false
	end
	local phase = playerPhase[userId]
	if phase == LobbyConfig.PHASE.WAITING_LOBBY then
		return true
	end
	if phase == LobbyConfig.PHASE.ARENA then
		return false
	end
	waitingQueue[#waitingQueue + 1] = player
	playerPhase[userId] = LobbyConfig.PHASE.WAITING_LOBBY
	remotes.TeleportToWaiting:FireClient(player)
	teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.WAITING)
	remotes.LobbyState:FireClient(player, buildStateForPlayer(player))
	broadcastStateToWaiting()
	if not matchStartingAt and #waitingQueue >= LobbyConfig.MIN_PLAYERS then
		matchStartingAt = os.clock()
		countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
		print("[Lobby] Countdown started – " .. #waitingQueue .. " player(s) in waiting lobby (" .. tostring(LobbyConfig.ARENA_COUNTDOWN_SECONDS) .. "s).")
		broadcastStateToWaiting()
		startCountdownTick()
		task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, sendToArena)
	end
	return true
end

local function setupPortal()
	local portalName = "WaitingLobbyPortal"
	local portal = Workspace:FindFirstChild(portalName)
	if not portal then
		portal = Instance.new("Part")
		portal.Name = portalName
		portal.Size = Vector3.new(6, 8, 1)
		portal.Position = Vector3.new(0, 4, 0)
		portal.Anchored = true
		portal.BrickColor = BrickColor.new("Bright blue")
		portal.Material = Enum.Material.Neon
		portal.Parent = Workspace
	end
	portal.Touched:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model or not model:FindFirstChild("Humanoid") then
			return
		end
		local player = Players:GetPlayerFromCharacter(model)
		if not player then
			return
		end
		addPlayerToWaitingLobby(player)
	end)
end

local function bindRemoteHandlers()
	remotes.JoinWaitingLobby.OnServerInvoke = function(player)
		local userId = player.UserId
		if isInLeaveCooldown(userId) then
			return { success = false, error = "Please wait a moment" }
		end
		local phase = playerPhase[userId]
		if phase == LobbyConfig.PHASE.WAITING_LOBBY then
			return { success = true, state = buildStateForPlayer(player) }
		end
		if phase == LobbyConfig.PHASE.ARENA then
			return { success = false, error = "Already in a match" }
		end
		waitingQueue[#waitingQueue + 1] = player
		playerPhase[userId] = LobbyConfig.PHASE.WAITING_LOBBY
		remotes.TeleportToWaiting:FireClient(player)
		teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.WAITING)
		local state = buildStateForPlayer(player)
		remotes.LobbyState:FireClient(player, state)
		broadcastStateToWaiting()
		if not matchStartingAt and #waitingQueue >= LobbyConfig.MIN_PLAYERS then
			matchStartingAt = os.clock()
			countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
			print("[Lobby] Countdown started – " .. #waitingQueue .. " player(s) in waiting lobby (" .. tostring(LobbyConfig.ARENA_COUNTDOWN_SECONDS) .. "s).")
			broadcastStateToWaiting()
			startCountdownTick()
			task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, sendToArena)
		end
		return { success = true, state = state }
	end

	remotes.LeaveWaitingLobby.OnServerEvent:Connect(function(player)
		local userId = player.UserId
		if playerPhase[userId] ~= LobbyConfig.PHASE.WAITING_LOBBY then
			return
		end
		lastLeftWaitingAt[userId] = os.clock()
		removeFromWaitingQueue(player)
		if matchStartingAt and #waitingQueue < LobbyConfig.MIN_PLAYERS then
			cancelCountdown()
		end
		remotes.TeleportToShop:FireClient(player)
		teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
		remotes.LobbyState:FireClient(player, buildStateForPlayer(player))
		broadcastStateToWaiting()
	end)

	remotes.GetLobbyState.OnServerInvoke = function(player)
		return buildStateForPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		removeFromWaitingQueue(player)
		playerPhase[player.UserId] = nil
		if matchStartingAt and #waitingQueue < LobbyConfig.MIN_PLAYERS then
			cancelCountdown()
		end
		broadcastStateToWaiting()
	end)
end

-- Public API
return {
	Init = function(onRoundStartedCallback)
		onArenaRoundStarted = onRoundStartedCallback
		remotes = ensureRemotes()
		ensureSpawnsFolder()
		bindRemoteHandlers()
		setupPortal()
	end,

	AddPlayerToWaitingLobby = addPlayerToWaitingLobby,

	ReturnPlayerToShop = function(player)
		playerPhase[player.UserId] = LobbyConfig.PHASE.SHOP_LOBBY
		remotes.TeleportToShop:FireClient(player)
		teleportPlayerTo(player, LobbyConfig.SPAWN_NAMES.SHOP)
		remotes.LobbyState:FireClient(player, buildStateForPlayer(player))
	end,

	GetPhase = function(userId)
		return playerPhase[userId] or LobbyConfig.PHASE.SHOP_LOBBY
	end,
}
