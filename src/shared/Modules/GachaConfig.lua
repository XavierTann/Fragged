--[[
	Gacha roll configuration: rarity tiers, weighted pool, first-roll guarantee.
	DEVELOPER_PRODUCT_ID must be set after creating the product in Creator Dashboard.
]]

return {
	DEVELOPER_PRODUCT_ID = 0,
	ROLL_ROBUX_PRICE = 75,

	FIRST_ROLL = {
		weaponId = "PlasmaCarbine",
		rounds = 5,
		isFree = true,
	},

	RARITIES = {
		{ name = "Common",    weight = 60, color = Color3.fromRGB(180, 180, 180) },
		{ name = "Rare",      weight = 25, color = Color3.fromRGB(80, 160, 255)  },
		{ name = "Epic",      weight = 12, color = Color3.fromRGB(180, 80, 255)  },
		{ name = "Legendary", weight = 3,  color = Color3.fromRGB(255, 200, 40)  },
	},

	POOL = {
		{ weaponId = "PlasmaCarbine", rarity = "Common",  permanent = false, rounds = 3  },
		{ weaponId = "PrismRipper",   rarity = "Common",  permanent = false, rounds = 3  },
		{ weaponId = "HeliosThread",  rarity = "Common",  permanent = false, rounds = 3  },
		{ weaponId = "PlasmaCarbine", rarity = "Rare",    permanent = false, rounds = 10 },
		{ weaponId = "PrismRipper",   rarity = "Rare",    permanent = false, rounds = 10 },
		{ weaponId = "HeliosThread",  rarity = "Rare",    permanent = false, rounds = 10 },
		{ weaponId = "PlasmaCarbine", rarity = "Epic",    permanent = true  },
		{ weaponId = "PrismRipper",   rarity = "Epic",    permanent = true  },
		{ weaponId = "HeliosThread",  rarity = "Epic",    permanent = true  },
	},

	DUPE_PERM_CONSOLATION_ROUNDS = 15,
}
