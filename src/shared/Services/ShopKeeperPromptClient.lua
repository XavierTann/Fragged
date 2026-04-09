--[[
	Client: Shop keeper under Workspace.GunShop (or gunshop) / ShopKeeper.
	- ProximityPrompt (E / gamepad) opens ShopGUI.
	- Touch devices: on-screen button near the bottom when in range (tap to open shop).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopGUI = require(Shared.UI.Shop.ShopGUI)
local Theme = require(Shared.UI.Shop.ShopTheme)

local LocalPlayer = Players.LocalPlayer

local SHOP_KEEPER_NAME = "ShopKeeper"
local PROMPT_NAME = "ShopBuyProximityPrompt"
local MOBILE_GUI_NAME = "ShopKeeperMobileButton"
local MAX_DISTANCE = 14
local POLL_INTERVAL = 0.2

local keeperPart: BasePart? = nil
local mobileCallout: Frame? = nil
local heartbeatConn: RBXScriptConnection? = nil

local function findGunShopFolder(): Instance?
	local ws = Workspace
	return ws:FindFirstChild("GunShop") or ws:FindFirstChild("gunshop")
end

local function findBasePartForPrompt(model: Model): BasePart?
	print(model:GetDescendants())
	if model.PrimaryPart then
		print("PrimaryPart found")
		return model.PrimaryPart
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.Parent and humanoid.Parent:IsA("Model") then
		local root = (humanoid.Parent :: Model):FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function isShopScreenOpen(): boolean
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	local sg = pg:FindFirstChild("ShopReactGUI")
	return sg ~= nil and sg:IsA("ScreenGui") and (sg :: ScreenGui).Enabled == true
end

local function updateMobileCalloutVisibility()
	local callout = mobileCallout
	if not callout then
		return
	end
	if not UserInputService.TouchEnabled then
		callout.Visible = false
		return
	end
	local part = keeperPart
	if not part or not part.Parent then
		callout.Visible = false
		return
	end
	if isShopScreenOpen() then
		callout.Visible = false
		return
	end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		callout.Visible = false
		return
	end
	local dist = ((hrp :: BasePart).Position - part.Position).Magnitude
	callout.Visible = dist <= MAX_DISTANCE
end

local function createMobileCallout()
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild(MOBILE_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = MOBILE_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 40
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = true
	screenGui.Parent = pg

	local container = Instance.new("Frame")
	container.Name = "TapToShopCallout"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -140)
	container.Size = UDim2.new(0.88, 0, 0, 54)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = screenGui
	mobileCallout = container

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(340, 80)
	sizeCap.Parent = container

	local btn = Instance.new("TextButton")
	btn.Name = "OpenShop"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Theme.Panel
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = "Buy items from the shop"
	btn.TextColor3 = Theme.TextBright
	btn.TextSize = 18
	btn.Font = Theme.FontDisplay
	btn.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.NeonCyan
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = btn

	btn.Activated:Connect(function()
		ShopGUI.Show()
	end)
end

local function wireProximityPrompt(part: BasePart)
	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ObjectText = "Shop Keeper"
	prompt.ActionText = "Buy items from the shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		ShopGUI.Show()
	end)
end

local function trySetupKeeper(keeper: Instance)
	if not keeper:IsA("Model") then
		return
	end
	local part = findBasePartForPrompt(keeper :: Model)
	if not part then
		warn("[ShopKeeperPromptClient] ShopKeeper has no BasePart / PrimaryPart for prompt.")
		return
	end
	keeperPart = part
	wireProximityPrompt(part)
end

local function startRangePolling()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	local acc = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < POLL_INTERVAL then
			return
		end
		acc = 0
		updateMobileCalloutVisibility()
	end)
end

local ShopKeeperPromptClient = {}

function ShopKeeperPromptClient.Init()
	task.spawn(function()
		local gunShop = findGunShopFolder()
		if not gunShop then
			gunShop = Workspace:WaitForChild("GunShop", 120) or Workspace:WaitForChild("gunshop", 5)
		end
		if not gunShop then
			warn("[ShopKeeperPromptClient] Workspace.GunShop / gunshop not found.")
			return
		end

		local keeper = gunShop:FindFirstChild(SHOP_KEEPER_NAME)
			or gunShop:WaitForChild(SHOP_KEEPER_NAME, 120)
		if not keeper then
			warn("[ShopKeeperPromptClient] ShopKeeper model not found under GunShop.")
			return
		end

		trySetupKeeper(keeper)
		createMobileCallout()
		startRangePolling()

		gunShop.ChildAdded:Connect(function(child)
			if child.Name == SHOP_KEEPER_NAME then
				task.defer(function()
					trySetupKeeper(child)
					updateMobileCalloutVisibility()
				end)
			end
		end)
	end)
end

return ShopKeeperPromptClient
