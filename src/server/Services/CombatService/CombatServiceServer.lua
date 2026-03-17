--[[
	CombatService (server)
	Shooting (visible bullets), health, round end. Server-authoritative.
	Init() sets up remotes and handlers. StartRound(players, onRoundEnd) is called when arena round starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)

local remotes = nil
local currentRoundPlayers = {}
local onRoundEndCallback = nil
local diedConnections = {}
local lastFiredAt = {}
local BULLETS_FOLDER_NAME = "CombatBullets"

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local r = folder:FindFirstChild(CombatConfig.REMOTES.FIRE_GUN)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = CombatConfig.REMOTES.FIRE_GUN
		r.Parent = folder
	end
	return r
end

local function getBulletsFolder()
	local folder = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = BULLETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function countAliveInRound()
	local count = 0
	for _, p in ipairs(currentRoundPlayers) do
		if p and p.Parent and p.Character then
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then
				count = count + 1
			end
		end
	end
	return count
end

local function checkRoundEnd()
	if #currentRoundPlayers == 0 then
		return
	end
	local alive = countAliveInRound()
	if alive <= 1 and onRoundEndCallback then
		print("[Combat] Round has finished.")
		local cb = onRoundEndCallback
		onRoundEndCallback = nil
		for _, conn in pairs(diedConnections) do
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
		end
		diedConnections = {}
		currentRoundPlayers = {}
		cb()
	end
end

local function spawnBullet(shooter, startPos, direction, gunId)
	local gun = GunsConfig[gunId] or GunsConfig.Pistol
	local dir = direction.Unit
	local bullet = Instance.new("Part")
	bullet.Name = "Bullet"
	bullet.Size = gun.bulletSize
	bullet.Color = gun.bulletColor
	bullet.Material = Enum.Material.Neon
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CFrame = CFrame.lookAt(startPos, startPos + dir)
	bullet.Parent = getBulletsFolder()
	local shooterUserId = shooter.UserId
	local speed = gun.bulletSpeed
	local lastPos = startPos
	local params = RaycastParams.new()
	local filter = { bullet, getBulletsFolder() }
	if shooter.Character then
		filter[#filter + 1] = shooter.Character
	end
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not bullet.Parent then
			conn:Disconnect()
			return
		end
		local move = dir * speed * dt
		local newPos = lastPos + move
		local result = Workspace:Raycast(lastPos, move, params)
		if result and result.Instance then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			if model then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local hitPlayer = humanoid and Players:GetPlayerFromCharacter(model)
				if hitPlayer and hitPlayer.UserId ~= shooterUserId then
					conn:Disconnect()
					humanoid:TakeDamage(gun.damage)
					bullet:Destroy()
					return
				end
			end
		end
		lastPos = newPos
		bullet.CFrame = CFrame.lookAt(newPos, newPos + dir)
	end)
	task.delay(5, function()
		if bullet and bullet.Parent then
			conn:Disconnect()
			bullet:Destroy()
		end
	end)
end

local function bindHandlers()
	remotes.OnServerEvent:Connect(function(player, aimDirection, gunId)
		if not aimDirection or typeof(aimDirection) ~= "Vector3" then
			return
		end
		if aimDirection.Magnitude < 0.01 then
			return
		end
		local gun = GunsConfig[gunId or "Pistol"] or GunsConfig.Pistol
		local now = os.clock()
		local last = lastFiredAt[player.UserId] or 0
		if now - last < gun.fireRate then
			return
		end
		lastFiredAt[player.UserId] = now
		local character = player.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local startPos = root.Position + aimDirection.Unit * 2
		local pelletCount = gun.pelletCount or 1
		local spreadDeg = gun.spreadDegrees or 0
		for i = 1, pelletCount do
			local dir = aimDirection.Unit
			if spreadDeg > 0 and pelletCount > 1 then
				local angle = math.rad(spreadDeg * (math.random() * 2 - 1))
				local perp = Vector3.new(-dir.Z, 0, dir.X)
				dir = (dir * math.cos(angle) + perp * math.sin(angle)).Unit
				-- add vertical spread
				local up = Vector3.new(0, 1, 0)
				local angle2 = math.rad(spreadDeg * 0.5 * (math.random() * 2 - 1))
				dir = (dir * math.cos(angle2) + up * math.sin(angle2)).Unit
			end
			spawnBullet(player, startPos, dir, gunId or "Pistol")
		end
	end)
end

return {
	Init = function()
		remotes = ensureRemotes()
		bindHandlers()
	end,

	StartRound = function(players, onRoundEnd)
		onRoundEndCallback = onRoundEnd
		currentRoundPlayers = {}
		for _, p in ipairs(players) do
			currentRoundPlayers[#currentRoundPlayers + 1] = p
			local character = p.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
					humanoid.Health = CombatConfig.DEFAULT_HEALTH
					local conn = humanoid.Died:Connect(function()
						checkRoundEnd()
					end)
					diedConnections[p.UserId] = conn
				end
			end
		end
		task.defer(checkRoundEnd)
	end,
}
