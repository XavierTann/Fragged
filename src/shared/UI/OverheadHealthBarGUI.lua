--[[
	OverheadHealthBarGUI
	Creates and manages BillboardGui overhead health bars above each player's head
	(including the local player) in the arena. Fill color matches that player's team (blue vs
	orange; server internal key for orange side is still "Red"). Orange avoids looking like a
	"low health" red bar. Colors refresh when team assignments change. Only visible while the arena
	phase is active.

	On damage, a short white segment appears over the lost portion of the bar, then shrinks and
	fades so the bar readout matches the new health — clear hit feedback for shooters and spectators.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local BILLBOARD_NAME       = "OverheadHealthBar"
local BILLBOARD_SIZE       = UDim2.fromOffset(100, 10)
local BILLBOARD_OFFSET     = Vector3.new(0, 2.55, 0)
local BILLBOARD_MAX_DIST   = 60

local BAR_BG_COLOR         = Color3.fromRGB(22, 22, 22)
local BAR_BG_TRANSPARENCY  = 0.3
local COLOR_TEAM_BLUE      = Color3.fromRGB(70, 150, 255)
local COLOR_TEAM_ORANGE    = Color3.fromRGB(255, 145, 55)
local COLOR_UNKNOWN_TEAM   = Color3.fromRGB(160, 160, 160)
local COLOR_DAMAGE_FLASH   = Color3.fromRGB(255, 255, 255)

local DAMAGE_TWEEN_TIME    = 0.42
local DAMAGE_EASING        = Enum.EasingStyle.Quad
local DAMAGE_EASING_DIR    = Enum.EasingDirection.Out

-- [userId] -> "Blue" | "Red"
local playerTeams = {}

-- Weak keys: released when billboard is destroyed
local lastHealthByBillboard = setmetatable({}, { __mode = "k" })
local damageTweenByBillboard = setmetatable({}, { __mode = "k" })

-- [userId] -> { characterAdded, health, maxHealth, died }
local playerConnections = {}

local function getBarColor(userId)
	local team = playerTeams[userId]
	if team == "Blue" then
		return COLOR_TEAM_BLUE
	end
	if team == "Red" then
		return COLOR_TEAM_ORANGE
	end
	return COLOR_UNKNOWN_TEAM
end

local function cancelDamageTween(billboard)
	local tw = damageTweenByBillboard[billboard]
	if tw then
		tw:Cancel()
		damageTweenByBillboard[billboard] = nil
	end
end

-- Returns fill, damageFlash (inside BarClip under Background).
local function ensureBarClipContents(billboard)
	local bg = billboard:FindFirstChild("Background")
	if not bg then
		return nil, nil
	end
	bg.ClipsDescendants = true

	local clip = bg:FindFirstChild("BarClip")
	if not clip then
		clip = Instance.new("Frame")
		clip.Name = "BarClip"
		clip.BackgroundTransparency = 1
		clip.BorderSizePixel = 0
		clip.Size = UDim2.fromScale(1, 1)
		clip.ZIndex = 0
		clip.Parent = bg

		local oldFill = bg:FindFirstChild("Fill")
		if oldFill then
			oldFill.Parent = clip
		else
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = COLOR_TEAM_BLUE
			fill.BackgroundTransparency = 0
			fill.BorderSizePixel = 0
			fill.ZIndex = 1
			fill.Parent = clip
			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(1, 0)
			fillCorner.Parent = fill
		end
	end

	local fill = clip:FindFirstChild("Fill")
	if not fill then
		return nil, nil
	end
	fill.ZIndex = 1

	local damage = clip:FindFirstChild("DamageFlash")
	if not damage then
		damage = Instance.new("Frame")
		damage.Name = "DamageFlash"
		damage.AnchorPoint = Vector2.new(0, 0)
		damage.Position = UDim2.fromScale(0, 0)
		damage.Size = UDim2.fromScale(0, 1)
		damage.BackgroundColor3 = COLOR_DAMAGE_FLASH
		damage.BackgroundTransparency = 0
		damage.BorderSizePixel = 0
		damage.Visible = false
		damage.ZIndex = 2
		damage.Parent = clip
	end

	return fill, damage
end

local function resetDamageVisual(billboard)
	cancelDamageTween(billboard)
	local _, damage = ensureBarClipContents(billboard)
	if damage then
		damage.Visible = false
		damage.BackgroundTransparency = 0
		damage.Size = UDim2.fromScale(0, 1)
	end
end

local function findOrCreateBillboard(head)
	local existing = head:FindFirstChild(BILLBOARD_NAME)
	if existing then
		ensureBarClipContents(existing)
		existing.Size = BILLBOARD_SIZE
		existing.StudsOffset = BILLBOARD_OFFSET
		return existing
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name            = BILLBOARD_NAME
	billboard.Size            = BILLBOARD_SIZE
	billboard.StudsOffset     = BILLBOARD_OFFSET
	billboard.AlwaysOnTop     = false
	billboard.ResetOnSpawn    = false
	billboard.MaxDistance     = BILLBOARD_MAX_DIST
	billboard.Parent          = head

	local bg = Instance.new("Frame")
	bg.Name                   = "Background"
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = BAR_BG_COLOR
	bg.BackgroundTransparency = BAR_BG_TRANSPARENCY
	bg.BorderSizePixel        = 0
	bg.ClipsDescendants       = true
	bg.Parent                 = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent       = bg

	local clip = Instance.new("Frame")
	clip.Name = "BarClip"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = 0
	clip.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_TEAM_BLUE
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = clip

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local damage = Instance.new("Frame")
	damage.Name = "DamageFlash"
	damage.AnchorPoint = Vector2.new(0, 0)
	damage.Position = UDim2.fromScale(0, 0)
	damage.Size = UDim2.fromScale(0, 1)
	damage.BackgroundColor3 = COLOR_DAMAGE_FLASH
	damage.BackgroundTransparency = 0
	damage.BorderSizePixel = 0
	damage.Visible = false
	damage.ZIndex = 2
	damage.Parent = clip

	return billboard
end

local function applyFill(billboard, humanoid, userId)
	local fill = select(1, ensureBarClipContents(billboard))
	if not fill then
		return
	end
	local health    = humanoid.Health
	local maxHealth = humanoid.MaxHealth
	local ratio     = maxHealth > 0 and (health / maxHealth) or 0
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.BackgroundColor3 = getBarColor(userId)
end

local function playDamageFlash(billboard, humanoid, userId, oldHealth, newHealth)
	local fill, damage = ensureBarClipContents(billboard)
	if not fill or not damage then
		return
	end

	local maxHealth = humanoid.MaxHealth
	if maxHealth <= 0 then
		applyFill(billboard, humanoid, userId)
		return
	end

	local oldR = math.clamp(oldHealth / maxHealth, 0, 1)
	local newR = math.clamp(newHealth / maxHealth, 0, 1)
	local delta = oldR - newR
	if delta <= 1e-4 then
		applyFill(billboard, humanoid, userId)
		return
	end

	cancelDamageTween(billboard)

	fill.Size = UDim2.fromScale(newR, 1)
	fill.BackgroundColor3 = getBarColor(userId)

	damage.Visible = true
	damage.BackgroundTransparency = 0
	damage.Position = UDim2.fromScale(newR, 0)
	damage.Size = UDim2.fromScale(delta, 1)

	local tweenInfo = TweenInfo.new(DAMAGE_TWEEN_TIME, DAMAGE_EASING, DAMAGE_EASING_DIR)
	local tween = TweenService:Create(damage, tweenInfo, {
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
	})
	damageTweenByBillboard[billboard] = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Cancelled and damage.Parent then
			damage.Visible = false
			damage.BackgroundTransparency = 0
			damage.Size = UDim2.fromScale(0, 1)
		end
		if damageTweenByBillboard[billboard] == tween then
			damageTweenByBillboard[billboard] = nil
		end
	end)
	tween:Play()
