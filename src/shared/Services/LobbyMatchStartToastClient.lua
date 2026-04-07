--[[
	LobbyMatchStartToastClient
	Center-screen toast for arena lobby countdown (3…2…1).

	Server fires LobbyMatchCountdown with a plain number (reliable); LobbyState tables
	can lose or alter fields over the wire, which prevented the toast from appearing.

	Cancel when LobbyState arrives with matchStarting false — wired synchronously from
	LobbyServiceClient before deferred subscribers run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local CenterScreenToast = require(ReplicatedStorage.Shared.UI.CenterScreenToast)

local T = LobbyConfig.TEXT
local COLOR_COUNTDOWN = Color3.fromRGB(255, 220, 100)

local lastSecondsShown = nil

local function showCountdownSeconds(sec)
	if typeof(sec) ~= "number" then
		sec = tonumber(sec)
	end
	if sec == nil then
		return
	end

	if sec > 0 then
		if lastSecondsShown == sec then
			return
		end
		lastSecondsShown = sec
		CenterScreenToast.Show({
			text = string.format(T.MATCH_STARTING_IN, sec),
			textColor = COLOR_COUNTDOWN,
			holdSeconds = 0.92,
			fadeSeconds = 0.35,
			textSize = 32,
		})
		return
	end

	if lastSecondsShown == 0 then
		return
	end
	lastSecondsShown = 0
	CenterScreenToast.Show({
		text = T.MATCH_STARTING,
		textColor = COLOR_COUNTDOWN,
		holdSeconds = 1.15,
		fadeSeconds = 0.45,
		textSize = 32,
	})
end

--- Call synchronously from LobbyServiceClient on every LobbyState (before task.spawn subscribers).
local function applyLobbyState(state)
	if not state or state.matchStarting ~= false then
		return
	end
	if lastSecondsShown ~= nil then
		CenterScreenToast.Cancel()
	end
	lastSecondsShown = nil
end

return {
	ApplyLobbyState = applyLobbyState,
	OnMatchCountdown = showCountdownSeconds,

	Init = function()
		task.defer(function()
			local LobbyServiceClient = require(ReplicatedStorage.Shared.Services.LobbyServiceClient)
			applyLobbyState(LobbyServiceClient.GetState())
		end)
	end,
}
