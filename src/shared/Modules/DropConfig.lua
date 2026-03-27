--[[
	DropConfig
	Random drop system: spawn rate, max drops, drop types.
	FactoryFloor: name of Workspace part defining spawn bounds. Tag part "DropSpawnArea" as alternative.
]]

return {
	-- Part name in Workspace for spawn bounds (or use DROP_SPAWN_TAG)
	FACTORY_FLOOR_NAME = "FactoryFloor",
	-- Alternative: tag a part with this to use as spawn area
	DROP_SPAWN_TAG = "DropSpawnArea",

	-- Spawn interval in seconds
	SPAWN_INTERVAL_SECONDS = 10,
	-- Max active instances per drop type (e.g. 5 health + 5 rockets = up to 10 total)
	MAX_ACTIVE_PER_TYPE = 5,
	-- Optional per-type override: maxActive = 3
	-- Minimum spacing between drops (studs) to avoid overlap
	MIN_DROP_SPACING = 4,
	-- Raise all drops this many studs above the raycast hit (avoids clipping into floor mesh)
	SPAWN_GROUND_EXTRA_HEIGHT = 1.5,

	-- Drop types with weight for rarity among types that are under their cap (higher = more common)
	DROPS = {
		RocketLauncher = {
			weight = 1,
			-- After X=90° placement, snap AABB bottom to placeY + this (studs); fixes pivot vs mesh sitting in floor
			groundClearanceStuds = 1.25,
			visualSize = Vector3.new(3, 1, 1),
			visualColor = Color3.fromRGB(80, 60, 40),
		},
		-- ReplicatedStorage.Imports.3DModels.HealthPack (Model). Part fields = fallback if asset missing.
		HealthPack = {
			weight = 1,
			modelAssetName = "HealthPack",
			-- World rotation at pivot before ground snap. (-90,0,0) lays a Y-upright mesh flat on XZ.
			placementRotationDegrees = Vector3.new(-90, 0, 0),
			groundClearanceStuds = 0.25,
			visualSize = Vector3.new(1.5, 0.55, 1.1),
			visualColor = Color3.fromRGB(45, 255, 130),
			material = Enum.Material.Neon,
			anchored = true,
		},
	},
}
