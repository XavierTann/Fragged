--[[
	GachaGUI layout configuration.
	All positioning and sizing constants live here so you can
	tweak the UI without digging through GachaGUI.lua.

	Scale values are fractions of the parent element (0-1).
	Pixel values are used only for reel animation cells.
]]

local Config = {}

-- ─── Modal ───────────────────────────────────────────────
Config.Modal = {
	Width          = 0.8,
	Height         = 0.9,
	CornerRadius   = 16,
}

-- ─── General layout ──────────────────────────────────────
Config.Layout = {
	PadX           = 0.1,
	ContentW       = 0.8,
}

-- ─── Title ───────────────────────────────────────────────
Config.Title = {
	Width          = 0.9,
	Height         = 0.07,
	PosX           = 0.1,   -- usually = PadX
	PosY           = 0.1,
}

-- ─── Close button ────────────────────────────────────────
Config.CloseBtn = {
	Width          = 0.1,
	Height         = 0.1,
	PosX           = 0.97,
	PosY           = 0.05,
}

-- ─── Reel viewport (scale, fraction of modal) ────────────
Config.Reel = {
	Height         = 0.4,
	PosY           = 0.25,
	CornerRadius   = 12,
}

-- ─── Reel animation (pixel values) ──────────────────────
Config.ReelAnim = {
	CellSize       = 70,
	Gap            = 10,
	VisibleCells   = 10,
	SpinCells      = 60,
	SpinDuration   = 6.0,   -- seconds to decelerate into the overshoot position
	SettleDuration = 1.5,   -- seconds to ease back from overshoot to exact target
	SpinPower      = 3,     -- exponent for ease-out curve (higher = decelerates faster)
	-- Overshoot: fraction past targetX the reel travels before settling back (0 = no bounce)
	Overshoot      = 0.008,
	-- Seconds between the reel finishing its settle and the selector glow starting
	LandPause      = 0.2,
	-- Seconds between the selector glow starting and the result panel appearing
	ResultDelay    = 0.6,
}
Config.ReelAnim.CellStride   = Config.ReelAnim.CellSize + Config.ReelAnim.Gap
Config.ReelAnim.TotalCells   = Config.ReelAnim.SpinCells + Config.ReelAnim.VisibleCells

-- ─── Reel cell internals (fraction of cell) ──────────────
Config.ReelCell = {
	IconScale      = 0.81,
	NameTagH       = 0.219,
	NameTagY       = 1.03,
	CornerRadius   = 10,
}

-- ─── Selector highlight (fraction of reel viewport) ─────
Config.Selector = {
	Width          = 0.16,
	Height         = 1.05,
	CornerRadius   = 8,
}

-- ─── Gradient fades (fraction of reel viewport) ─────────
Config.GradientFade = {
	Width          = 0.167,
}

-- ─── Roll button ─────────────────────────────────────────
Config.RollBtn = {
	Width          = 0.4,
	Height         = 0.08,
	PosX           = 0.3,
	PosY           = 0.7,
	CornerRadius   = 10,
}

-- ─── Result panel (fills the full modal) ─────────────────
Config.Result = {
	Width          = 1,
	Height         = 1,
	PosX           = 0,
	PosY           = 0,
	CornerRadius   = 12,
}

-- ─── Result panel children (fraction of result panel) ───
Config.ResultIcon = {
	Width          = 0.45,
	Height         = 0.38,
	PosY           = 0.08,
}

Config.ResultRarity = {
	Width          = 0.8,
	Height         = 0.09,
	PosX           = 0.1,
	PosY           = 0.52,
}

Config.ResultName = {
	Width          = 0.8,
	Height         = 0.11,
	PosX           = 0.1,
	PosY           = 0.63,
}

Config.ResultRounds = {
	Width          = 0.8,
	Height         = 0.09,
	PosX           = 0.1,
	PosY           = 0.76,
}

Config.ObtainBtn = {
	Width          = 0.4,
	Height         = 0.07,
	PosX           = 0.3,
	PosY           = 0.88,
	CornerRadius   = 10,
}

-- ─── Derived (computed once) ─────────────────────────────
Config.ReelBottom    = Config.Reel.PosY + Config.Reel.Height
Config.ResultBtnPosY = Config.Result.PosY + Config.Result.Height + 0.02

return Config