end

local function updateBar(billboard, humanoid, userId)
	if not billboard or not billboard.Parent then
		return
	end
	applyFill(billboard, humanoid, userId)
end

local function onHumanoidHealthChanged(billboard, humanoid, userId)
	if not billboard or not billboard.Parent then
		return
	end

	local newHealth = humanoid.Health
	local prev = lastHealthByBillboard[billboard]
	lastHealthByBillboard[billboard] = newHealth

	if prev ~= nil and newHealth < prev - 1e-3 then
		playDamageFlash(billboard, humanoid, userId, prev, newHealth)
	else
		resetDamageVisual(billboard)
		updateBar(billboard, humanoid, userId)
	end
end

local function disconnectHealthConnections(userId)
	local conns = playerConnections[userId]
	if not conns then
		return
	end
	if conns.health    then conns.health:Disconnect();    conns.health    = nil end
	if conns.maxHealth then conns.maxHealth:Disconnect(); conns.maxHealth = nil end
	if conns.died      then conns.died:Disconnect();      conns.died      = nil end
end

local function bindCharacter(player, character)
	local userId = player.UserId
	disconnectHealthConnections(userId)

	-- Do not create a bar until team assignment is known; avoids showing stale
	-- or default-enemy colors from a previous round or before TEAM_ASSIGNMENT fires.

	local head = character:FindFirstChild("Head")
	if not head then
		head = character:WaitForChild("Head", 5)
	end
	if not head then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5)
	end
	if not humanoid then
		return
	end

	local billboard = findOrCreateBillboard(head)
	updateBar(billboard, humanoid, userId)
	lastHealthByBillboard[billboard] = humanoid.Health

	local conns = playerConnections[userId] or {}
	conns.health = humanoid.HealthChanged:Connect(function()
		onHumanoidHealthChanged(billboard, humanoid, userId)
	end)
	conns.maxHealth = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		lastHealthByBillboard[billboard] = humanoid.Health
		resetDamageVisual(billboard)
		updateBar(billboard, humanoid, userId)
	end)
	conns.died = humanoid.Died:Connect(function()
		lastHealthByBillboard[billboard] = humanoid.Health
		resetDamageVisual(billboard)
		updateBar(billboard, humanoid, userId)
	end)
	playerConnections[userId] = conns
