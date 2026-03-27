--[[
	CombatGrenades
	Grenade spawning, explosion visual, and damage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local GrenadeConfig = require(ReplicatedStorage.Shared.Modules.GrenadeConfig)
local GrenadeAngularResistance = require(ReplicatedStorage.Shared.Modules.GrenadeAngularResistance)
local CombatRemotes = require(script.Parent.CombatRemotes)

local GRENADES_FOLDER_NAME = "CombatGrenades"
local COLLISION_GROUP_GRENADES = "Grenades"
local GRENADE_TEMPLATE_NAME = "GrenadeVisual"

local function getGrenadesFolder()
	local folder = Workspace:FindFirstChild(GRENADES_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = GRENADES_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function getGrenadeRootPart(instance)
	if instance:IsA("Tool") then
		return instance:FindFirstChild("Handle") or instance:FindFirstChildWhichIsA("BasePart")
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	elseif instance:IsA("BasePart") then
		return instance
	end
	return nil
end

local function doExplosionDamage(state, center, radius, damage, throwerUserId)
	local radiusSq = radius * radius
	local throwerTeam = throwerUserId and state.playerTeams[throwerUserId]
	for _, p in ipairs(state.currentRoundPlayers) do
		if p and p.Parent and p.Character then
			if not (throwerTeam and throwerTeam == (state.playerTeams[p.UserId] or "")) then
				local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
				local root = p.Character:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and root then
					local offset = root.Position - center
					local distSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
					if distSq <= radiusSq then
						local dist = math.sqrt(distSq)
						local falloff = dist > 0 and math.max(0, 1 - dist / radius) or 1
						local dmg = math.ceil(damage * falloff)
						if dmg > 0 then
							humanoid:SetAttribute("LastDamagerUserId", throwerUserId or 0)
							humanoid:TakeDamage(dmg)
							CombatRemotes.notifyAttackerDamage(state, throwerUserId, p.Character, dmg)
						end
					end
				end
			end
		end
	end
end

local function spawnGrenade(state, thrower, startPos, direction)
	local cfg = GrenadeConfig
	local dir = direction.Unit
	local throwDir = (Vector3.new(dir.X, 0, dir.Z) * (1 - cfg.throwArcUp) + Vector3.new(0, cfg.throwArcUp, 0)).Unit
	local velocity = throwDir * cfg.throwSpeed

	local grenade
	local rootPart

	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local template = models3D and models3D:FindFirstChild(GRENADE_TEMPLATE_NAME)
	if template then
		grenade = template:Clone()
		rootPart = getGrenadeRootPart(grenade)
		if rootPart then
			if grenade:IsA("Model") and not grenade.PrimaryPart then
				grenade.PrimaryPart = rootPart
			end
			grenade.Parent = getGrenadesFolder()
			rootPart.CFrame = CFrame.new(startPos)
			rootPart.AssemblyLinearVelocity = velocity
			rootPart.Anchored = false
			rootPart.CanCollide = true
			rootPart.CollisionGroup = COLLISION_GROUP_GRENADES
			rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, cfg.restitution, 1, 1)
		else
			grenade:Destroy()
			grenade = nil
		end
	end

	if not grenade or not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "Grenade"
		rootPart.Size = cfg.size
		rootPart.Color = cfg.color
		rootPart.Material = cfg.material
		rootPart.Shape = Enum.PartType.Ball
		rootPart.Anchored = false
		rootPart.CanCollide = true
		rootPart.CFrame = CFrame.new(startPos)
		rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, cfg.restitution, 1, 1)
		rootPart.AssemblyLinearVelocity = velocity
		rootPart.CollisionGroup = COLLISION_GROUP_GRENADES
		rootPart.Parent = getGrenadesFolder()
		grenade = rootPart
	end

	grenade:SetAttribute("ThrowerUserId", thrower.UserId)

	GrenadeAngularResistance.attach(rootPart, cfg)

	task.delay(cfg.fuseTime, function()
		if not grenade or not grenade.Parent then
			return
		end
		local center = rootPart.Position
		grenade:Destroy()

		if cfg.explosionSoundId then
			local soundAnchor = Instance.new("Part")
			soundAnchor.Name = "ExplosionSoundAnchor"
			soundAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
			soundAnchor.Transparency = 1
			soundAnchor.CanCollide = false
			soundAnchor.Anchored = true
			soundAnchor.CFrame = CFrame.new(center)
			soundAnchor.Parent = getGrenadesFolder()
			local sound = Instance.new("Sound")
			sound.SoundId = cfg.explosionSoundId
			sound.Volume = 1
			sound.RollOffMode = Enum.RollOffMode.Inverse
			sound.RollOffMaxDistance = 300
			sound.RollOffMinDistance = 10
			sound.Parent = soundAnchor
			sound:Play()
			sound.Ended:Connect(function()
				soundAnchor:Destroy()
			end)
		end

		local explosionPart = Instance.new("Part")
		explosionPart.Name = "Explosion"
		explosionPart.Shape = Enum.PartType.Ball
		explosionPart.Size = Vector3.new(1, 1, 1)
		explosionPart.Anchored = true
		explosionPart.CanCollide = false
		explosionPart.Material = Enum.Material.Neon
		explosionPart.Color = Color3.fromRGB(255, 120, 40)
		explosionPart.CFrame = CFrame.new(center)
		explosionPart.Transparency = 0.3
		explosionPart.Parent = getGrenadesFolder()
		local startSize = 1
		local endSize = cfg.radius * 2
		local duration = 0.2
		local elapsed = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed = elapsed + dt
			if elapsed >= duration then
				conn:Disconnect()
				explosionPart:Destroy()
				return
			end
			local t = elapsed / duration
			local s = startSize + (endSize - startSize) * t
			explosionPart.Size = Vector3.new(s, s, s)
			explosionPart.Transparency = 0.3 + 0.6 * t
		end)

		doExplosionDamage(state, center, cfg.radius, cfg.damage, thrower and thrower.UserId or nil)
	end)
end

return {
	getGrenadesFolder = getGrenadesFolder,
	spawnGrenade = spawnGrenade,
}
