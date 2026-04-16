--[[
	LobbyPadLightBeamPulse (client)
	Pulses Transparency on light beam models under each arena mode folder's
	LightBeam folder (BlueLightBeam / RedLightBeam).
	Only beams with Active == true (set by server PadQueueService) pulse;
	inactive beams are fully transparent.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local PULSE_SPEED = 1.5
local TRANSPARENCY_MIN = 0.4
local TRANSPARENCY_MAX = 0.88

local cachedBeamModels = {}
local renderConn = nil
local rebuildScheduled = false

local function getAllLightBeamModels()
	local lobby = Workspace:FindFirstChild("Lobby")
	local arenaZone = lobby and lobby:FindFirstChild("ArenaZone")
	local arenaPads = arenaZone and arenaZone:FindFirstChild("ArenaPads")
	if not arenaPads then
		return {}
	end
	local models = {}
	for _, modeFolder in ipairs(arenaPads:GetChildren()) do
		local lightBeamFolder = modeFolder:FindFirstChild("LightBeam")
		if lightBeamFolder then
			for _, child in ipairs(lightBeamFolder:GetChildren()) do
				if child:IsA("Model") then
					models[#models + 1] = child
				end
			end
		end
	end
	return models
end

local function rebuildCache()
	cachedBeamModels = getAllLightBeamModels()
end

local function scheduleRebuild()
	if rebuildScheduled then
		return
	end
	rebuildScheduled = true
	task.defer(function()
		rebuildScheduled = false
		rebuildCache()
	end)
end

local function setModelPartsTransparency(model, transparency)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = transparency
		end
	end
end

local function onRenderStepped()
	local phase = 0.5 + 0.5 * math.sin(os.clock() * PULSE_SPEED)
	local activeTransparency = TRANSPARENCY_MIN + (TRANSPARENCY_MAX - TRANSPARENCY_MIN) * phase

	for i = #cachedBeamModels, 1, -1 do
		local model = cachedBeamModels[i]
		if not model.Parent then
			table.remove(cachedBeamModels, i)
		else
			local active = model:GetAttribute("Active") == true
			if active then
				setModelPartsTransparency(model, activeTransparency)
			else
				setModelPartsTransparency(model, 1)
			end
		end
	end
end

return {
	Init = function()
		if renderConn then
			return
		end
		local models = getAllLightBeamModels()
		if #models > 0 then
			cachedBeamModels = models
			for _, model in ipairs(cachedBeamModels) do
				setModelPartsTransparency(model, 1)
			end
		else
			task.spawn(function()
				local lobby = Workspace:WaitForChild("Lobby", 60)
				if not lobby then
					return
				end
				local arenaZone = lobby:WaitForChild("ArenaZone", 30)
				if not arenaZone then
					return
				end
				local arenaPads = arenaZone:WaitForChild("ArenaPads", 30)
				if not arenaPads then
					return
				end
				if #arenaPads:GetChildren() == 0 then
					arenaPads.ChildAdded:Wait()
				end
				rebuildCache()
				for _, model in ipairs(cachedBeamModels) do
					setModelPartsTransparency(model, 1)
				end
			end)
		end

		local lobby = Workspace:FindFirstChild("Lobby")
		local arenaZone = lobby and lobby:FindFirstChild("ArenaZone")
		local arenaPads = arenaZone and arenaZone:FindFirstChild("ArenaPads")
		if arenaPads then
			arenaPads.DescendantAdded:Connect(function(inst)
				if inst:IsA("Model") and (inst.Name == "BlueLightBeam" or inst.Name == "RedLightBeam") then
					scheduleRebuild()
				end
			end)
			arenaPads.DescendantRemoving:Connect(function(inst)
				if inst:IsA("Model") and (inst.Name == "BlueLightBeam" or inst.Name == "RedLightBeam") then
					scheduleRebuild()
				end
			end)
		end

		renderConn = RunService.RenderStepped:Connect(onRenderStepped)
	end,
}
