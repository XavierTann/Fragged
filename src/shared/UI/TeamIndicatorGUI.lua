--[[
	TeamIndicatorGUI
	- Persistent top bar: "You are on the Blue/Orange Team" (server key Red → Orange in UI) while in arena.
	- Center toast on arena entry / team assignment: same copy and colors, longer hold, then fade.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)

local LocalPlayer = Players.LocalPlayer

local COLOR_BLUE = Color3.fromRGB(100, 170, 255)
local COLOR_ORANGE = Color3.fromRGB(255, 145, 55)

local HOLD_SECONDS = 2.85
local FADE_SECONDS = 0.55

local screenGui = nil
local topBarFrame = nil
local topBarLabel = nil

local toastContainer = nil
local toastLabel = nil
local toastStroke = nil

local arenaHudActive = false
local sequenceToken = 0
local fadeTweens = {}

local function cancelFadeTweens()
	for _, tw in ipairs(fadeTweens) do
		tw:Cancel()
	end
	fadeTweens = {}
end

local function teamBarPhrase(myTeam)
	if myTeam == "Blue" then
		return "You are on the Blue Team", COLOR_BLUE
	elseif myTeam == "Red" then
		return TeamDisplayUtils.youAreOnTeamPhrase("Red"), COLOR_ORANGE
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
	topBarFrame.Size = UDim2.fromOffset(260, 34)
	topBarFrame.Position = UDim2.new(0.5, 0, 0, 8)
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

	toastContainer = Instance.new("Frame")
	toastContainer.Name = "TeamToast"
	toastContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	toastContainer.Position = UDim2.fromScale(0.5, 0.5)
	toastContainer.Size = UDim2.fromOffset(560, 56)
	toastContainer.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	toastContainer.BackgroundTransparency = 1
	toastContainer.BorderSizePixel = 0
	toastContainer.Visible = false
	toastContainer.ZIndex = 2
	toastContainer.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = toastContainer

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = toastContainer

	toastLabel = Instance.new("TextLabel")
	toastLabel.BackgroundTransparency = 1
	toastLabel.Size = UDim2.fromScale(1, 1)
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.TextSize = 22
	toastLabel.TextColor3 = COLOR_BLUE
	toastLabel.TextTransparency = 1
	toastLabel.TextWrapped = true
	toastLabel.TextXAlignment = Enum.TextXAlignment.Center
	toastLabel.TextYAlignment = Enum.TextYAlignment.Center
	toastLabel.Text = ""
	toastLabel.ZIndex = 2
	toastLabel.Parent = toastContainer

	toastStroke = Instance.new("UIStroke")
	toastStroke.Thickness = 1.8
	toastStroke.Color = Color3.fromRGB(0, 0, 0)
	toastStroke.Transparency = 1
	toastStroke.Parent = toastLabel
end

local function tryPlayTeamToast()
	if not arenaHudActive then
		return
	end
	ensureGui()
	local assignment = CombatServiceClient.GetTeamAssignment()
	local myTeam = assignment and assignment.myTeam
	local phrase, color = teamBarPhrase(myTeam)
	if not phrase then
		return
	end

	sequenceToken = sequenceToken + 1
	local token = sequenceToken
	cancelFadeTweens()

	toastLabel.Text = phrase
	toastLabel.TextColor3 = color
	toastContainer.BackgroundTransparency = 0.62
	toastLabel.TextTransparency = 0.06
	toastStroke.Transparency = 0.35
	toastContainer.Visible = true

	task.delay(HOLD_SECONDS, function()
		if token ~= sequenceToken or not arenaHudActive then
			return
		end
		local ti = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local t1 = TweenService:Create(toastLabel, ti, { TextTransparency = 1 })
		local t2 = TweenService:Create(toastStroke, ti, { Transparency = 1 })
		local t3 = TweenService:Create(toastContainer, ti, { BackgroundTransparency = 1 })
		fadeTweens = { t1, t2, t3 }
		t1:Play()
		t2:Play()
		t3:Play()
		t1.Completed:Connect(function()
			if token ~= sequenceToken then
				return
			end
			toastContainer.Visible = false
			cancelFadeTweens()
		end)
	end)
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
		sequenceToken = sequenceToken + 1
		cancelFadeTweens()
		if topBarFrame then
			topBarFrame.Visible = false
		end
		if toastContainer then
			toastContainer.Visible = false
		end
		if toastLabel then
			toastLabel.TextTransparency = 1
		end
		if toastStroke then
			toastStroke.Transparency = 1
		end
		if toastContainer then
			toastContainer.BackgroundTransparency = 1
		end
	end,
}
