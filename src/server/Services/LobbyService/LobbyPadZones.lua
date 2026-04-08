--[[
	LobbyPadZones
	Players queue by standing on pad models under Workspace/Lobby/SpawnPads:
	Models named "BluePad" (Blue) and "RedPad" (Red)—typically one of each (LOBBY_SHARED_TEAM_PADS).
	Queue if HRP is inside the pad model’s X–Z bounds (bounding box local X/Z); Y ignored.

	When LOBBY_SHARED_TEAM_PADS is false: each pad may be claimed by at most one queued player
	(LobbyPadOccupantUserId).
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local LobbyQueue = require(script.Parent.LobbyQueue)
local LobbyPadScreens = require(script.Parent.LobbyPadScreens)

local OCC_ATTR = LobbyConfig.LOBBY_PAD_OCCUPANT_USER_ID_ATTRIBUTE or "LobbyPadOccupantUserId"
local SHARED_PADS = LobbyConfig.LOBBY_SHARED_TEAM_PADS == true

local function getPadsContainer()
	local inst = Workspace
	for _, name in ipairs(LobbyConfig.LOBBY_PADS_FOLDER_PATH) do
		inst = inst:FindFirstChild(name)
		if not inst then
			return nil
		end
	end
	return inst
end

-- Cached list of { model = Model, team = "Blue"|"Red" }
local cachedPads = {}

local function teamForPadName(name)
	if name == LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME then
		return "Blue"
	end
	if name == LobbyConfig.LOBBY_RED_PAD_MODEL_NAME then
		return "Red"
	end
	return nil
end

local function rebuildPadList(container)
	table.clear(cachedPads)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			local team = teamForPadName(child.Name)
			if team then
				cachedPads[#cachedPads + 1] = { model = child, team = team }
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
	local pad = 0.6
	return math.abs(localPos.X) <= half.X + pad and math.abs(localPos.Z) <= half.Z + pad
end

local function getOccupantUserId(model)
	local v = model:GetAttribute(OCC_ATTR)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return nil
end

local function clearPadOccupantForUser(userId)
	local folder = getPadsContainer()
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and teamForPadName(child.Name) then
			if child:GetAttribute(OCC_ATTR) == userId then
				child:SetAttribute(OCC_ATTR, nil)
			end
		end
	end
end

--[[
	Overlapping pad. If already queued, prefer a candidate matching that team.
]]
local function getValidQueuePadModelAndTeam(state, player, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return nil, nil
	end
	local preferredTeam = LobbyQueue.playerQueuedTeam(state, player)
	local candidates = {}
	for _, entry in ipairs(cachedPads) do
		local model = entry.model
		if hrpOverlapsModelBounds(hrp, model) then
			if SHARED_PADS then
				candidates[#candidates + 1] = entry
			else
				local occ = getOccupantUserId(model)
				if not occ or occ == player.UserId then
					candidates[#candidates + 1] = entry
				end
			end
		end
	end
	if #candidates == 0 then
		return nil, nil
	end
	if preferredTeam then
		for _, entry in ipairs(candidates) do
			if entry.team == preferredTeam then
				return entry.model, entry.team
			end
		end
	end
	local first = candidates[1]
	return first.model, first.team
end

local function syncPlayerPadOccupancy(userId, targetPadModel)
	if not targetPadModel or not targetPadModel.Parent then
		return
	end
	if getOccupantUserId(targetPadModel) == userId then
		return
	end
	clearPadOccupantForUser(userId)
	targetPadModel:SetAttribute(OCC_ATTR, userId)
end

local function padModelForTeamFolder(folder, team)
	if not folder then
		return nil
	end
	local name = team == "Blue" and LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME or LobbyConfig.LOBBY_RED_PAD_MODEL_NAME
	local m = folder:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

--[[
	Players on the strictly fuller team's pad: toast if queue is over max diff, or they cannot join fuller team.
]]
local function tryFireTeamQueueBalanceToasts(state, remotes)
	local re = remotes and remotes.TeamQueueBalanceToast
	if not re then
		return
	end
	local fuller, other = LobbyQueue.strictFullerTeam(state)
	if not fuller or not other then
		return
	end
	local b = #state.waitingQueueBlue
	local r = #state.waitingQueueRed
	local absDiff = math.abs(b - r)
	local maxDiff = LobbyQueue.maxQueueTeamDiff()
	local folder = getPadsContainer()
	local pad = padModelForTeamFolder(folder, fuller)
	if not pad then
		return
	end
	local cooldown = LobbyConfig.LOBBY_TEAM_QUEUE_BALANCE_TOAST_COOLDOWN or 5
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.ARENA then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				if hrpOverlapsModelBounds(hrp, pad) then
					local queued = LobbyQueue.playerQueuedTeam(state, player)
					local shouldToast = false
					if queued == fuller then
						shouldToast = absDiff > maxDiff
					else
						shouldToast = not LobbyQueue.balanceAllowsPlayerJoinTeam(state, player, fuller)
					end
					if shouldToast then
						local uid = player.UserId
						if now >= (state.teamQueueBalanceToastCooldown[uid] or 0) then
							re:FireClient(player, other)
							state.teamQueueBalanceToastCooldown[uid] = now + cooldown
						end
					end
				end
			end
		end
	end
end

local function reconcilePadOccupancyWithQueues(state)
	local folder = getPadsContainer()
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and teamForPadName(child.Name) then
			local occ = getOccupantUserId(child)
			if occ then
				local p = Players:GetPlayerByUserId(occ)
				local ok = p
					and p.Parent
					and state.playerPhase[occ] == LobbyConfig.PHASE.WAITING_LOBBY
					and LobbyQueue.playerQueuedTeam(state, p) ~= nil
				if not ok then
					child:SetAttribute(OCC_ATTR, nil)
				end
			end
		end
	end
end

local function init(state, remotes, teleportPlayerTo)
	local container = getPadsContainer()
	rebuildPadList(container)
	if container then
		container.ChildAdded:Connect(function()
			task.defer(function()
				rebuildPadList(getPadsContainer())
			end)
		end)
		container.ChildRemoved:Connect(function()
			task.defer(function()
				rebuildPadList(getPadsContainer())
			end)
		end)
		container.Destroying:Connect(function()
			table.clear(cachedPads)
		end)
	end

	local acc = 0
	local interval = LobbyConfig.LOBBY_PAD_POLL_INTERVAL or 0.2
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < interval then
			return
		end
		acc = 0
		if #cachedPads == 0 then
			local c = getPadsContainer()
			if c then
				rebuildPadList(c)
			end
		end
		if #cachedPads == 0 then
			return
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local phase = state.playerPhase[player.UserId]
			if phase ~= LobbyConfig.PHASE.ARENA then
				local char = player.Character
				if not char then
					if phase == LobbyConfig.PHASE.WAITING_LOBBY then
						LobbyQueue.removeFromWaitingQueue(state, player)
						clearPadOccupantForUser(player.UserId)
						LobbyQueue.maybeCancelCountdown(state, remotes)
						remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
						LobbyQueue.broadcastStateToWaiting(state, remotes)
					end
				else
					local humanoid = char:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local padModel, padTeam = getValidQueuePadModelAndTeam(state, player, char)
						local queued = LobbyQueue.playerQueuedTeam(state, player)
						if padModel and padTeam then
							if phase ~= LobbyConfig.PHASE.WAITING_LOBBY or queued ~= padTeam then
								LobbyQueue.addPlayerToTeamQueue(state, remotes, teleportPlayerTo, player, padTeam, true)
							end
							if not SHARED_PADS and LobbyQueue.playerQueuedTeam(state, player) == padTeam then
								syncPlayerPadOccupancy(player.UserId, padModel)
							end
						elseif queued then
							LobbyQueue.removeFromWaitingQueue(state, player)
							clearPadOccupantForUser(player.UserId)
							LobbyQueue.maybeCancelCountdown(state, remotes)
							remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
							LobbyQueue.broadcastStateToWaiting(state, remotes)
						end
					end
				end
			end
		end

		reconcilePadOccupancyWithQueues(state)
		tryFireTeamQueueBalanceToasts(state, remotes)
		LobbyPadScreens.sync(state)
	end)
end

return {
	Init = init,
	clearPadOccupantForUser = clearPadOccupantForUser,
}
