--[[
	LobbyQueueBalanceToastClient (client)
	Shows CenterScreenToast when server detects player on a suppressed (fuller-team) pad,
	or when they stand on another player's occupied queue pad.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)
local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)
local CenterScreenToast = require(ReplicatedStorage.Shared.UI.CenterScreenToast)

local COLOR_NEUTRAL = Color3.fromRGB(220, 210, 255)

return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(LobbyConfig.REMOTE_FOLDER_NAME, 30)
		if not folder then
			return
		end
		local re = folder:WaitForChild(LobbyConfig.REMOTES.QUEUE_BALANCE_TOAST, 10)
		if re and re:IsA("RemoteEvent") then
			re.OnClientEvent:Connect(function(fullerTeam, otherTeam)
				if fullerTeam ~= "Blue" and fullerTeam ~= "Red" then
					return
				end
				if otherTeam ~= "Blue" and otherTeam ~= "Red" then
					return
				end
				local otherName = TeamDisplayUtils.displayName(otherTeam)
				local fullerName = TeamDisplayUtils.displayName(fullerTeam)
				local text = string.format(
					"Please join the %s Team. The %s Team has too many players.",
					otherName,
					fullerName
				)
				CenterScreenToast.Show({
					text = text,
					textColor = COLOR_NEUTRAL,
					holdSeconds = 3.2,
					fadeSeconds = 0.55,
					textSize = 20,
				})
			end)
		end

		local padRe = folder:WaitForChild(LobbyConfig.REMOTES.PAD_OCCUPIED_TOAST, 10)
		if padRe and padRe:IsA("RemoteEvent") then
			padRe.OnClientEvent:Connect(function()
				CenterScreenToast.Show({
					text = "This pad is already occupied. Please use another pad.",
					textColor = COLOR_NEUTRAL,
					holdSeconds = 3.2,
					fadeSeconds = 0.55,
					textSize = 20,
				})
			end)
		end
	end,
}
