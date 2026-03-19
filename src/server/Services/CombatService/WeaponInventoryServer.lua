--[[
	WeaponInventoryServer
	Tracks which weapons each player has (default + picked up). Persists across rounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local DEFAULT_WEAPONS = { "Pistol", "Rifle", "Shotgun", "Grenade" }
local playerWeapons = {}
local weaponInventoryRE = nil

local function ensureRemote()
	if weaponInventoryRE then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if folder then
		weaponInventoryRE = folder:FindFirstChild(CombatConfig.REMOTES.WEAPON_INVENTORY)
	end
end

local function getWeapons(player)
	local list = playerWeapons[player.UserId]
	if not list then
		return DEFAULT_WEAPONS
	end
	return list
end

local function setWeapons(player, weapons)
	playerWeapons[player.UserId] = weapons
	ensureRemote()
	if weaponInventoryRE and player.Parent then
		weaponInventoryRE:FireClient(player, weapons)
	end
end

local function addWeapon(player, weaponId)
	local list = getWeapons(player)
	for _, w in ipairs(list) do
		if w == weaponId then
			return false
		end
	end
	local newList = {}
	for _, w in ipairs(list) do
		newList[#newList + 1] = w
	end
	newList[#newList + 1] = weaponId
	setWeapons(player, newList)
	return true
end

local function removeWeapon(player, weaponId)
	local list = getWeapons(player)
	local newList = {}
	for _, w in ipairs(list) do
		if w ~= weaponId then
			newList[#newList + 1] = w
		end
	end
	setWeapons(player, newList)
end

local function sendToPlayer(player)
	ensureRemote()
	if weaponInventoryRE and player.Parent then
		weaponInventoryRE:FireClient(player, getWeapons(player))
	end
end

return {
	addWeapon = addWeapon,
	removeWeapon = removeWeapon,
	getWeapons = getWeapons,
	setWeapons = setWeapons,
	sendToPlayer = sendToPlayer,
	DEFAULT_WEAPONS = DEFAULT_WEAPONS,
}
