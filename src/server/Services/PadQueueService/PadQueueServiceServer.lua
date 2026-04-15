--[[
	PadQueueService (server)
	Discovers every SpawnPadsN folder under Workspace.Lobby, creates a fully
	independent queue per folder. Each folder has its own blue/red queues,
	countdown, and match trigger — folders never share players.

	Heartbeat polls each folder's pads to auto-queue/dequeue players.
	When a folder's queue conditions are met, fires the onMatchReady callback.
	Fires LobbyState / countdown / teleport remotes so the client stays in sync.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)

local PadQueueServiceServer = {}

-- ── Remotes (created once in Init) ──

local remotes = nil

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
		LobbyState = remote(LobbyConfig.REMOTES.LOBBY_STATE, "RemoteEvent"),
		TeleportToWaiting = remote(LobbyConfig.REMOTES.TELEPORT_TO_WAITING, "RemoteEvent"),
		TeleportToArena = remote(LobbyConfig.REMOTES.TELEPORT_TO_ARENA, "RemoteEvent"),
		TeleportToLobby = remote(LobbyConfig.REMOTES.TELEPORT_TO_LOBBY, "RemoteEvent"),
		LobbyMatchCountdown = remote(LobbyConfig.REMOTES.LOBBY_MATCH_COUNTDOWN, "RemoteEvent"),
		TeamQueueBalanceToast = remote(LobbyConfig.REMOTES.TEAM_QUEUE_BALANCE_TOAST, "RemoteEvent"),
	}
end

-- ── Types ──

local function newFolderState(folderName)
	return {
		folderName = folderName,
		waitingQueueBlue = {},
		waitingQueueRed = {},
		playerPhase = {},           -- userId -> LobbyConfig.PHASE.*
		lastLeftWaitingAt = {},
		joinQueueBlockedUntil = {},
		teamQueueBalanceToastCooldown = {},
		matchStartingAt = nil,
		countdownEndTime = nil,
		countdownThread = nil,
		cachedPads = {},            -- { { model, team } }
	}
end

-- ── Module state ──

local folderStates = {}        -- folderName -> folderState
local playerFolderMap = {}     -- userId -> folderName (prevents multi-queue)
local onMatchReadyCallback = nil
local POLL_INTERVAL = LobbyConfig.LOBBY_PAD_POLL_INTERVAL or 0.2
local SHARED_PADS = LobbyConfig.LOBBY_SHARED_TEAM_PADS == true
local OCC_ATTR = LobbyConfig.LOBBY_PAD_OCCUPANT_USER_ID_ATTRIBUTE or "LobbyPadOccupantUserId"

-- ── Helpers ──

local function teamForPadName(name)
	if name == LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME then return "Blue" end
	if name == LobbyConfig.LOBBY_RED_PAD_MODEL_NAME then return "Red" end
	return nil
end

local function rebuildPadList(fState, folder)
	table.clear(fState.cachedPads)
	if not folder or not folder.Parent then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local team = teamForPadName(child.Name)
			if team then
				table.insert(fState.cachedPads, { model = child, team = team })
			end
		end
	end
end

local function hrpOverlapsModelBounds(hrp, model)
	if not model.Parent then
		return false
	end
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not cf or not size then
		return false
	end
	local localPos = cf:PointToObjectSpace(hrp.Position)
	local half = size * 0.5
	local padExtra = 0.6
	return math.abs(localPos.X) <= half.X + padExtra and math.abs(localPos.Z) <= half.Z + padExtra
end

-- ── Queue logic (per folder) ──

local function maxQueueTeamDiff()
	return LobbyConfig.LOBBY_MAX_WAITING_QUEUE_TEAM_DIFF or 1
end

local function playerQueuedTeam(fState, player)
	for _, p in ipairs(fState.waitingQueueBlue) do
		if p == player then
			return "Blue"
		end
	end
	for _, p in ipairs(fState.waitingQueueRed) do
		if p == player then
			return "Red"
		end
	end
	return nil
end

-- ── Client notification helpers ──

