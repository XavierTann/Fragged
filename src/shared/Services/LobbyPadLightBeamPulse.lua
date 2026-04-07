--[[
	LobbyPadLightBeamPulse (client)
	Pulses Transparency on every part named LightBeam under BluePad/RedPad models in Lobby/SpawnPads.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyConfig = require(ReplicatedStorage.Shared.Modules.LobbyConfig)

local beams = {}
local folderConn = {}
local renderConn = nil
local rebuildScheduled = false

local function getSpawnPadsFolder()
	local inst = Workspace
	for _, name in ipairs(LobbyConfig.LOBBY_PADS_FOLDER_PATH) do
		inst = inst:FindFirstChild(name)
		if not inst then
			return nil
		end
	end
	return inst
end

local function isPadModel(model)
	return model:IsA("Model")
		and (model.Name == LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME or model.Name == LobbyConfig.LOBBY_RED_PAD_MODEL_NAME)
end

local function rebuildBeamList()
	table.clear(beams)
	local folder = getSpawnPadsFolder()
	if not folder then
		return
	end
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

local function disconnectFolder()
	for _, c in ipairs(folderConn) do
		c:Disconnect()
	end
	table.clear(folderConn)
end

local function watchFolder(folder)
	disconnectFolder()
	rebuildBeamList()
	folderConn[#folderConn + 1] = folder.ChildAdded:Connect(scheduleRebuild)
	folderConn[#folderConn + 1] = folder.ChildRemoved:Connect(scheduleRebuild)
	folderConn[#folderConn + 1] = folder.DescendantAdded:Connect(function(inst)
		if inst.Name == LobbyConfig.LOBBY_LIGHTBEAM_PART_NAME and inst:IsA("BasePart") then
			scheduleRebuild()
		end
	end)
	folderConn[#folderConn + 1] = folder.DescendantRemoving:Connect(function(inst)
		if inst.Name == LobbyConfig.LOBBY_LIGHTBEAM_PART_NAME then
			scheduleRebuild()
		end
	end)
end

local function tryBindSpawnPadsFolder()
	local folder = getSpawnPadsFolder()
	if folder then
		watchFolder(folder)
		return true
	end
	return false
end

local function onRenderStepped()
	local speed = LobbyConfig.LOBBY_LIGHTBEAM_PULSE_SPEED or 2.8
	local tMin = LobbyConfig.LOBBY_LIGHTBEAM_TRANSPARENCY_MIN or 0.12
	local tMax = LobbyConfig.LOBBY_LIGHTBEAM_TRANSPARENCY_MAX or 0.88
	local phase = 0.5 + 0.5 * math.sin(os.clock() * speed)
	local tr = tMin + (tMax - tMin) * phase
	for i = #beams, 1, -1 do
		local part = beams[i]
		if part.Parent then
			part.Transparency = tr
		else
			table.remove(beams, i)
		end
	end
end

return {
	Init = function()
		if renderConn then
			return
		end
		if not tryBindSpawnPadsFolder() then
			task.spawn(function()
				local inst = Workspace
				for _, name in ipairs(LobbyConfig.LOBBY_PADS_FOLDER_PATH) do
					inst = inst:WaitForChild(name, 60)
					if not inst then
						return
					end
				end
				if inst then
					watchFolder(inst)
				end
			end)
		end
		renderConn = RunService.RenderStepped:Connect(onRenderStepped)
	end,
}
