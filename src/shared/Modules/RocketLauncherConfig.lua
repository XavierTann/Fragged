--[[
	RocketLauncherConfig
	Rocket projectile: similar to grenade but different tuning.
	Fires on joystick release only.
]]

return {
	name = "RocketLauncher",
	fuseTime = 3,
	speed = 55,
	damage = 80,
	radius = 10,
	maxRockets = 3,
	regenTime = 6,
	size = Vector3.new(0.25, 0.25, 0.7),
	-- Scale applied to template model (1 = full size). Fallback Part uses size above.
	scale = 0.6,
	color = Color3.fromRGB(180, 100, 40),
	material = Enum.Material.Neon,
	restitution = 0.3,
	-- Client aim rectangle: max straight-line travel (studs) if nothing is hit; matches Heartbeat mover
	aimMaxRangeStuds = nil, -- nil => speed * fuseTime
	-- Cross-range width (studs) for client aim rectangle
	aimIndicatorWidthStuds = 0.6,
	throwSoundId = "rbxassetid://140444375264585",
	explosionSoundId = "rbxassetid://134825578212679",
}
