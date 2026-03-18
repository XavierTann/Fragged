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

local fireGunRE = nil
local ammoStateRE = nil
local currentRoundPlayers = {}
local onRoundEndCallback = nil
local diedConnections = {}
local lastFiredAt = {}
local ammoInMagazine = {} -- [userId][gunId] = count
local reloadEndAt = {} -- [userId][gunId] = os.clock() when reload finishes
local BULLETS_FOLDER_NAME = "CombatBullets"

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(CombatConfig.REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CombatConfig.REMOTE_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local fireR = folder:FindFirstChild(CombatConfig.REMOTES.FIRE_GUN)
	if not fireR then
		fireR = Instance.new("RemoteEvent")
		fireR.Name = CombatConfig.REMOTES.FIRE_GUN
		fireR.Parent = folder
	end
	local ammoR = folder:FindFirstChild(CombatConfig.REMOTES.AMMO_STATE)
	if not ammoR then
		ammoR = Instance.new("RemoteEvent")
		ammoR.Name = CombatConfig.REMOTES.AMMO_STATE
		ammoR.Parent = folder
	end
	return fireR, ammoR
end

local function sendAmmoState(player, gunId, ammoCount, isReloading)
	if ammoStateRE then
		ammoStateRE:FireClient(player, gunId, ammoCount, isReloading)
	end
end

local function initPlayerAmmo(userId)
	ammoInMagazine[userId] = {}
	reloadEndAt[userId] = {}
	for gunId, gun in pairs(GunsConfig) do
		local mag = gun.magazineSize or 6
		ammoInMagazine[userId][gunId] = mag
		reloadEndAt[userId][gunId] = nil
	end
end

local function processReloads()
	local now = os.clock()
	for userId, gunReloads in pairs(reloadEndAt) do
		for gunId, endTime in pairs(gunReloads) do
			if endTime and now >= endTime then
				local gun = GunsConfig[gunId]
				if gun then
					ammoInMagazine[userId][gunId] = gun.magazineSize or 6
					reloadEndAt[userId][gunId] = nil
					local player = Players:GetPlayerByUserId(userId)
					if player then
						sendAmmoState(player, gunId, ammoInMagazine[userId][gunId], false)
					end
				end
			end
		end
	end
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
	fireGunRE.OnServerEvent:Connect(function(player, aimDirection, gunId)
		if not aimDirection or typeof(aimDirection) ~= "Vector3" then
			return
		end
		if aimDirection.Magnitude < 0.01 then
			return
		end
		gunId = gunId or "Pistol"
		local gun = GunsConfig[gunId] or GunsConfig.Pistol
		local now = os.clock()
		local uid = player.UserId

		-- Fire rate check
		local last = lastFiredAt[uid] or 0
		if now - last < gun.fireRate then
			return
		end

		-- Ammo check: ensure player has ammo state for this weapon
		ammoInMagazine[uid] = ammoInMagazine[uid] or {}
		reloadEndAt[uid] = reloadEndAt[uid] or {}
		local ammo = ammoInMagazine[uid][gunId]
		if ammo == nil then
			ammoInMagazine[uid][gunId] = gun.magazineSize or 6
			ammo = ammoInMagazine[uid][gunId]
		end

		-- Reloading check
		if reloadEndAt[uid][gunId] and now < reloadEndAt[uid][gunId] then
			sendAmmoState(player, gunId, ammo, true)
			return
		end

		-- Ammo check
		if ammo <= 0 then
			-- Auto-start reload (if not already)
			if not reloadEndAt[uid][gunId] then
				local reloadTime = gun.reloadTime or 1.5
				reloadEndAt[uid][gunId] = now + reloadTime
			end
			sendAmmoState(player, gunId, 0, true)
			return
		end

		lastFiredAt[uid] = now
		ammoInMagazine[uid][gunId] = ammo - 1
		local newAmmo = ammoInMagazine[uid][gunId]

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
		for _ = 1, pelletCount do
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
			spawnBullet(player, startPos, dir, gunId)
		end

		-- If magazine empty after shot, auto-start reload
		if newAmmo <= 0 then
			local reloadTime = gun.reloadTime or 1.5
			reloadEndAt[uid][gunId] = now + reloadTime
			sendAmmoState(player, gunId, 0, true)
		else
			sendAmmoState(player, gunId, newAmmo, false)
		end
	end)
end

return {
	Init = function()
		fireGunRE, ammoStateRE = ensureRemotes()
		bindHandlers()
		RunService.Heartbeat:Connect(processReloads)
	end,

	StartRound = function(players, onRoundEnd)
		onRoundEndCallback = onRoundEnd
		currentRoundPlayers = {}
		for _, p in ipairs(players) do
			currentRoundPlayers[#currentRoundPlayers + 1] = p
			initPlayerAmmo(p.UserId)
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
			-- Send initial ammo state for all weapons
			for gunId, ammo in pairs(ammoInMagazine[p.UserId] or {}) do
				sendAmmoState(p, gunId, ammo, false)
			end
		end
		task.defer(checkRoundEnd)
	end,
}
