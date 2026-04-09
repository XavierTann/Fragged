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

local LobbyServiceModule = require(LobbyService)
local CombatServiceModule = require(CombatService)
local EconomyServiceModule = require(EconomyService)
local DropServiceModule = require(DropService)
local CharacterServiceModule = require(CharacterService)
local LoadoutServiceModule = require(LoadoutService)
local WeaponInventoryServer = require(Services:WaitForChild("CombatService"):WaitForChild("WeaponInventoryServer"))

CharacterServiceModule.Init()
CombatServiceModule.Init()
EconomyServiceModule.Init()
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
	CombatServiceModule.StartRound(players, function()
		for _, p in ipairs(players) do
			LobbyServiceModule.ReturnPlayerToLobby(p)
		end
	end, playerTeamsMap)
end)

print("Server startup complete.")
