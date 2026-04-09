--[[
	Shop offerings: shop id matches GunsConfig key for purchased weapons.
]]

local Theme = require(script.Parent.Parent.UI.Shop.ShopTheme)

export type CatalogEntry = {
	id: string,
	name: string,
	price: number,
	tag: string?,
	accent: Color3,
	imageAssetId: number?,
}

local ITEMS: { CatalogEntry } = {
	{
		id = "PlasmaCarbine",
		name = "Plasma Carbine",
		price = 1200,
		tag = "RIFLE",
		accent = Theme.NeonMagenta,
		imageAssetId = 85001511160443,
	},
	{
		id = "HeliosThread",
		name = "Helios Thread",
		price = 980,
		tag = "BEAM",
		accent = Theme.NeonCyan,
		imageAssetId = 14826766010,
	},
	{
		id = "PrismRipper",
		name = "Prism Ripper",
		price = 750,
		tag = "RICO",
		accent = Theme.NeonLime,
		imageAssetId = 117104799815404,
	},
}

local shopGunSet: { [string]: boolean } = {}
for _, it in ipairs(ITEMS) do
	shopGunSet[it.id] = true
end

local ShopCatalog = {}

function ShopCatalog.getItems(): { CatalogEntry }
	return ITEMS
end

function ShopCatalog.getEntry(shopId: string): CatalogEntry?
	for _, it in ipairs(ITEMS) do
		if it.id == shopId then
			return it
		end
	end
	return nil
end

function ShopCatalog.isShopGun(gunId: string): boolean
	return shopGunSet[gunId] == true
end

return ShopCatalog
