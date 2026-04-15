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

local CombatRemotes = require(script.Parent.CombatRemotes)
local CombatBullets = require(script.Parent.CombatBullets)

local GUN_ID = "HeliosThread"

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

-- Returns beam length used for VFX (studs along aim from origin), applies damage to enemies along path.
local function castLaserAndDamage(state, shooter, origin, dirUnit, damage)
	local maxRange = HeliosLaserConfig.MAX_RANGE
	local radius = HeliosLaserConfig.BEAM_RADIUS
	local step = HeliosLaserConfig.CAST_STEP
	local params = buildLaserRaycastParams(shooter.Character)
	local shooterTeam = state.playerTeams[shooter.UserId]
	local damagedUserIds = {}
	local pos = origin
	local traveled = 0
	local beamEndDist = maxRange
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
				beamEndDist = math.min(beamEndDist, (result.Position - origin).Magnitude)
				break
			else
				local advance = math.max(0.1, (result.Position - pos).Magnitude + 0.05)
				pos = pos + dirUnit * advance
				traveled += advance
			end
		end
	end

	beamEndDist = math.clamp(beamEndDist, 0, maxRange)
	return beamEndDist
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

local function sendHeliosCommitRejected(state, player, err)
	if not state or not player or not err then
		return
	end
	local resetRate = err == "BadOrigin" or err == "BadDirection" or err == "InvalidArgs" or err == "NotEquipped" or err == "WeaponNotOwned"
	CombatRemotes.sendFireGunRejected(state, player, err, "HeliosThread", resetRate)
	local uid = player.UserId
	local gun = GunsConfig[GUN_ID]
	state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
	state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
	local ammo = state.ammoInMagazine[uid][GUN_ID]
	if ammo == nil then
		ammo = gun.magazineSize or 6
		state.ammoInMagazine[uid][GUN_ID] = ammo
	end
	local now = os.clock()
	local isReloading = state.reloadEndAt[uid][GUN_ID] ~= nil and now < state.reloadEndAt[uid][GUN_ID]
	CombatRemotes.sendAmmoState(state, player, GUN_ID, ammo, isReloading)
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

-- Commit on release: validate, lock movement, after CHARGE_DURATION fire beam (aim fixed from this call).
function CombatHeliosLaser.commitChargedBeamAfterRelease(state, player, shotOrigin, aimUnit, validateOriginFn, playerOwnsGunFn)
	if not state or state.matchEnded or not player or not player.Parent then
		return false, "NoState"
	end
	local uid = player.UserId

	state.heliosMovementSave = state.heliosMovementSave or {}
	if state.heliosMovementSave[uid] then
		return false, "Busy"
	end

	if not playerOwnsGunFn(player, GUN_ID) then
		return false, "WeaponNotOwned"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return false, "NoCharacter"
	end
	if not characterHasGunEquipped(character, GUN_ID) then
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

	local gun = GunsConfig[GUN_ID]
	local now = os.clock()
	local last = state.lastFiredAt[uid] or 0
	if now - last < (gun.fireRate or 0.08) - 0.02 then
		return false, "Cooldown"
	end

	state.reloadEndAt[uid] = state.reloadEndAt[uid] or {}
	if state.reloadEndAt[uid][GUN_ID] and now < state.reloadEndAt[uid][GUN_ID] then
		return false, "Reloading"
	end

	state.ammoInMagazine[uid] = state.ammoInMagazine[uid] or {}
	local ammo = state.ammoInMagazine[uid][GUN_ID]
	if ammo == nil then
		ammo = gun.magazineSize or 6
		state.ammoInMagazine[uid][GUN_ID] = ammo
	end
	if ammo <= 0 then
		if not state.reloadEndAt[uid][GUN_ID] then
			state.reloadEndAt[uid][GUN_ID] = now + (gun.reloadTime or 2.4)
		end
		CombatRemotes.sendAmmoState(state, player, GUN_ID, 0, true)
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

	task.delay(HeliosLaserConfig.CHARGE_DURATION, function()
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
		if not characterHasGunEquipped(char2, GUN_ID) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "NotEquipped")
			return
		end
		if not playerOwnsGunFn(player, GUN_ID) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "WeaponNotOwned")
			return
		end

		local now2 = os.clock()
		local last2 = state.lastFiredAt[uid] or 0
		if now2 - last2 < (gun.fireRate or 0.08) - 0.02 then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "Cooldown")
			return
		end

		if state.reloadEndAt[uid][GUN_ID] and now2 < state.reloadEndAt[uid][GUN_ID] then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "Reloading")
			return
		end

		local ammo2 = state.ammoInMagazine[uid][GUN_ID]
		if ammo2 == nil or ammo2 <= 0 then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "EmptyMag")
			return
		end

		if not validateOriginFn(root2.Position, lockedShotOrigin, lockedAimUnit) then
			unfreezeHeliosMovement(state, player)
			sendHeliosCommitRejected(state, player, "BadOrigin")
			return
		end

		local originForward = CombatConfig.SHOT_ORIGIN_FORWARD_STUDS or 0
		local startPos = root2.Position + lockedAimUnit * originForward

		state.lastFiredAt[uid] = now2
		state.ammoInMagazine[uid][GUN_ID] = ammo2 - 1
		local newAmmo = state.ammoInMagazine[uid][GUN_ID]

		local beamLen = castLaserAndDamage(state, player, startPos, lockedAimUnit, gun.damage)
		CombatRemotes.broadcastHeliosLaserVFX(state, uid, startPos, lockedAimUnit, beamLen)
		CombatRemotes.broadcastGunshotSpatial(state, uid, GUN_ID)

		if newAmmo <= 0 then
			state.reloadEndAt[uid][GUN_ID] = now2 + (gun.reloadTime or 2.4)
			CombatRemotes.sendAmmoState(state, player, GUN_ID, 0, true)
		else
			CombatRemotes.sendAmmoState(state, player, GUN_ID, newAmmo, false)
		end

		unfreezeHeliosMovement(state, player)
	end)

	return true, nil
end

return CombatHeliosLaser
