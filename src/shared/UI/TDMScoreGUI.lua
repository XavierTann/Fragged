--[[
	TDMScoreGUI
	Persistent top-right score display during TDM matches.
	Shows both teams: flag (team color) + kills/killLimit (e.g. 5/10).
	Updates in real time when TeamScoreUpdate fires.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)

local gui = nil
local blueScoreLabel = nil
local redScoreLabel = nil

local TEAM_COLORS = {
	Blue = Color3.fromRGB(80, 140, 220),
	Red = Color3.fromRGB(220, 80, 80),
}

local KILL_LIMIT = TDMConfig.KILL_LIMIT

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "TDMScoreGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name = "ScoreContainer"
	container.Size = UDim2.fromOffset(140, 72)
	container.Position = UDim2.new(1, -156, 0, 16)
	container.AnchorPoint = Vector2.new(0, 0)
	container.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	-- Blue row
	local blueRow = Instance.new("Frame")
	blueRow.Name = "BlueRow"
	blueRow.Size = UDim2.new(1, -16, 0, 28)
	blueRow.Position = UDim2.fromOffset(8, 8)
	blueRow.BackgroundTransparency = 1
	blueRow.Parent = container

	local blueFlag = Instance.new("Frame")
	blueFlag.Name = "BlueFlag"
	blueFlag.Size = UDim2.fromOffset(20, 20)
	blueFlag.Position = UDim2.fromOffset(0, 4)
	blueFlag.BackgroundColor3 = TEAM_COLORS.Blue
	blueFlag.BorderSizePixel = 0
	blueFlag.Parent = blueRow
	local blueFlagCorner = Instance.new("UICorner")
	blueFlagCorner.CornerRadius = UDim.new(0, 4)
	blueFlagCorner.Parent = blueFlag

	blueScoreLabel = Instance.new("TextLabel")
	blueScoreLabel.Name = "BlueScore"
	blueScoreLabel.Size = UDim2.new(1, -28, 1, 0)
	blueScoreLabel.Position = UDim2.fromOffset(28, 0)
	blueScoreLabel.BackgroundTransparency = 1
	blueScoreLabel.Text = "0/" .. tostring(KILL_LIMIT)
	blueScoreLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	blueScoreLabel.TextSize = 16
	blueScoreLabel.Font = Enum.Font.GothamBold
	blueScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	blueScoreLabel.Parent = blueRow

	-- Red row
	local redRow = Instance.new("Frame")
	redRow.Name = "RedRow"
	redRow.Size = UDim2.new(1, -16, 0, 28)
	redRow.Position = UDim2.fromOffset(8, 36)
	redRow.BackgroundTransparency = 1
	redRow.Parent = container

	local redFlag = Instance.new("Frame")
	redFlag.Name = "RedFlag"
	redFlag.Size = UDim2.fromOffset(20, 20)
	redFlag.Position = UDim2.fromOffset(0, 4)
	redFlag.BackgroundColor3 = TEAM_COLORS.Red
	redFlag.BorderSizePixel = 0
	redFlag.Parent = redRow
	local redFlagCorner = Instance.new("UICorner")
	redFlagCorner.CornerRadius = UDim.new(0, 4)
	redFlagCorner.Parent = redFlag

	redScoreLabel = Instance.new("TextLabel")
	redScoreLabel.Name = "RedScore"
	redScoreLabel.Size = UDim2.new(1, -28, 1, 0)
	redScoreLabel.Position = UDim2.fromOffset(28, 0)
	redScoreLabel.BackgroundTransparency = 1
	redScoreLabel.Text = "0/" .. tostring(KILL_LIMIT)
	redScoreLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	redScoreLabel.TextSize = 16
	redScoreLabel.Font = Enum.Font.GothamBold
	redScoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	redScoreLabel.Parent = redRow

	return gui
end

local function updateScore(blueKills, redKills)
	createGui()
	blueKills = blueKills or 0
	redKills = redKills or 0
	if blueScoreLabel then
		blueScoreLabel.Text = tostring(blueKills) .. "/" .. tostring(KILL_LIMIT)
	end
	if redScoreLabel then
		redScoreLabel.Text = tostring(redKills) .. "/" .. tostring(KILL_LIMIT)
	end
end

local function init()
	createGui()
	local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
	local teamScoreRE = folder:WaitForChild(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
	teamScoreRE.OnClientEvent:Connect(updateScore)
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			updateScore(0, 0)
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
	UpdateScore = updateScore,
}
