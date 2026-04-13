--[[
	ReloadBarGUI
	Progress bar showing reload state. Fills as reload progresses.
	Visible only when the current weapon is reloading. Full bar = reload complete.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local gui = nil
local barFrame = nil
local fillFrame = nil
local updateConnection = nil

local BAR_WIDTH = 200
local BAR_HEIGHT = 16
local BAR_OFFSET_Y = 100 -- above weapon bar

local reloadTextLabel = nil

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "ReloadBarGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function createBar(parent)
	local container = Instance.new("Frame")
	container.Name = "ReloadBarContainer"
	container.Size = UDim2.fromOffset(BAR_WIDTH + 24, BAR_HEIGHT + 36)
	container.Position = UDim2.new(0.5, 0, 1, -BAR_OFFSET_Y)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	reloadTextLabel = Instance.new("TextLabel")
	reloadTextLabel.Name = "ReloadingText"
	reloadTextLabel.Size = UDim2.new(1, 0, 0, 18)
	reloadTextLabel.Position = UDim2.fromOffset(0, 0)
	reloadTextLabel.BackgroundTransparency = 1
	reloadTextLabel.Text = "Reloading..."
	reloadTextLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	reloadTextLabel.TextSize = 14
	reloadTextLabel.Font = Enum.Font.GothamBold
	reloadTextLabel.Parent = container

	barFrame = Instance.new("Frame")
	barFrame.Name = "ReloadBar"
	barFrame.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	barFrame.Position = UDim2.new(0.5, -BAR_WIDTH / 2, 0, 28)
	barFrame.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	barFrame.BorderSizePixel = 0
	barFrame.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = barFrame

	fillFrame = Instance.new("Frame")
	fillFrame.Name = "ReloadFill"
	fillFrame.Size = UDim2.fromScale(0, 1)
	fillFrame.Position = UDim2.fromOffset(0, 0)
	fillFrame.AnchorPoint = Vector2.new(0, 0)
	fillFrame.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fillFrame

	return container
end

local function updateProgress()
	if not barFrame or not fillFrame then
		return
	end
	local state = CombatServiceClient.GetAmmoState()
	if not state.isReloading then
		barFrame.Parent.Visible = false
		return
	end
	barFrame.Parent.Visible = true
	local now = os.clock()
	local elapsed = now - (state.reloadStartedAt or now)
	local progress = math.clamp(elapsed / state.reloadTime, 0, 1)
	fillFrame.Size = UDim2.fromScale(progress, 1)
	if progress >= 1 then
		-- Reload complete; bar will hide when next AmmoState arrives
		fillFrame.Size = UDim2.fromScale(1, 1)
	end
end

local function startUpdateLoop()
	if updateConnection then
		return
	end
	updateConnection = RunService.RenderStepped:Connect(updateProgress)
end

local function stopUpdateLoop()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
end

local isVisible = false

local function onAmmoStateChanged()
	-- When ammo state changes, ensure we refresh (e.g. reload started)
	if isVisible then
		updateProgress()
	end
end

local function init()
	createGui()
	local container = Instance.new("Frame")
	container.Name = "ReloadBarRoot"
	container.Size = UDim2.fromScale(1, 1)
	container.Position = UDim2.fromScale(0, 0)
	container.BackgroundTransparency = 1
	container.Parent = gui
	createBar(container)
	CombatServiceClient.SubscribeAmmoState(onAmmoStateChanged)
	gui.Enabled = true
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			isVisible = true
			startUpdateLoop()
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
			isVisible = false
			stopUpdateLoop()
		end
	end,
}
