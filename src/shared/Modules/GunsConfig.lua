--[[
	Gun definitions for the shooting system.
	Extend with more guns later (e.g. Rifle, Shotgun).
]]

return {
	Pistol = {
		name = "Pistol",
		bulletSpeed = 200,
		damage = 25,
		fireRate = 0.4, -- seconds between shots
		bulletSize = Vector3.new(0.25, 0.25, 0.8),
		bulletColor = Color3.fromRGB(220, 180, 80),
	},
}
