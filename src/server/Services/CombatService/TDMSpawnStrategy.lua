--[[
	TDMSpawnStrategy
	TDM-only spawn strategy: random spawn from TDMSpawnLocations, avoids nearby enemies.
	Modular and swappable; other modes can use different strategies.
]]

local Workspace = game:GetService("Workspace")

local TDMConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.TDMConfig)

local PARENT_FOLDER_NAME = TDMConfig.TDM_SPAWN_PARENT
local FOLDER_NAME = TDMConfig.TDM_SPAWN_FOLDER
local SAFE_DISTANCE = TDMConfig.TDM_SAFE_DISTANCE
local MAX_ATTEMPTS = TDMConfig.TDM_SPAWN_MAX_ATTEMPTS

-- Fallback positions when TDMSpawnLocations folder is empty or missing
local FALLBACK_POSITIONS = {
	Vector3.new(35, 5, -8),
	Vector3.new(45, 5, 8),
	Vector3.new(40, 5, 0),
	Vector3.new(30, 5, 0),
	Vector3.new(50, 5, 0),
	Vector3.new(40, 5, -15),
	Vector3.new(40, 5, 15),
	Vector3.new(25, 5, -5),
	Vector3.new(55, 5, 5),
}

local function getFolder()
	local parent = Workspace:FindFirstChild(PARENT_FOLDER_NAME)
	if not parent then
		parent = Instance.new("Folder")
		parent.Name = PARENT_FOLDER_NAME
		parent.Parent = Workspace
	end
	local folder = parent:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = parent
	end
	return folder
end

local function ensureFallbackSpawns(folder)
	local children = folder:GetChildren()
	local hasValidSpawn = false
	for _, child in ipairs(children) do
		if child:IsA("BasePart") or child:IsA("Model") and child.PrimaryPart then
			hasValidSpawn = true
			break
		end
	end
	if hasValidSpawn then
		return
	end
	for i, pos in ipairs(FALLBACK_POSITIONS) do
		local part = Instance.new("Part")
		part.Name = "TDMSpawnLocation" .. tostring(i)
		part.Size = Vector3.new(6, 1, 6)
		part.Position = pos
		part.Anchored = true
		part.Transparency = 1
		part.CanCollide = true
		part.Parent = folder
	end
end

local function getSpawnPoints()
	local folder = getFolder()
	ensureFallbackSpawns(folder)
	local points = {}
	for _, child in ipairs(folder:GetChildren()) do
		local part, cf
		if child:IsA("BasePart") then
			part = child
			cf = child.CFrame
		elseif child:IsA("Model") and child.PrimaryPart then
			part = child.PrimaryPart
			cf = child.PrimaryPart.CFrame
		end
		if part and cf then
			table.insert(points, { part = part, cf = cf })
		end
	end
	return points
end

local function getPositionFromSpawnPoint(sp)
	local part = sp.part
	local cf = sp.cf
	local offset = part and part:IsA("BasePart") and (part.Size.Y / 2 + 2.5) or 3
	return (cf + Vector3.new(0, offset, 0)).Position
end

local function getCFrameFromSpawnPoint(sp)
	local part = sp.part
	local cf = sp.cf
	local offset = part and part:IsA("BasePart") and (part.Size.Y / 2 + 2.5) or 3
	return cf + Vector3.new(0, offset, 0)
end

local function hasEnemyNearby(position, playerTeam, playerTeams, currentRoundPlayers, excludeUserId)
	local safeSq = SAFE_DISTANCE * SAFE_DISTANCE
	for _, p in ipairs(currentRoundPlayers or {}) do
		if p and p.Parent and p.UserId ~= excludeUserId then
			local otherTeam = playerTeams and playerTeams[p.UserId]
			if otherTeam and otherTeam ~= playerTeam then
				local char = p.Character
				if char then
					local root = char:FindFirstChild("HumanoidRootPart")
					if root and root.Position then
						local humanoid = char:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 then
							local delta = root.Position - position
							if delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z <= safeSq then
								return true
							end
						end
					end
				end
			end
		end
	end
	return false
end

--[[
	@param player Player
	@param context { playerTeams: { [userId]: team }, currentRoundPlayers: Player[] }
	@return CFrame
]]
local function getSpawnCFrame(player, context)
	local playerTeams = context and context.playerTeams or {}
	local currentRoundPlayers = context and context.currentRoundPlayers or {}
	local playerTeam = playerTeams[player.UserId]

	local points = getSpawnPoints()
	if #points == 0 then
		return CFrame.new(0, 10, 0)
	end

	-- Shuffle for random selection
	local shuffled = table.clone(points)
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local attempts = 0
	for _, sp in ipairs(shuffled) do
		attempts = attempts + 1
		local pos = getPositionFromSpawnPoint(sp)
		if not hasEnemyNearby(pos, playerTeam, playerTeams, currentRoundPlayers, player.UserId) then
			return getCFrameFromSpawnPoint(sp)
		end
		if attempts >= MAX_ATTEMPTS then
			break
		end
	end

	-- Fallback: use any random spawn
	local idx = math.random(1, #points)
	return getCFrameFromSpawnPoint(points[idx])
end

return {
	getSpawnCFrame = getSpawnCFrame,
}
