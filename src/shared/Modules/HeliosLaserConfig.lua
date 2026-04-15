--[[
	Helios Thread: after release, movement locks for CHARGE_DURATION then beam (server hit).
	Placeholder sounds / VFX ids — replace when assets are ready.
]]

return {
	-- Wind-up after commit (release): beam fires when this elapses (server + client lock duration).
	CHARGE_DURATION = 0.85,
	MAX_RANGE = 360,
	-- Spherecast radius (studs) — narrow pencil beam.
	BEAM_RADIUS = 1.05,
	-- Segment length per spherecast step (studs).
	CAST_STEP = 6,

	-- Cosmetic beam (client + replicated feel).
	BEAM_THICKNESS_STUDS = 2.1,
	BEAM_COLOR = Color3.fromRGB(120, 240, 255),
	BEAM_GLOW_TIME = 0.28,

	-- Empty string = no sound until you assign rbxassetid://...
	PLACEHOLDER_CHARGE_SOUND_ID = "",
	PLACEHOLDER_FIRE_SOUND_ID = "",
}
