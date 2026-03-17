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

local LobbyServiceModule = require(LobbyService)
local CombatServiceModule = require(CombatService)
CombatServiceModule.Init()

LobbyServiceModule.Init(function(players)
	CombatServiceModule.StartRound(players, function()
		for _, p in ipairs(players) do
			LobbyServiceModule.ReturnPlayerToShop(p)
		end
	end)
end)

print("Server startup complete.")
