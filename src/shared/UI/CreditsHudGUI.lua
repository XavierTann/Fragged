--[[
	CreditsHudGUI
	Compact pill at the top-right showing the player's current credit balance.
	Subscribes to ShopEconomyClient for live updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopEconomyClient = require(Shared.Services.ShopEconomyClient)
local Theme = require(Shared.UI.Shop.ShopTheme)
local UIConfig = require(Shared.Modules.CreditsHudGUIConfig)

local LocalPlayer = Players.LocalPlayer

local gui: ScreenGui? = nil
local creditLabel: TextLabel? = nil

local function updateText()
	if not creditLabel then
		return
	end
	local snap = ShopEconomyClient.GetSnapshot()
	creditLabel.Text = tostring(snap.credits)
end

local function createGui()
	if gui then
		return
	end

	local pg = LocalPlayer:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "CreditsHudGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	gui.IgnoreGuiInset = false
	gui.Enabled = false
	gui.Parent = pg

	local C = UIConfig.Pill

	local pill = Instance.new("Frame")
	pill.Name = "CreditPill"
	pill.Size = UDim2.fromScale(C.Width, C.Height)
	pill.Position = UDim2.fromScale(C.PosX, C.PosY)
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.BackgroundColor3 = Theme.Card
	pill.BackgroundTransparency = C.BgTransparency
	pill.BorderSizePixel = 0
	pill.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, C.CornerRadius)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.NeonAmber
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = pill

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(C.PadX, 0)
	pad.PaddingRight = UDim.new(C.PadX, 0)
	pad.PaddingTop = UDim.new(C.PadY, 0)
	pad.PaddingBottom = UDim.new(C.PadY, 0)
	pad.Parent = pill

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(UIConfig.Icon.Width, 1)
	icon.Position = UDim2.fromScale(0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "◆"
	icon.TextColor3 = Theme.NeonAmber
	icon.TextScaled = true
	icon.Font = Theme.FontBody
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.Parent = pill

	creditLabel = Instance.new("TextLabel")
	creditLabel.Name = "CreditLabel"
	creditLabel.Size = UDim2.fromScale(1 - UIConfig.Label.PosX, 1)
	creditLabel.Position = UDim2.fromScale(UIConfig.Label.PosX, 0)
	creditLabel.BackgroundTransparency = 1
	creditLabel.Text = "0"
	creditLabel.TextColor3 = Theme.NeonAmber
	creditLabel.TextScaled = true
	creditLabel.Font = Theme.FontBody
	creditLabel.TextXAlignment = Enum.TextXAlignment.Left
	creditLabel.Parent = pill

	updateText()
end

local CreditsHudGUI = {}

function CreditsHudGUI.Init()
	createGui()
	ShopEconomyClient.Subscribe(function()
		updateText()
	end)
end

function CreditsHudGUI.Show()
	if gui then
		gui.Enabled = true
		updateText()
	end
end

function CreditsHudGUI.Hide()
	if gui then
		gui.Enabled = false
	end
end

return CreditsHudGUI
