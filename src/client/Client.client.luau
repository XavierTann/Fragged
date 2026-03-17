--[[
	Client root startup script.
	Requires each client service module and calls its Init().
]]

print("Client starting.")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyConfig = require(Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
LobbyServiceClient.Init()

local CombatServiceClient = require(Shared.Services.CombatServiceClient)
CombatServiceClient.Init()

local TopDownCameraService = require(Shared.Services.TopDownCameraService)
TopDownCameraService.Init()

local LobbyGUI = require(Shared.UI.LobbyGUI)
LobbyGUI.Init()
LobbyGUI.Show()


local RotationJoystickGUI = require(Shared.UI.RotationJoystickGUI)
RotationJoystickGUI.Init()

-- Enable shooting only in arena
LobbyServiceClient.Subscribe(function(state)
	local inArena = state and state.phase == LobbyConfig.PHASE.ARENA
	CombatServiceClient.SetShootingEnabled(inArena)
end)
CombatServiceClient.SetShootingEnabled(LobbyServiceClient.GetState() and LobbyServiceClient.GetState().phase == LobbyConfig.PHASE.ARENA)

print("Client startup complete.")
