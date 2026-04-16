--[[
	DropConfig
	Spawn rate, caps, drop types. World Y comes from FIXED_DROP_WORLD_Y or per-type fixedWorldY (no raycasts).
	Primary X/Z: arena SpawnLocations.ItemSpawnLocations (see TDMConfig). Fallback: DropSpawnArea tag or FactoryFloor part.
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

	-- Default world Y when a drop type has no fixedWorldY.
	FIXED_DROP_WORLD_Y = 2.183,

	-- Neon-style pickup outline (Highlight). Set false to disable.
	DROP_PICKUP_HIGHLIGHT = true,
	-- Fallback when a drop type has no highlightOutlineColor.
	DROP_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 250, 90),
	-- 1 = outline only; lower (e.g. 0.9) adds a faint fill for extra pop.
	DROP_HIGHLIGHT_FILL_TRANSPARENCY = 1,
	DROP_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 240, 100),

	-- Drop types with weight for rarity among types that are under their cap (higher = more common)
	DROPS = {
		RocketLauncher = {
			weight = 1,
			-- Overrides global FIXED_DROP_WORLD_Y for this drop type only.
			fixedWorldY = 2.1,
			visualSize = Vector3.new(3, 1, 1),
			visualColor = Color3.fromRGB(80, 60, 40),
			highlightOutlineColor = Color3.fromRGB(255, 65, 70),
		},
		-- ReplicatedStorage.Imports.3DModels.HealthPack (Model). Part fields = fallback if asset missing.
		HealthPack = {
			weight = 1,
			modelAssetName = "HealthPack",
			fixedWorldY = 1.9,
			-- World rotation at pivot before ground snap. (-90,0,0) lays a Y-upright mesh flat on XZ.
			placementRotationDegrees = Vector3.new(-90, 0, 0),
			visualSize = Vector3.new(1.5, 0.55, 1.1),
			visualColor = Color3.fromRGB(45, 255, 130),
			material = Enum.Material.Neon,
			anchored = true,
			highlightOutlineColor = Color3.fromRGB(55, 255, 140),
			-- Server: one-shot on HRP when the pack is consumed (not when already full health).
			dropPickupSoundId = "rbxassetid://140272163846580",
		},
	},
}
