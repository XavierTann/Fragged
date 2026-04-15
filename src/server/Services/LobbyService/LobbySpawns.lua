--[[
	LobbySpawns
	Spawn locations and player teleportation.
	LobbySpawnLocation now lives directly under Workspace.
]]

local Workspace = game:GetService("Workspace")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)

local function getLobbySpawn()
	return Workspace:FindFirstChild(LobbyConfig.LOBBY_SPAWN_NAME)
end

local function getSpawnCFrame(spawnName)
	local spawn = Workspace:FindFirstChild(spawnName)
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
	local lobbySpawn = getLobbySpawn()
	if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
		lobbySpawn.Neutral = true
		lobbySpawn.Enabled = true
	end
end

return {
	getLobbySpawn = getLobbySpawn,
	getSpawnCFrame = getSpawnCFrame,
	teleportPlayerTo = teleportPlayerTo,
	configureSpawnLocations = configureSpawnLocations,
}
