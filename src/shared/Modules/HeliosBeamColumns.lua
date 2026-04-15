--[[
	Helios beam is sampled as parallel columns across the beam width (XZ plane).
	Each column can clip at its own wall so open lanes still deal damage / show preview.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local CombatConfig = require(script.Parent.CombatConfig)

local function isSolidWall(instance)
	if not instance then
		return false
	end
	if CollectionService:HasTag(instance, CombatConfig.BULLET_BLOCKER_TAG) then
		return true
	end
	return instance.CanCollide == true
end

local HeliosBeamColumns = {}

function HeliosBeamColumns.getRightUnitXZ(dirUnit)
	if typeof(dirUnit) ~= "Vector3" or dirUnit.Magnitude < 0.01 then
		return Vector3.new(1, 0, 0)
	end
	local flat = Vector3.new(dirUnit.X, 0, dirUnit.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(1, 0, 0)
	end
	flat = flat.Unit
	return Vector3.new(-flat.Z, 0, flat.X)
end

function HeliosBeamColumns.getColumnOffsets(columnCount, beamRadius, spreadFraction)
	local spread = beamRadius * 2 * spreadFraction
	local t = table.create(columnCount)
	if columnCount <= 1 then
		t[1] = 0
		return t
	end
	for i = 1, columnCount do
		local alpha = (i - 1) / (columnCount - 1) - 0.5
		t[i] = alpha * spread
	end
	return t
end

-- Client-side aim preview: first solid hit per column along dir (cheap ray vs server spherecast).
function HeliosBeamColumns.computeRayClipLengths(
	origin,
	dirUnit,
	maxRange,
	beamRadius,
	columnCount,
	spreadFraction,
	raycastParams
)
	local u = dirUnit.Unit
	local right = HeliosBeamColumns.getRightUnitXZ(u)
	local offs = HeliosBeamColumns.getColumnOffsets(columnCount, beamRadius, spreadFraction)
	local lengths = table.create(columnCount)
	for i = 1, columnCount do
		local start = origin + right * offs[i] + Vector3.new(0, 0.1, 0)
		local cast = Workspace:Raycast(start, u * maxRange, raycastParams)
		if cast and isSolidWall(cast.Instance) then
			lengths[i] = math.max(0.12, cast.Distance - 0.08)
		else
			lengths[i] = maxRange
		end
	end
	return offs, lengths
end

return HeliosBeamColumns
