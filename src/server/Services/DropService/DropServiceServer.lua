--[[
	DropService (server)
	Random drop system: spawns collectible items within FactoryFloor bounds.
	Modular and independent. Pickup logic delegates to callback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DropConfig = require(ReplicatedStorage.Shared.Modules.DropConfig)

local DROPS_FOLDER_NAME = "Drops"
local activeDrops = {}
local spawnConnection = nil
local onPickupCallback = nil

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

local function getRandomDropType()
	local totalWeight = 0
	for _, drop in pairs(DropConfig.DROPS) do
		totalWeight = totalWeight + (drop.weight or 1)
	end
	if totalWeight <= 0 then
		return "RocketLauncher"
	end
	local r = math.random() * totalWeight
	for dropId, drop in pairs(DropConfig.DROPS) do
		r = r - (drop.weight or 1)
		if r <= 0 then
			return dropId
		end
	end
	return "RocketLauncher"
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
			local finalPos = Vector3.new(pos.X, groundY + 0.5, pos.Z)
			if isPositionValid(finalPos, nil) then
				return finalPos
			end
		end
	end
	return nil
end

local function spawnDrop()
	local spawnArea = getSpawnArea()
	if not spawnArea then
		return nil
	end
	if #activeDrops >= DropConfig.MAX_ACTIVE_DROPS then
		return nil
	end

	local dropType = getRandomDropType()
	local cfg = DropConfig.DROPS[dropType]
	if not cfg then
		return nil
	end

	local pos = findGroundPosition(spawnArea)
	if not pos then
		return nil
	end

	local drop
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	local modelTemplate = dropType == "RocketLauncher" and models3D and models3D:FindFirstChild("RocketLauncherModel")
	if modelTemplate and (modelTemplate:IsA("Model") or modelTemplate:IsA("BasePart")) then
		drop = modelTemplate:Clone()
		drop.Name = "Drop_" .. dropType
		-- Anchor all parts so the model stays together instead of scattering
		for _, desc in ipairs(drop:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
		end
		drop.Parent = getDropsFolder()
		local orient = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0)
		if drop:IsA("Model") then
			drop:PivotTo(orient)
		else
			drop.CFrame = orient
		end
	else
		drop = Instance.new("Part")
		drop.Name = "Drop_" .. dropType
		drop.Size = cfg.visualSize or Vector3.new(1, 1, 1)
		drop.Color = cfg.visualColor or Color3.fromRGB(120, 120, 120)
		drop.Material = Enum.Material.SmoothPlastic
		drop.Anchored = false
		drop.CanCollide = true
		drop.CFrame = CFrame.new(pos)
		drop.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0.5, 1, 1)
		drop.Parent = getDropsFolder()
	end

	drop:SetAttribute("DropType", dropType)

	local function onTouched(hit)
		if not drop.Parent then
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
		if onPickupCallback then
			local consumed = onPickupCallback(player, dropType, drop)
			if consumed then
				for i, d in ipairs(activeDrops) do
					if d == drop then
						table.remove(activeDrops, i)
						break
					end
				end
				drop:Destroy()
			end
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

local function cleanupDestroyedDrops()
	for i = #activeDrops, 1, -1 do
		if not activeDrops[i].Parent then
			table.remove(activeDrops, i)
		end
	end
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
