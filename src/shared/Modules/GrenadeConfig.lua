--[[
	Grenade configuration for throwable explosive.
]]

return {
	name = "Grenade",
	fuseTime = 2.5, -- seconds before explosion
	throwSpeed = 70, -- initial velocity magnitude
	throwArcUp = 0.7, -- upward component for arc (0 = flat, 1 = mostly up)
	damage = 60, -- damage at center
	radius = 12, -- explosion radius in studs
	cooldown = 4, -- seconds between throws per player
	-- Visual
	size = Vector3.new(0.5, 0.5, 0.5),
	color = Color3.fromRGB(60, 100, 50),
	material = Enum.Material.Neon,
	-- Physics: bounciness (Restitution)
	restitution = 0.6,
}
