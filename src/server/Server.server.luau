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
local DropService = Services:WaitForChild("DropService"):WaitForChild("DropServiceServer")

local LobbyServiceModule = require(LobbyService)
local CombatServiceModule = require(CombatService)
local DropServiceModule = require(DropService)
local WeaponInventoryServer = require(Services:WaitForChild("CombatService"):WaitForChild("WeaponInventoryServer"))

CombatServiceModule.Init()

DropServiceModule.SetPickupCallback(function(player, dropType, _drop)
	if dropType == "RocketLauncher" then
		local added = WeaponInventoryServer.addWeapon(player, "RocketLauncher")
		if added then
			CombatServiceModule.InitRocketsForPlayer(player)
			CombatServiceModule.GiveRocketLauncherTool(player)
			return true
		end
	end
	return false
end)
DropServiceModule.Init()

LobbyServiceModule.Init(function(players)
	CombatServiceModule.StartRound(players, function()
		for _, p in ipairs(players) do
			LobbyServiceModule.ReturnPlayerToShop(p)
		end
	end)
end)

print("Server startup complete.")
