--[[
	CombatAmmo
	Ammo state and reload logic.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)

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

local function processReloads(state)
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
	processReloads = processReloads,
	startReloadLoop = startReloadLoop,
}
