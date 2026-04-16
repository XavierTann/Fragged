--[[
	DropService (server)
	Per-match timed pickups: X/Z from Arena SpawnLocations.ItemSpawnLocations (shuffled, then cycled),
	or random top-face points on tagged FactoryFloor if item folder is missing.
	World Y from DropConfig. No raycasts; PivotTo / CFrame at config Y.
	Pickup: server Touched on drop parts runs SetPickupCallback. Client may play predicted SFX only (DropPickupClient).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DropConfig = require(ReplicatedStorage.Shared.Modules.DropConfig)
local TDMConfig = require(ReplicatedStorage.Shared.Modules.TDMConfig)

local DROPS_FOLDER_NAME = "Drops"
local onPickupCallback = nil
-- matchId -> { drops, thread, running, arenaModel, spawnSlots, spawnSlotIndex }
local matchDropData = {}

local function shuffleInPlace(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function getSpawnAreaPart()
	local tagged = CollectionService:GetTagged(DropConfig.DROP_SPAWN_TAG)
	if #tagged > 0 then
		local inst = tagged[1]
		if inst:IsA("BasePart") then
			return inst
		end
		local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart then
			return model.PrimaryPart
		end
	end
	local found = Workspace:FindFirstChild(DropConfig.FACTORY_FLOOR_NAME, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
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

local function countActiveOfType(activeDrops, dropTypeId)
	local n = 0
	for _, drop in ipairs(activeDrops) do
		if drop.Parent and drop:GetAttribute("DropType") == dropTypeId then
			n += 1
		end
	end
	return n
end

local function getCapForDropType(dropCfg)
	return dropCfg.maxActive ~= nil and dropCfg.maxActive or DropConfig.MAX_ACTIVE_PER_TYPE
end

local function getRandomDropType(activeDrops, dropWeightOverrides)
	local candidates = {}
	local totalWeight = 0
	for dropId, drop in pairs(DropConfig.DROPS) do
		local cap = getCapForDropType(drop)
		if not cap or countActiveOfType(activeDrops, dropId) < cap then
			local w = (dropWeightOverrides and dropWeightOverrides[dropId]) or drop.weight or 1
			totalWeight += w
			table.insert(candidates, { id = dropId, weight = w })
		end
	end
	if totalWeight <= 0 or #candidates == 0 then
		return nil
	end
	shuffleInPlace(candidates)
	local r = math.random() * totalWeight
	for _, entry in ipairs(candidates) do
		r -= entry.weight
		if r <= 0 then
			return entry.id
		end
	end
	return candidates[#candidates].id
end

local function resolveItemSpawnFolder(arenaModel)
	if arenaModel then
		local f = TDMConfig.getItemSpawnFolder(arenaModel)
		if f then
			return f
		end
	end
	local arenasFolder = Workspace:FindFirstChild("ActiveArenas")
	if arenasFolder then
		for _, arena in ipairs(arenasFolder:GetChildren()) do
			local f = TDMConfig.getItemSpawnFolder(arena)
			if f then
				return f
			end
		end
	end
	local arena = Workspace:FindFirstChild("Arena")
	if arena then
		return TDMConfig.getItemSpawnFolder(arena)
	end
	return nil
end

local function collectSlotsFromItemSpawnFolder(folder)
	if not folder then
		return {}
	end
	local slots = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(slots, { gx = child.Position.X, gz = child.Position.Z })
		elseif child:IsA("Model") and child.PrimaryPart then
			table.insert(slots, { gx = child.PrimaryPart.Position.X, gz = child.PrimaryPart.Position.Z })
		end
	end
	return slots
end

local function resolveWorldY(dropType)
	if dropType then
		local dc = DropConfig.DROPS[dropType]
		if dc and typeof(dc.fixedWorldY) == "number" then
			return dc.fixedWorldY
		end
	end
	if typeof(DropConfig.FIXED_DROP_WORLD_Y) == "number" then
		return DropConfig.FIXED_DROP_WORLD_Y
	end
	warn("[DropService] No world Y: set FIXED_DROP_WORLD_Y or per-type fixedWorldY for", dropType)
	return nil
end

local FALLBACK_SPAWN_POINT_COUNT = 24

-- Shuffled { gx, gz } from ItemSpawnLocations, else random top-face points on fallback part.
local function buildShuffledSpawnSlots(arenaModel)
	local folder = resolveItemSpawnFolder(arenaModel)
	local slots = collectSlotsFromItemSpawnFolder(folder)
	if #slots > 0 then
		shuffleInPlace(slots)
		return slots
	end
	local floorPart = getSpawnAreaPart()
	if not floorPart then
		return {}
	end
	local cf = floorPart.CFrame
	local size = floorPart.Size
	local halfX = math.max(0.5, size.X * 0.5 - 1)
	local halfZ = math.max(0.5, size.Z * 0.5 - 1)
	for _ = 1, FALLBACK_SPAWN_POINT_COUNT do
		local rx = (math.random() * 2 - 1) * halfX
		local rz = (math.random() * 2 - 1) * halfZ
		local world = cf:PointToWorldSpace(Vector3.new(rx, size.Y * 0.5, rz))
		table.insert(slots, { gx = world.X, gz = world.Z })
	end
	shuffleInPlace(slots)
	return slots
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

local function placementRotationFromConfig(cfg)
	local d = cfg.placementRotationDegrees
	if d and typeof(d) == "Vector3" then
		return CFrame.Angles(math.rad(d.X), math.rad(d.Y), math.rad(d.Z))
	end
	return CFrame.new()
end

local function configurePickupPart(part)
	part.CanCollide = false
	part.CanTouch = true
end

local function applyDropPickupHighlight(root, dropType)
	if DropConfig.DROP_PICKUP_HIGHLIGHT == false then
		return
	end
	local dc = dropType and DropConfig.DROPS[dropType]
	local hl = Instance.new("Highlight")
	hl.Name = "DropPickupHighlight"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.OutlineTransparency = 0
	local fillT = dc and dc.highlightFillTransparency
	if typeof(fillT) ~= "number" then
		fillT = DropConfig.DROP_HIGHLIGHT_FILL_TRANSPARENCY
	end
	hl.FillTransparency = typeof(fillT) == "number" and fillT or 1
	local outline = dc and dc.highlightOutlineColor
	if typeof(outline) ~= "Color3" then
		outline = DropConfig.DROP_HIGHLIGHT_OUTLINE_COLOR
	end
	hl.OutlineColor = typeof(outline) == "Color3" and outline or Color3.fromRGB(255, 250, 90)
	if hl.FillTransparency < 1 then
		local fillC = dc and dc.highlightFillColor
		if typeof(fillC) ~= "Color3" then
			fillC = DropConfig.DROP_HIGHLIGHT_FILL_COLOR
		end
		hl.FillColor = typeof(fillC) == "Color3" and fillC or Color3.fromRGB(255, 240, 100)
	end
	if root:IsA("Model") then
		hl.Parent = root
	elseif root:IsA("BasePart") then
		hl.Adornee = root
		hl.Parent = root
	end
end

local function cleanupDestroyedDrops(activeDrops)
	for i = #activeDrops, 1, -1 do
		if not activeDrops[i].Parent then
			table.remove(activeDrops, i)
		end
	end
end

local function consumeNextSpawnSpot(data, dropType)
	local worldY = resolveWorldY(dropType)
	if typeof(worldY) ~= "number" then
		return nil
	end
	local slots = data.spawnSlots
	if not slots or #slots == 0 then
		return nil
	end
	local i = data.spawnSlotIndex
	local slot = slots[i]
	data.spawnSlotIndex = (i % #slots) + 1
	return { gx = slot.gx, gz = slot.gz, worldY = worldY }
end

local function spawnDrop(matchId)
	local data = matchDropData[matchId]
	if not data then
		return nil
	end
	local activeDrops = data.drops

	cleanupDestroyedDrops(activeDrops)

	local dropType = getRandomDropType(activeDrops, data.dropWeightOverrides)
	if not dropType then
		return nil
	end
	local cfg = DropConfig.DROPS[dropType]
	if not cfg then
		return nil
	end

	local spot = consumeNextSpawnSpot(data, dropType)
	if not spot then
		return nil
	end
	local gx, gz, placeY = spot.gx, spot.gz, spot.worldY

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
			else
				drop.CFrame = CFrame.new(gx, placeY, gz) * rotX90
			end
		else
			local rot = placementRotationFromConfig(cfg)
			if drop:IsA("Model") then
				if not drop.PrimaryPart then
					drop.PrimaryPart = drop:FindFirstChildWhichIsA("BasePart", true)
				end
				drop:PivotTo(CFrame.new(gx, placeY, gz) * rot)
			elseif drop:IsA("BasePart") then
				drop.CFrame = CFrame.new(gx, placeY, gz) * rot
			end
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
		drop.CFrame = CFrame.new(gx, placeY + sizeVec.Y * 0.5, gz)
		if not drop.Anchored then
			drop.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0.5, 1, 1)
		end
		drop.Parent = getDropsFolder()
	end

	applyDropPickupHighlight(drop, dropType)
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
		if not player or not onPickupCallback then
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

local function clearAllDrops(activeDrops)
	for _, d in ipairs(activeDrops) do
		if d and d.Parent then
			d:Destroy()
		end
	end
end

local cleanupLoopStarted = false

return {
	Init = function()
		if cleanupLoopStarted then
			return
		end
		cleanupLoopStarted = true
		task.spawn(function()
			while true do
				task.wait(5)
				for _, data in pairs(matchDropData) do
					cleanupDestroyedDrops(data.drops)
				end
			end
		end)
	end,

	Start = function(matchId, arenaModel, modeConfig)
		if matchDropData[matchId] then
			return
		end
		local data = {
			drops = {},
			arenaModel = arenaModel,
			running = true,
			thread = nil,
			spawnSlots = buildShuffledSpawnSlots(arenaModel),
			spawnSlotIndex = 1,
			dropWeightOverrides = modeConfig and modeConfig.dropWeights or nil,
		}
		matchDropData[matchId] = data

		if #data.spawnSlots == 0 then
			warn(
				"[DropService] No item spawn slots for match",
				matchId,
				"- add SpawnLocations.ItemSpawnLocations under Arena, or FactoryFloor / DropSpawnArea"
			)
		end

		task.defer(function()
			spawnDrop(matchId)
		end)

		data.thread = task.spawn(function()
			while data.running do
				task.wait(DropConfig.SPAWN_INTERVAL_SECONDS or 15)
				if data.running then
					spawnDrop(matchId)
				end
			end
		end)
	end,

	Stop = function(matchId)
		local data = matchDropData[matchId]
		if not data then
			return
		end
		data.running = false
		if data.thread then
			task.cancel(data.thread)
			data.thread = nil
		end
		clearAllDrops(data.drops)
		matchDropData[matchId] = nil
	end,

	SetPickupCallback = function(cb)
		onPickupCallback = cb
	end,

	GetActiveDropsCount = function(matchId)
		if matchId then
			local data = matchDropData[matchId]
			if data then
				cleanupDestroyedDrops(data.drops)
				return #data.drops
			end
			return 0
		end
		local total = 0
		for _, data in pairs(matchDropData) do
			cleanupDestroyedDrops(data.drops)
			total += #data.drops
		end
		return total
	end,
}
