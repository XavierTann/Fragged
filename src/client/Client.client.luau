--[[
	Client root startup script.
	Requires each client service module and calls its Init().
]]

print("Client starting.")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Enable template ScreenGui at runtime (often disabled in Studio); keep ResetOnSpawn off so HUD is not re-cloned each life.
task.spawn(function()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function enableMainTemplate(inst)
		if inst and inst:IsA("ScreenGui") and inst.Name == "ScreenGui" then
			inst.ResetOnSpawn = false
			inst.Enabled = true
		end
	end
	pg.ChildAdded:Connect(enableMainTemplate)
	local sg = pg:FindFirstChild("ScreenGui") or pg:WaitForChild("ScreenGui")
	enableMainTemplate(sg)
end)

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

local FTUEPadArrowsGUI = require(Shared.UI.FTUEPadArrowsGUI)
FTUEPadArrowsGUI.Init()

local CenterScreenToast = require(Shared.UI.CenterScreenToast)
CenterScreenToast.Init()

local LobbyMatchStartToastClient = require(Shared.Services.LobbyMatchStartToastClient)
LobbyMatchStartToastClient.Init()

local LobbyTeamBalanceToastClient = require(Shared.Services.LobbyTeamBalanceToastClient)
LobbyTeamBalanceToastClient.Init()

local LobbyPadLightBeamPulse = require(Shared.Services.LobbyPadLightBeamPulse)
LobbyPadLightBeamPulse.Init()

local ShopGUI = require(Shared.UI.Shop.ShopGUI)
ShopGUI.Init()

local ShopKeeperPromptClient = require(Shared.Services.ShopKeeperPromptClient)
ShopKeeperPromptClient.Init()

local CombatServiceClient = require(Shared.Services.CombatServiceClient)
CombatServiceClient.Init()

local TopDownCameraService = require(Shared.Services.TopDownCameraService)
TopDownCameraService.Init()

LobbyServiceClient.OnTeleportToArena(function()
	TopDownCameraService.ArenaEntranceCameraReset()
end)

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

local LowHealthDecalGUI = require(Shared.UI.LowHealthDecalGUI)
LowHealthDecalGUI.Init()

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

local LoadoutGUI = require(Shared.UI.LoadoutGUI)
LoadoutGUI.Init()

local LeaveMatchGUI = require(Shared.UI.LeaveMatchGUI)
LeaveMatchGUI.Init()

local GachaGUI = require(Shared.UI.GachaGUI)
GachaGUI.Init()

local LobbyMenuDockGUI = require(Shared.UI.LobbyMenuDockGUI)
LobbyMenuDockGUI.Init()

local GachaServiceClient = require(Shared.Services.GachaServiceClient)
GachaServiceClient.Init()

local WeaponStoragePromptClient = require(Shared.Services.WeaponStoragePromptClient)
WeaponStoragePromptClient.Init()

local postMatchLeaderboard = false
local wasInArena = false

local function applyArenaHud(inArena, hideLeaderboardOverlay)
	local combatHud = inArena and not postMatchLeaderboard
	CombatServiceClient.SetShootingEnabled(combatHud)
	TopDownCameraService.SetEnabled(inArena)
	if inArena then
		TopDownCameraService.SetFollowFrozen(postMatchLeaderboard)
	else
		TopDownCameraService.SetFollowFrozen(false)
	end
	DirectionIndicatorClient.SetEnabled(combatHud)
	if hideLeaderboardOverlay then
		LeaderboardGUI.Hide()
	end
	if combatHud then
		RotationJoystickGUI.Show()
	else
		RotationJoystickGUI.Hide()
	end
	if inArena and not postMatchLeaderboard then
		LoadoutGUI.Hide()
		WeaponSelectGUI.Show()
		ReloadBarGUI.Show()
		ManualReloadGUI.Show()
		TDMScoreGUI.Show()
		HealthGUI.Show()
		LowHealthDecalGUI.Show()
		TeamIndicatorGUI.Show()
		LeaveMatchGUI.Show()
		CombatServiceClient.SetCurrentWeapon(CombatServiceClient.GetCurrentWeapon())
	elseif not inArena then
		WeaponSelectGUI.Hide()
		ReloadBarGUI.Hide()
		ManualReloadGUI.Hide()
		TDMScoreGUI.Hide()
		HealthGUI.Hide()
		LowHealthDecalGUI.Hide()
		RespawnTimerGUI.Hide()
		OverheadHealthBarGUI.Hide()
		TeamIndicatorGUI.Hide()
		LeaveMatchGUI.Hide()
	end
end

CombatServiceClient.SubscribeMatchEnded(function(payload)
	postMatchLeaderboard = true
	CombatServiceClient.SetShootingEnabled(false)
	TopDownCameraService.SetEnabled(true)
	TopDownCameraService.SetFollowFrozen(true)
	DirectionIndicatorClient.SetEnabled(false)
	RotationJoystickGUI.Hide()
	LoadoutGUI.Hide()
	WeaponSelectGUI.Hide()
	ReloadBarGUI.Hide()
	ManualReloadGUI.Hide()
	TDMScoreGUI.Hide()
	HealthGUI.Hide()
	LowHealthDecalGUI.Hide()
	RespawnTimerGUI.Hide()
	OverheadHealthBarGUI.Hide()
	TeamIndicatorGUI.Hide()
	LeaveMatchGUI.Hide()
	if payload then
		LeaderboardGUI.Show(payload)
	end
end)

LobbyServiceClient.OnTeleportToLobby(function()
	postMatchLeaderboard = false
	LeaderboardGUI.Hide()
	RotationJoystickGUI.Hide()
	CombatServiceClient.SetShootingEnabled(false)
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
