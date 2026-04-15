--[[

	Helios Thread: charged laser — commit timing, beam sim, VFX, sounds, and imported tool mesh tuning.

]]



return {

	-- Wind-up after commit (release): beam fires when this elapses (server + client movement lock).

	CHARGE_DURATION = 1.05,



	MAX_RANGE = 360,

	-- Spherecast radius (studs) — narrow pencil beam.

	BEAM_RADIUS = 1.05,

	-- Segment length per spherecast step (studs).

	CAST_STEP = 6,

	-- Parallel samples across beam width; each column clips at its own wall.

	LASER_COLUMN_COUNT = 7,

	-- Fraction of (2 × BEAM_RADIUS) used when placing column centers (≤ 1).

	COLUMN_SPREAD_FRACTION = 0.92,



	-- Cosmetic beam (client + replicated feel).

	BEAM_THICKNESS_STUDS = 2.1,

	BEAM_COLOR = Color3.fromRGB(120, 240, 255),

	-- Beam VFX: hold at peak opacity, then tween parts + lights to invisible (see CombatServiceClient).

	BEAM_GLOW_TIME = 0.12,

	BEAM_FADE_OUT_TIME = 0.5,



	-- One-shot wind-up during laser charge. Client sets PlaybackSpeed from Sound.TimeLength

	-- so the clip lines up with CHARGE_DURATION (see CombatServiceClient).

	CHARGE_BUILDUP_SOUND_ID = "rbxassetid://6835752707",

	CHARGE_BUILDUP_PLAYBACK_SPEED_MIN = 0.25,

	CHARGE_BUILDUP_PLAYBACK_SPEED_MAX = 8,



	-- One-shot when the charged laser beam VFX plays (all clients at beam origin).

	LASER_BEAM_FIRE_SOUND_ID = "rbxassetid://130290471154787",

	LASER_BEAM_FIRE_SOUND_VOLUME = 0.78,



	-- Empty string = no sound until you assign rbxassetid://...

	PLACEHOLDER_CHARGE_SOUND_ID = "",

	PLACEHOLDER_FIRE_SOUND_ID = "",



	-- Imported Helios Thread tool: grip, muzzle charge orb, optional hold animation.

	CHARGE_BALL_START_DIAMETER = 0.32,

	CHARGE_BALL_END_DIAMETER = 1.65,

	BALL_COLOR = Color3.fromRGB(255, 140, 70),

	MUZZLE_ATTACHMENT_NAMES = { "Muzzle", "BarrelTip", "Tip", "Fire", "MuzzleAttachment" },

	GRIP_POS = Vector3.new(0, 0, -0.25),

	GRIP_FORWARD = Vector3.new(0, 0, -1),

	GRIP_RIGHT = Vector3.new(1, 0, 0),

	GRIP_UP = Vector3.new(0, 1, 0),

	HOLD_ANIMATION_ID = "",

}


