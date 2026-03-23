--[[
	CombatService (server)
	Shooting (visible bullets), health, round end. Server-authoritative.
	Init() sets up remotes and handlers. StartRound(players, onRoundEnd) is called when arena round starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local TDMSpawnStrategy = require(script.Parent.TDMSpawnStrategy)

local CombatState = require(script.Parent.CombatState)
local CombatRemotes = require(script.Parent.CombatRemotes)
local CombatAmmo = require(script.Parent.CombatAmmo)
local CombatBullets = require(script.Parent.CombatBullets)
local CombatGrenades = require(script.Parent.CombatGrenades)
local CombatRockets = require(script.Parent.CombatRockets)
local CombatTDM = require(script.Parent.CombatTDM)
local WeaponInventoryServer = require(script.Parent.WeaponInventoryServer)

local COLLISION_GROUP_WALLS = "CombatWalls"
local COLLISION_GROUP_GRENADES = "Grenades"

local state = CombatState()

local function giveRocketLauncherTool(player)
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local template = models3D and models3D:FindFirstChild("RocketLauncherTool")
	if template and template:IsA("Tool") and player:FindFirstChild("Backpack") then
		local tool = template:Clone()
		tool.Name = "RocketLauncher"
		tool.Parent = player.Backpack
	end
end

local function setupWallCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_WALLS)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_GRENADES)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_WALLS, COLLISION_GROUP_GRENADES, false)
end

