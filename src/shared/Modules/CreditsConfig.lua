--[[
	Credits / match rewards tuning. Winners get WIN_CREDITS; everyone on the losing team gets LOSS_CREDITS.
]]

return {
	WIN_CREDITS = 165,
	LOSS_CREDITS = 45,
	DATASTORE_NAME = "TanxyxPlayerEconomy_v1",

	-- TESTING: every player gets this balance on join (overwrites saved credits). Set false before shipping.
	GRANT_TEST_CREDITS = true,
	TEST_CREDITS_BALANCE = 2000,

	-- TESTING: grant Helios Thread ownership (no credit cost) and set it as secondary loadout on join. Set true for local playtest; false before shipping.
	AUTO_OWN_HELIOS_AND_EQUIP_SECONDARY = true,

	-- TESTING: grant ownership of all shop weapons and all skins on join. Set false before shipping.
	GRANT_ALL_WEAPONS = true,
	GRANT_ALL_SKINS = true,
}
