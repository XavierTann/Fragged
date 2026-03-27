--[[
	FloatingDamageNumbers
	Listens for server DamageNumber (damage, worldPosition) on the local client only.
	Spawns a BillboardGui at the hit position: rises, fades, then cleans up.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)

local FOLDER_NAME = "FloatingDamageNumbers"
local RISE_STUDS = 2.75
local MOVE_DURATION = 0.8
local CLEANUP_AFTER = 1.15

local function getFolder()
	local f = Workspace:FindFirstChild(FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = Workspace
	end
	return f
end

local function spawnNumber(damage, worldPosition)
	if typeof(damage) ~= "number" or typeof(worldPosition) ~= "Vector3" then
		return
	end
	local amount = math.floor(damage + 0.5)
	if amount <= 0 then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumberAnchor"
	anchor.Size = Vector3.one * 0.05
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(worldPosition)
	anchor.Parent = getFolder()

	local bb = Instance.new("BillboardGui")
	bb.Name = "DamageBillboard"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(168, 58)
	bb.StudsOffset = Vector3.zero
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 34
	label.Text = tostring(amount)
	label.TextColor3 = Color3.fromRGB(255, 235, 140)
	label.TextTransparency = 0.05
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(12, 12, 18)
	stroke.Transparency = 0.15
	stroke.Parent = label

	local moveInfo = TweenInfo.new(MOVE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local endCf = anchor.CFrame + Vector3.new(0, RISE_STUDS, 0)
	TweenService:Create(anchor, moveInfo, { CFrame = endCf }):Play()
	TweenService:Create(label, moveInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, moveInfo, { Transparency = 1 }):Play()

	Debris:AddItem(anchor, CLEANUP_AFTER)
end

local initialized = false

return {
	Init = function()
		if initialized then
			return
		end
		initialized = true
		local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
		local re = folder:WaitForChild(CombatConfig.REMOTES.DAMAGE_NUMBER)
		re.OnClientEvent:Connect(function(damage, worldPosition)
			spawnNumber(damage, worldPosition)
		end)
	end,
}
