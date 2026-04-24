--[[
	LoadoutGUI layout configuration.
	All positioning and sizing constants live here so you can
	tweak the UI without digging through LoadoutGUI.lua.

	Scale values are fractions of the parent element (0-1).
]]

local Config = {}

-- ─── General ─────────────────────────────────────────────
Config.CornerRadius = 14

-- ─── Modal ───────────────────────────────────────────────
Config.Modal = {
	Width          = 0.6,
	Height         = 0.9,
}

-- ─── Layout grid ─────────────────────────────────────────
Config.Layout = {
	PadX           = 0.033,
	HeaderH        = 0.105,
	LeftColW       = 0.2,
	RowLabelH      = 0.043,
	RowGap         = 0.024,
	IconRowH       = 0.133,
	EquippedBarH   = 0.21,
}

-- ─── Title ───────────────────────────────────────────────
Config.Title = {
	Width          = 0.83,
	Height         = 0.076,
	PosX           = 0.033,   -- = PadX
	PosY           = 0.019,
}

-- ─── Close button ────────────────────────────────────────
Config.CloseBtn = {
	Width          = 0.065,
	Height         = 0.08,
	PosX           = 0.98,
	PosY           = 0.024,
}

-- ─── Primary row offsets (added to cursorY) ──────────────
Config.PrimaryRow = {
	FrameOffsetY   = 0.03,
	ListPadding    = 0.03,
}

-- ─── Secondary row offsets ───────────────────────────────
Config.SecondaryRow = {
	LabelOffsetY   = 0.03,
	FrameOffsetY   = 0.07,
	ListPadding    = 0.03,
}

-- ─── Detail panel ────────────────────────────────────────
Config.DetailPanel = {
	Width          = 0.43,
	PosX           = 0.45,
	BottomPad      = 0.038,
	CornerRadius   = 10,
}

-- ─── Detail: weapon icon ─────────────────────────────────
Config.DetailIcon = {
	Width          = 0.42,
	Height         = 0.2,
	PosY           = 0.033,
}

-- ─── Detail: weapon name ─────────────────────────────────
Config.DetailName = {
	Width          = 0.906,
	Height         = 0.05,
	PosX           = 0.047,
	PosY           = 0.25,
}

-- ─── Detail: weapon description ──────────────────────────
Config.DetailDesc = {
	Width          = 0.906,
	Height         = 0.167,
	PosX           = 0.047,
	PosY           = 0.35,
}

-- ─── Detail: lock label ──────────────────────────────────
Config.DetailLock = {
	Width          = 0.906,
	Height         = 0.05,
	PosX           = 0.047,
	PosY           = 0.528,
}

-- ─── Detail: equip button ────────────────────────────────
Config.DetailEquipBtn = {
	Width          = 0.859,
	Height         = 0.06,
	PosX           = 0.071,
	PosY           = 0.872,
	CornerRadius   = 8,
}

-- ─── Detail: skins label ─────────────────────────────────
Config.SkinsLabel = {
	Width          = 0.906,
	Height         = 0.039,
	PosX           = 0.047,
	PosYLocked     = 0.589,
	PosYUnlocked   = 0.533,
}

-- ─── Detail: skins scroll frame ─────────────────────────
Config.SkinsFrame = {
	Width          = 0.906,
	Height         = 0.16,
	DisplayH       = 0.10,
	PosX           = 0.047,
	PosYLocked     = 0.633,
	PosYUnlocked   = 0.578,
	ScrollBarThickness = 3,
	ListPadding    = 0.04,
}

-- ─── Skin button (inside skins scroll) ──────────────────
Config.SkinBtn = {
	Width          = 0.5,
	CornerRadius   = 8,
}

-- ─── Lock overlay (on weapon / skin buttons) ──────────
Config.LockOverlay = {
	Width          = 0.6,
	Height         = 0.6,
	PosX           = 0.5,
	PosY           = 0.5,
	BgTransparency = 0.7,
	IconText       = "\xF0\x9F\x94\x92",
}

-- ─── Weapon button (primary / secondary grid) ───────────
Config.WeaponBtn = {
	Width          = 0.5,
	CornerRadius   = 10,
}

-- ─── Temp badge (on weapon button) ──────────────────────
Config.TempBadge = {
	Width          = 0.7,
	Height         = 0.28,
	PosX           = 0.96,
	PosY           = 0.96,
	CornerRadius   = 6,
}

-- ─── Equipped bar ────────────────────────────────────────
Config.EquippedBar = {
	HeightExtra    = 0.4,
	PosYOffset     = 0.12,
}

-- ─── Equipped bar: title ─────────────────────────────────
Config.EquippedTitle = {
	Height         = 0.07,
	PosY           = 0.05,
}

-- ─── Equipped bar: slot labels ───────────────────────────
Config.SlotLabel = {
	Width          = 0.107,
	Height         = 0.06,
	PosY           = 0.15,
}

-- ─── Equipped bar: slot frames ──────────────────────────
Config.Slot = {
	Width          = 0.107,
	Height         = 0.545,
	PosY           = 0.25,
	CornerRadius   = 8,
	IconScale      = 0.83,
}

-- ─── Equipped bar: secondary slot X offset ──────────────
Config.SecondarySlotX = 0.143

return Config
