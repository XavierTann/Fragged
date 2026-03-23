--[[
	TeamIndicatorGUI
	HUD label at the top of the screen showing the local player's current team.
	"You are on the Blue Team" / "You are on the Red Team" in matching team color.
	Only visible during arena phase.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local LocalPlayer = Players.LocalPlayer

local COLOR_BLUE    = Color3.fromRGB(100, 170, 255)
local COLOR_RED     = Color3.fromRGB(255, 100, 100)
local COLOR_DEFAULT = Color3.fromRGB(220, 220, 220)

local gui   = nil
local label = nil

local function createGui()
	if gui then
		return gui
	end

	gui = Instance.new("ScreenGui")
	gui.Name             = "TeamIndicatorGUI"
	gui.ResetOnSpawn     = false
	gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder     = 9
	gui.Enabled          = false
	gui.Parent           = LocalPlayer:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name                   = "Container"
	container.Size                   = UDim2.fromOffset(260, 34)
	container.Position               = UDim2.new(0.5, 0, 0, 8)
	container.AnchorPoint            = Vector2.new(0.5, 0)
	container.BackgroundColor3       = Color3.fromRGB(18, 22, 34)
	container.BackgroundTransparency = 0.4
	container.BorderSizePixel        = 0
	container.Parent                 = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent       = container

	label = Instance.new("TextLabel")
	label.Name               = "TeamLabel"
	label.Size               = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text               = ""
	label.TextColor3         = COLOR_DEFAULT
	label.TextSize           = 14
	label.Font               = Enum.Font.GothamBold
	label.Parent             = container

	return gui
end

local function updateLabel(myTeam)
	if not label then
		return
	end
	if myTeam == "Blue" then
		label.Text       = "You are on the Blue Team"
		label.TextColor3 = COLOR_BLUE
	elseif myTeam == "Red" then
		label.Text       = "You are on the Red Team"
		label.TextColor3 = COLOR_RED
	else
		label.Text       = ""
		label.TextColor3 = COLOR_DEFAULT
	end
end

local initialized = false

return {
	Init = function()
		if initialized then return end
		initialized = true

		createGui()

		CombatServiceClient.SubscribeTeamAssignment(function(assignment)
			updateLabel(assignment.myTeam)
		end)
	end,

	Show = function()
		if not gui then return end
		gui.Enabled = true
		local assignment = CombatServiceClient.GetTeamAssignment()
		if assignment then
			updateLabel(assignment.myTeam)
		end
	end,

	Hide = function()
		if gui then
			gui.Enabled = false
		end
	end,
}
