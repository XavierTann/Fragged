--[[
	Gacha roll configuration: rarity tiers, weighted skin pool, first-roll guarantee.
	DEVELOPER_PRODUCT_ID must be set after creating the product in Creator Dashboard.
]]

return {
	DEV_FREE_ROLLS = true, -- set false for production
	DEVELOPER_PRODUCT_ID = 0,
	ROLL_ROBUX_PRICE = 75,

	FIRST_ROLL = {
		skinId = "HeliosThreadSkin",
		isFree = true,
	},

	DUPE_CONSOLATION_CREDITS = 300,

	RARITIES = {
		{ name = "Common",    weight = 60, color = Color3.fromRGB(180, 180, 180) },
		{ name = "Rare",      weight = 25, color = Color3.fromRGB(80, 160, 255)  },
		{ name = "Epic",      weight = 12, color = Color3.fromRGB(180, 80, 255)  },
		{ name = "Legendary", weight = 3,  color = Color3.fromRGB(255, 200, 40)  },
	},

	POOL = {
		{ skinId = "HeliosThreadSkin", rarity = "Rare" },
		{ skinId = "PrismRipperSkin", rarity = "Rare" },
		{ skinId = "PlasmaCarbineSkin", rarity = "Rare" },
	},
}
