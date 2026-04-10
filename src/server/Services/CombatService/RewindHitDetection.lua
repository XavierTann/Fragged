--[[
	RewindHitDetection
	Catch-up projectile simulation against historical player positions for lag compensation.
	Does NOT physically move characters — uses manual segment-sphere intersection against
	the HistoryBuffer to test hits during the rewind window, then returns the caught-up
	bullet position for normal live simulation if no hit occurred.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunsConfig = require(ReplicatedStorage.Shared.Modules.GunsConfig)
local LagCompConfig = require(ReplicatedStorage.Shared.Modules.LagCompensationConfig)

local RewindHitDetection = {}

local function segmentSphereIntersect(segStart: Vector3, segEnd: Vector3, center: Vector3, radius: number): number?
	local d = segEnd - segStart
	local f = segStart - center
	local a = d:Dot(d)
	if a < 1e-8 then
		return nil
	end
	local b = 2 * f:Dot(d)
	local c = f:Dot(f) - radius * radius
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local sqrtDisc = math.sqrt(disc)
	local t1 = (-b - sqrtDisc) / (2 * a)
	if t1 >= 0 and t1 <= 1 then
		return t1
	end
	local t2 = (-b + sqrtDisc) / (2 * a)
	if t2 >= 0 and t2 <= 1 then
		return t2
	end
	if t1 < 0 and t2 > 1 then
		return 0
	end
	return nil
end

local function buildWorldRaycastParams(roundPlayers: { Player })
	local filter = {}
	for _, player in ipairs(roundPlayers) do
		if player.Character then
			filter[#filter + 1] = player.Character
		end
	end
	local bulletsFolder = Workspace:FindFirstChild("CombatBullets")
	if bulletsFolder then
		filter[#filter + 1] = bulletsFolder
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = filter
	params.FilterType = Enum.RaycastFilterType.Exclude
	return params
end

--[[
	Run the catch-up simulation from fireTime to currentTime.

	params:
		startPos          : Vector3   — muzzle position at fire time
		direction         : Vector3   — aim unit vector
		gunId             : string    — key into GunsConfig
		fireTime          : number    — estimated server time when client fired
		currentTime       : number    — server os.clock() now
		historyBuffer     : HistoryBuffer
		shooterUserId     : number
		roundPlayers      : { Player }
		playerTeams       : { [number]: string }
		shooterViewDelay  : number?   — extra offset (seconds) to shift enemy history lookups
		                                back, approximating the shooter's screen delay (≈ one-way ping).
		                                When set, enemy positions are sampled at (simTime - viewDelay)
		                                instead of simTime, matching what the shooter actually saw.

	Returns:
		hitResult : { hitPlayer: Player, hitPosition: Vector3, hitTime: number,
		              historicalTargetPos: Vector3 } | nil
		continuePos : Vector3 | nil   — position to spawn the live bullet (nil = bullet died on geometry)
]]
function RewindHitDetection.catchUpSimulate(params)
	local startPos = params.startPos
	local direction = params.direction.Unit
	local gunId = params.gunId
	local fireTime = params.fireTime
	local currentTime = params.currentTime
	local historyBuffer = params.historyBuffer
	local shooterUserId = params.shooterUserId
	local roundPlayers = params.roundPlayers
	local playerTeams = params.playerTeams
	local viewDelay = params.shooterViewDelay or 0

	local shooterTeam = playerTeams[shooterUserId]
	local gun = GunsConfig[gunId] or GunsConfig.Rifle
	local speed = gun.bulletSpeed
	local stepDt = LagCompConfig.CATCH_UP_STEP_SECONDS
	local hitRadius = LagCompConfig.PLAYER_HITBOX_RADIUS

	local elapsed = currentTime - fireTime
	if elapsed <= 0 then
		return nil, startPos
	end

	local worldParams = buildWorldRaycastParams(roundPlayers)
	local pos = startPos
	local simTime = fireTime
	local stepsNeeded = math.ceil(elapsed / stepDt)

	local debugLog = LagCompConfig.DEBUG_LOGGING

	for step = 1, stepsNeeded do
		local dt = math.min(stepDt, fireTime + elapsed - simTime)
		if dt <= 1e-6 then
			break
		end

		local moveVec = direction * speed * dt
		local newPos = pos + moveVec
		simTime = simTime + dt

		local worldHit = Workspace:Raycast(pos, moveVec, worldParams)
		local worldT = nil
		if worldHit then
			local dist = (worldHit.Position - pos).Magnitude
			local moveMag = moveVec.Magnitude
			worldT = if moveMag > 1e-6 then dist / moveMag else 0
		end

		local closestT = 2
		local closestPlayer = nil
		local closestHistPos = nil

		local enemyLookupTime = simTime - viewDelay

		for _, player in ipairs(roundPlayers) do
			if player.UserId ~= shooterUserId then
				local targetTeam = playerTeams[player.UserId]
				if targetTeam and shooterTeam and targetTeam ~= shooterTeam then
					local histState = historyBuffer:getStateAtTime(player.UserId, enemyLookupTime)
					if histState then
						local t = segmentSphereIntersect(pos, newPos, histState.position, hitRadius)
						if t and t < closestT then
							closestT = t
							closestPlayer = player
							closestHistPos = histState.position
						end
					end
				end
			end
		end

		local playerHitFirst = closestPlayer and (not worldT or closestT <= worldT)
		local worldHitFirst = worldT and (not closestPlayer or worldT < closestT)

		if playerHitFirst then
			local hitPos = pos + moveVec * closestT
			if debugLog then
				print(("[LagComp] Catch-up HIT player %s at step %d/%d | hitPos=%s | histTargetPos=%s"):format(
					closestPlayer.Name, step, stepsNeeded, tostring(hitPos), tostring(closestHistPos)
				))
			end
			return {
				hitPlayer = closestPlayer,
				hitPosition = hitPos,
				hitTime = simTime - dt + dt * closestT,
				historicalTargetPos = closestHistPos,
			}, nil
		end

		if worldHitFirst then
			if debugLog then
				print(("[LagComp] Catch-up bullet hit GEOMETRY at step %d/%d | pos=%s"):format(
					step, stepsNeeded, tostring(worldHit.Position)
				))
			end
			return nil, nil
		end

		pos = newPos
	end

	if debugLog then
		print(("[LagComp] Catch-up complete, no hit | caughtUpPos=%s | steps=%d"):format(
			tostring(pos), stepsNeeded
		))
	end
	return nil, pos
end

--[[
	Validate that a client-supplied fireTime is plausible.
	Returns clamped rewind seconds (>= 0), or nil + reason string if rejected.
]]
function RewindHitDetection.validateFireTime(fireTime: number, serverNow: number): (number?, string?)
	if typeof(fireTime) ~= "number" or fireTime ~= fireTime then
		return nil, "BadTimestamp"
	end
	local delta = serverNow - fireTime
	if delta < -LagCompConfig.MAX_FUTURE_TOLERANCE_SECONDS then
		return nil, "FutureTimestamp"
	end
	local rewind = math.clamp(delta, 0, LagCompConfig.MAX_REWIND_SECONDS)
	return rewind, nil
end

return RewindHitDetection
