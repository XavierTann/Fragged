--[[
	LobbyPadZones
	Players queue by standing on pad models under Workspace/Lobby/SpawnPads:
	six Models named "BluePad" (Blue) and six named "RedPad" (Red).
	Queue if HRP is inside the pad model’s X–Z bounds (bounding box local X/Z); Y ignored.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local LobbyQueue = require(script.Parent.LobbyQueue)

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
	-- Only X–Z vs pad footprint; Y (height) is ignored so jumping / slight levitation still counts.
	local localPos = cf:PointToObjectSpace(hrp.Position)
	local half = size * 0.5
	local pad = 0.6
	return math.abs(localPos.X) <= half.X + pad and math.abs(localPos.Z) <= half.Z + pad
end

local function getTeamPadUnderCharacter(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	for _, entry in ipairs(cachedPads) do
		if hrpOverlapsModelBounds(hrp, entry.model) then
			return entry.team
		end
	end
	return nil
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
						LobbyQueue.maybeCancelCountdown(state, remotes)
						remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
						LobbyQueue.broadcastStateToWaiting(state, remotes)
					end
				else
					local humanoid = char:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local padTeam = getTeamPadUnderCharacter(char)
						local queued = LobbyQueue.playerQueuedTeam(state, player)
						if padTeam then
							if phase ~= LobbyConfig.PHASE.WAITING_LOBBY or queued ~= padTeam then
								LobbyQueue.addPlayerToTeamQueue(state, remotes, teleportPlayerTo, player, padTeam, true)
							end
						elseif queued then
							LobbyQueue.removeFromWaitingQueue(state, player)
							LobbyQueue.maybeCancelCountdown(state, remotes)
							remotes.LobbyState:FireClient(player, LobbyQueue.buildStateForPlayer(state, remotes, player))
							LobbyQueue.broadcastStateToWaiting(state, remotes)
						end
					end
				end
			end
		end
	end)
end

return {
	Init = init,
}
