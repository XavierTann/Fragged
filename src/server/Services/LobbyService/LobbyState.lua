--[[
	LobbyState
	Mutable state for the lobby queue and countdown.
]]

return function()
	return {
		waitingQueue = {},
		playerPhase = {},
		lastLeftWaitingAt = {},
		matchStartingAt = nil,
		countdownEndTime = nil,
		countdownTickConnection = nil,
		onArenaRoundStarted = nil,
	}
end
