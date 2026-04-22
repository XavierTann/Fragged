--[[
	Server: Helios Thread — release commits aim, movement locks for CHARGE_DURATION, then beam + damage + VFX.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Shared.Modules.CombatConfig)
local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local HeliosLaserConfig = require(ReplicatedStorage.Shared.Modules.HeliosLaserConfig)
local HeliosBeamColumns = require(ReplicatedStorage.Shared.Modules.HeliosBeamColumns)
local CombatRemotes = require(script.Parent.CombatRemotes)
local CombatBullets = require(script.Parent.CombatBullets)

local function characterHasGunEquipped(character, gunId)
	local tool = character and character:FindFirstChild(gunId)
	return tool ~= nil and tool:IsA("Tool")
end

local function buildLaserRaycastParams(shooterCharacter)
	local filter = { CombatBullets.getBulletsFolder() }
	if shooterCharacter then
		filter[#filter + 1] = shooterCharacter
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true
	return params
end

local function isBulletBlocker(instance)
	if not instance then
		return false
	end
	return CollectionService:HasTag(instance, CombatConfig.BULLET_BLOCKER_TAG)
end

local function modelFromInstance(inst)
	if not inst then
		return nil
	end
	return inst:FindFirstAncestorOfClass("Model")
end

-- One lateral column: spherecast sweep along dirUnit; each column clips at its own wall.
local function sweepHeliosColumn(
	state,
	shooter,
	shooterTeam,
	columnOrigin,
	dirUnit,
	damage,
	maxRange,
	radius,
	step,
	params,
	damagedUserIds
)
	local pos = columnOrigin
	local traveled = 0
	local wallAxialFromColumnStart = maxRange
	local safety = 0

	while traveled < maxRange - 0.01 and safety < 80 do
		safety += 1
		local seg = math.min(step, maxRange - traveled)
		local castDir = dirUnit * seg
		local result = Workspace:Spherecast(pos, radius, castDir, params)
		if not result then
			pos = pos + castDir
			traveled += seg
		else
			local inst = result.Instance
			local model = modelFromInstance(inst)
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			local hitPlayer = humanoid and Players:GetPlayerFromCharacter(model)
			if hitPlayer and hitPlayer.UserId ~= shooter.UserId and humanoid then
				local hitTeam = state.playerTeams[hitPlayer.UserId]
				if shooterTeam and hitTeam and shooterTeam ~= hitTeam and not damagedUserIds[hitPlayer.UserId] then
					damagedUserIds[hitPlayer.UserId] = true
					if humanoid.Health > 0 then
						humanoid:SetAttribute("LastDamagerUserId", shooter.UserId)
						humanoid:TakeDamage(damage)
						CombatRemotes.notifyAttackerDamage(state, shooter.UserId, model, damage)
					end
				end
				local advance = math.max(0.15, (result.Position - pos).Magnitude + 0.2)
				pos = pos + dirUnit * advance
				traveled += advance
			elseif hitPlayer and humanoid then
				local advance = math.max(0.15, (result.Position - pos).Magnitude + 0.2)
				pos = pos + dirUnit * advance
				traveled += advance
			elseif isBulletBlocker(inst) or (inst and inst.CanCollide) then
				local axial = (result.Position - columnOrigin):Dot(dirUnit)
				wallAxialFromColumnStart = math.min(wallAxialFromColumnStart, math.clamp(axial, 0, maxRange))
				break
			else
				local advance = math.max(0.1, (result.Position - pos).Magnitude + 0.05)
				pos = pos + dirUnit * advance
				traveled += advance
			end
		end
	end

	return math.clamp(wallAxialFromColumnStart, 0.05, maxRange)
end

-- Parallel columns across beam width; returns lateral offsets + per-column length for VFX (each clips at its own wall).
local function castLaserAndDamage(state, shooter, origin, dirUnit, damage)
	local maxRange = HeliosLaserConfig.MAX_RANGE
	local radius = HeliosLaserConfig.BEAM_RADIUS
	local step = HeliosLaserConfig.CAST_STEP
	local params = buildLaserRaycastParams(shooter.Character)
	local shooterTeam = state.playerTeams[shooter.UserId]
	local damagedUserIds = {}
	local n = math.clamp(HeliosLaserConfig.LASER_COLUMN_COUNT or 7, 1, 15)
	local spreadFrac = HeliosLaserConfig.COLUMN_SPREAD_FRACTION or 0.92
	local right = HeliosBeamColumns.getRightUnitXZ(dirUnit)
	local offsets = HeliosBeamColumns.getColumnOffsets(n, radius, spreadFrac)
	local lengths = table.create(n)
	for i = 1, n do
		local colOrigin = origin + right * offsets[i]
		lengths[i] = sweepHeliosColumn(
			state,
			shooter,
			shooterTeam,
			colOrigin,
			dirUnit,
			damage,
			maxRange,
			radius,
			step,
			params,
			damagedUserIds
		)
	end
	return offsets, lengths
end

local function unfreezeHeliosMovement(state, player)
	if not state or not player then
		return
	end
	local uid = player.UserId
	local save = state.heliosMovementSave and state.heliosMovementSave[uid]
	if not save then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and save.WalkSpeed ~= nil then
		hum.WalkSpeed = save.WalkSpeed
	end
	state.heliosMovementSave[uid] = nil
end

local function freezeHeliosMovement(state, player)
	if not state or not player then
		return false
	end
	local uid = player.UserId
	state.heliosMovementSave = state.heliosMovementSave or {}
	if state.heliosMovementSave[uid] then
		return false
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	-- Only zero horizontal speed: player can still aim (AutoRotate) and jump; sprint/run stops for the charge window.
	state.heliosMovementSave[uid] = {
		WalkSpeed = hum.WalkSpeed,
	}
	hum.WalkSpeed = 0
	return true
end

local CombatHeliosLaser = {}

local function sendHeliosCommitRejected(state, player, err, laserGunId)
	if not state or not player or not err or not laserGunId then
		return
	end
	local resetRate = err == "BadOrigin" or err == "BadDirection" or err == "InvalidArgs" or err == "NotEquipped" or err == "WeaponNotOwned"
	CombatRemotes.sendFireGunRejected(state, player, err, laserGunId, resetRate)
	local uid = player.UserId
	local gun = GunsConfig[laserGunId]
	if not gun then
		return
	end
	state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
	state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
	local ammo = state.ammoInMagazine[uid][laserGunId]
	if ammo == nil then
		ammo = gun.magazineSize or 6
		state.ammoInMagazine[uid][laserGunId] = ammo
	end
	local now = os.clock()
	local isReloading = state.reloadEndAt[uid][laserGunId] ~= nil and now < state.reloadEndAt[uid][laserGunId]
	CombatRemotes.sendAmmoState(state, player, laserGunId, ammo, isReloading)
end

function CombatHeliosLaser.cancelActiveCommitForPlayer(state, player)
	if not state or not player then
		return
	end
	local uid = player.UserId
	state.heliosCommitSeq = state.heliosCommitSeq or {}
	state.heliosCommitSeq[uid] = (state.heliosCommitSeq[uid] or 0) + 1
	unfreezeHeliosMovement(state, player)
end

-- Commit on release: validate, lock movement, after charge delay fire beam (Helios Thread charged laser).
function CombatHeliosLaser.commitChargedBeamAfterRelease(state, player, laserGunId, shotOrigin, aimUnit, validateOriginFn, playerOwnsGunFn, beamColorOverride)
	if not state or state.matchEnded or not player or not player.Parent then
		return false, "NoState"
	end
	local uid = player.UserId
	local gun = GunsConfig[laserGunId]
	if not gun then
		return false, "InvalidWeapon"
	end

	state.heliosMovementSave = state.heliosMovementSave or {}
	if state.heliosMovementSave[uid] then
		return false, "Busy"
	end

	if not playerOwnsGunFn(player, laserGunId) then
		return false, "WeaponNotOwned"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return false, "NoCharacter"
	end
	if not characterHasGunEquipped(character, laserGunId) then
		return false, "NotEquipped"
	end

	if typeof(shotOrigin) ~= "Vector3" or typeof(aimUnit) ~= "Vector3" then
		return false, "InvalidArgs"
	end
	if aimUnit.Magnitude < 0.99 then
		return false, "BadDirection"
	end
	if not validateOriginFn(root.Position, shotOrigin, aimUnit) then
		return false, "BadOrigin"
	end

	local now = os.clock()
	local last = state.lastFiredAt[uid] or 0
	if now - last < (gun.fireRate or 0.08) - 0.02 then
		return false, "Cooldown"
	end

	state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
	if state.reloadEndAt[uid][laserGunId] and now < state.reloadEndAt[uid][laserGunId] then
		return false, "Reloading"
	end

	state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
	local ammo = state.ammoInMagazine[uid][laserGunId]
	if ammo == nil then
		ammo = gun.magazineSize or 6
		state.ammoInMagazine[uid][laserGunId] = ammo
	end
	if ammo <= 0 then
		if not state.reloadEndAt[uid][laserGunId] then
			state.reloadEndAt[uid][laserGunId] = now + (gun.reloadTime or 2.4)
		end
		CombatRemotes.sendAmmoState(state, player, laserGunId, 0, true)
		return false, "EmptyMag"
	end

	if not freezeHeliosMovement(state, player) then
		return false, "NoCharacter"
	end

	state.heliosCommitSeq = state.heliosCommitSeq or {}
	state.heliosCommitSeq[uid] = (state.heliosCommitSeq[uid] or 0) + 1
	local mySeq = state.heliosCommitSeq[uid]

	local lockedAimUnit = aimUnit.Unit
	local lockedShotOrigin = shotOrigin
	local chargeDelay = HeliosLaserConfig.CHARGE_DURATION

	task.delay(chargeDelay, function()
		if not player.Parent then
			unfreezeHeliosMovement(state, player)
			return
		end
		if not state or state.matchEnded then
			unfreezeHeliosMovement(state, player)
			return
		end
		if (state.heliosCommitSeq[uid] or 0) ~= mySeq then
			return
		end

		local char2 = player.Character
		local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
		local root2 = char2 and char2:FindFirstChild("HumanoidRootPart")
		if not char2 or not hum2 or hum2.Health <= 0 or not root2 then
			unfreezeHeliosMovement(state, player)
			return
		end
		if not characterHasGunEquipped(char2, laserGunId) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "NotEquipped", laserGunId)
			return
		end
		if not playerOwnsGunFn(player, laserGunId) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "WeaponNotOwned", laserGunId)
			return
		end

		local now2 = os.clock()
		local last2 = state.lastFiredAt[uid] or 0
		if now2 - last2 < (gun.fireRate or 0.08) - 0.02 then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "Cooldown", laserGunId)
			return
		end

		if state.reloadEndAt[uid][laserGunId] and now2 < state.reloadEndAt[uid][laserGunId] then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "Reloading", laserGunId)
			return
		end

		local ammo2 = state.ammoInMagazine[uid][laserGunId]
		if ammo2 == nil or ammo2 <= 0 then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "EmptyMag", laserGunId)
			return
		end

		if not validateOriginFn(root2.Position, lockedShotOrigin, lockedAimUnit) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "BadOrigin", laserGunId)
			return
		end

		local originForward = CombatConfig.SHOT_ORIGIN_FORWARD_STUDS or 0
		local startPos = root2.Position + lockedAimUnit * originForward

		state.lastFiredAt[uid] = now2
		state.ammoInMagazine[uid][laserGunId] = ammo2 - 1
		local newAmmo = state.ammoInMagazine[uid][laserGunId]

		local colOffsets, colLengths = castLaserAndDamage(state, player, startPos, lockedAimUnit, gun.damage)
		CombatRemotes.broadcastHeliosLaserVFX(state, uid, startPos, lockedAimUnit, colOffsets, colLengths, beamColorOverride)
		CombatRemotes.broadcastGunshotSpatial(state, uid, laserGunId)

		if newAmmo <= 0 then
			state.reloadEndAt[uid][laserGunId] = now2 + (gun.reloadTime or 2.4)
			CombatRemotes.sendAmmoState(state, player, laserGunId, 0, true)
		else
			CombatRemotes.sendAmmoState(state, player, laserGunId, newAmmo, false)
		end

		unfreezeHeliosMovement(state, player)
	end)

	return true, nil
end

return CombatHeliosLaser
