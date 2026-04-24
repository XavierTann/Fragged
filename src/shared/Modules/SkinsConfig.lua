--[[
	SkinsConfig
	Central registry of weapon skins. Each skinId maps to a weapon, display info,
	tool template name, and optional VFX overrides (e.g. beamColor for Helios).
]]

local SKINS = {
	HeliosThreadSkin = {
		weaponId = "HeliosThread",
		name = "Helios Thread - Void",
		iconAssetId = 92467241832850,
		iconDecalName = "HeliosThreadSkinIcon",
		toolTemplateName = "HeliosThreadSkin Tool",
		beamColor = Color3.fromRGB(160, 60, 255),
		rarity = "Rare",
	},
	PrismRipperSkin = {
		weaponId = "PrismRipper",
		name = "Prism Ripper - Frostbite",
		iconAssetId = 88732502416860,
		iconDecalName = "PrismRipperSkinIcon",
		toolTemplateName = "PrismRipperSkin Tool",
		bulletColor = Color3.fromRGB(0, 170, 255),
		rarity = "Rare",
	},
	PlasmaCarbineSkin = {
		weaponId = "PlasmaCarbine",
		name = "Plasma Carbine - Frostbite",
		iconDecalName = "PlasmaCarbineSkinIcon",
		toolTemplateName = "PlasmaCarbineSkin Tool",
		rarity = "Rare",
	},
}

local weaponToSkins: { [string]: { string } } = {}
for skinId, def in pairs(SKINS) do
	local wid = def.weaponId
	if not weaponToSkins[wid] then
		weaponToSkins[wid] = {}
	end
	table.insert(weaponToSkins[wid], skinId)
end
for _, list in pairs(weaponToSkins) do
	table.sort(list)
end

local SkinsConfig = {}

function SkinsConfig.getSkin(skinId: string)
	return SKINS[skinId]
end

function SkinsConfig.isValidSkin(skinId: string): boolean
	return SKINS[skinId] ~= nil
end

function SkinsConfig.getSkinsForWeapon(weaponId: string): { string }
	return weaponToSkins[weaponId] or {}
end

function SkinsConfig.getAllSkinIds(): { string }
	local ids = {}
	for skinId in pairs(SKINS) do
		table.insert(ids, skinId)
	end
	table.sort(ids)
	return ids
end

return SkinsConfig
