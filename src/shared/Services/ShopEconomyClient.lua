--[[
	Client cache of credits / match count / owned shop guns; purchase invoke + server sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Modules.CombatConfig)

export type TempWeaponInfo = {
	id: string,
	roundsLeft: number,
}

export type EconomySnapshot = {
	credits: number,
	matchesPlayed: number,
	ownedShopGunIds: { [string]: boolean },
	tempWeapons: { TempWeaponInfo },
	freeSpinAvailable: boolean,
	ownedSkinIds: { [string]: boolean },
}

local snapshot: EconomySnapshot = {
	credits = 0,
	matchesPlayed = 0,
	ownedShopGunIds = {},
	tempWeapons = {},
	freeSpinAvailable = false,
	ownedSkinIds = {},
}

local subscribers: { (EconomySnapshot) -> () } = {}

local function fillOwnedFromList(list: any)
	local owned: { [string]: boolean } = {}
	if typeof(list) == "table" then
		for _, id in ipairs(list) do
			if typeof(id) == "string" then
				owned[id] = true
			end
		end
	end
	return owned
end

local function parseTempWeapons(raw: any): { TempWeaponInfo }
	local result: { TempWeaponInfo } = {}
	if typeof(raw) == "table" then
		for _, tw in ipairs(raw) do
			if typeof(tw) == "table" and typeof(tw.id) == "string" and typeof(tw.roundsLeft) == "number" then
				table.insert(result, { id = tw.id, roundsLeft = tw.roundsLeft })
			end
		end
	end
	return result
end

local function applyPayload(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	snapshot.credits = math.max(0, math.floor(tonumber(payload.credits) or 0))
	snapshot.matchesPlayed = math.max(0, math.floor(tonumber(payload.matchesPlayed) or 0))
	snapshot.ownedShopGunIds = fillOwnedFromList(payload.ownedShopGunIds)
	snapshot.tempWeapons = parseTempWeapons(payload.tempWeapons)
	snapshot.freeSpinAvailable = payload.freeSpinAvailable == true
	snapshot.ownedSkinIds = fillOwnedFromList(payload.ownedSkinIds)
	for _, cb in ipairs(subscribers) do
		cb(snapshot)
	end
end

local ShopEconomyClient = {}

function ShopEconomyClient.Init()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME, 120)
		if not folder then
			return
		end
		local sync = folder:WaitForChild(CombatConfig.REMOTES.ECONOMY_SYNC, 60)
		if sync and sync:IsA("RemoteEvent") then
			sync.OnClientEvent:Connect(function(payload)
				applyPayload(payload)
			end)
		end
	end)
end

function ShopEconomyClient.GetSnapshot(): EconomySnapshot
	return snapshot
end

function ShopEconomyClient.Subscribe(callback: (EconomySnapshot) -> ())
	table.insert(subscribers, callback)
end

function ShopEconomyClient.TryPurchase(itemId: string): any
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	local rf = folder and folder:FindFirstChild(CombatConfig.REMOTES.SHOP_PURCHASE)
	if rf and rf:IsA("RemoteFunction") then
		return rf:InvokeServer(itemId)
	end
	return { ok = false, error = "NoRemote" }
end

return ShopEconomyClient
