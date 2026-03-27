--[[
	KillNotificationGUI
	Center-screen "Eliminated [Name]" toast for the killer only. Hold, then fade; restacks if another kill arrives.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local LocalPlayer = Players.LocalPlayer

local HOLD_SECONDS = 1.1
local FADE_SECONDS = 0.5

local screenGui = nil
local container = nil
local label = nil
local stroke = nil
local sequenceToken = 0
local fadeTweens = {}

local function cancelFadeTweens()
	for _, tw in ipairs(fadeTweens) do
		tw:Cancel()
	end
	fadeTweens = {}
end

local function ensureGui()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KillNotificationGUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 24
	screenGui.Enabled = true
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.Name = "KillToast"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(520, 52)
	container.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Visible = false
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = container

	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 252, 245)
	label.TextTransparency = 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = container

	stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.8
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = label
end

local function showEliminated(victimDisplayName)
	ensureGui()
	if type(victimDisplayName) ~= "string" or victimDisplayName == "" then
		victimDisplayName = "Player"
	end

	sequenceToken = sequenceToken + 1
	local token = sequenceToken
	cancelFadeTweens()

	container.BackgroundTransparency = 0.62
	label.Text = "Eliminated " .. victimDisplayName
	label.TextTransparency = 0.06
	stroke.Transparency = 0.35
	container.Visible = true

	task.delay(HOLD_SECONDS, function()
		if token ~= sequenceToken then
			return
		end
		local ti = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local t1 = TweenService:Create(label, ti, { TextTransparency = 1 })
		local t2 = TweenService:Create(stroke, ti, { Transparency = 1 })
		local t3 = TweenService:Create(container, ti, { BackgroundTransparency = 1 })
		fadeTweens = { t1, t2, t3 }
		t1:Play()
		t2:Play()
		t3:Play()
		t1.Completed:Connect(function()
			if token ~= sequenceToken then
				return
			end
			container.Visible = false
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
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		local re = folder:WaitForChild(CombatConfig.REMOTES.KILL_NOTIFICATION)
		re.OnClientEvent:Connect(showEliminated)
	end,
}
