--[[
	Server-side gacha roll service.
	Handles free first spin (guaranteed Plasma Carbine for 5 rounds) and
	paid Robux rolls via Developer Products with weighted rarity RNG.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Modules.CombatConfig)
local GachaConfig = require(Shared.Modules.GachaConfig)

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

local function playerOwnsGunPermanently(player, gunId): boolean
	local data = EconomyServiceServer.GetPlayerData(player)
	if not data then
		return false
	end
	for _, g in ipairs(data.ownedShopGuns) do
		if g == gunId then
			return true
		end
	end
	return false
end

local function executeRoll(player: Player): { weaponId: string, rarity: string, permanent: boolean, rounds: number? }
	local rarity = pickRarity()
	local pool = getPoolByRarity(rarity)

	if #pool == 0 then
		rarity = GachaConfig.RARITIES[1].name
		pool = getPoolByRarity(rarity)
	end

	local pick = pool[math.random(1, #pool)]

	if pick.permanent and playerOwnsGunPermanently(player, pick.weaponId) then
		local altPool = {}
		for _, e in ipairs(pool) do
			if not e.permanent or not playerOwnsGunPermanently(player, e.weaponId) then
				table.insert(altPool, e)
			end
		end
		if #altPool > 0 then
			pick = altPool[math.random(1, #altPool)]
		else
			return {
				weaponId = pick.weaponId,
				rarity = rarity,
				permanent = false,
				rounds = GachaConfig.DUPE_PERM_CONSOLATION_ROUNDS,
			}
		end
	end

	return {
		weaponId = pick.weaponId,
		rarity = rarity,
		permanent = pick.permanent == true,
		rounds = pick.rounds,
	}
end

local function grantRollResult(player: Player, result)
	if result.permanent then
		EconomyServiceServer.AddPermanentGun(player, result.weaponId)
	else
		EconomyServiceServer.AddTempWeapon(player, result.weaponId, result.rounds or 3)
	end
end

local function fireResult(player: Player, result, isFree: boolean?)
	if not gachaResultRE or not player.Parent then
		return
	end
	gachaResultRE:FireClient(player, {
		weaponId = result.weaponId,
		rarity = result.rarity,
		permanent = result.permanent,
		rounds = result.rounds,
		isFree = isFree == true,
	})
end

local GachaServiceServer = {}

function GachaServiceServer.Init()
	ensureRemotes()

	if gachaFreeSpinRE then
		gachaFreeSpinRE.OnServerEvent:Connect(function(player)
			local data = EconomyServiceServer.GetPlayerData(player)
			if not data or data.hasUsedFirstRoll then
				return
			end

			local firstRoll = GachaConfig.FIRST_ROLL
			local result = {
				weaponId = firstRoll.weaponId,
				rarity = "Legendary",
				permanent = false,
				rounds = firstRoll.rounds,
			}

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
