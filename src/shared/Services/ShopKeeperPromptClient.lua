--[[
	Client: Shop keeper under Workspace.GunShop (or gunshop) / ShopKeeper.
	Opens ShopGUI via a single ProximityPrompt (keyboard, gamepad, touch).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopGUI = require(Shared.UI.Shop.ShopGUI)

local LocalPlayer = Players.LocalPlayer

local SHOP_KEEPER_NAME = "ShopKeeper"
local PROMPT_NAME = "ShopBuyProximityPrompt"
local MAX_DISTANCE = 14

local function findGunShopFolder(): Instance?
	local ws = Workspace
	local direct = ws:FindFirstChild("GunShop") or ws:FindFirstChild("gunshop")
	if direct then
		return direct
	end
	local lobby = ws:FindFirstChild("Lobby")
	if lobby then
		return lobby:FindFirstChild("GunShop") or lobby:FindFirstChild("gunshop")
	end
	return nil
end

local function findBasePartForPrompt(model: Model): BasePart?
	if model.PrimaryPart then
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
	wireProximityPrompt(part)
end

local ShopKeeperPromptClient = {}

function ShopKeeperPromptClient.Init()
	task.spawn(function()
		local gunShop = findGunShopFolder()
		if not gunShop then
			local lobby = Workspace:FindFirstChild("Lobby") or Workspace:WaitForChild("Lobby", 10)
			if lobby then
				gunShop = lobby:FindFirstChild("GunShop") or lobby:WaitForChild("GunShop", 120)
			end
		end
		if not gunShop then
			gunShop = Workspace:WaitForChild("GunShop", 5) or Workspace:WaitForChild("gunshop", 5)
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

		gunShop.ChildAdded:Connect(function(child)
			if child.Name == SHOP_KEEPER_NAME then
				task.defer(function()
					trySetupKeeper(child)
				end)
			end
		end)
	end)
end

return ShopKeeperPromptClient
