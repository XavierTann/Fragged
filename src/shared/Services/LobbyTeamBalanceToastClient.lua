--[[
	LobbyTeamBalanceToastClient (client)
	Server fires when standing on the fuller team's pad while the queue needs balance.
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
		local re = folder:WaitForChild(LobbyConfig.REMOTES.TEAM_QUEUE_BALANCE_TOAST, 10)
		if re and re:IsA("RemoteEvent") then
			re.OnClientEvent:Connect(function(otherTeam)
				if otherTeam ~= "Blue" and otherTeam ~= "Red" then
					return
				end
				local otherName = TeamDisplayUtils.displayName(otherTeam)
				local text = string.format(LobbyConfig.TEXT.TEAM_QUEUE_BALANCE_TOAST, otherName)
				CenterScreenToast.Show({
					text = text,
					textColor = COLOR_NEUTRAL,
					holdSeconds = 3.2,
					fadeSeconds = 0.55,
					textSize = 20,
				})
			end)
		end
	end,
}
