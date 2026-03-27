--[[
	CombatRockets
	Rocket projectile: straight-line travel. Explodes on hitting any wall (including BulletBlocker).
	Server-authoritative.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
local CombatRemotes = require(script.Parent.CombatRemotes)

local ROCKETS_FOLDER_NAME = "CombatRockets"
local PROJECTILE_TEMPLATE_NAME = "RocketLauncherProjectile"

local function getRocketsFolder()
	local folder = Workspace:FindFirstChild(ROCKETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ROCKETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function getProjectileRootPart(instance)
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

local function triggerExplosion(state, center, thrower)
	local cfg = RocketLauncherConfig
	local folder = getRocketsFolder()

	if cfg.explosionSoundId then
		local soundAnchor = Instance.new("Part")
		soundAnchor.Name = "RocketExplosionSoundAnchor"
		soundAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
		soundAnchor.Transparency = 1
		soundAnchor.CanCollide = false
		soundAnchor.Anchored = true
		soundAnchor.CFrame = CFrame.new(center)
		soundAnchor.Parent = folder
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
	explosionPart.Name = "RocketExplosion"
	explosionPart.Shape = Enum.PartType.Ball
	explosionPart.Size = Vector3.new(1, 1, 1)
	explosionPart.Anchored = true
	explosionPart.CanCollide = false
	explosionPart.Material = Enum.Material.Neon
	explosionPart.Color = Color3.fromRGB(255, 80, 20)
	explosionPart.CFrame = CFrame.new(center)
	explosionPart.Transparency = 0.3
	explosionPart.Parent = folder
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
end

local function spawnRocket(state, thrower, startPos, direction)
	local cfg = RocketLauncherConfig
	local dir = direction.Unit
	local folder = getRocketsFolder()

	local rocket
	local rootPart
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local template = models3D and models3D:FindFirstChild(PROJECTILE_TEMPLATE_NAME)
	if template then
		rocket = template:Clone()
		rootPart = getProjectileRootPart(rocket)
		if rootPart then
			if rocket:IsA("Model") and not rocket.PrimaryPart then
				rocket.PrimaryPart = rootPart
			end
			for _, descendant in ipairs(rocket:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
				end
			end
			rocket.Name = "Rocket"
			rocket.Parent = folder
			local scale = cfg.scale or 1
			if rocket:IsA("Model") and scale ~= 1 then
				rocket:ScaleTo(scale)
			end
			local initialCf = CFrame.lookAt(startPos, startPos + dir)
			if rocket:IsA("Model") then
				rocket:PivotTo(initialCf)
			else
				rootPart.CFrame = initialCf
			end
		else
			rocket:Destroy()
			rocket = nil
		end
	end

	if not rocket or not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "Rocket"
		rootPart.Size = cfg.size
		rootPart.Color = cfg.color
		rootPart.Material = cfg.material
		rootPart.Shape = Enum.PartType.Ball
		rootPart.Anchored = true
		rootPart.CanCollide = false
		rootPart.CFrame = CFrame.lookAt(startPos, startPos + dir)
		rootPart.Parent = folder
		rocket = rootPart
	end

	local params = RaycastParams.new()
	local filter = { folder }
	if thrower and thrower.Character then
		table.insert(filter, thrower.Character)
	end
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude

	local lastPos = startPos
	local speed = cfg.speed
	local fuseEndTime = os.clock() + cfg.fuseTime
	local conn

	local function setVisualCf(cf)
		if rocket:IsA("Model") then
			rocket:PivotTo(cf)
		else
			rocket.CFrame = cf
		end
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		if not rocket.Parent then
			conn:Disconnect()
			return
		end
		local move = dir * speed * dt
		local newPos = lastPos + move
		local result = Workspace:Raycast(lastPos, move + dir * 0.5, params)
		if result and result.Instance then
			conn:Disconnect()
			rocket:Destroy()
			triggerExplosion(state, result.Position, thrower)
			return
		end
		if os.clock() >= fuseEndTime then
			conn:Disconnect()
			rocket:Destroy()
			triggerExplosion(state, newPos, thrower)
			return
		end
		lastPos = newPos
		setVisualCf(CFrame.lookAt(newPos, newPos + dir))
	end)
end

return {
	getRocketsFolder = getRocketsFolder,
	spawnRocket = spawnRocket,
}
