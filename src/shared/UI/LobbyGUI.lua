--[[
	LobbyGUI
	Shop lobby: "Find match" button.
	Waiting lobby: "Waiting for players (X/Y)", Leave button, countdown when match starting.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyServiceClient = require(ReplicatedStorage.Shared.Services.LobbyServiceClient)

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
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function createShopView(parent)
	local frame = Instance.new("Frame")
	frame.Name = "ShopView"
	frame.Size = UDim2.fromScale(0.28, 0.12)
	frame.Position = UDim2.fromScale(0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Position = UDim2.fromOffset(0, 4)
	title.BackgroundTransparency = 1
	title.Text = "Shop Lobby"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = frame

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -16, 0, 14)
	hint.Position = UDim2.fromOffset(8, 24)
	hint.BackgroundTransparency = 1
	hint.Text = "Join the waiting lobby to find a match."
	hint.TextColor3 = Color3.fromRGB(200, 200, 200)
	hint.TextSize = 10
	hint.Font = Enum.Font.Gotham
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = frame

	local findMatchBtn = Instance.new("TextButton")
	findMatchBtn.Name = "FindMatch"
	findMatchBtn.Size = UDim2.new(1, -16, 0, 24)
	findMatchBtn.Position = UDim2.fromOffset(8, 44)
	findMatchBtn.BackgroundColor3 = Color3.fromRGB(56, 142, 60)
	findMatchBtn.Text = "Find match"
	findMatchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	findMatchBtn.TextSize = 11
	findMatchBtn.Font = Enum.Font.GothamMedium
	findMatchBtn.Parent = frame
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = findMatchBtn

	findMatchBtn.MouseButton1Click:Connect(function()
		local result = LobbyServiceClient.JoinWaitingLobby()
		if result and result.success then
			-- State update will switch to waiting view via LobbyState event
			return
		end
		-- Could show result.error in UI
	end)

	return frame
end

local function createWaitingView(parent)
	local frame = Instance.new("Frame")
	frame.Name = "WaitingView"
	frame.Size = UDim2.fromScale(0.3, 0.14)
	frame.Position = UDim2.fromScale(0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Position = UDim2.fromOffset(0, 4)
	title.BackgroundTransparency = 1
	title.Text = "Waiting Lobby"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = frame

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, 0, 0, 16)
	countLabel.Position = UDim2.fromOffset(0, 24)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "Players: 0 / 2"
	countLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	countLabel.TextSize = 12
	countLabel.Font = Enum.Font.GothamMedium
	countLabel.Parent = frame

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(1, 0, 0, 16)
	countdownLabel.Position = UDim2.fromOffset(0, 42)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = ""
	countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	countdownLabel.TextSize = 12
	countdownLabel.Font = Enum.Font.GothamBold
	countdownLabel.Visible = false
	countdownLabel.Parent = frame

	local leaveBtn = Instance.new("TextButton")
	leaveBtn.Name = "Leave"
	leaveBtn.Size = UDim2.new(1, -16, 0, 24)
	leaveBtn.Position = UDim2.fromOffset(8, 62)
	leaveBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	leaveBtn.Text = "Leave waiting lobby"
	leaveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	leaveBtn.TextSize = 11
	leaveBtn.Font = Enum.Font.GothamMedium
	leaveBtn.Parent = frame
	local leaveCorner = Instance.new("UICorner")
	leaveCorner.CornerRadius = UDim.new(0, 6)
	leaveCorner.Parent = leaveBtn

	leaveBtn.MouseButton1Click:Connect(function()
		LobbyServiceClient.LeaveWaitingLobby()
	end)

	return frame
end

local function updateUI(state)
	if not state then
		state = LobbyServiceClient.GetState()
	end
	if not mainFrame then
		return
	end
	local shopView = mainFrame:FindFirstChild("ShopView")
	local waitingView = mainFrame:FindFirstChild("WaitingView")
	if not shopView or not waitingView then
		return
	end
	local phase = state and state.phase or LobbyServiceClient.PHASE.SHOP_LOBBY
	shopView.Visible = (phase == LobbyServiceClient.PHASE.SHOP_LOBBY)
	waitingView.Visible = (phase == LobbyServiceClient.PHASE.WAITING_LOBBY)
	if phase == LobbyServiceClient.PHASE.WAITING_LOBBY then
		local count = state.waitingCount or 0
		local minP = state.minPlayers or LobbyServiceClient.MIN_PLAYERS
		waitingView.Count.Text = string.format("Players: %d / %d", count, minP)
		local cdl = waitingView:FindFirstChild("Countdown")
		if cdl and state.matchStarting then
			cdl.Visible = true
			-- Server sends secondsRemaining every second; no client-side timer needed
			local sec = state.secondsRemaining
			cdl.Text = (sec ~= nil and sec > 0) and ("Match starting in " .. tostring(sec) .. "...") or "Match starting..."
		elseif cdl then
			cdl.Visible = false
			if countdownConnection then
				task.cancel(countdownConnection)
				countdownConnection = nil
			end
		end
	end
	if phase == LobbyServiceClient.PHASE.ARENA then
		shopView.Visible = false
		waitingView.Visible = false
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
	createShopView(mainFrame)
	createWaitingView(mainFrame)
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