local function assignToWallGroup(instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = COLLISION_GROUP_WALLS
	elseif instance:IsA("Model") then
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = COLLISION_GROUP_WALLS
			end
		end
	end
end

local function setupBulletBlockerWalls()
	for _, instance in ipairs(CollectionService:GetTagged(CombatConfig.BULLET_BLOCKER_TAG)) do
		assignToWallGroup(instance)
	end
	CollectionService:GetInstanceAddedSignal(CombatConfig.BULLET_BLOCKER_TAG):Connect(assignToWallGroup)
end

local function bindHandlers()
	state.fireGunRE.OnServerEvent:Connect(function(player, aimDirection, gunId)
		if state.matchEnded then
			return
		end
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

		local last = state.lastFiredAt[uid] or 0
		if now - last < gun.fireRate then
			return
		end

		state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
		state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
		local ammo = state.ammoInMagazine[uid][gunId]
		if ammo == nil then
			state.ammoInMagazine[uid][gunId] = gun.magazineSize or 6
			ammo = state.ammoInMagazine[uid][gunId]
		end

		if state.reloadEndAt[uid][gunId] and now < state.reloadEndAt[uid][gunId] then
			CombatRemotes.sendAmmoState(state, player, gunId, ammo, true)
			return
		end

		if ammo <= 0 then
			if not state.reloadEndAt[uid][gunId] then
				state.reloadEndAt[uid][gunId] = now + (gun.reloadTime or 1.5)
			end
			CombatRemotes.sendAmmoState(state, player, gunId, 0, true)
			return
		end

		state.lastFiredAt[uid] = now
		state.ammoInMagazine[uid][gunId] = ammo - 1
		local newAmmo = state.ammoInMagazine[uid][gunId]

		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end
		local root = character.HumanoidRootPart
		local startPos = root.Position + aimDirection.Unit * 2
		local pelletCount = gun.pelletCount or 1
		local spreadDeg = gun.spreadDegrees or 0
		for _ = 1, pelletCount do
			local dir = aimDirection.Unit
			if spreadDeg > 0 and pelletCount > 1 then
				local angle = math.rad(spreadDeg * (math.random() * 2 - 1))
				local perp = Vector3.new(-dir.Z, 0, dir.X)
				dir = (dir * math.cos(angle) + perp * math.sin(angle)).Unit
				local angle2 = math.rad(spreadDeg * 0.5 * (math.random() * 2 - 1))
				dir = (dir * math.cos(angle2) + Vector3.new(0, 1, 0) * math.sin(angle2)).Unit
			end
			CombatBullets.spawnBullet(state, player, startPos, dir, gunId)
		end

		if newAmmo <= 0 then
			state.reloadEndAt[uid][gunId] = now + (gun.reloadTime or 1.5)
			CombatRemotes.sendAmmoState(state, player, gunId, 0, true)
		else
			CombatRemotes.sendAmmoState(state, player, gunId, newAmmo, false)
		end
	end)

	state.throwGrenadeRE.OnServerEvent:Connect(function(player, aimDirection)
		if state.matchEnded then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude < 0.01 then
			return
		end
		local uid = player.UserId
		local count = state.grenadeCount[uid] or 0
		if count <= 0 then
			return
		end
		state.grenadeCount[uid] = count - 1
		local regenTimes = state.grenadeRegenTimes[uid]
		if not regenTimes then
			regenTimes = {}
			state.grenadeRegenTimes[uid] = regenTimes
		end
		table.insert(regenTimes, os.clock() + (GrenadeConfig.regenerationTime or 5))
		table.sort(regenTimes)
		CombatRemotes.sendGrenadeState(state, player, state.grenadeCount[uid])
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end
		local startPos = character.HumanoidRootPart.Position + aimDirection.Unit * 2
		CombatGrenades.spawnGrenade(state, player, startPos, aimDirection)
	end)

	state.throwRocketRE.OnServerEvent:Connect(function(player, aimDirection)
		if state.matchEnded then
			return
		end
		if not aimDirection or typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude < 0.01 then
			return
		end
		local uid = player.UserId
		local count = state.rocketCount[uid] or 0
		if count <= 0 then
			return
		end
		state.rocketCount[uid] = count - 1
		local newCount = state.rocketCount[uid]
		CombatRemotes.sendRocketState(state, player, newCount)
		if newCount <= 0 then
			WeaponInventoryServer.removeWeapon(player, "RocketLauncher")
			local rl = player.Backpack and player.Backpack:FindFirstChild("RocketLauncher")
			if rl then
				rl:Destroy()
			end
			if player.Character then
				rl = player.Character:FindFirstChild("RocketLauncher")
				if rl then
					rl:Destroy()
				end
			end
		end
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end
		local startPos = character.HumanoidRootPart.Position + aimDirection.Unit * 2
		CombatRockets.spawnRocket(state, player, startPos, aimDirection)
	end)
end

return {
	Init = function()
		state = CombatState()
		setupWallCollisionGroups()
		setupBulletBlockerWalls()
		CombatRemotes.ensureRemotes(state)
		bindHandlers()
		CombatAmmo.startReloadLoop(state)
	end,

	StartRound = function(players, onRoundEnd)
		state.onRoundEndCallback = onRoundEnd
		state.matchEnded = false
		state.currentRoundPlayers = {}
		state.playerTeams = {}
		state.teamKills = { Blue = 0, Red = 0 }
		state.playerKills = {}
		state.playerDeaths = {}
		for i, p in ipairs(players) do
			state.currentRoundPlayers[#state.currentRoundPlayers + 1] = p
			state.playerTeams[p.UserId] = (i % 2 == 1) and "Blue" or "Red"
			state.playerKills[p.UserId] = 0
			state.playerDeaths[p.UserId] = 0
			CombatAmmo.initPlayerAmmo(state, p.UserId)
			CombatAmmo.initPlayerGrenades(state, p.UserId)
			local weapons = WeaponInventoryServer.getWeapons(p)
			for _, w in ipairs(weapons) do
				if w == "RocketLauncher" then
					CombatAmmo.initPlayerRockets(state, p.UserId)
					giveRocketLauncherTool(p)
					break
				end
			end
			WeaponInventoryServer.sendToPlayer(p)
			local cf = TDMSpawnStrategy.getSpawnCFrame(p, CombatTDM.getTDMContext(state))
			local character = p.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				character.HumanoidRootPart.CFrame = cf
			end
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.MaxHealth = CombatConfig.DEFAULT_HEALTH
					humanoid.Health = CombatConfig.DEFAULT_HEALTH
					state.diedConnections[p.UserId] = humanoid.Died:Connect(function()
						CombatTDM.onPlayerDied(state, p)
					end)
				end
			end
			local conn = p.CharacterAdded:Connect(function()
				local inv = WeaponInventoryServer.getWeapons(p)
				for _, w in ipairs(inv) do
					if w == "RocketLauncher" then
						task.defer(function()
							giveRocketLauncherTool(p)
						end)
						break
					end
				end
			end)
			state.characterAddedConnections[p.UserId] = conn
			for gunId, ammo in pairs(state.ammoInMagazine[p.UserId] or {}) do
				CombatRemotes.sendAmmoState(state, p, gunId, ammo, false)
			end
		CombatRemotes.sendGrenadeState(state, p, state.grenadeCount[p.UserId] or 0)
		if state.rocketCount[p.UserId] then
			CombatRemotes.sendRocketState(state, p, state.rocketCount[p.UserId])
		end
	end
	CombatRemotes.broadcastTeamScore(state)
	for _, p in ipairs(players) do
		CombatRemotes.sendTeamAssignment(state, p, state.playerTeams[p.UserId] or "Blue", state.playerTeams)
	end
end,

	InitRocketsForPlayer = function(player)
		CombatAmmo.initPlayerRockets(state, player.UserId)
		CombatRemotes.sendRocketState(state, player, state.rocketCount[player.UserId] or 0)
	end,

	GiveRocketLauncherTool = giveRocketLauncherTool,
}
