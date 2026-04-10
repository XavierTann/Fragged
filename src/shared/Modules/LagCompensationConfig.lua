--[[
	Lag compensation configuration for server-side projectile rewind.
	Client sends estimated server time with each shot; server uses the delta
	to catch-up simulate the projectile against historical player positions.
]]

return {
	MAX_REWIND_SECONDS = 0.4,
	HISTORY_DURATION_SECONDS = 0.6,
	CATCH_UP_STEP_SECONDS = 1 / 60,
	PLAYER_HITBOX_RADIUS = 2.5,
	MAX_FUTURE_TOLERANCE_SECONDS = 0.05,
	TIME_SYNC_REMOTE_NAME = "CombatTimeSync",
	VIEW_DELAY_ENABLED = true,
	MAX_VIEW_DELAY_SECONDS = 0.2,
	DEBUG_LOGGING = false,
}
