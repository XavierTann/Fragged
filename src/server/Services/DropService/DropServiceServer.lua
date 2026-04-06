--[[
	DropService (server)
	Random drop system: spawns at TDM spawn markers (Workspace/SpawnLocations/TDMSpawnLocations),
	with fallback to FactoryFloor raycast. Pickup logic delegates to callback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DropConfig = require(ReplicatedStorage.Shared.Modules.DropConfig)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)

local DROPS_FOLDER_NAME = "Drops"
local activeDrops = {}
local spawnConnection = nil
local onPickupCallback = nil

local function shuffleInPlace(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function getSpawnArea()
	local tagged = CollectionService:GetTagged(DropConfig.DROP_SPAWN_TAG)
	if #tagged > 0 then
		local part = tagged[1]
		if part:IsA("BasePart") then
			return part
		end
		local model = part:IsA("Model") and part or part:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart then
			return model.PrimaryPart
		end
	end
	return Workspace:FindFirstChild(DropConfig.FACTORY_FLOOR_NAME, true)
end

local function getDropsFolder()
	local folder = Workspace:FindFirstChild(DROPS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = DROPS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function countActiveOfType(dropTypeId)
	local n = 0
	for _, drop in ipairs(activeDrops) do
		if drop.Parent and drop:GetAttribute("DropType") == dropTypeId then
			n = n + 1
		end
	end
	return n
end

local function getCapForDropType(dropCfg)
	local cap = dropCfg.maxActive
	if cap == nil then
		cap = DropConfig.MAX_ACTIVE_PER_TYPE
	end
	return cap
end

-- Picks among types that are under their per-type cap; nil if every type is at cap.
-- Candidates are shuffled each roll so spawn order is not tied to table / pairs iteration order.
local function getRandomDropType()
	local candidates = {}
	local totalWeight = 0
	for dropId, drop in pairs(DropConfig.DROPS) do
		local cap = getCapForDropType(drop)
		if not cap or countActiveOfType(dropId) < cap then
			local w = drop.weight or 1
			totalWeight = totalWeight + w
			table.insert(candidates, { id = dropId, weight = w })
		end
	end
	if totalWeight <= 0 or #candidates == 0 then
		return nil
	end
	shuffleInPlace(candidates)
	local r = math.random() * totalWeight
	for _, entry in ipairs(candidates) do
		r = r - entry.weight
		if r <= 0 then
			return entry.id
		end
	end
	return candidates[#candidates].id
end

local function isPositionValid(pos, excludeDrop)
	for _, drop in pairs(activeDrops) do
		if drop ~= excludeDrop and drop.Parent then
			local dropPos = drop:IsA("BasePart") and drop.Position or (drop.PrimaryPart and drop.PrimaryPart.Position)
			if dropPos and (dropPos - pos).Magnitude < DropConfig.MIN_DROP_SPACING then
				return false
			end
		end
	end
	return true
end

local function getTdmSpawnFolder()
	local parent = Workspace:FindFirstChild(TDMConfig.TDM_SPAWN_PARENT)
	if not parent then
		return nil
	end
	return parent:FindFirstChild(TDMConfig.TDM_SPAWN_FOLDER)
end

-- Top surface of spawn marker (XZ center); same idea as player spawn footing on the part.
local function basePartTopY(part)
	return part.Position.Y + part.Size.Y * 0.5
end

-- Collect TDMSpawnLocation* BaseParts / Models under TDMSpawnLocations (e.g. .../TDMSpawnLocation1..8).
local function getTdmSpawnMarkers()
	local folder = getTdmSpawnFolder()
	if not folder then
		return {}
	end
	local markers = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(markers, child)
		elseif child:IsA("Model") and child.PrimaryPart then
			table.insert(markers, child.PrimaryPart)
		end
	end
	return markers
end

-- TDM spawn markers: try every marker once in random order (avoids hammering occupied slots),
-- then random retries for MIN_DROP_SPACING. Returns gx, gz, groundY (surface to place on).
local function findGroundPositionAtTdmSpawn()
	local markers = getTdmSpawnMarkers()
	if #markers == 0 then
		return nil
	end
	local order = table.clone(markers)
	shuffleInPlace(order)
	for _, part in ipairs(order) do
		if part.Parent then
			local gx, gz = part.Position.X, part.Position.Z
			local groundY = basePartTopY(part)
			local samplePos = Vector3.new(gx, groundY + 0.5, gz)
			if isPositionValid(samplePos, nil) then
				return { gx = gx, gz = gz, groundY = groundY }
			end
		end
	end
	for _ = 1, 24 do
		local part = markers[math.random(1, #markers)]
		if part.Parent then
			local gx, gz = part.Position.X, part.Position.Z
			local groundY = basePartTopY(part)
			local samplePos = Vector3.new(gx, groundY + 0.5, gz)
			if isPositionValid(samplePos, nil) then
				return { gx = gx, gz = gz, groundY = groundY }
			end
		end
	end
	return nil
end

local function findGroundPosition(spawnArea)
	local cf = spawnArea.CFrame
	local size = spawnArea.Size
	local halfX = size.X / 2 - 1
	local halfZ = size.Z / 2 - 1
	local topY = cf.Y + size.Y / 2

	for _ = 1, 20 do
		local rx = (math.random() * 2 - 1) * halfX
		local rz = (math.random() * 2 - 1) * halfZ
		local pos = cf:PointToWorldSpace(Vector3.new(rx, size.Y / 2, rz))
		pos = Vector3.new(pos.X, topY + 2, pos.Z)

		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { spawnArea, getDropsFolder() }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local result = Workspace:Raycast(pos, Vector3.new(0, -100, 0), params)
		if result and result.Instance then
			local groundY = result.Position.Y
			local samplePos = Vector3.new(pos.X, groundY + 0.5, pos.Z)
			if isPositionValid(samplePos, nil) then
				return { gx = pos.X, gz = pos.Z, groundY = groundY }
			end
		end
	end
	return nil
end

local function resolveModelTemplate(dropType, cfg, models3D)
	if not models3D then
		return nil
	end
	if cfg.modelAssetName then
		local t = models3D:FindFirstChild(cfg.modelAssetName)
		if t and (t:IsA("Model") or t:IsA("BasePart")) then
			return t
		end
	end
	if dropType == "RocketLauncher" then
		local t = models3D:FindFirstChild("RocketLauncherModel")
		if t and (t:IsA("Model") or t:IsA("BasePart")) then
			return t
		end
	end
	return nil
end

-- After pivot + rotation, shift model along world Y so AABB bottom matches ground + clearance (no local-Y drift).
local function snapModelBoundingBoxBottomToGround(model, groundY, clearanceStuds)
	local clearance = clearanceStuds or 0
	local cf, size = model:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y * 0.5
	local lift = (groundY + clearance) - bottomY
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position + Vector3.new(0, lift, 0)) * pivot.Rotation)
end

local function placementRotationFromConfig(cfg)
	local d = cfg.placementRotationDegrees
	if d and typeof(d) == "Vector3" then
		return CFrame.Angles(math.rad(d.X), math.rad(d.Y), math.rad(d.Z))
	end
	return CFrame.new()
end

-- No physical blocking; CanTouch keeps Touched firing for pickup when CanCollide is false.
local function configurePickupPart(part)
	part.CanCollide = false
	part.CanTouch = true
end

local function cleanupDestroyedDrops()
	for i = #activeDrops, 1, -1 do
		if not activeDrops[i].Parent then
			table.remove(activeDrops, i)
		end
	end
end

local function spawnDrop()
	cleanupDestroyedDrops()

	local dropType = getRandomDropType()
	if not dropType then
		return nil
	end
	local cfg = DropConfig.DROPS[dropType]
	if not cfg then
		return nil
	end

	local spot = findGroundPositionAtTdmSpawn()
	if not spot then
		local spawnArea = getSpawnArea()
		if not spawnArea then
			return nil
		end
		spot = findGroundPosition(spawnArea)
	end
	if not spot then
		return nil
	end
	local gx, gz, groundY = spot.gx, spot.gz, spot.groundY
	local placeY = groundY

	local drop
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local modelTemplate = resolveModelTemplate(dropType, cfg, models3D)
	if modelTemplate then
		drop = modelTemplate:Clone()
		drop.Name = "Drop_" .. dropType
		if drop:IsA("BasePart") then
			drop.Anchored = true
			configurePickupPart(drop)
		else
			for _, desc in ipairs(drop:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					configurePickupPart(desc)
				end
			end
		end
		drop.Parent = getDropsFolder()

		if dropType == "RocketLauncher" then
			local rotX90 = CFrame.Angles(math.rad(90), 0, 0)
			if drop:IsA("Model") then
				drop:PivotTo(CFrame.new(gx, placeY, gz) * rotX90)
				snapModelBoundingBoxBottomToGround(drop, placeY, cfg.groundClearanceStuds)
			else
				drop.CFrame = CFrame.new(gx, placeY, gz) * rotX90
			end
		else
			if drop:IsA("Model") and not drop.PrimaryPart then
				drop.PrimaryPart = drop:FindFirstChildWhichIsA("BasePart", true)
			end
			local rot = placementRotationFromConfig(cfg)
			local pivotPos = Vector3.new(gx, placeY, gz)
			drop:PivotTo(CFrame.new(pivotPos) * rot)
			snapModelBoundingBoxBottomToGround(drop, placeY, cfg.groundClearanceStuds)
		end
	else
		drop = Instance.new("Part")
		drop.Name = "Drop_" .. dropType
		local sizeVec = cfg.visualSize or Vector3.new(1, 1, 1)
		drop.Size = sizeVec
		drop.Color = cfg.visualColor or Color3.fromRGB(120, 120, 120)
		drop.Material = cfg.material or Enum.Material.SmoothPlastic
		drop.Anchored = cfg.anchored == true
		configurePickupPart(drop)
		local centerY = placeY + sizeVec.Y * 0.5
		drop.CFrame = CFrame.new(gx, centerY, gz)
		if not drop.Anchored then
			drop.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0.5, 1, 1)
		end
		drop.Parent = getDropsFolder()
	end

	drop:SetAttribute("DropType", dropType)

	local pickupLocked = false
	local failedPickupCooldownUntil = 0
	local function onTouched(hit)
		if os.clock() < failedPickupCooldownUntil or pickupLocked or not drop.Parent then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model or not model:FindFirstChildOfClass("Humanoid") then
			return
		end
		local player = Players:GetPlayerFromCharacter(model)
		if not player then
			return
		end
		if not onPickupCallback then
			return
		end
		pickupLocked = true
		local consumed = onPickupCallback(player, dropType, drop)
		if consumed then
			for i, d in ipairs(activeDrops) do
				if d == drop then
					table.remove(activeDrops, i)
					break
				end
			end
			drop:Destroy()
		else
			failedPickupCooldownUntil = os.clock() + 0.35
			pickupLocked = false
		end
	end

	local function connectTouched(target)
		if target:IsA("BasePart") then
			target.Touched:Connect(onTouched)
		end
		for _, child in ipairs(target:GetDescendants()) do
			if child:IsA("BasePart") then
				child.Touched:Connect(onTouched)
			end
		end
	end
	connectTouched(drop)
	table.insert(activeDrops, drop)
	return drop
end

local function startSpawnLoop()
	if spawnConnection then
		return
	end
	spawnConnection = task.spawn(function()
		while true do
			task.wait(DropConfig.SPAWN_INTERVAL_SECONDS or 15)
			spawnDrop()
		end
	end)
end

return {
	Init = function()
		task.defer(function()
			spawnDrop()
		end)
		startSpawnLoop()
		task.spawn(function()
			while true do
				task.wait(5)
				cleanupDestroyedDrops()
			end
		end)
	end,

	SetPickupCallback = function(cb)
		onPickupCallback = cb
	end,

	GetActiveDropsCount = function()
		cleanupDestroyedDrops()
		return #activeDrops
	end,
}
