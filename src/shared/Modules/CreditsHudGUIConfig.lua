--[[
	CreditsHudGUI layout configuration.
	All positioning and sizing constants live here so you can
	tweak the UI without digging through CreditsHudGUI.lua.

	Scale values are fractions of the screen (0-1).
]]

local Config = {}

Config.Pill = {
	Width          = 0.2,
	Height         = 0.09,
	PosX           = 0.99,
	PosY           = -0.1,
	CornerRadius   = 10,
	BgTransparency = 0.25,
	PadX           = 0.12,
	PadY           = 0.1,
}

Config.Icon = {
	Width          = 0.22,
}

Config.Label = {
	PosX           = 0.22,
}

return Config
