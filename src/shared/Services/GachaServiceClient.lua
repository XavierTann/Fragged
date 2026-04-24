--[[
	Client-side gacha service: ProximityPrompt on Workspace.Lobby.Gacha.GachaCounter,
	free spin detection, and roll result forwarding to GachaGUI.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Modules.CombatConfig)
local ShopEconomyClient = require(Shared.Services.ShopEconomyClient)

local LocalPlayer = Players.LocalPlayer

local PROMPT_NAME = "GachaProximityPrompt"
local MAX_DISTANCE = 14

local gachaGUI = nil
local prompt = nil
local resultSubscribers = {}

local GachaServiceClient = {}

local function updatePromptText()
	if not prompt then
		return
	end
	local snap = ShopEconomyClient.GetSnapshot()
	if snap.freeSpinAvailable then
		prompt.ActionText = "FREE SPIN!"
		prompt.ObjectText = "Weapon Fabricator"
	else
		prompt.ActionText = "Roll"
		prompt.ObjectText = "Weapon Fabricator"
	end
end

local function findGachaCounterPart(): BasePart?
	local lobby = Workspace:FindFirstChild("Lobby")
	local gachaFolder = lobby and lobby:FindFirstChild("Gacha")
	if gachaFolder then
		local counter = gachaFolder:FindFirstChild("GachaCounter")
		if counter then
			if counter:IsA("BasePart") then
				return counter
			elseif counter:IsA("Model") then
				return counter.PrimaryPart or counter:FindFirstChildWhichIsA("BasePart", true)
			end
		end
	end
	return nil
end

local function wireProximityPrompt(part: BasePart)
	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ObjectText = "Weapon Fabricator"
	prompt.ActionText = "Roll"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Parent = part

	updatePromptText()

	prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		if gachaGUI then
			gachaGUI.Show()
		end
	end)
end

function GachaServiceClient.Init()
	gachaGUI = require(Shared.UI.GachaGUI)
	gachaGUI.SetFreeSpinRequester(function()
		GachaServiceClient.RequestFreeSpin()
	end)

	task.spawn(function()
		local counterPart = findGachaCounterPart()
		if not counterPart then
			local lobby = Workspace:WaitForChild("Lobby", 120)
			local gachaFolder = lobby and lobby:WaitForChild("Gacha", 120)
			if gachaFolder then
				local counterInst = gachaFolder:FindFirstChild("GachaCounter") or gachaFolder:WaitForChild("GachaCounter", 120)
				if counterInst then
					if counterInst:IsA("BasePart") then
						counterPart = counterInst
					elseif counterInst:IsA("Model") then
						counterPart = counterInst.PrimaryPart or counterInst:FindFirstChildWhichIsA("BasePart", true)
					end
				end
			end
		end
		if not counterPart then
			warn("[GachaServiceClient] Workspace.Lobby.Gacha.GachaCounter not found.")
			return
		end
		wireProximityPrompt(counterPart)
	end)

	ShopEconomyClient.Subscribe(function()
		updatePromptText()
	end)

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME, 120)
		if not folder then
			return
		end
		local resultRE = folder:WaitForChild(CombatConfig.REMOTES.GACHA_RESULT, 60)
		if resultRE and resultRE:IsA("RemoteEvent") then
			resultRE.OnClientEvent:Connect(function(payload)
				if gachaGUI then
					gachaGUI.ShowResult(payload)
				end
				for _, cb in ipairs(resultSubscribers) do
					task.spawn(cb, payload)
				end
			end)
		end
	end)
end

function GachaServiceClient.SubscribeResult(callback: (any) -> ())
	table.insert(resultSubscribers, callback)
end

function GachaServiceClient.RequestFreeSpin()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		return
	end
	local re = folder:FindFirstChild(CombatConfig.REMOTES.GACHA_FREE_SPIN)
	if re and re:IsA("RemoteEvent") then
		re:FireServer()
	end
end

return GachaServiceClient
