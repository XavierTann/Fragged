--[[
	HealthGUI
	Custom health bar for the local player. Shown in arena when default Roblox health is disabled.
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local gui = nil
local container = nil
local fillFrame = nil
local healthConnection = nil
local diedConnection = nil

local BAR_WIDTH = 20
local BAR_HEIGHT = 140

local function createGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "HealthGUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.Name = "HealthContainer"
	container.Size = UDim2.fromOffset(BAR_WIDTH + 16, BAR_HEIGHT + 16)
	container.AnchorPoint = Vector2.new(0, 0.5)
	container.Position = UDim2.new(0, 8, 0.5, 0)
	container.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
	container.BackgroundTransparency = 0.5
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local barFrame = Instance.new("Frame")
	barFrame.Name = "HealthBar"
	barFrame.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	barFrame.Position = UDim2.fromOffset(8, 8)
	barFrame.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	barFrame.BackgroundTransparency = 0.4
	barFrame.BorderSizePixel = 0
	barFrame.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barFrame

	fillFrame = Instance.new("Frame")
	fillFrame.Name = "HealthFill"
	fillFrame.Size = UDim2.fromScale(1, 1)
	fillFrame.Position = UDim2.fromScale(0, 1)
	fillFrame.AnchorPoint = Vector2.new(0, 1)
	fillFrame.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
	fillFrame.BackgroundTransparency = 0.1
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fillFrame

	return gui
end

local function disconnectHumanoid()
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if diedConnection then
		diedConnection:Disconnect()
		diedConnection = nil
	end
end

local function updateHealth(humanoid)
	if not fillFrame or not humanoid then
		return
	end
	local health = humanoid.Health
	local maxHealth = humanoid.MaxHealth
	local ratio = maxHealth > 0 and (health / maxHealth) or 0
	fillFrame.Size = UDim2.fromScale(1, math.clamp(ratio, 0, 1))
	if ratio < 0.30 then
		fillFrame.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
	elseif ratio < 0.75 then
		fillFrame.BackgroundColor3 = Color3.fromRGB(220, 200, 60)
	else
		fillFrame.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
	end
end

local function bindToCharacter(character)
	disconnectHumanoid()
	if not character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5)
	end
	if not humanoid then
		return
	end
	updateHealth(humanoid)
	healthConnection = humanoid.HealthChanged:Connect(function()
		updateHealth(humanoid)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHealth(humanoid)
	end)
	diedConnection = humanoid.Died:Connect(function()
		updateHealth(humanoid)
	end)
end

local function init()
	createGui()
	LocalPlayer.CharacterAdded:Connect(function(character)
		if gui and gui.Enabled then
			bindToCharacter(character)
		end
	end)
	if LocalPlayer.Character and gui and gui.Enabled then
		bindToCharacter(LocalPlayer.Character)
	end
end

return {
	Init = init,
	Show = function()
		if gui then
			gui.Enabled = true
			bindToCharacter(LocalPlayer.Character)
		end
	end,
	Hide = function()
		if gui then
			gui.Enabled = false
			disconnectHumanoid()
		end
	end,
}
