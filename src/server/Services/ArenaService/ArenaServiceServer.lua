--[[
	ArenaService (server)
	Clones arena templates from ServerStorage, places them at unique offsets,
	tracks active arenas by matchId, and cleans up on match end.
	Supports unlimited concurrent arenas.
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ARENA_TEMPLATE_NAME = "Arena"
local ARENAS_WORKSPACE_FOLDER = "ActiveArenas"
local OFFSET_STUDS = 1000

local ArenaServiceServer = {}

local nextSlotIndex = 0
local activeArenas = {} -- matchId -> { model, slotIndex, offset }

local function getOrCreateArenasFolder()
	local folder = Workspace:FindFirstChild(ARENAS_WORKSPACE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ARENAS_WORKSPACE_FOLDER
		folder.Parent = Workspace
	end
	return folder
end

local function getTemplate()
	return ServerStorage:FindFirstChild(ARENA_TEMPLATE_NAME)
end

function ArenaServiceServer.CreateArena(matchId)
	local template = getTemplate()
	if not template then
		warn("[ArenaService] Arena template not found in ServerStorage")
		return nil
	end

	local clone = template:Clone()
	clone.Name = "Arena_" .. matchId

	local slot = nextSlotIndex
	nextSlotIndex = nextSlotIndex + 1

	local offset = Vector3.new(slot * OFFSET_STUDS, 0, 0)
	if clone:IsA("Model") then
		clone:PivotTo(clone:GetPivot() + offset)
	end

	local folder = getOrCreateArenasFolder()
	clone.Parent = folder

	activeArenas[matchId] = {
		model = clone,
		slotIndex = slot,
		offset = offset,
	}

	return clone
end

function ArenaServiceServer.GetArenaOffset(matchId)
	local entry = activeArenas[matchId]
	if not entry then
		return Vector3.new(0, 0, 0)
	end
	return entry.offset
end

function ArenaServiceServer.GetArenaModel(matchId)
	local entry = activeArenas[matchId]
	return entry and entry.model or nil
end

function ArenaServiceServer.DestroyArena(matchId)
	local entry = activeArenas[matchId]
	if not entry then
		return
	end
	if entry.model and entry.model.Parent then
		entry.model:Destroy()
	end
	activeArenas[matchId] = nil
end

function ArenaServiceServer.IsArenaActive(matchId)
	return activeArenas[matchId] ~= nil
end

function ArenaServiceServer.Init()
	getOrCreateArenasFolder()
end

return ArenaServiceServer
