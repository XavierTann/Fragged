--[[
	LobbyState
	Mutable state for the lobby queue and countdown.
]]

return function()
	return {
		waitingQueueBlue = {},
		waitingQueueRed = {},
		playerPhase = {},
		lastLeftWaitingAt = {},
		joinQueueBlockedUntil = {}, -- after LeaveWaitingLobby: block pad re-queue briefly
		balanceToastCooldown = {}, -- uid -> os.clock() when next queue-balance toast allowed
		padOccupiedToastCooldown = {}, -- uid -> os.clock() when next pad-occupied toast allowed
		matchStartingAt = nil,
		countdownEndTime = nil,
		countdownTickConnection = nil,
		onArenaRoundStarted = nil,
	}
end