local function buildStateForPlayer(fState, player)
	local userId = player.UserId
	local phase = fState.playerPhase[userId] or LobbyConfig.PHASE.LOBBY
	local b, r = #fState.waitingQueueBlue, #fState.waitingQueueRed
	local result = {
		phase = phase,
		waitingCount = b + r,
		waitingCountBlue = b,
		waitingCountRed = r,
		queuedTeam = playerQueuedTeam(fState, player),
		minPlayers = LobbyConfig.MIN_PLAYERS,
		minPlayersPerTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM,
		maxPlayers = LobbyConfig.MAX_PLAYERS,
		matchStarting = fState.matchStartingAt ~= nil,
		countdownEndTime = fState.countdownEndTime,
		secondsRemaining = nil,
	}
	if fState.countdownEndTime then
		result.secondsRemaining = math.max(0, math.ceil(fState.countdownEndTime - os.clock()))
	end
	return result
end

local function broadcastStateToFolder(fState)
	if not remotes then
		return
	end
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not seen[p] then
			local phase = fState.playerPhase[p.UserId]
			if phase and phase ~= LobbyConfig.PHASE.ARENA then
				seen[p] = true
				remotes.LobbyState:FireClient(p, buildStateForPlayer(fState, p))
				if fState.matchStartingAt and fState.countdownEndTime and playerQueuedTeam(fState, p) then
					local sec = math.max(0, math.ceil(fState.countdownEndTime - os.clock()))
					remotes.LobbyMatchCountdown:FireClient(p, sec)
				end
			end
		end
	end
	-- Also notify lobby players who aren't in this folder's state but need updated counts
	for _, p in ipairs(Players:GetPlayers()) do
		if not seen[p] then
			local fn = playerFolderMap[p.UserId]
			if not fn then
				seen[p] = true
				remotes.LobbyState:FireClient(p, buildStateForPlayer(fState, p))
			end
		end
	end
end

local function sendStateToPlayer(fState, player)
	if not remotes then
		return
	end
	remotes.LobbyState:FireClient(player, buildStateForPlayer(fState, player))
end

-- ── Per-folder pad screen sync ──

local T = LobbyConfig.TEXT

local function resolvePath(parent, segments)
	local p = parent
	for _, name in ipairs(segments) do
		p = p and p:FindFirstChild(name)
	end
	return p
end

local function findFrameUnderScreen(spawnPadsFolder, screenName)
	if not spawnPadsFolder then
		return nil
	end
	local root = spawnPadsFolder:FindFirstChild(screenName)
	if not root then
		return nil
	end
	local frame = resolvePath(root, LobbyConfig.LOBBY_PAD_SCREEN_FRAME_SEGMENTS)
	if frame and frame:IsA("GuiObject") then
		return frame
	end
	return nil
end

