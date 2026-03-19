--[[
	RespawnTimerGUI
	Centered respawn countdown shown when the local player dies during TDM.
	Displays "Respawn in X" and counts down until the server respawns them.
	Triggered by PlayerDied remote from server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local gui = nil
local timerLabel = nil
local countdownThread = nil

local BACKGROUND_TRANSPARENCY = 0.45

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "RespawnTimerGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name = "TimerContainer"
	container.Size = UDim2.fromOffset(200, 60)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	container.BackgroundTransparency = BACKGROUND_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, -24, 1, -16)
	timerLabel.Position = UDim2.fromOffset(12, 8)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "Respawn in 0"
	timerLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	timerLabel.TextSize = 24
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = container

	return gui
end

local function stopCountdown()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
end

local function showRespawnCountdown(respawnDelaySeconds)
	createGui()
	stopCountdown()

	local remaining = math.ceil(respawnDelaySeconds)
	if remaining <= 0 then
		gui.Enabled = false
		return
	end

	gui.Enabled = true
	timerLabel.Text = "Respawn in " .. tostring(remaining)

	local startTime = tick()
	countdownThread = task.spawn(function()
		while true do
			task.wait(0.1)
			local elapsed = tick() - startTime
			remaining = math.max(0, math.ceil(respawnDelaySeconds - elapsed))
			if timerLabel then
				timerLabel.Text = "Respawn in " .. tostring(remaining)
			end
			if remaining <= 0 then
				break
			end
		end
		countdownThread = nil
		if gui then
			gui.Enabled = false
		end
	end)
end

local function init()
	createGui()
	local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
	local playerDiedRE = folder:WaitForChild(CombatConfig.REMOTES.PLAYER_DIED)
	playerDiedRE.OnClientEvent:Connect(showRespawnCountdown)
end

return {
	Init = init,
	Show = function()
		-- No-op; shown by PlayerDied event
	end,
	Hide = function()
		stopCountdown()
		if gui then
			gui.Enabled = false
		end
	end,
}
