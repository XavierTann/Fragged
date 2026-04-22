--[[
	Server-side gacha roll service.
	Rolls award weapon skins (permanent unlocks). Duplicate rolls grant consolation credits.
	Handles free first spin and paid Robux rolls via Developer Products with weighted rarity RNG.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Modules.CombatConfig)
local GachaConfig = require(Shared.Modules.GachaConfig)
local SkinsConfig = require(Shared.Modules.SkinsConfig)

local EconomyServiceServer = require(script.Parent.Parent.EconomyService.EconomyServiceServer)

local gachaResultRE: RemoteEvent? = nil
local gachaFreeSpinRE: RemoteEvent? = nil

local pendingReceipts: { [number]: boolean } = {}

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local resultName = CombatConfig.REMOTES.GACHA_RESULT
	local ev = folder:FindFirstChild(resultName)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = resultName
		ev.Parent = folder
	end
	gachaResultRE = ev :: RemoteEvent

	local freeSpinName = CombatConfig.REMOTES.GACHA_FREE_SPIN
	local fs = folder:FindFirstChild(freeSpinName)
	if not fs then
		fs = Instance.new("RemoteEvent")
		fs.Name = freeSpinName
		fs.Parent = folder
	end
	gachaFreeSpinRE = fs :: RemoteEvent
end

local function pickRarity(): string
	local totalWeight = 0
	for _, r in ipairs(GachaConfig.RARITIES) do
		totalWeight += r.weight
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, r in ipairs(GachaConfig.RARITIES) do
		cumulative += r.weight
		if roll <= cumulative then
			return r.name
		end
	end
	return GachaConfig.RARITIES[#GachaConfig.RARITIES].name
end

local function getPoolByRarity(rarity: string)
	local entries = {}
	for _, entry in ipairs(GachaConfig.POOL) do
		if entry.rarity == rarity then
			table.insert(entries, entry)
		end
	end
	return entries
end

local function executeRoll(player: Player)
	local rarity = pickRarity()
	local pool = getPoolByRarity(rarity)

	if #pool == 0 then
		rarity = GachaConfig.RARITIES[1].name
		pool = getPoolByRarity(rarity)
	end

	if #pool == 0 then
		local allPool = GachaConfig.POOL
		if #allPool > 0 then
			local pick = allPool[math.random(1, #allPool)]
			rarity = pick.rarity
			pool = { pick }
		end
	end

	local pick = pool[math.random(1, #pool)]

	if EconomyServiceServer.OwnsSkin(player, pick.skinId) then
		local altPool = {}
		for _, e in ipairs(pool) do
			if not EconomyServiceServer.OwnsSkin(player, e.skinId) then
				table.insert(altPool, e)
			end
		end
		if #altPool > 0 then
			pick = altPool[math.random(1, #altPool)]
		else
			local consolation = GachaConfig.DUPE_CONSOLATION_CREDITS or 300
			return {
				skinId = pick.skinId,
				rarity = rarity,
				duplicate = true,
				consolationCredits = consolation,
			}
		end
	end

	return {
		skinId = pick.skinId,
		rarity = rarity,
		duplicate = false,
	}
end

local function grantRollResult(player: Player, result)
	if result.duplicate then
		EconomyServiceServer.AddCredits(player, result.consolationCredits)
	else
		EconomyServiceServer.AddSkin(player, result.skinId)
	end
end

local function fireResult(player: Player, result, isFree: boolean?)
	if not gachaResultRE or not player.Parent then
		return
	end
	local skin = SkinsConfig.getSkin(result.skinId)
	gachaResultRE:FireClient(player, {
		skinId = result.skinId,
		skinName = skin and skin.name or result.skinId,
		iconAssetId = skin and skin.iconAssetId or 0,
		rarity = result.rarity,
		duplicate = result.duplicate == true,
		consolationCredits = result.consolationCredits,
		isFree = isFree == true,
	})
end

local GachaServiceServer = {}

function GachaServiceServer.Init()
	ensureRemotes()

	if gachaFreeSpinRE then
		gachaFreeSpinRE.OnServerEvent:Connect(function(player)
			local data = EconomyServiceServer.GetPlayerData(player)
			if not data then
				return
			end

			if GachaConfig.DEV_FREE_ROLLS then
				local result = executeRoll(player)
				grantRollResult(player, result)
				fireResult(player, result, true)
				return
			end

			if data.hasUsedFirstRoll then
				return
			end

			local firstRoll = GachaConfig.FIRST_ROLL
			local result = {
				skinId = firstRoll.skinId,
				rarity = "Legendary",
				duplicate = EconomyServiceServer.OwnsSkin(player, firstRoll.skinId),
			}
			if result.duplicate then
				result.consolationCredits = GachaConfig.DUPE_CONSOLATION_CREDITS or 300
			end

			EconomyServiceServer.SetHasUsedFirstRoll(player)
			grantRollResult(player, result)
			fireResult(player, result, true)
		end)
	end

	local productId = GachaConfig.DEVELOPER_PRODUCT_ID
	if productId and productId > 0 then
		MarketplaceService.ProcessReceipt = function(receiptInfo)
			if receiptInfo.ProductId ~= productId then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
			if not player then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			if pendingReceipts[receiptInfo.PurchaseId] then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			pendingReceipts[receiptInfo.PurchaseId] = true

			local ok, err = pcall(function()
				local result = executeRoll(player)
				grantRollResult(player, result)
				fireResult(player, result, false)
			end)

			pendingReceipts[receiptInfo.PurchaseId] = nil

			if not ok then
				warn("[GachaServiceServer] Roll failed:", err)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
end

return GachaServiceServer
