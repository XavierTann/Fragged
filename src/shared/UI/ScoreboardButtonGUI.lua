--[[
	ScoreboardButtonGUI
	In-match button to open the full team K/D scoreboard (server-validated active round only).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local LeaderboardGUI = require(Shared.UI.LeaderboardGUI)

local LocalPlayer = Players.LocalPlayer

local gui = nil
local BACKGROUND_TRANSPARENCY = 0.45

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "ScoreboardButtonGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "OpenScoreboard"
	toggleButton.Size = UDim2.fromOffset(118, 36)
	toggleButton.Position = UDim2.fromOffset(12, 52)
	toggleButton.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	toggleButton.BackgroundTransparency = BACKGROUND_TRANSPARENCY
	toggleButton.BorderSizePixel = 0
	toggleButton.Text = "Scoreboard"
	toggleButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	toggleButton.TextSize = 14
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toggleButton
	toggleButton.Parent = gui

	toggleButton.MouseButton1Click:Connect(function()
		local data = CombatServiceClient.RequestLiveLeaderboard()
		if data then
			LeaderboardGUI.Show(data)
		end
	end)

	return gui
end

local function init()
	createGui()
end

return {
	Init = init,
	SetVisible = function(visible)
		createGui()
		gui.Enabled = visible == true
	end,
}
