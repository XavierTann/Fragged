--[[
	LobbyPadZones
	Players queue by standing on pad models under Workspace/Lobby/SpawnPads:
	six Models named "BluePad" (Blue) and six named "RedPad" (Red).
	Queue if HRP is inside the pad model’s X–Z bounds (bounding box local X/Z); Y ignored.

	Each pad may be claimed by at most one queued player (attribute LobbyPadOccupantUserId).
	Others overlapping that pad see a toast and cannot queue there; LightBeam is fully hidden on occupied pads.

	Team balance: when one queue has more players than the other, fuller-team pads stay
	suppressed unless a player already queued for that team stands on that pad (XZ).
	Others standing on extra fuller pads see toast + dimmed beam; they cannot queue there.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local LobbyQueue = require(script.Parent.LobbyQueue)

local SUP_ATTR = LobbyConfig.LOBBY_PAD_SUPPRESSED_ATTRIBUTE or "LobbyPadSuppressed"
local OCC_ATTR = LobbyConfig.LOBBY_PAD_OCCUPANT_USER_ID_ATTRIBUTE or "LobbyPadOccupantUserId"

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

-- True if a player already in `team`’s queue has HRP on this pad (XZ only).
-- Ignores non-queued players so extra fuller-team pads stay suppressed when someone steps on them.
local function isPadOccupiedByQueuedMemberOfTeam(state, model, team)
	for _, player in ipairs(Players:GetPlayers()) do
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.ARENA then
			if LobbyQueue.playerQueuedTeam(state, player) == team then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
					if hrpOverlapsModelBounds(hrp, model) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function isPadActiveForFullerTeamQueue(state, model, fullerTeam)
	local team = teamForPadName(model.Name)
	if team ~= fullerTeam then
		return false
	end
	local occUid = getOccupantUserId(model)
	if occUid then
		local p = Players:GetPlayerByUserId(occUid)
		if p and LobbyQueue.playerQueuedTeam(state, p) == fullerTeam then
			return true
		end
	end
	return isPadOccupiedByQueuedMemberOfTeam(state, model, fullerTeam)
end

local function updatePadSuppression(state)
	local folder = getPadsContainer()
	if not folder then
		return
	end
	local bCount = #state.waitingQueueBlue
	local rCount = #state.waitingQueueRed
	if bCount == rCount then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and teamForPadName(child.Name) then
				child:SetAttribute(SUP_ATTR, false)
			end
		end
		return
	end
	local fullerTeam = bCount > rCount and "Blue" or "Red"
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local team = teamForPadName(child.Name)
			if team then
				if team == fullerTeam then
					child:SetAttribute(SUP_ATTR, not isPadActiveForFullerTeamQueue(state, child, fullerTeam))
				else
					child:SetAttribute(SUP_ATTR, false)
				end
			end
		end
	end
end

local function tryFireQueueBalanceToasts(state, remotes)
	local toastRe = remotes and remotes.QueueBalanceToast
	if not toastRe then
		return
	end
	local bCount = #state.waitingQueueBlue
	local rCount = #state.waitingQueueRed
	if bCount == rCount then
		return
	end
	local fuller = bCount > rCount and "Blue" or "Red"
	local other = fuller == "Blue" and "Red" or "Blue"
	local folder = getPadsContainer()
	if not folder then
		return
	end
	local cooldown = LobbyConfig.LOBBY_QUEUE_BALANCE_TOAST_COOLDOWN or 5
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.ARENA then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				local uid = player.UserId
				for _, child in ipairs(folder:GetChildren()) do
					if
						child:IsA("Model")
						and teamForPadName(child.Name) == fuller
						and child:GetAttribute(SUP_ATTR) == true
					then
						if hrpOverlapsModelBounds(hrp, child) then
							if now >= (state.balanceToastCooldown[uid] or 0) then
								toastRe:FireClient(player, fuller, other)
								state.balanceToastCooldown[uid] = now + cooldown
							end
							break
						end
					end
				end
			end
		end
	end
end

local function overlapsAnotherPlayersOccupiedPad(hrp, player)
	for _, entry in ipairs(cachedPads) do
		if hrpOverlapsModelBounds(hrp, entry.model) then
			local occ = getOccupantUserId(entry.model)
			if occ and occ ~= player.UserId then
				return true
			end
		end
	end
	return false
end

local function tryFirePadOccupiedToasts(state, remotes)
	local toastRe = remotes and remotes.PadOccupiedToast
	if not toastRe then
		return
	end
	local cooldown = LobbyConfig.LOBBY_PAD_OCCUPIED_TOAST_COOLDOWN or 4
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		if state.playerPhase[player.UserId] ~= LobbyConfig.PHASE.ARENA then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				if overlapsAnotherPlayersOccupiedPad(hrp, player) then
					local uid = player.UserId
					if now >= (state.padOccupiedToastCooldown[uid] or 0) then
						toastRe:FireClient(player)
						state.padOccupiedToastCooldown[uid] = now + cooldown
					end
				end
			end
		end
	end
end

--[[
	Non-suppressed pad overlapping HRP where no other player holds the pad (or this player holds it).
	If already queued, prefer a candidate matching that team.
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
		if model:GetAttribute(SUP_ATTR) ~= true and hrpOverlapsModelBounds(hrp, model) then
			local occ = getOccupantUserId(model)
			if not occ or occ == player.UserId then
				candidates[#candidates + 1] = entry
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
				updatePadSuppression(state)
			end)
		end)
		container.ChildRemoved:Connect(function()
			task.defer(function()
				rebuildPadList(getPadsContainer())
				updatePadSuppression(state)
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
							if LobbyQueue.playerQueuedTeam(state, player) == padTeam then
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

		updatePadSuppression(state)
		tryFirePadOccupiedToasts(state, remotes)
		tryFireQueueBalanceToasts(state, remotes)
		reconcilePadOccupancyWithQueues(state)
	end)
end

return {
	Init = init,
	clearPadOccupantForUser = clearPadOccupantForUser,
}
