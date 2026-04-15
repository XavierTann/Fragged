--[[
	Client shop overlay: React tree under PlayerGui, starts disabled.
	Call ShopGUI.Show() when the player should see it (e.g. shop pad / prompt).
	Automatically hides when entering the arena so it does not cover combat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared.Modules.LobbyConfig)
local ShopCatalog = require(Shared.Modules.ShopCatalog)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
local ShopEconomyClient = require(Shared.Services.ShopEconomyClient)
local ShopReactMount = require(script.Parent.ShopReactMount)

local LocalPlayer = Players.LocalPlayer

local ShopGUI = {}

local mountHandle = nil
local coinOverride: number? = nil

local shopUiEnabled = false
local onOpenCallbacks = {}
local onCloseCallbacks = {}
local savedWalkSpeed: number? = nil
local savedJumpHeight: number? = nil

local function applyMovementFreeze(humanoid: Humanoid)
	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpHeight = humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function clearMovementLock()
	local walk = savedWalkSpeed
	local jump = savedJumpHeight
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	savedWalkSpeed = nil
	savedJumpHeight = nil
	if hum and hum.Parent and walk ~= nil then
		hum.WalkSpeed = walk
		hum.JumpHeight = jump or hum.JumpHeight
	end
end

local function setShopUiEnabled(enabled: boolean)
	enabled = enabled == true
	if mountHandle then
		mountHandle:setEnabled(enabled)
	end
	if enabled == shopUiEnabled then
		return
	end
	shopUiEnabled = enabled
	if enabled then
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			applyMovementFreeze(hum)
		end
	else
		clearMovementLock()
	end
end

local function buildDisplayItems(): { any }
	local snap = ShopEconomyClient.GetSnapshot()
	local credits = snap.credits
	local owned = snap.ownedShopGunIds
	local items: { any } = {}
	for _, def in ipairs(ShopCatalog.getItems()) do
		local ownedGun = owned[def.id] == true
		local statusNote: string? = nil
		local buyLabel = "BUY"
		local buyDisabled = false
		if ownedGun then
			buyLabel = "OWNED"
			buyDisabled = true
		elseif credits < def.price then
			buyDisabled = true
			statusNote = string.format("Need %d more credits", def.price - credits)
		end
		table.insert(items, {
			id = def.id,
			name = def.name,
			price = def.price,
			tag = def.tag,
			accent = def.accent,
			imageAssetId = def.imageAssetId,
			buyLabel = buyLabel,
			buyDisabled = buyDisabled,
			statusNote = statusNote,
		})
	end
	return items
end

local function pushProps()
	if not mountHandle then
		return
	end
	local snap = ShopEconomyClient.GetSnapshot()
	mountHandle:renderProps({
		coins = if coinOverride ~= nil then coinOverride else snap.credits,
		items = buildDisplayItems(),
		onClose = function()
			ShopGUI.Hide()
		end,
		onPurchase = function(item: any)
			if typeof(item) ~= "table" or item.buyDisabled then
				return
			end
			local r = ShopEconomyClient.TryPurchase(item.id)
			if r and r.ok then
				pushProps()
			end
		end,
	})
end

function ShopGUI.Init()
	ShopEconomyClient.Init()
	ShopEconomyClient.Subscribe(function()
		pushProps()
	end)

	local pg = LocalPlayer:WaitForChild("PlayerGui")
	mountHandle = ShopReactMount.mount({
		parent = pg,
		props = {},
		displayOrder = 11,
	})
	pushProps()
	setShopUiEnabled(false)

	LobbyServiceClient.Subscribe(function(state)
		if state and state.phase == LobbyConfig.PHASE.ARENA then
			setShopUiEnabled(false)
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(character)
		if not shopUiEnabled then
			return
		end
		task.defer(function()
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				applyMovementFreeze(hum)
			end
		end)
	end)
end

function ShopGUI.SetCoins(coins: number)
	coinOverride = coins
	pushProps()
end

function ShopGUI.Show()
	if mountHandle then
		pushProps()
		setShopUiEnabled(true)
		for _, cb in ipairs(onOpenCallbacks) do
			task.spawn(cb)
		end
	end
end

function ShopGUI.SubscribeOnOpen(cb)
	table.insert(onOpenCallbacks, cb)
end

function ShopGUI.Hide()
	local wasOpen = shopUiEnabled
	setShopUiEnabled(false)
	if wasOpen then
		for _, cb in ipairs(onCloseCallbacks) do
			task.spawn(cb)
		end
	end
end

function ShopGUI.SubscribeOnClose(cb)
	table.insert(onCloseCallbacks, cb)
end

return ShopGUI
