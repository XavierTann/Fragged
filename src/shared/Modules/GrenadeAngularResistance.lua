--[[
	GrenadeAngularResistance
	Contact-gated exponential damping of AssemblyAngularVelocity (rolling / angular drag).
	Uses short raycasts from the grenade center; no built-in rolling resistance in Roblox.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AXES = {
	Vector3.xAxis,
	Vector3.yAxis,
	Vector3.zAxis,
}

local function raycastExcludeForGrenade(rootPart: BasePart): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local p = rootPart.Parent
	if p and p:IsA("Model") then
		params.FilterDescendantsInstances = { p }
	else
		params.FilterDescendantsInstances = { rootPart }
	end
	params.RespectCanCollide = true
	return params
end

local function isNearCollidableSurface(rootPart: BasePart, paddingStuds: number, rayParams: RaycastParams): boolean
	local half = rootPart.Size * 0.5
	local reach = math.max(half.X, half.Y, half.Z) + paddingStuds
	local pos = rootPart.Position

	for _, axis in ipairs(AXES) do
		for s = -1, 1, 2 do
			local dir = axis * s
			local hit = Workspace:Raycast(pos, dir * reach, rayParams)
			if hit then
				return true
			end
		end
	end
	return false
end

export type ResistanceConfig = {
	angularDragPerSecond: number?,
	contactPaddingStuds: number?,
	minAngularVelocity: number?,
}

--[[
	Runs each Heartbeat: if the grenade assembly is within contactPaddingStuds of a collidable
	surface along ±X/±Y/±Z from its center, scales AssemblyAngularVelocity by exp(-k * dt).
	Returns a disconnect function (optional; also stops when rootPart is removed from the DataModel).
]]
local function attach(rootPart: BasePart, cfg: ResistanceConfig?)
	local c = cfg or {}
	local k = c.angularDragPerSecond or 3
	local padding = c.contactPaddingStuds or 0.15
	local minOmega = c.minAngularVelocity or 1e-3

	local rayParams = raycastExcludeForGrenade(rootPart)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not rootPart.Parent then
			conn:Disconnect()
			return
		end
		if dt <= 0 or dt > 0.1 then
			return
		end
		if not isNearCollidableSurface(rootPart, padding, rayParams) then
			return
		end

		local av = rootPart.AssemblyAngularVelocity
		local mag = av.Magnitude
		if mag < minOmega then
			if mag > 0 then
				rootPart.AssemblyAngularVelocity = Vector3.zero
			end
			return
		end

		rootPart.AssemblyAngularVelocity = av * math.exp(-k * dt)
	end)

	return function()
		if conn.Connected then
			conn:Disconnect()
		end
	end
end

return {
	attach = attach,
}
