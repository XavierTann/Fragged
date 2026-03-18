--[[
	TouchControlUtils
	Helpers for customizing Roblox's default touch controls.
	- Removes the jump button and lets the right joystick occupy that position.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Remove the default jump button from TouchGui. Only runs when TouchEnabled.
-- The jump button lives at: PlayerGui > TouchGui > TouchControlFrame > JumpButton
local function removeJumpButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	local touchGui = playerGui:WaitForChild("TouchGui", 10)
	if not touchGui then
		return
	end
	local controlFrame = touchGui:WaitForChild("TouchControlFrame", 5)
	if not controlFrame then
		return
	end
	local jumpButton = controlFrame:FindFirstChild("JumpButton")
	if jumpButton then
		jumpButton:Destroy()
	end
end

-- Call early in client startup. Spawns a deferred task to avoid blocking.
local function init()
	task.defer(function()
		removeJumpButton()
	end)
end

return {
	Init = init,
	RemoveJumpButton = removeJumpButton,
}
