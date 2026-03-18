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

local WeaponSelectGUI = require(Shared.UI.WeaponSelectGUI)
WeaponSelectGUI.Init()

local ReloadBarGUI = require(Shared.UI.ReloadBarGUI)
ReloadBarGUI.Init()

-- -- Enable shooting and weapon select only in arena
-- LobbyServiceClient.Subscribe(function(state)
-- 	local inArena = state and state.phase == LobbyConfig.PHASE.ARENA
-- 	CombatServiceClient.SetShootingEnabled(inArena)
-- 	if inArena then
-- 		WeaponSelectGUI.Show()
-- 		ReloadBarGUI.Show()
-- 	else
-- 		WeaponSelectGUI.Hide()
-- 		ReloadBarGUI.Hide()
-- 	end
-- end)


-- For Testing
CombatServiceClient.SetShootingEnabled(true)
WeaponSelectGUI.Show()
ReloadBarGUI.Show()

-- local initialState = LobbyServiceClient.GetState()
-- local inArena = initialState and initialState.phase == LobbyConfig.PHASE.ARENA
-- CombatServiceClient.SetShootingEnabled(inArena)
-- if inArena then
-- 	WeaponSelectGUI.Show()
-- 	ReloadBarGUI.Show()
-- end

print("Client startup complete.")
