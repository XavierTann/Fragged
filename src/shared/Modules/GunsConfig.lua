--[[
	Gun definitions for the shooting system.
	 magazineSize: bullets per magazine (1 shot = 1 ammo, shotgun = 1 trigger pull)
	 reloadTime: seconds to reload when magazine empty
]]

return {
	Pistol = {
		name = "Pistol",
		bulletSpeed = 200,
		damage = 40,
		fireRate = 0.4, -- slow, deliberate shots
		bulletSize = Vector3.new(0.4, 0.4, 1.2),
		bulletColor = Color3.fromRGB(255, 220, 100),
		magazineSize = 8,
		reloadTime = 1.2,
		gunshotSoundId = "rbxassetid://138905044369113",
		reloadSoundId = "rbxassetid://140301163976554",
	},
	Rifle = {
		name = "Rifle",
		bulletSpeed = 250,
		damage = 18,
		fireRate = 0.12, -- fast shooting
		bulletSize = Vector3.new(0.35, 0.35, 1.0),
		bulletColor = Color3.fromRGB(120, 200, 255),
		magazineSize = 24,
		reloadTime = 2.0,
		gunshotSoundId = "rbxassetid://139083804782836",
		reloadSoundId = "rbxassetid://140301163976554",
	},
	Shotgun = {
		name = "Shotgun",
		bulletSpeed = 120, -- slower, close range
		damage = 12, -- per pellet
		fireRate = 0.5, -- slow between bursts
		bulletSize = Vector3.new(0.5, 0.5, 0.9),
		bulletColor = Color3.fromRGB(255, 180, 80),
		pelletCount = 8,
		spreadDegrees = 12,
		-- Client direction indicator: sector radius on XZ (studs)
		aimPreviewRangeStuds = 28,
		magazineSize = 6,
		reloadTime = 2.5,
		gunshotSoundId = "rbxassetid://123510386263285",
		reloadSoundId = "rbxassetid://140301163976554",
	},
}