end

local function setupPlayer(player)
	local userId = player.UserId
	playerConnections[userId] = playerConnections[userId] or {}

	if not playerConnections[userId].characterAdded then
		playerConnections[userId].characterAdded = player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
	end

	if player.Character then

		bindCharacter(player, player.Character)
	end
end

local function teardownPlayer(userId)
	local conns = playerConnections[userId]
	if conns then
		if conns.characterAdded then conns.characterAdded:Disconnect() end
		disconnectHealthConnections(userId)
	end
	playerConnections[userId] = nil
end

local function destroyPlayerBillboard(player)
	local character = player.Character
	if not character then return end
	local head = character:FindFirstChild("Head")
	if not head then return end
	local billboard = head:FindFirstChild(BILLBOARD_NAME)
	if billboard then billboard:Destroy() end
end

local function refreshAllBars()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local head = character:FindFirstChild("Head")
			local billboard = head and head:FindFirstChild(BILLBOARD_NAME)
			if billboard then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					updateBar(billboard, humanoid, player.UserId)
					lastHealthByBillboard[billboard] = humanoid.Health
				end
			end
		end
	end
end

local initialized = false

return {
	Init = function()
		if initialized then return end
		initialized = true

		CombatServiceClient.SubscribeTeamAssignment(function(assignment)
			playerTeams = assignment.playerTeams or {}
			-- Call setupPlayer for every current player (including local) so that bars which were
			-- withheld (because team data was nil) are created now with correct colors,
			-- and any already-existing bars are recolored to match the new assignment.
			for _, player in ipairs(Players:GetPlayers()) do
				setupPlayer(player)
			end
		end)

		Players.PlayerAdded:Connect(function(player)
			setupPlayer(player)
		end)

		Players.PlayerRemoving:Connect(function(player)
			teardownPlayer(player.UserId)
		end)

	end,

	

	Hide = function()
		-- active = false
		-- Clear team state so stale assignments from this round never influence
		-- bar colors at the start of the next round before TEAM_ASSIGNMENT arrives.
		playerTeams = {}
		for _, player in ipairs(Players:GetPlayers()) do
			destroyPlayerBillboard(player)
			disconnectHealthConnections(player.UserId)
		end
	end,
}
