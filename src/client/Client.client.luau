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

local MountUI = require(Shared.UI.MountUI)
MountUI.Init()

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

local ScoreboardButtonGUI = require(Shared.UI.ScoreboardButtonGUI)
ScoreboardButtonGUI.Init()

local TDMScoreGUI = require(Shared.UI.TDMScoreGUI)
TDMScoreGUI.Init()

local HealthGUI = require(Shared.UI.HealthGUI)
HealthGUI.Init()

local RespawnTimerGUI = require(Shared.UI.RespawnTimerGUI)
RespawnTimerGUI.Init()

local OverheadHealthBarGUI = require(Shared.UI.OverheadHealthBarGUI)
OverheadHealthBarGUI.Init()

local TeamIndicatorGUI = require(Shared.UI.TeamIndicatorGUI)
TeamIndicatorGUI.Init()

local postMatchLeaderboard = false
local wasInArena = false

local function applyArenaHud(inArena, showScoreboardButton, hideLeaderboardOverlay)
	CombatServiceClient.SetShootingEnabled(inArena and not postMatchLeaderboard)
	ScoreboardButtonGUI.SetVisible(showScoreboardButton == true)
	if hideLeaderboardOverlay then
		LeaderboardGUI.Hide()
	end
	if inArena and not postMatchLeaderboard then
		WeaponSelectGUI.Show()
		ReloadBarGUI.Show()
		TDMScoreGUI.Show()
		HealthGUI.Show()
		TeamIndicatorGUI.Show()
		CombatServiceClient.SetCurrentWeapon(CombatServiceClient.GetCurrentWeapon())
	elseif not inArena then
		WeaponSelectGUI.Hide()
		ReloadBarGUI.Hide()
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
	TDMScoreGUI.Hide()
	HealthGUI.Hide()
	RespawnTimerGUI.Hide()
	OverheadHealthBarGUI.Hide()
	TeamIndicatorGUI.Hide()
	ScoreboardButtonGUI.SetVisible(false)
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
	local showScoreboardButton = inArena and not postMatchLeaderboard
	local hideLeaderboardOverlay = (not inArena) or (inArena and not previousInArena)
	applyArenaHud(inArena, showScoreboardButton, hideLeaderboardOverlay)
end)

local initialState = LobbyServiceClient.GetState()
local initialInArena = initialState and initialState.phase == LobbyConfig.PHASE.ARENA
wasInArena = initialInArena == true
local initialHideLeaderboard = not initialInArena
applyArenaHud(initialInArena, initialInArena and not postMatchLeaderboard, initialHideLeaderboard)

print("Client startup complete.")
