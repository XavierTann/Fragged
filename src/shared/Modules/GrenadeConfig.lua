--[[
	Grenade configuration for throwable explosive.
	Consumable ammo with independent per-slot regeneration.
]]

return {
	name = "Grenade",
	fuseTime = 2, -- seconds before explosion
	throwSpeed = 70, -- initial velocity magnitude
	throwArcUp = 0.4, -- upward component for arc (0 = flat, 1 = mostly up)
	damage = 60, -- damage at center
	radius = 12, -- explosion radius in studs
	maxCapacity = 3, -- grenades per player
	regenerationTime = 5, -- seconds per grenade to regenerate (each slot regens independently)
	throwSoundId = "rbxassetid://140246981967568",
	explosionSoundId = "rbxassetid://139210252225248",
	-- Visual
	size = Vector3.new(0.7, 0.7, 0.7),
	color = Color3.fromRGB(60, 100, 50),
	material = Enum.Material.Neon,
	-- Physics: bounciness (Restitution)
	restitution = 0.6,
	-- Contact-only angular drag (AssemblyAngularVelocity * exp(-k*dt) per Heartbeat); see GrenadeAngularResistance
	angularDragPerSecond = 4,
	contactPaddingStuds = 0.18,
}
