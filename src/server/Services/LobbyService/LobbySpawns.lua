--[[
	LobbySpawns
	Spawn locations and player teleportation.
]]

local Workspace = game:GetService("Workspace")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)

local SPAWN_OFFSETS = {
	[LobbyConfig.SPAWN_NAMES.SHOP] = Vector3.new(-14, 5, 0),
	[LobbyConfig.SPAWN_NAMES.LOBBY] = Vector3.new(20, 5, 0),
	[LobbyConfig.SPAWN_NAMES.RED_TEAM] = Vector3.new(35, 5, -8),
	[LobbyConfig.SPAWN_NAMES.BLUE_TEAM] = Vector3.new(45, 5, 8),
}

local function getSpawnsFolder()
	local folder = Workspace:FindFirstChild(LobbyConfig.SPAWNS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LobbyConfig.SPAWNS_FOLDER_NAME
		folder.Parent = Workspace
		for name, offset in pairs(SPAWN_OFFSETS) do
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = name
			spawn.Size = Vector3.new(6, 1, 6)
			spawn.Position = offset
			spawn.Anchored = true
			spawn.Transparency = 1
			spawn.CanCollide = true
			spawn.Neutral = true
			spawn.Enabled = (name == LobbyConfig.SPAWN_NAMES.SHOP)
			spawn.Parent = folder
		end
	end
	return folder
end

local function getSpawnCFrame(spawnName)
	local folder = getSpawnsFolder()
	if not folder then
		return CFrame.new(0, 10, 0)
	end
	local spawn = folder:FindFirstChild(spawnName)
	if not spawn then
		return CFrame.new(0, 10, 0)
	end
	local cf, part
	if spawn:IsA("BasePart") then
		part = spawn
		cf = spawn.CFrame
	elseif spawn:IsA("Model") and spawn.PrimaryPart then
		part = spawn.PrimaryPart
		cf = spawn.PrimaryPart.CFrame
	else
		return CFrame.new(0, 10, 0)
	end
	local offset = part and part:IsA("BasePart") and (part.Size.Y / 2 + 2.5) or 3
	return cf + Vector3.new(0, offset, 0)
end

local function teleportPlayerTo(player, spawnName)
	local cf = getSpawnCFrame(spawnName)
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char.HumanoidRootPart.CFrame = cf
	end
end

local function configureSpawnLocations()
	local folder = getSpawnsFolder()
	if not folder then
		return
	end
	local shopSpawn = folder:FindFirstChild(LobbyConfig.SPAWN_NAMES.SHOP)
	if shopSpawn and shopSpawn:IsA("SpawnLocation") then
		shopSpawn.Neutral = true
		shopSpawn.Enabled = true
	end
end

return {
	getSpawnsFolder = getSpawnsFolder,
	getSpawnCFrame = getSpawnCFrame,
	teleportPlayerTo = teleportPlayerTo,
	configureSpawnLocations = configureSpawnLocations,
}
