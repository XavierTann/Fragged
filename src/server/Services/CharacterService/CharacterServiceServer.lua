--[[
	CharacterServiceServer
	Server-side character setup applied to every player on CharacterAdded.
	Runs on the server so property changes replicate to all clients.
]]

local Players = game:GetService("Players")

local function applyCharacterSettings(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 10)
	end
	if not humanoid then
		return
	end
	-- Disable the built-in Roblox overhead health bar for all clients.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
end

return {
	Init = function()
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(function(character)
				task.defer(function()
					applyCharacterSettings(character)
				end)
			end)
			if player.Character then
				task.defer(function()
					applyCharacterSettings(player.Character)
				end)
			end
		end)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				task.defer(function()
					applyCharacterSettings(player.Character)
				end)
			end
		end
	end,
}
