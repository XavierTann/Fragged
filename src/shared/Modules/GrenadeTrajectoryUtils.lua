--[[
	GrenadeTrajectoryUtils
	Client-side grenade aim preview: same throw vector as server; flight uses analytical
	ballistic positions P(t)=p0+v0*t+0.5*g*t² up to fuseTime (matches explosion time),
	with segment raycasts for first wall. One straight rebound segment after first hit.
	BulletBlocker surfaces excluded (grenades pass through on server).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local CombatConfig = require(script.Parent.CombatConfig)
local GrenadeConfig = require(script.Parent.GrenadeConfig)

-- Max samples along the pre-bounce arc (subsampled on the client before Beams)
local DEFAULT_MAX_PRE_BOUNCE_POINTS = 18
local SKIN = 0.06
-- Time slices [0, fuseTime] for chord raycasts (thin walls need enough segments)
local ARC_TIME_SLICES = 36
local EMIT_EVERY_STUDS = 0.35

local function bounceVelocity(v, normal, restitution, friction)
	local vn = v:Dot(normal)
	local vT = v - normal * vn
	local vNOut = normal * (-restitution * vn)
	local dampT = math.clamp(1 - friction, 0, 1)
	return vNOut + vT * dampT
end

--[[
	returns:
	  beforeBounce: ordered world points along flight until first hit (or fuse), last = impact when bounced
	  reboundEnd: world position end of straight rebound hint, or nil if no bounce
]]
local function computeSimplifiedGrenadePath(character, aimDirection)
	local cfg = GrenadeConfig
	local beforeBounce = {}
	local reboundEnd = nil

	if not character or not aimDirection or aimDirection.Magnitude < 1e-4 then
		return { beforeBounce = beforeBounce, reboundEnd = reboundEnd }
	end

	local dir = aimDirection.Unit
	local horizontal = Vector3.new(dir.X, 0, dir.Z)
	if horizontal.Magnitude < 1e-4 then
		horizontal = Vector3.new(0, 0, -1)
	else
		horizontal = horizontal.Unit
	end

	local throwDir = (horizontal * (1 - cfg.throwArcUp) + Vector3.new(0, cfg.throwArcUp, 0)).Unit
	local v0 = throwDir * cfg.throwSpeed

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { beforeBounce = beforeBounce, reboundEnd = reboundEnd }
	end
	local startPos = root.Position + dir * 2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { character }
	for _, inst in ipairs(CollectionService:GetTagged(CombatConfig.BULLET_BLOCKER_TAG)) do
		table.insert(exclude, inst)
	end
	local grenadesFolder = Workspace:FindFirstChild("CombatGrenades")
	if grenadesFolder then
		table.insert(exclude, grenadesFolder)
	end
	params.FilterDescendantsInstances = exclude

	local gravity = Workspace.Gravity
	local gVec = Vector3.new(0, -gravity, 0)
	local fuseTime = cfg.fuseTime or 2
	local restitution = cfg.restitution or 0.6
	local friction = 0.3

	local function positionAtTime(t)
		return startPos + v0 * t + 0.5 * gVec * (t * t)
	end

	local function velocityAtTime(t)
		return v0 + gVec * t
	end

	table.insert(beforeBounce, startPos)
	local lastEmit = startPos
	local didBounce = false
	local tPrev = 0
	local pPrev = startPos

	for i = 1, ARC_TIME_SLICES do
		local tNext = fuseTime * (i / ARC_TIME_SLICES)
		local pNext = positionAtTime(tNext)
		local delta = pNext - pPrev
		local segLen = delta.Magnitude
		if segLen >= 1e-6 then
			local hit = Workspace:Raycast(pPrev, delta, params)
			if hit then
				local hitPos = hit.Position + hit.Normal * SKIN
				local frac = math.clamp(hit.Distance / segLen, 0, 1)
				local tHit = tPrev + frac * (tNext - tPrev)
				if (hitPos - beforeBounce[#beforeBounce]).Magnitude > 0.08 then
					table.insert(beforeBounce, hitPos)
				end
				didBounce = true
				local vHit = velocityAtTime(tHit)
				local vOut = bounceVelocity(vHit, hit.Normal, restitution, friction)
				if vOut.Magnitude >= 0.5 then
					local remain = math.max(0, fuseTime - tHit)
					local reboundLen = math.clamp(vOut.Magnitude * remain * 0.42, 15, 52)
					reboundEnd = hitPos + vOut.Unit * reboundLen
				end
				break
			end
		end

		tPrev = tNext
		pPrev = pNext
		if (pNext - lastEmit).Magnitude >= EMIT_EVERY_STUDS then
			table.insert(beforeBounce, pNext)
			lastEmit = pNext
		end
	end

	if not didBounce then
		local pEnd = positionAtTime(fuseTime)
		if (pEnd - beforeBounce[#beforeBounce]).Magnitude > 0.05 then
			table.insert(beforeBounce, pEnd)
		end
	end

	return { beforeBounce = beforeBounce, reboundEnd = reboundEnd }
end

local function subsamplePoints(points, maxPoints)
	if #points <= maxPoints then
		return points
	end
	local out = {}
	local n = #points
	local take = maxPoints
	if take <= 1 then
		table.insert(out, points[1])
		return out
	end
	for i = 1, take do
		local idx = math.floor((i - 1) / (take - 1) * (n - 1)) + 1
		table.insert(out, points[idx])
	end
	return out
end

--[[
	Merges pre-bounce polyline (subsampled) with optional rebound endpoint for beam chain.
]]
local function mergeGrenadePreviewPoints(result, maxPreBounce)
	local pre = subsamplePoints(result.beforeBounce, maxPreBounce)
	local pts = {}
	for _, p in ipairs(pre) do
		table.insert(pts, p)
	end
	if result.reboundEnd and #pts > 0 then
		local last = pts[#pts]
		if (result.reboundEnd - last).Magnitude > 0.12 then
			table.insert(pts, result.reboundEnd)
		end
	end
	return pts
end

return {
	computeSimplifiedGrenadePath = computeSimplifiedGrenadePath,
	subsamplePoints = subsamplePoints,
	mergeGrenadePreviewPoints = mergeGrenadePreviewPoints,
	DEFAULT_MAX_PRE_BOUNCE_POINTS = DEFAULT_MAX_PRE_BOUNCE_POINTS,
}
