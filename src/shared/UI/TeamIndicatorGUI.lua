--[[
	TeamIndicatorGUI
	- Persistent top bar: "You are on the Blue/Red Team" while in arena.
	- Center toast on arena entry / team assignment via CenterScreenToast.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)
local CenterScreenToast = require(ReplicatedStorage.Shared.UI.CenterScreenToast)

local LocalPlayer = Players.LocalPlayer

local COLOR_BLUE = Color3.fromRGB(100, 170, 255)
local COLOR_RED = Color3.fromRGB(255, 80, 90)

local HOLD_SECONDS = 2.85
local FADE_SECONDS = 0.55

local screenGui = nil
local topBarFrame = nil
local topBarLabel = nil

local arenaHudActive = false

local function teamBarPhrase(myTeam)
	if myTeam == "Blue" then
		return "You are on the Blue Team", COLOR_BLUE
	elseif myTeam == "Red" then
		return TeamDisplayUtils.youAreOnTeamPhrase("Red"), COLOR_RED
	end
	return nil, nil
end

local function updateTopBar()
	if not topBarLabel or not topBarFrame then
		return
	end
	local assignment = CombatServiceClient.GetTeamAssignment()
	local myTeam = assignment and assignment.myTeam
	local phrase, color = teamBarPhrase(myTeam)
	if phrase then
		topBarLabel.Text = phrase
		topBarLabel.TextColor3 = color
		topBarFrame.Visible = arenaHudActive
	else
		topBarLabel.Text = ""
		topBarFrame.Visible = false
	end
end

local function ensureGui()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TeamIndicatorGUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 9
	screenGui.Enabled = true
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	topBarFrame = Instance.new("Frame")
	topBarFrame.Name = "TopBar"
	topBarFrame.Size = UDim2.fromOffset(180, 24)	
	topBarFrame.Position = UDim2.new(0.5, 0, 0, 45)
	topBarFrame.AnchorPoint = Vector2.new(0.5, 0)
	topBarFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	topBarFrame.BackgroundTransparency = 0.4
	topBarFrame.BorderSizePixel = 0
	topBarFrame.Visible = false
	topBarFrame.Parent = screenGui

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 10)
	topCorner.Parent = topBarFrame

	topBarLabel = Instance.new("TextLabel")
	topBarLabel.Name = "TeamLabel"
	topBarLabel.Size = UDim2.fromScale(1, 1)
	topBarLabel.BackgroundTransparency = 1
	topBarLabel.Text = ""
	topBarLabel.TextSize = 14
	topBarLabel.Font = Enum.Font.GothamBold
	topBarLabel.TextColor3 = COLOR_BLUE
	topBarLabel.Parent = topBarFrame
end

local function tryPlayTeamToast()
	if not arenaHudActive then
		return
	end
	local assignment = CombatServiceClient.GetTeamAssignment()
	local myTeam = assignment and assignment.myTeam
	local phrase, color = teamBarPhrase(myTeam)
	if not phrase then
		return
	end
	CenterScreenToast.Show({
		text = phrase,
		textColor = color,
		holdSeconds = HOLD_SECONDS,
		fadeSeconds = FADE_SECONDS,
	})
end

local initialized = false

return {
	Init = function()
		if initialized then
			return
		end
		initialized = true
		ensureGui()
		CombatServiceClient.SubscribeTeamAssignment(function()
			updateTopBar()
			tryPlayTeamToast()
		end)
	end,

	Show = function()
		arenaHudActive = true
		ensureGui()
		updateTopBar()
		task.defer(tryPlayTeamToast)
	end,

	Hide = function()
		arenaHudActive = false
		CenterScreenToast.Cancel()
		if topBarFrame then
			topBarFrame.Visible = false
		end
	end,
}
