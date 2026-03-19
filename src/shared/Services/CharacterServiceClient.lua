--[[
	CharacterServiceClient
	Character-related logic on client (e.g. disable climbing, jumping).
	SetStateEnabled does not replicate; must run on client.
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local function applyCharacterRestrictions(character)
	if not character or not character.Parent then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid.Parent then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

return {
	Init = function()
		LocalPlayer.CharacterAdded:Connect(function(character)
			task.defer(function()
				applyCharacterRestrictions(character)
			end)
		end)
		if LocalPlayer.Character then
			task.defer(function()
				applyCharacterRestrictions(LocalPlayer.Character)
			end)
		end
	end,
}
