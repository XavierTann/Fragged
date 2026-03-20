--[[
	Client root startup script.
	Requires each client service module and calls its Init().
]]

print("Client starting.")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyConfig = require(Shared.Modules.LobbyConfig)
local TouchControlUtils = require(Shared.Modules.TouchControlUtils)
TouchControlUtils.Init()

local StarterGui = game:GetService("StarterGui")
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

local CharacterServiceClient = require(Shared.Services.CharacterServiceClient)
CharacterServiceClient.Init()

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

local LeaderboardGUI = require(Shared.UI.LeaderboardGUI)
LeaderboardGUI.Init()

local TDMScoreGUI = require(Shared.UI.TDMScoreGUI)
TDMScoreGUI.Init()

local HealthGUI = require(Shared.UI.HealthGUI)
HealthGUI.Init()

local RespawnTimerGUI = require(Shared.UI.RespawnTimerGUI)
RespawnTimerGUI.Init()

CombatServiceClient.SubscribeMatchEnded(function(payload)
	WeaponSelectGUI.Hide()
	ReloadBarGUI.Hide()
	TDMScoreGUI.Hide()
	HealthGUI.Hide()
	RespawnTimerGUI.Hide()
	if payload then
		LeaderboardGUI.Show(payload)
	end
end)

-- Enable shooting and weapon select only in arena
LobbyServiceClient.Subscribe(function(state)
	local inArena = state and state.phase == LobbyConfig.PHASE.ARENA
	CombatServiceClient.SetShootingEnabled(inArena)
	if inArena then
		WeaponSelectGUI.Show()
		ReloadBarGUI.Show()
		TDMScoreGUI.Show()
		HealthGUI.Show()
		LeaderboardGUI.Hide()
		CombatServiceClient.SetCurrentWeapon(CombatServiceClient.GetCurrentWeapon())
	else
		WeaponSelectGUI.Hide()
		ReloadBarGUI.Hide()
		TDMScoreGUI.Hide()
		HealthGUI.Hide()
		RespawnTimerGUI.Hide()
		LeaderboardGUI.Hide()
	end
end)

local initialState = LobbyServiceClient.GetState()
local inArena = initialState and initialState.phase == LobbyConfig.PHASE.ARENA
CombatServiceClient.SetShootingEnabled(inArena)
if inArena then
	WeaponSelectGUI.Show()
	ReloadBarGUI.Show()
	TDMScoreGUI.Show()
	HealthGUI.Show()
	CombatServiceClient.SetCurrentWeapon(CombatServiceClient.GetCurrentWeapon())
else
	WeaponSelectGUI.Hide()
	ReloadBarGUI.Hide()
	TDMScoreGUI.Hide()
	HealthGUI.Hide()
	RespawnTimerGUI.Hide()
end

print("Client startup complete.")
