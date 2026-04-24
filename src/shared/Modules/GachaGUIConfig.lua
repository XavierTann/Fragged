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
	Height         = 0.3,
	PosY           = 0.25,
	CornerRadius   = 12,
}

-- ─── Reel animation (pixel values) ──────────────────────
Config.ReelAnim = {
	CellSize       = 60,
	Gap            = 10,
	VisibleCells   = 10,
	SpinCells      = 60,
	SpinDuration   = 6.0,
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
	PosY           = 0.6,
	CornerRadius   = 10,
}

-- ─── Result panel ────────────────────────────────────────
Config.Result = {
	Height         = 0.5,
	PosY           = 0.2,
	CornerRadius   = 12,
}

-- ─── Result panel children (fraction of result panel) ───
Config.ResultIcon = {
	Width          = 0.147,
	Height         = 0.293,
	PosY           = 0.04,
}

Config.ResultRarity = {
	Width          = 0.947,
	Height         = 0.10,
	PosX           = 0.027,
	PosY           = 0.36,
}

Config.ResultName = {
	Width          = 0.947,
	Height         = 0.12,
	PosX           = 0.027,
	PosY           = 0.493,
}

Config.ResultRounds = {
	Width          = 0.947,
	Height         = 0.11,
	PosX           = 0.027,
	PosY           = 0.68,
}

-- ─── Derived (computed once) ─────────────────────────────
Config.ReelBottom    = Config.Reel.PosY + Config.Reel.Height
Config.ResultBtnPosY = Config.Result.PosY + Config.Result.Height + 0.02

return Config
