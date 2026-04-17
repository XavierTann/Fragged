--[[
	Gun definitions for the shooting system.
	 magazineSize: bullets per magazine (1 shot = 1 ammo, shotgun = 1 trigger pull)
	 reloadTime: seconds to reload when magazine empty
]]

local GunsConfig = {
	Rifle = {
		name = "Rifle",
		bulletSpeed = 1000,
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
	PlasmaCarbine = {
		name = "Plasma Carbine",
		bulletSpeed = 1000,
		damage = 24,
		fireRate = 0.1,
		-- Longer bolt (Z = forward along tracer)
		bulletSize = Vector3.new(0.4, 0.4, 1.75),
		bulletColor = Color3.fromRGB(255, 255, 255),
		magazineSize = 28,
		reloadTime = 2.2,
		gunshotSoundId = "rbxassetid://127207975351230",
		-- Asset is longer than a single tap; trim playback so one shot matches one burst
		gunshotMaxDurationSeconds = 0.28,
		reloadSoundId = "rbxassetid://140301163976554",
	},
	HeliosThread = {
		name = "Helios Thread",
		bulletSpeed = 300,
		fireRate = 0.08,
		bulletSize = Vector3.new(0.32, 0.32, 1.0),
		bulletColor = Color3.fromRGB(120, 240, 255),
		magazineSize = 6,
		reloadTime = 2.4,
		gunshotSoundId = "rbxassetid://139083804782836",
		reloadSoundId = "rbxassetid://140301163976554",
	},
	PrismRipper = {
		name = "Prism Ripper",
		bulletSpeed = 240,
		damage = 15,
		fireRate = 0.16,
		bulletSize = Vector3.new(0.4, 0.4, 1.1),
		bulletColor = Color3.fromRGB(0, 255, 60),
		magazineSize = 15,
		reloadTime = 1.9,
		maxRicochets = 1,
		-- Sound asset TBD — swap this ID once the final firing sound is provided.
		gunshotSoundId = "rbxassetid://139083804782836",
		reloadSoundId = "rbxassetid://140301163976554",
	},
}

-- Helios laser hit uses this value (4× default primary); keep in sync if Rifle damage changes.
GunsConfig.HeliosThread.damage = GunsConfig.Rifle.damage * 4

return GunsConfig
