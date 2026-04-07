--[[
	LobbyGUI
	One panel for the whole lobby: queue counts / status and match countdown.
	Visible for both ShopLobby and WaitingLobby server phases; hidden in Arena.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(ReplicatedStorage.Shared.Services.LobbyServiceClient)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)

local T = LobbyConfig.TEXT

-- When total < MIN_PLAYERS, name the team with fewer queued players (ties: "Blue team or Orange team").
local function lackingTeamPhraseForMoreTotal(blueCount, redCount)
	if blueCount < redCount then
		return TeamDisplayUtils.displayName("Blue") .. " team"
	end
	if redCount < blueCount then
		return TeamDisplayUtils.displayName("Red") .. " team"
	end
	return TeamDisplayUtils.displayName("Blue") .. " team or " .. TeamDisplayUtils.displayName("Red") .. " team"
end

local function buildQueueStatusLines(blueCount, redCount, minPlayers)
	local total = blueCount + redCount
	if total < minPlayers then
		local need = minPlayers - total
		local teamPhrase = lackingTeamPhraseForMoreTotal(blueCount, redCount)
		if need == 1 then
			return string.format(T.LOBBY_QUEUE_STATUS_NEED_MORE_TOTAL_ONE, teamPhrase)
		end
		return string.format(T.LOBBY_QUEUE_STATUS_NEED_MORE_TOTAL_MANY, need, teamPhrase)
	end
	if LobbyConfig.REQUIRE_BOTH_TEAMS_TO_START then
		if blueCount < 1 then
			return string.format(T.LOBBY_QUEUE_STATUS_NEED_ON_TEAM, TeamDisplayUtils.displayName("Blue"))
		end
		if redCount < 1 then
			return string.format(T.LOBBY_QUEUE_STATUS_NEED_ON_TEAM, TeamDisplayUtils.displayName("Red"))
		end
	end
	return ""
end

local LocalPlayer = Players.LocalPlayer
local gui = nil
local mainFrame = nil
local countdownConnection = nil

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "LobbyGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function createLobbyPanel(parent)
	local frame = Instance.new("Frame")
	frame.Name = "LobbyPanel"
	frame.Size = UDim2.fromScale(0.34, 0.25)
	frame.Position = UDim2.new(0.5, 0, 0, 32)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	frame.BorderSizePixel = 0
	frame.Visible = true
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Position = UDim2.fromOffset(0, 8)
	title.BackgroundTransparency = 1
	title.Text = T.LOBBY_PANEL_TITLE
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = frame

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, -16, 0, 100)
	countLabel.Position = UDim2.fromOffset(8, 32)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = string.format(T.LOBBY_QUEUE_COUNT_INITIAL, 0, LobbyConfig.MIN_PLAYERS)
	countLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	countLabel.TextSize = 12
	countLabel.Font = Enum.Font.GothamMedium
	countLabel.TextWrapped = true
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Top
	countLabel.Parent = frame

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(1, -16, 0, 16)
	countdownLabel.Position = UDim2.fromOffset(8, 136)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = ""
	countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	countdownLabel.TextSize = 12
	countdownLabel.Font = Enum.Font.GothamBold
	countdownLabel.Visible = false
	countdownLabel.Parent = frame

	return frame
end

local function updateUI(state)
	if not state then
		state = LobbyServiceClient.GetState()
	end
	if not mainFrame then
		return
	end
	local panel = mainFrame:FindFirstChild("LobbyPanel")
	if not panel then
		return
	end

	local phase = state and state.phase or LobbyServiceClient.PHASE.SHOP_LOBBY
	local inLobby = phase == LobbyServiceClient.PHASE.SHOP_LOBBY or phase == LobbyServiceClient.PHASE.WAITING_LOBBY
	panel.Visible = inLobby

	if not inLobby then
		return
	end

	local count = state.waitingCount or 0
	local minP = state.minPlayers or LobbyServiceClient.MIN_PLAYERS
	local b = state.waitingCountBlue or 0
	local r = state.waitingCountRed or 0
	local team = state.queuedTeam
	local youSuffix = (team == "Blue" or team == "Red") and string.format(T.LOBBY_QUEUE_YOU_SUFFIX, team) or ""
	local needLine = buildQueueStatusLines(b, r, minP)
	panel.Count.Text = string.format(T.LOBBY_QUEUE_HEADER, count, b, r) .. needLine .. youSuffix

	local cdl = panel:FindFirstChild("Countdown")
	if cdl and state.matchStarting then
		cdl.Visible = true
		local sec = state.secondsRemaining
		cdl.Text = (sec ~= nil and sec > 0) and string.format(T.MATCH_STARTING_IN, sec) or T.MATCH_STARTING
	elseif cdl then
		cdl.Visible = false
		if countdownConnection then
			task.cancel(countdownConnection)
			countdownConnection = nil
		end
	end
end

local function init()
	createGui()
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "LobbyFrame"
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.Position = UDim2.fromScale(0, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = gui
	createLobbyPanel(mainFrame)
	LobbyServiceClient.Subscribe(updateUI)
	updateUI(LobbyServiceClient.GetState())
end

return {
	Init = init,
	Show = function()
		if not gui then
			init()
		end
		gui.Enabled = true
		updateUI(LobbyServiceClient.GetState())
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