local function findTextChild(frame, name)
	if not frame then
		return nil
	end
	local c = frame:FindFirstChild(name)
	if c and (c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox")) then
		return c
	end
	return nil
end

local function setTextIfChanged(guiObject, text)
	if not guiObject then
		return
	end
	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		guiObject.RichText = true
	end
	if guiObject.Text ~= text then
		guiObject.Text = text
	end
end

local function setPlainTextIfChanged(guiObject, text)
	if not guiObject then
		return
	end
	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		guiObject.RichText = false
		if guiObject.Text ~= text then
			guiObject.Text = text
		end
	end
end

local function displayNameForPlayer(player)
	if not player or not player.Parent then
		return ""
	end
	local dn = player.DisplayName
	if type(dn) == "string" and dn ~= "" then
		return dn
	end
	return player.Name
end

local function syncPadScreensForFolder(fState)
	local lobby = Workspace:FindFirstChild("Lobby")
	local spawnPads = lobby and lobby:FindFirstChild(fState.folderName)
	if not spawnPads then
		return
	end

	local blueFrame = findFrameUnderScreen(spawnPads, LobbyConfig.LOBBY_BLUE_PAD_SCREEN_NAME)
	local redFrame = findFrameUnderScreen(spawnPads, LobbyConfig.LOBBY_RED_PAD_SCREEN_NAME)

	local b = #fState.waitingQueueBlue
	local r = #fState.waitingQueueRed
	local minTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM or 2

	local function playerCountLine(count, screenTeam)
		local key = screenTeam == "Blue" and "blue" or "red"
		if count == 1 then
			return string.format(T.PAD_SCREEN_PLAYER_COUNT_ONE, count, key)
		end
		return string.format(T.PAD_SCREEN_PLAYER_COUNT_MANY, count, key)
	end

	local function alertTextForTeam(screenTeam)
		local c = screenTeam == "Blue" and b or r
		local o = screenTeam == "Blue" and r or b
		local name = TeamDisplayUtils.displayName(screenTeam)
		if c < minTeam then
			local need = minTeam - c
			if need == 1 then
				return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_ONE, name)
			end
			return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_MANY, need, name)
		end
		if o > c then
			local need = o - c
			if need == 1 then
				return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_ONE, name)
			end
			return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_MANY, need, name)
		end
		return string.format(T.PAD_SCREEN_TEAM_HAS_ENOUGH, name)
	end

	local function findPlayerNameListFrame(screenFrame)
		if not screenFrame then
			return nil
		end
		return resolvePath(screenFrame, LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_NAMES_SEGMENTS)
	end

	local function syncPlayerNameSlots(listFrame, queue)
		local prefix = LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_NAME_SLOT_PREFIX or "Player"
		local maxSlots = LobbyConfig.MAX_PLAYERS_PER_TEAM or 6
		if not listFrame then
			return
		end
		for i = 1, maxSlots do
			local label = listFrame:FindFirstChild(prefix .. tostring(i))
			if label then
				setPlainTextIfChanged(label, displayNameForPlayer(queue[i]))
			end
		end
	end

	if blueFrame then
		setTextIfChanged(findTextChild(blueFrame, LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_COUNT_NAME), playerCountLine(b, "Blue"))
		setTextIfChanged(findTextChild(blueFrame, LobbyConfig.LOBBY_PAD_SCREEN_ALERT_NAME), alertTextForTeam("Blue"))
		syncPlayerNameSlots(findPlayerNameListFrame(blueFrame), fState.waitingQueueBlue)
	end
	if redFrame then
		setTextIfChanged(findTextChild(redFrame, LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_COUNT_NAME), playerCountLine(r, "Red"))
		setTextIfChanged(findTextChild(redFrame, LobbyConfig.LOBBY_PAD_SCREEN_ALERT_NAME), alertTextForTeam("Red"))
		syncPlayerNameSlots(findPlayerNameListFrame(redFrame), fState.waitingQueueRed)
	end
end

local function removeFromQueue(fState, player)
	for i = #fState.waitingQueueBlue, 1, -1 do
		if fState.waitingQueueBlue[i] == player then
			table.remove(fState.waitingQueueBlue, i)
			break
		end
	end
	for i = #fState.waitingQueueRed, 1, -1 do
		if fState.waitingQueueRed[i] == player then
			table.remove(fState.waitingQueueRed, i)
			break
		end
	end
	fState.playerPhase[player.UserId] = LobbyConfig.PHASE.LOBBY
	playerFolderMap[player.UserId] = nil
	sendStateToPlayer(fState, player)
	broadcastStateToFolder(fState)
end

local function canStartCountdown(fState)
	local b, r = #fState.waitingQueueBlue, #fState.waitingQueueRed
	local minTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM or 1
	local minTotal = LobbyConfig.MIN_PLAYERS or 2

	if b == 0 and r == 0 then return false end

	if minTotal <= 1 then
		if b >= minTeam and r == 0 then return true end
		if r >= minTeam and b == 0 then return true end
		if b >= minTeam and r >= minTeam and b == r then return true end
		return false
	end

	if b < minTeam or r < minTeam then return false end
	if b ~= r then return false end
	return true
end

local function cancelCountdown(fState)
	local wasActive = fState.matchStartingAt ~= nil
	if fState.countdownThread then
		task.cancel(fState.countdownThread)
		fState.countdownThread = nil
	end
	fState.matchStartingAt = nil
	fState.countdownEndTime = nil
	if wasActive then
		broadcastStateToFolder(fState)
	end
end

