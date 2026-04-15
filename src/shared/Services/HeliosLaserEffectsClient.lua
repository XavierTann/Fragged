--[[
	Client: Helios Thread — grip offsets for imported mesh, optional hold animation,
	and a growing charge sphere at the muzzle during the charged-laser commit window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeliosLaserConfig = require(Shared.Modules.HeliosLaserConfig)
local CombatServiceClient = require(Shared.Services.CombatServiceClient)

local TOOL_NAME = "HeliosThread"

local chargeBallPart = nil
local chargeBallTween = nil
local chargeBallAlignConn = nil
local holdTrack = nil

local function findMuzzleAttachment(tool)
	for _, name in ipairs(HeliosLaserConfig.MUZZLE_ATTACHMENT_NAMES or {}) do
		local a = tool:FindFirstChild(name, true)
		if a and a:IsA("Attachment") then
			return a
		end
	end
	return nil
end

local function destroyChargeBall()
	if chargeBallAlignConn then
		chargeBallAlignConn:Disconnect()
		chargeBallAlignConn = nil
	end
	if chargeBallTween then
		chargeBallTween:Cancel()
		chargeBallTween = nil
	end
	if chargeBallPart then
		chargeBallPart:Destroy()
		chargeBallPart = nil
	end
end

local function startChargeBall(duration)
	destroyChargeBall()
	local player = Players.LocalPlayer
	local char = player.Character
	if not char then
		return
	end
	local tool = char:FindFirstChild(TOOL_NAME)
	if not tool or not tool:IsA("Tool") then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local muzzle = findMuzzleAttachment(tool)
	local d0 = HeliosLaserConfig.CHARGE_BALL_START_DIAMETER or 0.15
	local d1 = HeliosLaserConfig.CHARGE_BALL_END_DIAMETER or 0.9
	local ball = Instance.new("Part")
	ball.Name = "HeliosChargeOrb"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = HeliosLaserConfig.BALL_COLOR
	ball.Anchored = false
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Massless = true
	ball.Size = Vector3.one * d0
	ball.Parent = tool
	if muzzle then
		ball.CFrame = muzzle.WorldCFrame
	else
		ball.CFrame = handle.CFrame * CFrame.new(0, 0, -handle.Size.Z * 0.5 - d0 * 0.25)
	end
	chargeBallPart = ball
	chargeBallAlignConn = RunService.RenderStepped:Connect(function()
		if not chargeBallPart or not chargeBallPart.Parent then
			return
		end
		if muzzle and muzzle.Parent then
			chargeBallPart.CFrame = muzzle.WorldCFrame
		elseif handle.Parent then
			chargeBallPart.CFrame = handle.CFrame * CFrame.new(0, 0, -handle.Size.Z * 0.5 - chargeBallPart.Size.Z * 0.25)
		end
	end)
	local dur = typeof(duration) == "number" and duration or (HeliosLaserConfig.CHARGE_DURATION or 0.85)
	local ti = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	chargeBallTween = TweenService:Create(ball, ti, { Size = Vector3.one * d1 })
	chargeBallTween:Play()
end

local function stopHoldAnimation()
	if holdTrack then
		holdTrack:Stop()
		holdTrack:Destroy()
		holdTrack = nil
	end
end

local function applyToolGrip(tool)
	local cfg = HeliosLaserConfig
	pcall(function()
		tool.GripForward = cfg.GRIP_FORWARD
		tool.GripRight = cfg.GRIP_RIGHT
		tool.GripUp = cfg.GRIP_UP
		tool.GripPos = cfg.GRIP_POS
	end)
end

local function tryPlayHold(humanoid)
	local url = HeliosLaserConfig.HOLD_ANIMATION_ID
	if typeof(url) ~= "string" or url == "" then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = url
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	stopHoldAnimation()
	holdTrack = animator:LoadAnimation(anim)
	holdTrack.Priority = Enum.AnimationPriority.Action
	holdTrack.Looped = true
	holdTrack:Play()
end

local hookedTools = {}

local function onHeliosToolEquippedState(tool)
	local player = Players.LocalPlayer
	if tool.Parent == player.Character then
		applyToolGrip(tool)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			tryPlayHold(hum)
		end
	elseif tool.Parent ~= player.Backpack then
		stopHoldAnimation()
	end
end

local function hookHeliosLaserTool(tool)
	if not tool:IsA("Tool") or tool.Name ~= TOOL_NAME then
		return
	end
	if hookedTools[tool] then
		return
	end
	hookedTools[tool] = true
	tool.AncestryChanged:Connect(function()
		onHeliosToolEquippedState(tool)
	end)
	onHeliosToolEquippedState(tool)
end

local function scanContainer(container)
	if not container then
		return
	end
	for _, c in ipairs(container:GetChildren()) do
		hookHeliosLaserTool(c)
	end
end

local HeliosLaserEffectsClient = {}

function HeliosLaserEffectsClient.Init()
	local player = Players.LocalPlayer

	CombatServiceClient.SubscribeLaserChargeVisual(function(weaponId, phase, duration)
		if weaponId ~= "HeliosThread" then
			return
		end
		if phase == "start" and typeof(duration) == "number" then
			startChargeBall(duration)
		elseif phase == "end" or phase == "cancel" then
			destroyChargeBall()
		end
	end)

	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(c)
			hookHeliosLaserTool(c)
		end)
		task.defer(function()
			scanContainer(char)
		end)
	end)

	local bp = player:WaitForChild("Backpack")
	bp.ChildAdded:Connect(function(c)
		hookHeliosLaserTool(c)
	end)
	scanContainer(bp)

	if player.Character then
		player.Character.ChildAdded:Connect(function(c)
			hookHeliosLaserTool(c)
		end)
		scanContainer(player.Character)
	end
end

return HeliosLaserEffectsClient
