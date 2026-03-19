--[[
	CombatAmmo
	Ammo state and reload logic. Also grenade count and regeneration.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)

local CombatRemotes = require(script.Parent.CombatRemotes)

local function initPlayerAmmo(state, userId)
	state.ammoInMagazine[userId] = {}
	state.reloadEndAt[userId] = {}
	for gunId, gun in pairs(GunsConfig) do
		local mag = gun.magazineSize or 6
		state.ammoInMagazine[userId][gunId] = mag
		state.reloadEndAt[userId][gunId] = nil
	end
end

local function initPlayerGrenades(state, userId)
	state.grenadeCount[userId] = GrenadeConfig.maxCapacity or 3
	state.grenadeRegenTimes[userId] = {}
end

local function initPlayerRockets(state, userId)
	state.rocketCount[userId] = RocketLauncherConfig.maxRockets or 3
	state.rocketRegenTimes[userId] = {}
end

local function processGrenadeRegen(state)
	local now = os.clock()
	local maxCap = GrenadeConfig.maxCapacity or 3
	for userId, regenTimes in pairs(state.grenadeRegenTimes) do
		while #regenTimes > 0 and regenTimes[1] <= now do
			table.remove(regenTimes, 1)
			local count = state.grenadeCount[userId] or 0
			if count < maxCap then
				state.grenadeCount[userId] = count + 1
				local player = Players:GetPlayerByUserId(userId)
				if player then
					CombatRemotes.sendGrenadeState(state, player, state.grenadeCount[userId])
				end
			end
		end
	end
end

local function processRocketRegen(state)
	local now = os.clock()
	local maxCap = RocketLauncherConfig.maxRockets or 3
	for userId, regenTimes in pairs(state.rocketRegenTimes) do
		while #regenTimes > 0 and regenTimes[1] <= now do
			table.remove(regenTimes, 1)
			local count = state.rocketCount[userId] or 0
			if count < maxCap then
				state.rocketCount[userId] = count + 1
				local player = Players:GetPlayerByUserId(userId)
				if player then
					CombatRemotes.sendRocketState(state, player, state.rocketCount[userId])
				end
			end
		end
	end
end

local function processReloads(state)
	processGrenadeRegen(state)
	processRocketRegen(state)
	local now = os.clock()
	for userId, gunReloads in pairs(state.reloadEndAt) do
		for gunId, endTime in pairs(gunReloads) do
			if endTime and now >= endTime then
				local gun = GunsConfig[gunId]
				if gun then
					state.ammoInMagazine[userId][gunId] = gun.magazineSize or 6
					state.reloadEndAt[userId][gunId] = nil
					local player = Players:GetPlayerByUserId(userId)
					if player then
						CombatRemotes.sendAmmoState(state, player, gunId, state.ammoInMagazine[userId][gunId], false)
					end
				end
			end
		end
	end
end

local function startReloadLoop(state)
	RunService.Heartbeat:Connect(function()
		processReloads(state)
	end)
end

return {
	initPlayerAmmo = initPlayerAmmo,
	initPlayerGrenades = initPlayerGrenades,
	initPlayerRockets = initPlayerRockets,
	processReloads = processReloads,
	startReloadLoop = startReloadLoop,
}
