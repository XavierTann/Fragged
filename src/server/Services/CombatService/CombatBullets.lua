--[[
	CombatBullets
	Bullet spawning and raycast collision.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local CombatRemotes = require(script.Parent.CombatRemotes)

local BULLETS_FOLDER_NAME = "CombatBullets"

local function getBulletsFolder()
	local folder = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = BULLETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local TRACER_TRAIL_LENGTH = 4 -- studs behind bullet

local function reflectVector(incoming, normal)
	return incoming - 2 * incoming:Dot(normal) * normal
end

local function spawnBullet(state, shooter, startPos, direction, gunId, bulletColorOverride)
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local effectiveColor = bulletColorOverride or gun.bulletColor
	local dir = direction.Unit
	local shooterUserId = shooter.UserId
	local bullet = Instance.new("Part")
	bullet.Name = "Bullet"
	bullet.Size = gun.bulletSize
	bullet.Color = effectiveColor
	bullet.Material = Enum.Material.Neon
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CFrame = CFrame.lookAt(startPos, startPos + dir)
	bullet:SetAttribute("ShooterUserId", shooterUserId)
	bullet.Parent = getBulletsFolder()

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, -TRACER_TRAIL_LENGTH)
	att0.Parent = bullet
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, gun.bulletSize.Z / 2)
	att1.Parent = bullet
	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(effectiveColor)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = gun.bulletSize.X * 1.5
	beam.Width1 = gun.bulletSize.X * 0.5
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = bullet

	local speed = gun.bulletSpeed
	local lastPos = startPos
	local maxRicochets = gun.maxRicochets or 0
	local bounceCount = 0

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
					local shooterTeam = state.playerTeams[shooterUserId]
					local hitTeam = state.playerTeams[hitPlayer.UserId]
					if shooterTeam and hitTeam and shooterTeam ~= hitTeam then
						conn:Disconnect()
						humanoid:SetAttribute("LastDamagerUserId", shooterUserId)
						humanoid:TakeDamage(gun.damage)
						CombatRemotes.notifyAttackerDamage(state, shooterUserId, model, gun.damage)
						bullet:Destroy()
						return
					end
				end
			end

			if bounceCount < maxRicochets then
				bounceCount = bounceCount + 1
				dir = reflectVector(dir, result.Normal).Unit
				speed = speed * 0.6
				lastPos = result.Position + result.Normal * 0.1
				bullet.Size = bullet.Size * 1.4
				beam.Width0 = bullet.Size.X * 1.5
				beam.Width1 = bullet.Size.X * 0.5
				bullet.CFrame = CFrame.lookAt(lastPos, lastPos + dir)
				return
			end

			conn:Disconnect()
			bullet:Destroy()
			return
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

local function spawnVisualTracer(shooterUserId, startPos, direction, gunId, roundPlayers, bulletColorOverride)
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local effectiveColor = bulletColorOverride or gun.bulletColor
	local dir = direction.Unit
	local bullet = Instance.new("Part")
	bullet.Name = "Bullet"
	bullet.Size = gun.bulletSize
	bullet.Color = effectiveColor
	bullet.Material = Enum.Material.Neon
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CFrame = CFrame.lookAt(startPos, startPos + dir)
	bullet:SetAttribute("ShooterUserId", shooterUserId)
	bullet.Parent = getBulletsFolder()

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, -TRACER_TRAIL_LENGTH)
	att0.Parent = bullet
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, gun.bulletSize.Z / 2)
	att1.Parent = bullet
	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(effectiveColor)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = gun.bulletSize.X * 1.5
	beam.Width1 = gun.bulletSize.X * 0.5
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = bullet

	local speed = gun.bulletSpeed
	local lastPos = startPos
	local params = RaycastParams.new()
	local filter = { bullet, getBulletsFolder() }
	for _, p in ipairs(roundPlayers or {}) do
		if p.Character then
			filter[#filter + 1] = p.Character
		end
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
		if result then
			conn:Disconnect()
			bullet:Destroy()
			return
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

return {
	getBulletsFolder = getBulletsFolder,
	spawnBullet = spawnBullet,
	spawnVisualTracer = spawnVisualTracer,
}
