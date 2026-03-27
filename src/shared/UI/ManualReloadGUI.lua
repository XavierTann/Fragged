--[[
	ManualReloadGUI
	Top-right reload icon below HealthGUI; requests server reload for magazine weapons only.
]]

local RELOAD_ICON_ASSET_ID = "rbxassetid://6943199776"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local GunsConfig = require(Shared.Modules.GunsConfig)

local LocalPlayer = Players.LocalPlayer

local gui = nil
local reloadBtn = nil

-- Match HealthGUI outer frame: BAR_HEIGHT 14 + vertical padding 16
local HEALTH_STRIP_HEIGHT = 30
local GAP = 8
local BUTTON_SIZE = 48

local function updateButtonVisual()
	if not reloadBtn then
		return
	end
	local gunId = CombatServiceClient.GetCurrentWeapon()
	local gun = GunsConfig[gunId]
	if not gun then
		reloadBtn.Visible = false
		return
	end
	reloadBtn.Visible = true
	local state = CombatServiceClient.GetAmmoState(gunId)
	local maxMag = gun.magazineSize or 6
	local canReload = not state.isReloading and state.ammo < maxMag
	reloadBtn.Active = canReload
	reloadBtn.AutoButtonColor = canReload
	reloadBtn.ImageTransparency = canReload and 0 or 0.45
end

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "ManualReloadGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	reloadBtn = Instance.new("ImageButton")
	reloadBtn.Name = "ReloadButton"
	reloadBtn.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	reloadBtn.AnchorPoint = Vector2.new(1, 0)
	reloadBtn.Position = UDim2.new(1, 0, 0, HEALTH_STRIP_HEIGHT + GAP)
	reloadBtn.BackgroundTransparency = 1
	reloadBtn.BorderSizePixel = 0
	reloadBtn.Image = RELOAD_ICON_ASSET_ID
	reloadBtn.ScaleType = Enum.ScaleType.Fit
	reloadBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
	reloadBtn.AutoButtonColor = true
	reloadBtn.Parent = gui

	reloadBtn.Activated:Connect(function()
		CombatServiceClient.RequestReload()
		task.defer(updateButtonVisual)
	end)

	return gui
end

local function init()
	createGui()
	CombatServiceClient.SubscribeAmmoState(function()
		updateButtonVisual()
	end)
	CombatServiceClient.SubscribeWeaponChanged(function()
		updateButtonVisual()
	end)
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateButtonVisual()
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
