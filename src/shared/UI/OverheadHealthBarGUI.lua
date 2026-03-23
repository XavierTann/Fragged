--[[
	OverheadHealthBarGUI
	Creates and manages BillboardGui overhead health bars above every other player's head
	in the arena. Green for teammates, red for opponents. Colors refresh when team
	assignments change. Only visible while the arena phase is active.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatServiceClient = require(ReplicatedStorage.Shared.Services.CombatServiceClient)

local LocalPlayer = Players.LocalPlayer

local BILLBOARD_NAME       = "OverheadHealthBar"
local BILLBOARD_SIZE       = UDim2.fromOffset(72, 7)
local BILLBOARD_OFFSET     = Vector3.new(0, 2.4, 0)
local BILLBOARD_MAX_DIST   = 60

local BAR_BG_COLOR         = Color3.fromRGB(22, 22, 22)
local BAR_BG_TRANSPARENCY  = 0.3
local COLOR_FRIENDLY       = Color3.fromRGB(80, 200, 100)
local COLOR_ENEMY          = Color3.fromRGB(220, 70, 70)

-- [userId] -> "Blue" | "Red"
local playerTeams = {}
local myTeam      = nil
local active      = false

-- [userId] -> { characterAdded, health, maxHealth, died }
local playerConnections = {}

local function getBarColor(userId)
	local theirTeam = playerTeams[userId]
	print("[getBarColor] userId:", userId, "| myTeam:", myTeam, "| theirTeam:", theirTeam)
	print("[getBarColor] playerTeams dump:")
	for id, team in pairs(playerTeams) do
		print("  userId:", id, "-> team:", team)
	end
	if not theirTeam or not myTeam then
		print("[getBarColor] -> COLOR_ENEMY (team data missing)")
		return COLOR_ENEMY
	end
	if theirTeam == myTeam then
		print("[getBarColor] -> COLOR_FRIENDLY (teammate)")
	else
		print("[getBarColor] -> COLOR_ENEMY (opponent)")
	end
	return (theirTeam == myTeam) and COLOR_FRIENDLY or COLOR_ENEMY
end

local function findOrCreateBillboard(head)
	local existing = head:FindFirstChild(BILLBOARD_NAME)
	if existing then
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
	bg.Parent                 = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent       = bg

	local fill = Instance.new("Frame")
	fill.Name                   = "Fill"
	fill.Size                   = UDim2.fromScale(1, 1)
	fill.BackgroundColor3       = COLOR_FRIENDLY
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel        = 0
	fill.Parent                 = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent       = fill

	return billboard
end

local function updateBar(billboard, humanoid, userId)
	if not billboard or not billboard.Parent then
		return
	end
	local bg   = billboard:FindFirstChild("Background")
	local fill = bg and bg:FindFirstChild("Fill")
	if not fill then
		return
	end
	local health    = humanoid.Health
	local maxHealth = humanoid.MaxHealth
	local ratio     = maxHealth > 0 and (health / maxHealth) or 0
	fill.Size             = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.BackgroundColor3 = getBarColor(userId)
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
	print("Binding")
	local userId = player.UserId
	disconnectHealthConnections(userId)

	-- Do not create a bar until team assignment is known; avoids showing stale
	-- or default-enemy colors from a previous round or before TEAM_ASSIGNMENT fires.

	local head = character:FindFirstChild("Head")
	if not head then
		head = character:WaitForChild("Head", 5)
	end
	if not head then
		print("No head")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5)
	end
	if not humanoid then
		print("No humanoid")
		return
	end

	local billboard = findOrCreateBillboard(head)
	updateBar(billboard, humanoid, userId)

	local conns = playerConnections[userId] or {}
	conns.health = humanoid.HealthChanged:Connect(function()
		updateBar(billboard, humanoid, userId)
	end)
	print("Connected health")
	conns.maxHealth = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateBar(billboard, humanoid, userId)
	end)
	print("Connected max health")
	conns.died = humanoid.Died:Connect(function()
		updateBar(billboard, humanoid, userId)
	end)
	print("Connected died")
	playerConnections[userId] = conns
	print("Connected")
end

local function setupPlayer(player)
	local userId = player.UserId
	playerConnections[userId] = playerConnections[userId] or {}

	if not playerConnections[userId].characterAdded then
		playerConnections[userId].characterAdded = player.CharacterAdded:Connect(function(character)
			print("Character added")
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
		if player ~= LocalPlayer then
			local character = player.Character
			if character then
				local head      = character:FindFirstChild("Head")
				local billboard = head and head:FindFirstChild(BILLBOARD_NAME)
				if billboard then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						updateBar(billboard, humanoid, player.UserId)
					end
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
			myTeam      = assignment.myTeam
			playerTeams = assignment.playerTeams or {}
			-- Call setupPlayer for every current player so that bars which were
			-- withheld (because myTeam was nil) are created now with correct colors,
			-- and any already-existing bars are recolored to match the new assignment.
			print("Combatservice remote event fired")
			print(myTeam)

				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LocalPlayer then
						setupPlayer(player)
					end
				end

		end)

		Players.PlayerAdded:Connect(function(player)
			if player ~= LocalPlayer then
				setupPlayer(player)
			end
		end)

		Players.PlayerRemoving:Connect(function(player)
			teardownPlayer(player.UserId)
		end)

		-- for _, player in ipairs(Players:GetPlayers()) do
		-- 	if player ~= LocalPlayer then
		-- 		setupPlayer(player)
		-- 	end
		-- end
	end,

	Show = function()
		active = true
		-- for _, player in ipairs(Players:GetPlayers()) do
		-- 	if player ~= LocalPlayer then
		-- 		setupPlayer(player)
		-- 	end
		-- end
	end,

	Hide = function()
		active = false
		-- Clear team state so stale assignments from this round never influence
		-- bar colors at the start of the next round before TEAM_ASSIGNMENT arrives.
		myTeam      = nil
		playerTeams = {}
		for _, player in ipairs(Players:GetPlayers()) do
			destroyPlayerBillboard(player)
			disconnectHealthConnections(player.UserId)
		end
	end,
}
