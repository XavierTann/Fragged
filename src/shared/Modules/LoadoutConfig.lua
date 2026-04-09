--[[
	LoadoutConfig
	Weapon categories (Primary = hold-to-fire, Secondary = release-to-fire),
	display metadata, default loadout, and helper queries.
]]

local CATEGORY = {
	PRIMARY = "Primary",
	SECONDARY = "Secondary",
}

local WEAPONS = {
	Rifle = {
		category = CATEGORY.PRIMARY,
		name = "Rifle",
		desc = "Full-auto kinetic rifle. High rate of fire, reliable at all ranges.",
		icon = 168510758,
	},
	PlasmaCarbine = {
		category = CATEGORY.PRIMARY,
		name = "Plasma Carbine",
		desc = "Superheated plasma rounds with blistering fire rate and tight spread.",
		icon = 85001511160443,
	},
	PrismRipper = {
		category = CATEGORY.PRIMARY,
		name = "Prism Ripper",
		desc = "Refracted energy bolts that hit hard. Slower cycle, bigger punch.",
		icon = 117104799815404,
	},
	HeliosThread = {
		category = CATEGORY.SECONDARY,
		name = "Helios Thread",
		desc = "Solar micro-filament burst. Fires on release for precise timing.",
		icon = 14826766010,
	},
	Shotgun = {
		category = CATEGORY.SECONDARY,
		name = "Shotgun",
		desc = "Wide pellet spread, devastating at close range. Fires on release.",
		icon = 4753989987,
	},
}

local DEFAULT = {
	primary = "Rifle",
	secondary = "Shotgun",
}

local LoadoutConfig = {}
LoadoutConfig.CATEGORY = CATEGORY
LoadoutConfig.WEAPONS = WEAPONS
LoadoutConfig.DEFAULT = DEFAULT

function LoadoutConfig:isPrimaryWeapon(id)
	local w = WEAPONS[id]
	return w ~= nil and w.category == CATEGORY.PRIMARY
end

function LoadoutConfig:isSecondaryWeapon(id)
	local w = WEAPONS[id]
	return w ~= nil and w.category == CATEGORY.SECONDARY
end

function LoadoutConfig:getByCategory(cat)
	local result = {}
	for id, w in pairs(WEAPONS) do
		if w.category == cat then
			result[#result + 1] = { id = id, data = w }
		end
	end
	table.sort(result, function(a, b)
		return a.data.name < b.data.name
	end)
	return result
end

return LoadoutConfig
