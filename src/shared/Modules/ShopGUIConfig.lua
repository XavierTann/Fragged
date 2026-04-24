--[[
	ShopGUI (ShopApp) layout configuration.
	All positioning and sizing constants live here so you can
	tweak the UI without digging through ShopApp.lua.

	Scale values are fractions of the parent element (0-1).
]]

local Config = {}

-- ─── Modal panel ─────────────────────────────────────────
Config.Modal = {
	Width          = 0.7,
	Height         = 0.95,
	CornerRadius   = 14,
	StrokeThickness = 2,
}

-- ─── Header bar (fraction of modal) ─────────────────────
Config.Header = {
	Height         = 0.09,
	PosY           = 0.03,
}

-- ─── Close button (fraction of modal) ───────────────────
Config.CloseBtn = {
	Width          = 0.065,
	Height         = 0.052,
	PosX           = 0.94,
	StrokeThickness = 1,
}

-- ─── Credit pill (fraction of header) ───────────────────
Config.CreditPill = {
	Width          = 0.12,
	Height         = 0.6,
	PadX           = 0.05,
	PadY           = 0.15,
	CornerRadius   = 8,
	GapToTitle     = 0.02,
	PosX           = 0.03,
}

-- ─── Body / scroll area (fraction of modal) ─────────────
Config.Body = {
	Width          = 0.954,
	Height         = 0.92,
	PosX           = 0.023,
	PosY           = 0.15,
	CornerRadius   = 10,
	ScrollBarThickness = 8,
	InnerPadX      = 0.012,
	InnerPadY      = 0.009,
}

-- ─── List layout (fraction of scroll area) ──────────────
Config.List = {
	Spacing        = 0.02,
	PadTop         = 0.03,
	PadBottom      = 0.03,
	PadX           = 0.015,
}

-- ─── Item card (fraction of card parent) ────────────────
Config.Card = {
	Width          = 0.977,
	HeightNormal   = 0.3,
	HeightWithNote = 0.3,
	CornerRadius   = 10,
	StrokeThickness = 1.5,
	PadTop         = 0.085,
	PadBottom      = 0.085,
	PadLeft        = 0.028,
	PadRight       = 0.028,
}

-- ─── Card: weapon icon (fraction of card) ───────────────
Config.CardIcon = {
	Width          = 0.5,
	Height         = 0.95,
	PosX           = 0.025,
	PosY           = 0.04,
	CornerRadius   = 8,
}

-- ─── Card: weapon name (fraction of card) ───────────────
Config.CardName = {
	PosX           = 0.2,
	PosY           = 0.085,
	Height         = 0.3,
	RightInset     = 0.2,
}

-- ─── Card: tag badge (fraction of card) ─────────────────
Config.CardTag = {
	Width          = 0.13,
	Height         = 0.17,
	PosXFromRight  = 0.15,
	PosY           = 0,
	CornerRadius   = 6,
}

-- ─── Card: price label (fraction of card) ───────────────
Config.CardPrice = {
	PosX           = 0.2,
	PosY           = 0.43,
	Height         = 0.2,
	RightInset     = 0.2,
}

-- ─── Card: status note (fraction of card) ───────────────
Config.CardStatus = {
	PosX           = 0.2,
	PosY           = 0.48,
	Height         = 0.14,
	RightInset     = 0.2,
}

-- ─── Card: buy button (fraction of card) ────────────────
Config.CardBuyBtn = {
	Width          = 0.18,
	Height         = 0.29,
	CornerRadius   = 8,
	TextPadX       = 0.15,
	TextPadY       = 0.1,
}

return Config
