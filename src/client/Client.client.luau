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

local CharacterServiceClient = require(Shared.Services.CharacterServiceClient)
CharacterServiceClient.Init()

local DirectionIndicatorClient = require(Shared.Services.DirectionIndicatorClient)
DirectionIndicatorClient.Init()

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

local ManualReloadGUI = require(Shared.UI.ManualReloadGUI)
ManualReloadGUI.Init()

local LeaderboardGUI = require(Shared.UI.LeaderboardGUI)
LeaderboardGUI.Init()

local TDMScoreGUI = require(Shared.UI.TDMScoreGUI)
TDMScoreGUI.Init()

local HealthGUI = require(Shared.UI.HealthGUI)
HealthGUI.Init()

local RespawnTimerGUI = require(Shared.UI.RespawnTimerGUI)
RespawnTimerGUI.Init()

local OverheadHealthBarGUI = require(Shared.UI.OverheadHealthBarGUI)
OverheadHealthBarGUI.Init()

local FloatingDamageNumbers = require(Shared.UI.FloatingDamageNumbers)
FloatingDamageNumbers.Init()

local KillNotificationGUI = require(Shared.UI.KillNotificationGUI)
KillNotificationGUI.Init()

local TeamIndicatorGUI = require(Shared.UI.TeamIndicatorGUI)
TeamIndicatorGUI.Init()

local postMatchLeaderboard = false
local wasInArena = false

local function applyArenaHud(inArena, hideLeaderboardOverlay)
	CombatServiceClient.SetShootingEnabled(inArena and not postMatchLeaderboard)
	if hideLeaderboardOverlay then
		LeaderboardGUI.Hide()
	end
	if inArena and not postMatchLeaderboard then
		WeaponSelectGUI.Show()
		ReloadBarGUI.Show()
		ManualReloadGUI.Show()
		TDMScoreGUI.Show()
		HealthGUI.Show()
		TeamIndicatorGUI.Show()
		CombatServiceClient.SetCurrentWeapon(CombatServiceClient.GetCurrentWeapon())
	elseif not inArena then
		WeaponSelectGUI.Hide()
		ReloadBarGUI.Hide()
		ManualReloadGUI.Hide()
		TDMScoreGUI.Hide()
		HealthGUI.Hide()
		RespawnTimerGUI.Hide()
		OverheadHealthBarGUI.Hide()
		TeamIndicatorGUI.Hide()
	end
end

CombatServiceClient.SubscribeMatchEnded(function(payload)
	postMatchLeaderboard = true
	WeaponSelectGUI.Hide()
	ReloadBarGUI.Hide()
	ManualReloadGUI.Hide()
	TDMScoreGUI.Hide()
	HealthGUI.Hide()
	RespawnTimerGUI.Hide()
	OverheadHealthBarGUI.Hide()
	TeamIndicatorGUI.Hide()
	if payload then
		LeaderboardGUI.Show(payload)
	end
end)

-- Enable shooting and weapon select only in arena
LobbyServiceClient.Subscribe(function(state)
	local inArena = state and state.phase == LobbyConfig.PHASE.ARENA
	local previousInArena = wasInArena
	if inArena and not previousInArena then
		postMatchLeaderboard = false
	end
	wasInArena = inArena == true
	local hideLeaderboardOverlay = (not inArena) or (inArena and not previousInArena)
	applyArenaHud(inArena, hideLeaderboardOverlay)
end)

local initialState = LobbyServiceClient.GetState()
local initialInArena = initialState and initialState.phase == LobbyConfig.PHASE.ARENA
wasInArena = initialInArena == true
local initialHideLeaderboard = not initialInArena
applyArenaHud(initialInArena, initialHideLeaderboard)

print("Client startup complete.")
