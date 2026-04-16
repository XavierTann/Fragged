--[[
	DropPickupClient
	While combat HUD is active, scan Workspace.Drops for proximity to local HRP and play predicted
	pickup SFX when likely valid (client heuristics only). Authoritative pickup is server Touched
	on drop parts — no ClaimDrop remote.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DropConfig = require(ReplicatedStorage.Shared.Modules.DropConfig)
local RocketLauncherConfig = require(ReplicatedStorage.Shared.Modules.RocketLauncherConfig)
local CombatServiceClient = require(script.Parent.CombatServiceClient)

local DROPS_FOLDER_NAME = "Drops"

local lastSfxByDrop = setmetatable({}, { __mode = "k" })
local predictedSfxSent = setmetatable({}, { __mode = "k" })

local function getDropWorldPosition(drop)
	if drop:IsA("Model") then
		return drop:GetPivot().Position
	end
	if drop:IsA("BasePart") then
		return drop.Position
	end
	return nil
end

local function playPredictedPickupSfx(dropType)
	local soundId = nil
	if dropType == "RocketLauncher" then
		soundId = RocketLauncherConfig.dropPickupSoundId
	elseif dropType == "HealthPack" then
		local cfg = DropConfig.DROPS and DropConfig.DROPS.HealthPack
		soundId = cfg and cfg.dropPickupSoundId
	end
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local parent = rootPart or Workspace
	local sound = Instance.new("Sound")
	sound.Name = "DropPickupPredicted"
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMaxDistance = 200
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function clientLikelyAllowsPickup(dropType)
	if dropType == "HealthPack" then
		local char = Players.LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return hum and hum.Health > 0 and hum.Health < hum.MaxHealth - 1e-3
	end
	if dropType == "RocketLauncher" then
		for _, w in ipairs(CombatServiceClient.GetAvailableWeapons()) do
			if w == "RocketLauncher" then
				return false
			end
		end
		return true
	end
	return false
end

local function onHeartbeat()
	if not CombatServiceClient.IsShootingEnabled() then
		return
	end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local folder = Workspace:FindFirstChild(DROPS_FOLDER_NAME)
	if not folder then
		return
	end

	local rClient = DropConfig.CLIENT_DROP_PROXIMITY_RADIUS or 9
	local cooldown = DropConfig.CLIENT_DROP_SFX_COOLDOWN or 0.35
	local now = os.clock()
	local rootPos = root.Position

	for _, drop in ipairs(folder:GetChildren()) do
		if drop.Parent == folder then
			local dropType = drop:GetAttribute("DropType")
			if typeof(dropType) == "string" then
				local pos = getDropWorldPosition(drop)
				if pos then
					local dist = (rootPos - pos).Magnitude
					if dist <= rClient then
						local last = lastSfxByDrop[drop]
						if clientLikelyAllowsPickup(dropType) and not predictedSfxSent[drop] then
							if not last or now - last >= cooldown then
								lastSfxByDrop[drop] = now
								playPredictedPickupSfx(dropType)
								predictedSfxSent[drop] = true
							end
						end
					else
						lastSfxByDrop[drop] = nil
						predictedSfxSent[drop] = nil
					end
				end
			end
		end
	end
end

local DropPickupClient = {}

function DropPickupClient.Init()
	RunService.Heartbeat:Connect(onHeartbeat)
end

return DropPickupClient
