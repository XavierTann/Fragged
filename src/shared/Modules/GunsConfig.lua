--[[
	Gun definitions for the shooting system.
]]

return {
	Pistol = {
		name = "Pistol",
		bulletSpeed = 200,
		damage = 25,
		fireRate = 0.4, -- slow, deliberate shots
		bulletSize = Vector3.new(0.25, 0.25, 0.8),
		bulletColor = Color3.fromRGB(220, 180, 80),
	},
	Rifle = {
		name = "Rifle",
		bulletSpeed = 250,
		damage = 18,
		fireRate = 0.12, -- fast shooting
		bulletSize = Vector3.new(0.2, 0.2, 0.6),
		bulletColor = Color3.fromRGB(180, 200, 220),
	},
	Shotgun = {
		name = "Shotgun",
		bulletSpeed = 120, -- slower, close range
		damage = 12, -- per pellet
		fireRate = 0.8, -- slow between bursts
		bulletSize = Vector3.new(0.35, 0.35, 0.5),
		bulletColor = Color3.fromRGB(200, 150, 100),
		pelletCount = 8,
		spreadDegrees = 12,
	},
}