local function takePlayersForArena(fState)
	local players = {}
	local teamByUserId = {}
	local preferBlue = true
	local maxP = LobbyConfig.MAX_PLAYERS or 8

	local function popNext()
		if preferBlue and #fState.waitingQueueBlue > 0 then
			return table.remove(fState.waitingQueueBlue, 1), "Blue"
		end
		if not preferBlue and #fState.waitingQueueRed > 0 then
			return table.remove(fState.waitingQueueRed, 1), "Red"
		end
		if #fState.waitingQueueBlue > 0 then
			return table.remove(fState.waitingQueueBlue, 1), "Blue"
		end
		if #fState.waitingQueueRed > 0 then
			return table.remove(fState.waitingQueueRed, 1), "Red"
		end
		return nil, nil
	end

	while #players < maxP do
		local p, team = popNext()
		if not p then break end
		if p.Parent then
			table.insert(players, p)
			teamByUserId[p.UserId] = team
		end
		preferBlue = not preferBlue
	end
	return players, teamByUserId
end

local function sendToArena(fState)
	if not canStartCountdown(fState) then
		cancelCountdown(fState)
		return
	end
	if fState.countdownEndTime and os.clock() < fState.countdownEndTime - 0.05 then
		local waitTime = fState.countdownEndTime - os.clock()
		task.delay(waitTime, function()
			sendToArena(fState)
		end)
		return
	end

	local players, teamByUserId = takePlayersForArena(fState)
	if #players == 0 then
		cancelCountdown(fState)
		return
	end

	for _, p in ipairs(players) do
		fState.playerPhase[p.UserId] = LobbyConfig.PHASE.ARENA
		if remotes then
			remotes.LobbyState:FireClient(p, {
				phase = LobbyConfig.PHASE.ARENA,
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
			remotes.TeleportToArena:FireClient(p)
		end
	end

	cancelCountdown(fState)
	broadcastStateToFolder(fState)

	if onMatchReadyCallback then
		onMatchReadyCallback(fState.folderName, players, teamByUserId)
	end
end

local function tryBeginCountdown(fState)
	if fState.matchStartingAt then
		return
	end
	if not canStartCountdown(fState) then
		return
	end

	fState.matchStartingAt = os.clock()
	fState.countdownEndTime = os.clock() + LobbyConfig.ARENA_COUNTDOWN_SECONDS
	broadcastStateToFolder(fState)

	fState.countdownThread = task.spawn(function()
		while fState.matchStartingAt and fState.countdownEndTime and os.clock() < fState.countdownEndTime do
			task.wait(1)
			if fState.matchStartingAt then
				broadcastStateToFolder(fState)
			end
		end
		fState.countdownThread = nil
	end)

	task.delay(LobbyConfig.ARENA_COUNTDOWN_SECONDS, function()
		sendToArena(fState)
	end)
end

local function maybeCancelCountdown(fState)
	if fState.matchStartingAt and not canStartCountdown(fState) then
		cancelCountdown(fState)
	end
end

local function balanceAllowsPlayerJoinTeam(fState, player, team)
	if team ~= "Blue" and team ~= "Red" then return false end
	if playerQueuedTeam(fState, player) == team then
		return true
	end

	local b, r = #fState.waitingQueueBlue, #fState.waitingQueueRed
	local q = playerQueuedTeam(fState, player)
	if q == "Blue" then
		b = b - 1
	elseif q == "Red" then
		r = r - 1
	end
	if team == "Blue" then
		b = b + 1
	else
		r = r + 1
	end
	return math.abs(b - r) <= maxQueueTeamDiff()
end

local function addPlayerToTeamQueue(fState, player, team)
	local userId = player.UserId
	local blockUntil = fState.joinQueueBlockedUntil[userId]
	if blockUntil and os.clock() < blockUntil then return false end

	local lt = fState.lastLeftWaitingAt[userId]
	if lt and os.clock() - lt < (LobbyConfig.LEAVE_WAITING_COOLDOWN_SECONDS or 2) then
		return false
	end

	local phase = fState.playerPhase[userId]
	if phase == LobbyConfig.PHASE.ARENA then return false end

	if team ~= "Blue" and team ~= "Red" then return false end

	-- Prevent joining a different folder's queue
	local existing = playerFolderMap[userId]
	if existing and existing ~= fState.folderName then return false end

	local onBlue = playerQueuedTeam(fState, player) == "Blue"
	local onRed  = playerQueuedTeam(fState, player) == "Red"
	if (team == "Blue" and onBlue) or (team == "Red" and onRed) then return true end

	if not balanceAllowsPlayerJoinTeam(fState, player, team) then return false end

	if onBlue or onRed then
		removeFromQueue(fState, player)
	end

	local cap = LobbyConfig.MAX_PLAYERS_PER_TEAM or 6
	local q = team == "Blue" and fState.waitingQueueBlue or fState.waitingQueueRed
	if #q >= cap then return false end

	table.insert(q, player)
	fState.playerPhase[userId] = LobbyConfig.PHASE.WAITING_LOBBY
	playerFolderMap[userId] = fState.folderName

	sendStateToPlayer(fState, player)
	broadcastStateToFolder(fState)
	tryBeginCountdown(fState)
	return true
end

-- ── Pad polling ──

local function getValidPadAndTeam(fState, player, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return nil, nil end

	local preferredTeam = playerQueuedTeam(fState, player)
	local candidates = {}
	for _, entry in ipairs(fState.cachedPads) do
		if hrpOverlapsModelBounds(hrp, entry.model) then
			if SHARED_PADS then
				table.insert(candidates, entry)
			else
				local occ = entry.model:GetAttribute(OCC_ATTR)
				if not occ or occ == player.UserId then
					table.insert(candidates, entry)
				end
			end
		end
	end
	if #candidates == 0 then return nil, nil end
	if preferredTeam then
		for _, entry in ipairs(candidates) do
			if entry.team == preferredTeam then return entry.model, entry.team end
		end
	end
	return candidates[1].model, candidates[1].team
end

local function pollFolder(fState, folder)
	if #fState.cachedPads == 0 then
		rebuildPadList(fState, folder)
	end
	if #fState.cachedPads == 0 then return end

	for _, player in ipairs(Players:GetPlayers()) do
		local phase = fState.playerPhase[player.UserId]
		if phase ~= LobbyConfig.PHASE.ARENA then
			local char = player.Character
			if not char then
				if phase == LobbyConfig.PHASE.WAITING_LOBBY then
					removeFromQueue(fState, player)
					maybeCancelCountdown(fState)
				end
			else
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local _, padTeam = getValidPadAndTeam(fState, player, char)
					local queued = playerQueuedTeam(fState, player)
					if padTeam then
						-- Only process if player isn't already in a different folder's queue
						local existingFolder = playerFolderMap[player.UserId]
						if not existingFolder or existingFolder == fState.folderName then
							if phase ~= LobbyConfig.PHASE.WAITING_LOBBY or queued ~= padTeam then
								addPlayerToTeamQueue(fState, player, padTeam)
							end
						end
					elseif queued and playerFolderMap[player.UserId] == fState.folderName then
						removeFromQueue(fState, player)
						maybeCancelCountdown(fState)
					end
				end
			end
		end
	end
end

local function strictFullerTeam(fState)
	local b = #fState.waitingQueueBlue
	local r = #fState.waitingQueueRed
	if b > r then
		return "Blue", "Red"
	end
	if r > b then
		return "Red", "Blue"
	end
	return nil, nil
end

local function padModelForTeam(fState, team)
	for _, entry in ipairs(fState.cachedPads) do
		if entry.team == team then
			return entry.model
		end
	end
	return nil
end

local function tryFireTeamBalanceToasts(fState)
	if not remotes or not remotes.TeamQueueBalanceToast then
		return
	end
	local fuller, other = strictFullerTeam(fState)
	if not fuller or not other then
		return
	end
	local b = #fState.waitingQueueBlue
	local r = #fState.waitingQueueRed
	local absDiff = math.abs(b - r)
	local maxDiff = maxQueueTeamDiff()
	local pad = padModelForTeam(fState, fuller)
	if not pad then
		return
	end
	local cooldown = LobbyConfig.LOBBY_TEAM_QUEUE_BALANCE_TOAST_COOLDOWN or 5
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		if fState.playerPhase[player.UserId] ~= LobbyConfig.PHASE.ARENA then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				if hrpOverlapsModelBounds(hrp, pad) then
					local queued = playerQueuedTeam(fState, player)
					local shouldToast = false
					if queued == fuller then
						shouldToast = absDiff > maxDiff
					else
						shouldToast = not balanceAllowsPlayerJoinTeam(fState, player, fuller)
					end
					if shouldToast then
						local uid = player.UserId
						if now >= (fState.teamQueueBalanceToastCooldown[uid] or 0) then
							remotes.TeamQueueBalanceToast:FireClient(player, other)
							fState.teamQueueBalanceToastCooldown[uid] = now + cooldown
						end
					end
				end
			end
		end
	end
end

-- ── Discovery ──

local function discoverPadFolders()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[PadQueueService] Workspace.Lobby not found")
		return {}
	end
	local folders = {}
	for _, child in ipairs(lobby:GetChildren()) do
		if child:IsA("Folder") and child.Name:match("^SpawnPads%d+$") then
			table.insert(folders, child)
		end
	end
	table.sort(folders, function(fa, fb)
		return fa.Name < fb.Name
	end)
	return folders
end

-- ── Public API ──

function PadQueueServiceServer.GetFolderState(folderName)
	return folderStates[folderName]
end

function PadQueueServiceServer.GetAllFolderStates()
	return folderStates
end

function PadQueueServiceServer.GetPlayerFolder(player)
	return playerFolderMap[player.UserId]
end

--[[
	Manually remove a player from whatever queue they're in.
]]
function PadQueueServiceServer.RemovePlayer(player)
	local fn = playerFolderMap[player.UserId]
	if not fn then return end
	local fState = folderStates[fn]
	if fState then
		removeFromQueue(fState, player)
		maybeCancelCountdown(fState)
	else
		playerFolderMap[player.UserId] = nil
	end
end

--[[
	Clear arena-phase for a list of players returning from a match.
	Called by the match system after EndMatch so players can re-queue.
]]
function PadQueueServiceServer.ClearMatchPlayers(players)
	for _, p in ipairs(players) do
		local userId = p.UserId
		local fn = playerFolderMap[userId]
		if fn then
			local fState = folderStates[fn]
			if fState then
				fState.playerPhase[userId] = nil
			end
			playerFolderMap[userId] = nil
		end
	end
end

--[[
	Clear a single player's arena phase so they can re-queue on pads.
	Used when a player voluntarily leaves a match mid-game.
]]
function PadQueueServiceServer.ClearPlayerArenaPhase(player)
	local userId = player.UserId
	local folderName = playerFolderMap[userId]
	if folderName then
		local fState = folderStates[folderName]
		if fState then
			fState.playerPhase[userId] = nil
		end
		playerFolderMap[userId] = nil
	end
end

function PadQueueServiceServer.Init(matchReadyCallback)
	onMatchReadyCallback = matchReadyCallback
	remotes = ensureRemotes()

	local padFolders = discoverPadFolders()
	for _, folder in ipairs(padFolders) do
		local fState = newFolderState(folder.Name)
		rebuildPadList(fState, folder)
		folderStates[folder.Name] = fState

		folder.ChildAdded:Connect(function()
			task.defer(function()
				rebuildPadList(fState, folder)
			end)
		end)
		folder.ChildRemoved:Connect(function()
			task.defer(function()
				rebuildPadList(fState, folder)
			end)
		end)
	end

	-- Heartbeat polling — one loop covers all folders
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < POLL_INTERVAL then
			return
		end
		acc = 0
		for folderName, fState in pairs(folderStates) do
			local lobby = Workspace:FindFirstChild("Lobby")
			local folder = lobby and lobby:FindFirstChild(folderName)
			pollFolder(fState, folder)
			syncPadScreensForFolder(fState)
			tryFireTeamBalanceToasts(fState)
		end
	end)

	-- Clean up players that leave the game
	Players.PlayerRemoving:Connect(function(player)
		PadQueueServiceServer.RemovePlayer(player)
	end)
end

return PadQueueServiceServer
