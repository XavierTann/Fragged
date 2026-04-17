--[[
	MatchForfeitToastClient
	Server fires when a match is forfeited due to insufficient players.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local CenterScreenToast = require(ReplicatedStorage.Shared.UI.CenterScreenToast)
local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

return {
	Init = function()
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME, 30)
		if not folder then
			return
		end
		local re = folder:WaitForChild(CombatConfig.REMOTES.MATCH_FORFEIT, 10)
		if re and re:IsA("RemoteEvent") then
			re.OnClientEvent:Connect(function()
				CombatServiceClient.SetShootingEnabled(false)
				CenterScreenToast.Show({
					text = "There are insufficient players for the game to continue.",
					textColor = Color3.fromRGB(255, 200, 100),
					holdSeconds = 4,
					fadeSeconds = 0.6,
					textSize = 20,
				})
			end)
		end
	end,
}
