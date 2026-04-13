--[[
	Client: Weapon storage under Workspace.GunShop (or gunshop) / WeaponStorage.
	Opens LoadoutGUI via ProximityPrompt on the model's PrimaryPart (keyboard, gamepad, touch).
	Only when not in arena (same rule as the previous lobby-only loadout access).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
local LoadoutGUI = require(Shared.UI.LoadoutGUI)

local LocalPlayer = Players.LocalPlayer

local WEAPON_STORAGE_NAME = "WeaponStorage"
local PROMPT_NAME = "WeaponStorageProximityPrompt"
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

local function findWeaponStorageModel(gunShop: Instance): Instance?
	return gunShop:FindFirstChild(WEAPON_STORAGE_NAME)
		or gunShop:FindFirstChild("weaponstorage")
		or gunShop:FindFirstChild("Weaponstorage")
end

local function getPrimaryPartForPrompt(model: Model): BasePart?
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then
		return pp
	end
	warn("[WeaponStoragePromptClient] WeaponStorage has no PrimaryPart; set PrimaryPart on the model for the prompt.")
	return nil
end

local function canOpenLoadout(): boolean
	local state = LobbyServiceClient.GetState()
	if not state then
		return true
	end
	return state.phase ~= LobbyConfig.PHASE.ARENA
end

local function wireProximityPrompt(part: BasePart)
	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ObjectText = "Weapon Storage"
	prompt.ActionText = "Customize loadout"
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
		if not canOpenLoadout() then
			return
		end
		LoadoutGUI.Show()
	end)
end

local function trySetupStorage(storage: Instance)
	if not storage:IsA("Model") then
		return
	end
	local part = getPrimaryPartForPrompt(storage :: Model)
	if not part then
		return
	end
	wireProximityPrompt(part)
end

local WeaponStoragePromptClient = {}

function WeaponStoragePromptClient.Init()
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
			warn("[WeaponStoragePromptClient] Workspace.GunShop / gunshop not found.")
			return
		end

		local storage = findWeaponStorageModel(gunShop)
		if not storage then
			storage = gunShop:WaitForChild(WEAPON_STORAGE_NAME, 120)
		end
		if not storage then
			warn("[WeaponStoragePromptClient] WeaponStorage model not found under GunShop.")
			return
		end

		trySetupStorage(storage)

		gunShop.ChildAdded:Connect(function(child)
			if child.Name == WEAPON_STORAGE_NAME or child.Name == "weaponstorage" or child.Name == "Weaponstorage" then
				task.defer(function()
					trySetupStorage(child)
				end)
			end
		end)
	end)
end

return WeaponStoragePromptClient
