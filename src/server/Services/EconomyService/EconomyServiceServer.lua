--[[
	Persisted credits, match count, and shop-owned guns. Awards on TDM end; validates shop purchases.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreditsConfig = require(Shared.Modules.CreditsConfig)
local ShopCatalog = require(Shared.Modules.ShopCatalog)
local CombatConfig = require(Shared.Modules.CombatConfig)

local WeaponInventoryServer = require(script.Parent.Parent.CombatService.WeaponInventoryServer)
local WeaponToolServer = require(script.Parent.Parent.CombatService.WeaponToolServer)

export type TempWeapon = {
	id: string,
	roundsLeft: number,
}

export type EconomyData = {
	credits: number,
	matchesPlayed: number,
	ownedShopGuns: { string },
	tempWeapons: { TempWeapon },
	hasUsedFirstRoll: boolean,
}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(CreditsConfig.DATASTORE_NAME)
end)

local cache: { [number]: EconomyData } = {}
local loadLocks: { [number]: boolean } = {}
local syncRE: RemoteEvent? = nil
local purchaseRF: RemoteFunction? = nil

local function defaultData(): EconomyData
	return {
		credits = 0,
		matchesPlayed = 0,
		ownedShopGuns = {},
		tempWeapons = {},
		hasUsedFirstRoll = false,
	}
end

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local nameSync = CombatConfig.REMOTES.ECONOMY_SYNC
	local namePurchase = CombatConfig.REMOTES.SHOP_PURCHASE
	local ev = folder:FindFirstChild(nameSync)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = nameSync
		ev.Parent = folder
	end
	syncRE = ev :: RemoteEvent
	local rf = folder:FindFirstChild(namePurchase)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = namePurchase
		rf.Parent = folder
	end
	purchaseRF = rf :: RemoteFunction
end

local function ownsGun(data: EconomyData, gunId: string): boolean
	for _, g in ipairs(data.ownedShopGuns) do
		if g == gunId then
			return true
		end
	end
	return false
end

local function savePlayer(userId: number, data: EconomyData)
	if not store then
		return
	end
	local key = tostring(userId)
	local serializedTemp = {}
	for _, tw in ipairs(data.tempWeapons) do
		table.insert(serializedTemp, { id = tw.id, r = tw.roundsLeft })
	end
	local payload = {
		c = data.credits,
		m = data.matchesPlayed,
		g = data.ownedShopGuns,
		t = serializedTemp,
		f = data.hasUsedFirstRoll,
	}
	local ok, err = pcall(function()
		store:SetAsync(key, payload)
	end)
	if not ok then
		warn("[EconomyServiceServer] Save failed:", userId, err)
	end
end

local function loadPlayer(userId: number): EconomyData
	if not store then
		return defaultData()
	end
	local key = tostring(userId)
	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok or type(result) ~= "table" then
		return defaultData()
	end
	local data = defaultData()
	if typeof(result.c) == "number" then
		data.credits = math.max(0, math.floor(result.c))
	end
	if typeof(result.m) == "number" then
		data.matchesPlayed = math.max(0, math.floor(result.m))
	end
	if typeof(result.g) == "table" then
		for _, g in ipairs(result.g) do
			if typeof(g) == "string" and ShopCatalog.isShopGun(g) then
				table.insert(data.ownedShopGuns, g)
			end
		end
	end
	if typeof(result.t) == "table" then
		for _, tw in ipairs(result.t) do
			if typeof(tw) == "table" and typeof(tw.id) == "string" and typeof(tw.r) == "number" and tw.r > 0 then
				table.insert(data.tempWeapons, { id = tw.id, roundsLeft = math.floor(tw.r) })
			end
		end
	end
	if result.f == true then
		data.hasUsedFirstRoll = true
	end
	return data
end

local function getOrLoad(player: Player): EconomyData
	local uid = player.UserId
	if cache[uid] then
		return cache[uid]
	end
	while loadLocks[uid] do
		task.wait()
	end
	if cache[uid] then
		return cache[uid]
	end
	loadLocks[uid] = true
	local d = loadPlayer(uid)
	cache[uid] = d
	loadLocks[uid] = false
	return d
end

local function applyOwnedGunsToInventory(player: Player, data: EconomyData)
	for _, gunId in ipairs(data.ownedShopGuns) do
		if ShopCatalog.isShopGun(gunId) then
			WeaponInventoryServer.addWeapon(player, gunId)
			WeaponToolServer.giveGunToolIfMissing(player, gunId)
		end
	end
	for _, tw in ipairs(data.tempWeapons) do
		if tw.roundsLeft > 0 then
			WeaponInventoryServer.addWeapon(player, tw.id)
			WeaponToolServer.giveGunToolIfMissing(player, tw.id)
		end
	end
end

local function buildSyncPayload(data: EconomyData)
	local owned: { string } = {}
	for _, g in ipairs(data.ownedShopGuns) do
		table.insert(owned, g)
	end
	local tempList = {}
	for _, tw in ipairs(data.tempWeapons) do
		if tw.roundsLeft > 0 then
			table.insert(tempList, { id = tw.id, roundsLeft = tw.roundsLeft })
		end
	end
	return {
		credits = data.credits,
		matchesPlayed = data.matchesPlayed,
		ownedShopGunIds = owned,
		tempWeapons = tempList,
		freeSpinAvailable = not data.hasUsedFirstRoll,
	}
end

local function fireSync(player: Player)
	if not syncRE or not player.Parent then
		return
	end
	local data = getOrLoad(player)
	syncRE:FireClient(player, buildSyncPayload(data))
end

local function preparePlayerEconomy(player: Player)
	local data = getOrLoad(player)
	if CreditsConfig.GRANT_TEST_CREDITS == true then
		data.credits = math.max(0, math.floor(tonumber(CreditsConfig.TEST_CREDITS_BALANCE) or 2000))
		cache[player.UserId] = data
	end
	applyOwnedGunsToInventory(player, data)
	fireSync(player)
end

local EconomyServiceServer = {}

function EconomyServiceServer.Init()
	ensureRemotes()
	if purchaseRF then
		purchaseRF.OnServerInvoke = function(player, itemId: any)
			if typeof(itemId) ~= "string" then
				return { ok = false, error = "BadItem" }
			end
			local entry = ShopCatalog.getEntry(itemId)
			if not entry then
				return { ok = false, error = "UnknownItem" }
			end
			local data = getOrLoad(player)
			if ownsGun(data, entry.id) then
				return { ok = false, error = "AlreadyOwned" }
			end
			if data.credits < entry.price then
				return { ok = false, error = "NotEnoughCredits" }
			end
			data.credits -= entry.price
			table.insert(data.ownedShopGuns, entry.id)
			cache[player.UserId] = data
			WeaponInventoryServer.addWeapon(player, entry.id)
			WeaponToolServer.giveGunToolIfMissing(player, entry.id)
			savePlayer(player.UserId, data)
			fireSync(player)
			return {
				ok = true,
				credits = data.credits,
				matchesPlayed = data.matchesPlayed,
				ownedShopGunIds = buildSyncPayload(data).ownedShopGunIds,
			}
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			preparePlayerEconomy(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local data = cache[player.UserId]
		if data and store then
			savePlayer(player.UserId, data)
		end
		cache[player.UserId] = nil
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			preparePlayerEconomy(p)
		end)
	end
end

function EconomyServiceServer.ApplyMatchEndRewards(
	players: { Player },
	winningTeam: string,
	playerTeams: { [number]: string }
)
	for _, p in ipairs(players) do
		if p and p.Parent then
			local data = getOrLoad(p)
			data.matchesPlayed += 1
			local myTeam = playerTeams[p.UserId] or "Blue"
			if myTeam == winningTeam then
				data.credits += CreditsConfig.WIN_CREDITS
			else
				data.credits += CreditsConfig.LOSS_CREDITS
			end

			local surviving: { TempWeapon } = {}
			for _, tw in ipairs(data.tempWeapons) do
				tw.roundsLeft -= 1
				if tw.roundsLeft > 0 then
					table.insert(surviving, tw)
				else
					WeaponInventoryServer.removeWeapon(p, tw.id)
					local backpack = p:FindFirstChild("Backpack")
					if backpack then
						local tool = backpack:FindFirstChild(tw.id)
						if tool then
							tool:Destroy()
						end
					end
					local char = p.Character
					if char then
						local charTool = char:FindFirstChild(tw.id)
						if charTool then
							charTool:Destroy()
						end
					end
				end
			end
			data.tempWeapons = surviving

			cache[p.UserId] = data
			savePlayer(p.UserId, data)
			fireSync(p)
		end
	end
end

function EconomyServiceServer.GetPlayerData(player: Player): EconomyData?
	if not player or not player.Parent then
		return nil
	end
	return getOrLoad(player)
end

function EconomyServiceServer.AddTempWeapon(player: Player, weaponId: string, rounds: number)
	local data = getOrLoad(player)
	for _, tw in ipairs(data.tempWeapons) do
		if tw.id == weaponId then
			tw.roundsLeft += rounds
			cache[player.UserId] = data
			WeaponInventoryServer.addWeapon(player, weaponId)
			WeaponToolServer.giveGunToolIfMissing(player, weaponId)
			savePlayer(player.UserId, data)
			fireSync(player)
			return
		end
	end
	table.insert(data.tempWeapons, { id = weaponId, roundsLeft = rounds })
	cache[player.UserId] = data
	WeaponInventoryServer.addWeapon(player, weaponId)
	WeaponToolServer.giveGunToolIfMissing(player, weaponId)
	savePlayer(player.UserId, data)
	fireSync(player)
end

function EconomyServiceServer.AddPermanentGun(player: Player, gunId: string)
	local data = getOrLoad(player)
	if ownsGun(data, gunId) then
		return
	end
	table.insert(data.ownedShopGuns, gunId)
	cache[player.UserId] = data
	WeaponInventoryServer.addWeapon(player, gunId)
	WeaponToolServer.giveGunToolIfMissing(player, gunId)
	savePlayer(player.UserId, data)
	fireSync(player)
end

function EconomyServiceServer.SetHasUsedFirstRoll(player: Player)
	local data = getOrLoad(player)
	data.hasUsedFirstRoll = true
	cache[player.UserId] = data
	savePlayer(player.UserId, data)
	fireSync(player)
end

function EconomyServiceServer.FireSync(player: Player)
	fireSync(player)
end

return EconomyServiceServer
