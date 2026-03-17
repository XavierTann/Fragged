--[[
	Client root startup script.
	Requires each client service module and calls its Init().
]]

print("Client starting.")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
LobbyServiceClient.Init()

local LobbyGUI = require(Shared.UI.LobbyGUI)
LobbyGUI.Init()
LobbyGUI.Show()

print("Client startup complete.")
