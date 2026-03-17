--[[
	WeaponSelectGUI
	Bottom-center bar with weapon buttons. Click to switch weapons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local gui = nil
local buttonMap = {} -- gunId -> TextButton

local WEAPON_ORDER = { "Pistol", "Rifle", "Shotgun" }
local BAR_HEIGHT = 56
local BUTTON_WIDTH = 100
local BUTTON_GAP = 8

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponSelectGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function updateSelection(gunId)
	for id, btn in pairs(buttonMap) do
		if id == gunId then
			btn.BackgroundColor3 = Color3.fromRGB(70, 90, 120)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
			btn.TextColor3 = Color3.fromRGB(200, 200, 200)
		end
	end
end

local function createWeaponBar(parent)
	local totalWidth = #WEAPON_ORDER * BUTTON_WIDTH + (#WEAPON_ORDER - 1) * BUTTON_GAP
	local bar = Instance.new("Frame")
	bar.Name = "WeaponBar"
	bar.Size = UDim2.fromOffset(totalWidth + 24, BAR_HEIGHT + 16)
	bar.Position = UDim2.new(0.5, 0, 1, -BAR_HEIGHT - 24)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	bar.BorderSizePixel = 0
	bar.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar

	for i, gunId in ipairs(WEAPON_ORDER) do
		local gun = GunsConfig[gunId]
		if gun then
			local btn = Instance.new("TextButton")
			btn.Name = gunId
			btn.Size = UDim2.fromOffset(BUTTON_WIDTH, BAR_HEIGHT)
			btn.Position = UDim2.fromOffset(12 + (i - 1) * (BUTTON_WIDTH + BUTTON_GAP), 8)
			btn.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
			btn.TextColor3 = Color3.fromRGB(200, 200, 200)
			btn.Text = gun.name or gunId
			btn.TextSize = 16
			btn.Font = Enum.Font.GothamMedium
			btn.BorderSizePixel = 0
			btn.Parent = bar

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 8)
			btnCorner.Parent = btn

			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(0, 4, 1, 0)
			accent.Position = UDim2.fromOffset(0, 0)
			accent.BackgroundColor3 = gun.bulletColor or Color3.fromRGB(150, 150, 150)
			accent.BorderSizePixel = 0
			accent.Parent = btn
			local accentCorner = Instance.new("UICorner")
			accentCorner.CornerRadius = UDim.new(0, 8)
			accentCorner.Parent = accent

			btn.MouseButton1Click:Connect(function()
				CombatServiceClient.SetCurrentWeapon(gunId)
				updateSelection(gunId)
			end)

			buttonMap[gunId] = btn
		end
	end

	updateSelection(CombatServiceClient.GetCurrentWeapon())
end

local function init()
	createGui()
	local container = Instance.new("Frame")
	container.Name = "WeaponSelectContainer"
	container.Size = UDim2.fromScale(1, 1)
	container.Position = UDim2.fromScale(0, 0)
	container.BackgroundTransparency = 1
	container.Parent = gui
	createWeaponBar(container)
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateSelection(CombatServiceClient.GetCurrentWeapon())
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
