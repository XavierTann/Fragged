--[[
	CharacterServiceClient
	Character-related logic on client (e.g. disable climbing, jumping).
	Also owns CoreGui disabling — SetStateEnabled and SetCoreGuiEnabled do not
	replicate and must be called from a LocalScript context.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

local function disableCoreGui()
	local ok = false
	while not ok do
		ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if not ok then
			task.wait()
		end
	end
end

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
	-- Re-apply on each spawn in case Roblox resets CoreGui state.
	disableCoreGui()
end

return {
	Init = function()
		disableCoreGui()
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
