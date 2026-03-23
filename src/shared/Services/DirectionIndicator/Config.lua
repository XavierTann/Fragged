--[[
	Shared tuning for direction indicator (move dot + weapon aim overlays).
]]

return {
	OFFSET_RADIUS = 3.25,
	AIM_LINE_LENGTH = 8.5,
	Y_ABOVE_ROOT = 0.2,
	AIM_Y_ABOVE_ROOT = 0.34,
	DOT_DIAMETER = 0.38,
	AIM_BEAM_WIDTH = 0.28,
	ROCKET_RECT_THICKNESS = 0.14,
	MIN_INPUT_MAGNITUDE = 0.04,
	AIM_MIN_CURSOR_GROUND_DIST = 1.15,
	SMOOTH_RATE = 14,
	AIM_SMOOTH_RATE = 16,
	-- Shotgun sector (beams on XZ): point count along arc including both edges
	SHOTGUN_ARC_POINTS = 22,
	SHOTGUN_OUTLINE_BEAM_WIDTH = 0.075,
	SHOTGUN_FILL_BEAM_WIDTH = 0.42,
	SHOTGUN_FILL_TRANSPARENCY = 0.86,
	SHOTGUN_OUTLINE_TRANSPARENCY = 0.06,
}
