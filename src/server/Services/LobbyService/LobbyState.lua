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
		teamQueueBalanceToastCooldown = {}, -- uid -> os.clock() when next team-balance toast allowed
		matchStartingAt = nil,
		countdownEndTime = nil,
		countdownTickConnection = nil,
		onArenaRoundStarted = nil,
	}
end
