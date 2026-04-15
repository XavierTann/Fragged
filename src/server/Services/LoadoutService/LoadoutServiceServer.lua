--[[
	LoadoutServiceServer
	Stores per-player weapon loadout in memory (session-scoped, not persisted).
	Validates selections against LoadoutConfig categories and weapon ownership.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local LoadoutConfig = require(ReplicatedStorage.Shared.Modules.LoadoutConfig)
local ShopCatalog = require(ReplicatedStorage.Shared.Modules.ShopCatalog)

local playerLoadouts = {}
local loadoutRE = nil

local function isWeaponOwned(player, weaponId)
	if not ShopCatalog.isShopGun(weaponId) then
		return true
	end
	local EconomyServiceServer = require(script.Parent.Parent.EconomyService.EconomyServiceServer)
	local data = EconomyServiceServer.GetPlayerData(player)
	if not data then
		return false
	end
	for _, g in ipairs(data.ownedShopGuns) do
		if g == weaponId then
			return true
		end
	end
	for _, tw in ipairs(data.tempWeapons or {}) do
		if tw.id == weaponId and tw.roundsLeft > 0 then
			return true
		end
	end
	return false
end

local function validateLoadout(player, primary, secondary)
	if typeof(primary) ~= "string" or typeof(secondary) ~= "string" then
		return false
	end
	if not LoadoutConfig:isPrimaryWeapon(primary) then
		return false
	end
	if not LoadoutConfig:isSecondaryWeapon(secondary) then
		return false
	end
	if not isWeaponOwned(player, primary) then
		return false
	end
	if not isWeaponOwned(player, secondary) then
		return false
	end
	return true
end

local LoadoutServiceServer = {}

function LoadoutServiceServer.GetLoadout(player)
	local lo = playerLoadouts[player.UserId]
	if lo then
		return lo
	end
	return {
		primary = LoadoutConfig.DEFAULT.primary,
		secondary = LoadoutConfig.DEFAULT.secondary,
	}
end

function LoadoutServiceServer.SetLoadout(player, primary, secondary)
	if not validateLoadout(player, primary, secondary) then
		return false
	end
	playerLoadouts[player.UserId] = {
		primary = primary,
		secondary = secondary,
	}
	return true
end

function LoadoutServiceServer.Init()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	loadoutRE = folder:FindFirstChild(CombatConfig.REMOTES.LOADOUT_SELECT)
	if not loadoutRE then
		loadoutRE = Instance.new("RemoteEvent")
		loadoutRE.Name = CombatConfig.REMOTES.LOADOUT_SELECT
		loadoutRE.Parent = folder
	end

	loadoutRE.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local primary = payload.primary
		local secondary = payload.secondary
		if not validateLoadout(player, primary, secondary) then
			return
		end
		playerLoadouts[player.UserId] = {
			primary = primary,
			secondary = secondary,
		}
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerLoadouts[player.UserId] = nil
	end)
end

return LoadoutServiceServer
