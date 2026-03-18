--[[
	LeaderboardGUI
	Displays TDM match results with both teams visible to all players.
	Red Team and Blue Team sections, each with Player name, Kills, Deaths.
	Shown when MatchEnded fires.
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local gui = nil
local container = nil

local TEAM_COLORS = {
	Blue = Color3.fromRGB(80, 120, 200),
	Red = Color3.fromRGB(200, 80, 80),
}

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "LeaderboardGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function clearLeaderboard()
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

local function addTeamSection(parent, teamName, players, yOffset)
	local teamColor = TEAM_COLORS[teamName] or Color3.fromRGB(150, 150, 150)
	local header = Instance.new("TextLabel")
	header.Name = teamName .. "Header"
	header.Size = UDim2.new(1, -32, 0, 32)
	header.Position = UDim2.fromOffset(16, yOffset)
	header.BackgroundTransparency = 1
	header.Text = teamName .. " Team"
	header.TextColor3 = teamColor
	header.TextSize = 22
	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = parent

	local rowY = yOffset + 36
	for i, entry in ipairs(players or {}) do
		local row = Instance.new("Frame")
		row.Name = "PlayerRow"
		row.Size = UDim2.new(1, -32, 0, 32)
		row.Position = UDim2.fromOffset(16, rowY + (i - 1) * 36)
		row.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
		row.BorderSizePixel = 0
		row.Parent = parent

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, -16, 1, -8)
		nameLabel.Position = UDim2.fromOffset(12, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.name or "Player"
		nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		nameLabel.TextSize = 14
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local killsLabel = Instance.new("TextLabel")
		killsLabel.Size = UDim2.new(0.2, 0, 1, -8)
		killsLabel.Position = UDim2.new(0.55, 0, 0, 4)
		killsLabel.BackgroundTransparency = 1
		killsLabel.Text = "K: " .. tostring(entry.kills or 0)
		killsLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
		killsLabel.TextSize = 12
		killsLabel.Font = Enum.Font.GothamMedium
		killsLabel.Parent = row

		local deathsLabel = Instance.new("TextLabel")
		deathsLabel.Size = UDim2.new(0.2, 0, 1, -8)
		deathsLabel.Position = UDim2.new(0.75, 0, 0, 4)
		deathsLabel.BackgroundTransparency = 1
		deathsLabel.Text = "D: " .. tostring(entry.deaths or 0)
		deathsLabel.TextColor3 = Color3.fromRGB(220, 120, 120)
		deathsLabel.TextSize = 12
		deathsLabel.Font = Enum.Font.GothamMedium
		deathsLabel.Parent = row
	end
	return rowY + #(players or {}) * 36
end

local function showLeaderboard(payload)
	createGui()
	if not container then
		container = Instance.new("Frame")
		container.Name = "LeaderboardContainer"
		container.Size = UDim2.fromScale(0.65, 0.75)
		container.Position = UDim2.fromScale(0.175, 0.125)
		container.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
		container.BorderSizePixel = 0
		container.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = container
	end
	clearLeaderboard()
	gui.Enabled = true

	local bluePlayers = payload.bluePlayers or {}
	local redPlayers = payload.redPlayers or {}
	local winningTeam = payload.winningTeam

	-- Title and winner
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -32, 0, 40)
	title.Position = UDim2.fromOffset(16, 16)
	title.BackgroundTransparency = 1
	title.Text = "Match Results"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 24
	title.Font = Enum.Font.GothamBold
	title.Parent = container

	local yOffset = 60
	if winningTeam then
		local winnerColor = TEAM_COLORS[winningTeam] or Color3.fromRGB(120, 220, 120)
		local winnerLabel = Instance.new("TextLabel")
		winnerLabel.Size = UDim2.new(1, -32, 0, 24)
		winnerLabel.Position = UDim2.fromOffset(16, 52)
		winnerLabel.BackgroundTransparency = 1
		winnerLabel.Text = winningTeam .. " Team Victory!"
		winnerLabel.TextColor3 = winnerColor
		winnerLabel.TextSize = 18
		winnerLabel.Font = Enum.Font.GothamMedium
		winnerLabel.Parent = container
		yOffset = 84
	end

	-- Red Team section
	yOffset = addTeamSection(container, "Red", redPlayers, yOffset) + 16
	-- Blue Team section
	addTeamSection(container, "Blue", bluePlayers, yOffset)
end

local function hideLeaderboard()
	if gui then
		gui.Enabled = false
	end
end

local function init()
	createGui()
end

return {
	Init = init,
	Show = function(payload)
		if payload then
			showLeaderboard(payload)
		else
			gui.Enabled = true
		end
	end,
	Hide = hideLeaderboard,
}
