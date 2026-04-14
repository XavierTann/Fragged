--[[
	LeaveMatchGUI
	Small "Leave" button to the left of the TDM scoreboard, visible only during arena combat.
	Shows a confirmation dialog before firing LEAVE_MATCH to forfeit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("CombatConfig"))

local BTN_WIDTH = 60
local BTN_HEIGHT = 26
local BTN_COLOR = Color3.fromRGB(160, 35, 35)
local BTN_HOVER_COLOR = Color3.fromRGB(200, 50, 50)
local BTN_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local BTN_TRANSPARENCY = 0.35
local CORNER_RADIUS = 6

local DIALOG_WIDTH = 240
local DIALOG_HEIGHT = 120
local DIALOG_BG = Color3.fromRGB(30, 30, 30)
local DIALOG_CORNER = 10
local CONFIRM_COLOR = Color3.fromRGB(180, 40, 40)
local CONFIRM_HOVER = Color3.fromRGB(220, 50, 50)
local CANCEL_COLOR = Color3.fromRGB(60, 60, 60)
local CANCEL_HOVER = Color3.fromRGB(90, 90, 90)

local screenGui
local leaveBtn
local confirmOverlay
local leaveRE

local LeaveMatchGUI = {}

local function getRemote()
	if leaveRE then
		return leaveRE
	end
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if folder then
		leaveRE = folder:FindFirstChild(CombatConfig.REMOTES.LEAVE_MATCH)
	end
	return leaveRE
end

local function hideConfirm()
	if confirmOverlay then
		confirmOverlay.Visible = false
	end
end

local function showConfirm()
	if confirmOverlay then
		confirmOverlay.Visible = true
	end
end

local function makeDialogButton(parent, text, color, hoverColor, posX)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(90, 30)
	btn.Position = UDim2.new(0, posX, 1, -42)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = BTN_TEXT_COLOR
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = hoverColor
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = color
	end)

	return btn
end

local function buildConfirmDialog()
	confirmOverlay = Instance.new("Frame")
	confirmOverlay.Name = "ConfirmOverlay"
	confirmOverlay.Size = UDim2.fromScale(1, 1)
	confirmOverlay.Position = UDim2.fromScale(0, 0)
	confirmOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	confirmOverlay.BackgroundTransparency = 0.5
	confirmOverlay.BorderSizePixel = 0
	confirmOverlay.ZIndex = 50
	confirmOverlay.Visible = false
	confirmOverlay.Parent = screenGui

	local dialog = Instance.new("Frame")
	dialog.Name = "Dialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Size = UDim2.fromOffset(DIALOG_WIDTH, DIALOG_HEIGHT)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.BackgroundColor3 = DIALOG_BG
	dialog.BorderSizePixel = 0
	dialog.ZIndex = 51
	dialog.Parent = confirmOverlay

	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0, DIALOG_CORNER)
	dialogCorner.Parent = dialog

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Color = Color3.fromRGB(80, 80, 80)
	dialogStroke.Thickness = 1
	dialogStroke.Parent = dialog

	local prompt = Instance.new("TextLabel")
	prompt.Size = UDim2.new(1, -20, 0, 40)
	prompt.Position = UDim2.fromOffset(10, 16)
	prompt.BackgroundTransparency = 1
	prompt.Text = "Are you sure you want\nto leave the match?"
	prompt.TextColor3 = BTN_TEXT_COLOR
	prompt.Font = Enum.Font.GothamMedium
	prompt.TextSize = 15
	prompt.TextWrapped = true
	prompt.ZIndex = 52
	prompt.Parent = dialog

	local leaveConfirmBtn = makeDialogButton(dialog, "Leave", CONFIRM_COLOR, CONFIRM_HOVER, 25)
	leaveConfirmBtn.ZIndex = 52
	leaveConfirmBtn.Activated:Connect(function()
		hideConfirm()
		local re = getRemote()
		if re then
			leaveBtn.Active = false
			re:FireServer()
		end
	end)

	local cancelBtn = makeDialogButton(dialog, "Cancel", CANCEL_COLOR, CANCEL_HOVER, DIALOG_WIDTH - 90 - 25)
	cancelBtn.ZIndex = 52
	cancelBtn.Activated:Connect(function()
		hideConfirm()
	end)
end

local function build()
	if screenGui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LeaveMatchGUI"
	screenGui.DisplayOrder = 100
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	leaveBtn = Instance.new("TextButton")
	leaveBtn.Name = "LeaveBtn"
	leaveBtn.AnchorPoint = Vector2.new(1, 0)
	leaveBtn.Size = UDim2.fromOffset(BTN_WIDTH, BTN_HEIGHT)
	leaveBtn.Position = UDim2.new(0.35, -6, 0.05, 4)
	leaveBtn.BackgroundColor3 = BTN_COLOR
	leaveBtn.BackgroundTransparency = BTN_TRANSPARENCY
	leaveBtn.BorderSizePixel = 0
	leaveBtn.Text = "Leave"
	leaveBtn.TextColor3 = BTN_TEXT_COLOR
	leaveBtn.TextTransparency = 0.15
	leaveBtn.Font = Enum.Font.GothamBold
	leaveBtn.TextSize = 12
	leaveBtn.AutoButtonColor = false
	leaveBtn.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	corner.Parent = leaveBtn

	leaveBtn.MouseEnter:Connect(function()
		leaveBtn.BackgroundColor3 = BTN_HOVER_COLOR
		leaveBtn.BackgroundTransparency = 0.15
		leaveBtn.TextTransparency = 0
	end)
	leaveBtn.MouseLeave:Connect(function()
		leaveBtn.BackgroundColor3 = BTN_COLOR
		leaveBtn.BackgroundTransparency = BTN_TRANSPARENCY
		leaveBtn.TextTransparency = 0.15
	end)

	leaveBtn.Activated:Connect(function()
		showConfirm()
	end)

	buildConfirmDialog()
end

function LeaveMatchGUI.Init()
	build()
end

function LeaveMatchGUI.Show()
	if screenGui then
		screenGui.Enabled = true
		hideConfirm()
		if leaveBtn then
			leaveBtn.Active = true
		end
	end
end

function LeaveMatchGUI.Hide()
	if screenGui then
		screenGui.Enabled = false
		hideConfirm()
	end
end

return LeaveMatchGUI
