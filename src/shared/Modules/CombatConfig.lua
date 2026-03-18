--[[
	Combat configuration: health, remotes, etc.
]]

return {
	DEFAULT_HEALTH = 100,
	REMOTE_FOLDER_NAME = "CombatRemotes",
	REMOTES = {
		FIRE_GUN = "FireGun",
		AMMO_STATE = "AmmoState", -- Server -> Client: ammo count, isReloading, gunId
		THROW_GRENADE = "ThrowGrenade",
	},
}
