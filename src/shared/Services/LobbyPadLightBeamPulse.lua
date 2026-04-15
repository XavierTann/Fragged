--[[
	LobbyPadLightBeamPulse (client)
	Pulses Transparency on every part named LightBeam under BluePad/RedPad models
	in all Lobby/SpawnPadsN folders.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)

local beams = {}
local folderConns = {}
local renderConn = nil
local rebuildScheduled = false

local function getAllSpawnPadsFolders()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return {}
	end
	local results = {}
	for _, child in ipairs(lobby:GetChildren()) do
		if child:IsA("Folder") and child.Name:match("^SpawnPads%d+$") then
			table.insert(results, child)
		end
	end
	return results
end

local function isPadModel(model)
	return model:IsA("Model")
		and (model.Name == LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME or model.Name == LobbyConfig.LOBBY_RED_PAD_MODEL_NAME)
end

local function rebuildBeamList()
	table.clear(beams)
	local folders = getAllSpawnPadsFolders()
	for _, folder in ipairs(folders) do
		for _, child in ipairs(folder:GetChildren()) do
			if isPadModel(child) then
				for _, d in ipairs(child:GetDescendants()) do
					if d.Name == LobbyConfig.LOBBY_LIGHTBEAM_PART_NAME and d:IsA("BasePart") then
						beams[#beams + 1] = d
					end
				end
			end
		end
	end
end

local function scheduleRebuild()
	if rebuildScheduled then
		return
	end
	rebuildScheduled = true
	task.defer(function()
		rebuildScheduled = false
		rebuildBeamList()
	end)
end

local function disconnectFolders()
	for _, c in ipairs(folderConns) do
		c:Disconnect()
	end
	table.clear(folderConns)
end

local function watchFolders()
	disconnectFolders()
	rebuildBeamList()
	local folders = getAllSpawnPadsFolders()
	for _, folder in ipairs(folders) do
		table.insert(folderConns, folder.ChildAdded:Connect(scheduleRebuild))
		table.insert(folderConns, folder.ChildRemoved:Connect(scheduleRebuild))
		table.insert(folderConns, folder.DescendantAdded:Connect(function(inst)
			if inst.Name == LobbyConfig.LOBBY_LIGHTBEAM_PART_NAME and inst:IsA("BasePart") then
				scheduleRebuild()
			end
		end))
		table.insert(folderConns, folder.DescendantRemoving:Connect(function(inst)
			if inst.Name == LobbyConfig.LOBBY_LIGHTBEAM_PART_NAME then
				scheduleRebuild()
			end
		end))
	end
end

local function onRenderStepped()
	local speed = LobbyConfig.LOBBY_LIGHTBEAM_PULSE_SPEED or 2.8
	local tMin = LobbyConfig.LOBBY_LIGHTBEAM_TRANSPARENCY_MIN or 0.12
	local tMax = LobbyConfig.LOBBY_LIGHTBEAM_TRANSPARENCY_MAX or 0.88
	local phase = 0.5 + 0.5 * math.sin(os.clock() * speed)
	local tr = tMin + (tMax - tMin) * phase
	for i = #beams, 1, -1 do
		local part = beams[i]
		if not part.Parent then
			table.remove(beams, i)
		else
			part.Transparency = tr
		end
	end
end

return {
	Init = function()
		if renderConn then
			return
		end
		local folders = getAllSpawnPadsFolders()
		if #folders > 0 then
			watchFolders()
		else
			task.spawn(function()
				local lobby = Workspace:WaitForChild("Lobby", 60)
				if not lobby then
					return
				end
				local found = false
				for _, child in ipairs(lobby:GetChildren()) do
					if child:IsA("Folder") and child.Name:match("^SpawnPads%d+$") then
						found = true
						break
					end
				end
				if not found then
					lobby.ChildAdded:Wait()
				end
				watchFolders()
			end)
		end
		renderConn = RunService.RenderStepped:Connect(onRenderStepped)
	end,
}
