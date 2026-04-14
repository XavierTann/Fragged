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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("CombatConfig"))

local LobbyServiceModule = require(LobbyService)
local CombatServiceModule = require(CombatService)
local EconomyServiceModule = require(EconomyService)
local DropServiceModule = require(DropService)
local CharacterServiceModule = require(CharacterService)
local LoadoutServiceModule = require(LoadoutService)
local GachaServiceModule = require(GachaService)
local WeaponInventoryServer = require(Services:WaitForChild("CombatService"):WaitForChild("WeaponInventoryServer"))

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

LobbyServiceModule.Init(function(players, playerTeamsMap)
	DropServiceModule.Start()
	CombatServiceModule.StartRound(players, function()
		DropServiceModule.Stop()
		for _, p in ipairs(players) do
			LobbyServiceModule.ReturnPlayerToLobby(p)
		end
	end, playerTeamsMap)
end)

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
	leaveRE.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if leaveCooldowns[player.UserId] and now - leaveCooldowns[player.UserId] < 2 then
			return
		end
		leaveCooldowns[player.UserId] = now
		local removed = CombatServiceModule.RemovePlayerFromRound(player)
		if removed then
			LobbyServiceModule.ReturnPlayerToLobby(player)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		leaveCooldowns[player.UserId] = nil
	end)
end

print("Server startup complete.")
