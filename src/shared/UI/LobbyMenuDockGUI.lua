--[[
	Lobby-only vertical dock (right, compact): open Shop, Gacha, Loadout.
	Hidden in arena. Dock icons use rbxassetid images (see ICON_* below).
]]

local ICON_SHOP = 5436912533
local ICON_LOADOUT = 14749776450
local ICON_GACHA = 87223429981926

-- Panel + circular hit targets (compact dock)
local PANEL_BG = Color3.fromRGB(198, 228, 255)
local PANEL_CORNER = 8
local PANEL_PADDING = 4
local ICON_DIAMETER = 38
local ICON_GAP = 5
local ICON_LABEL_GAP = 1
local LABEL_HEIGHT = 13
local LABEL_TEXT_COLOR = Color3.new(0, 0, 0)
local LABEL_TEXT_SIZE = 10
-- Slightly wider than icon + padding so short labels (e.g. "Loadout") do not over-truncate.
local PANEL_WIDTH = math.max(ICON_DIAMETER + PANEL_PADDING * 2, 52)
local DOCK_EDGE_INSET = 10

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
local Theme = require(Shared.UI.Shop.ShopTheme)
local ShopGUI = require(Shared.UI.Shop.ShopGUI)
local GachaGUI = require(Shared.UI.GachaGUI)
local LoadoutGUI = require(Shared.UI.LoadoutGUI)

local LocalPlayer = Players.LocalPlayer

local LobbyMenuDockGUI = {}

local screenGui = nil
local dockFrame = nil

local function corner(inst, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 10)
	c.Parent = inst
end

local function circleCorner(inst)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = inst
end

local function closeOtherPanels(which)
	if which ~= "shop" then
		ShopGUI.Hide()
	end
	if which ~= "gacha" then
		GachaGUI.Hide()
	end
	if which ~= "loadout" then
		LoadoutGUI.Hide()
	end
end

local function closeAllPanels()
	ShopGUI.Hide()
	GachaGUI.Hide()
	LoadoutGUI.Hide()
end

local function rbxImage(assetId: number)
	return "rbxassetid://" .. tostring(assetId)
end

local function makeDockEntry(name, labelText, layoutOrder, imageAssetId: number, onActivated)
	local entry = Instance.new("Frame")
	entry.Name = name
	entry.BackgroundTransparency = 1
	entry.BorderSizePixel = 0
	entry.LayoutOrder = layoutOrder
	entry.Size = UDim2.fromScale(1, 0)
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.Parent = dockFrame

	local vlist = Instance.new("UIListLayout")
	vlist.FillDirection = Enum.FillDirection.Vertical
	vlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	vlist.VerticalAlignment = Enum.VerticalAlignment.Top
	vlist.Padding = UDim.new(0, ICON_LABEL_GAP)
	vlist.SortOrder = Enum.SortOrder.LayoutOrder
	vlist.Parent = entry

	local btn = Instance.new("ImageButton")
	btn.Name = "Icon"
	btn.AutoButtonColor = true
	btn.Size = UDim2.fromOffset(ICON_DIAMETER, ICON_DIAMETER)
	btn.BackgroundColor3 = Theme.PanelDeep
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.Image = rbxImage(imageAssetId)
	btn.ScaleType = Enum.ScaleType.Fit
	btn.ClipsDescendants = true
	btn.LayoutOrder = 1
	btn.Parent = entry
	circleCorner(btn)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, LABEL_HEIGHT)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = LABEL_TEXT_COLOR
	label.Font = Theme.FontBody
	label.TextSize = LABEL_TEXT_SIZE
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.LayoutOrder = 2
	label.Parent = entry

	local baseBg = Theme.PanelDeep
	local hoverBg = Theme.CardHover
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = hoverBg
		btn.BackgroundTransparency = 0.1
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = baseBg
		btn.BackgroundTransparency = 0.25
	end)
	btn.Activated:Connect(onActivated)
	return entry
end

local function setDockVisible(visible)
	if screenGui then
		screenGui.Enabled = visible == true
	end
end

local function isNonArenaPhase(state)
	return state and state.phase ~= LobbyConfig.PHASE.ARENA
end

function LobbyMenuDockGUI.Init()
	if screenGui then
		return
	end

	local pg = LocalPlayer:WaitForChild("PlayerGui")
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyMenuDockGUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 9
	screenGui.Enabled = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = pg

	dockFrame = Instance.new("Frame")
	dockFrame.Name = "DockPanel"
	dockFrame.AnchorPoint = Vector2.new(1, 0.5)
	dockFrame.Position = UDim2.new(1, -DOCK_EDGE_INSET, 0.5, 0)
	dockFrame.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	dockFrame.AutomaticSize = Enum.AutomaticSize.Y
	dockFrame.BackgroundColor3 = PANEL_BG
	dockFrame.BackgroundTransparency = 0.08
	dockFrame.BorderSizePixel = 0
	dockFrame.Parent = screenGui
	corner(dockFrame, PANEL_CORNER)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PANEL_PADDING)
	pad.PaddingBottom = UDim.new(0, PANEL_PADDING)
	pad.PaddingLeft = UDim.new(0, PANEL_PADDING)
	pad.PaddingRight = UDim.new(0, PANEL_PADDING)
	pad.Parent = dockFrame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Padding = UDim.new(0, ICON_GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = dockFrame

	makeDockEntry("ShopEntry", "Shop", 1, ICON_SHOP, function()
		closeOtherPanels("shop")
		ShopGUI.Show()
	end)

	makeDockEntry("GachaEntry", "Gacha", 2, ICON_GACHA, function()
		closeOtherPanels("gacha")
		GachaGUI.Show()
	end)

	makeDockEntry("LoadoutEntry", "Loadout", 3, ICON_LOADOUT, function()
		closeOtherPanels("loadout")
		LoadoutGUI.Show()
	end)

	LobbyServiceClient.Subscribe(function(state)
		if state and state.phase == LobbyConfig.PHASE.ARENA then
			closeAllPanels()
		end
		setDockVisible(isNonArenaPhase(state))
	end)

	local initial = LobbyServiceClient.GetState()
	setDockVisible(isNonArenaPhase(initial))
end

return LobbyMenuDockGUI
