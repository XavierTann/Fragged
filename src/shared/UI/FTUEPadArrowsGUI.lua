--[[
	FTUEPadArrowsGUI — Multi-stage first-time user experience.

	Stages (sequential, each advances on the relevant close/action):
	1. PRE_MATCH  — Yellow ground arrows → pad needing players + floating pad arrows + PLAY button
	2. SHOP       — After first match: arrows → shop + "Buy weapons here!" billboard
	3. GACHA      — After shop close: arrows → gacha + "Try your luck here!" billboard
	4. LOADOUT    — After gacha close: arrows → weapon storage + "Equip your weapons and skins here!" billboard
	5. RETURN_PAD — After loadout close: arrows → pad + "Try your new weapon or skin in another match!" billboard
	6. DONE       — FTUE complete, nothing shown
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local ShopGUI = require(Shared.UI.Shop.ShopGUI)
local GachaGUI = require(Shared.UI.GachaGUI)
local LoadoutGUI = require(Shared.UI.LoadoutGUI)

local LocalPlayer = Players.LocalPlayer

-- ── Stages ──
local STAGE = {
	PRE_MATCH  = 1,
	SHOP       = 2,
	GACHA      = 3,
	LOADOUT    = 4,
	RETURN_PAD = 5,
	DONE       = 6,
}

local currentStage = STAGE.PRE_MATCH
local pendingStage = nil
local stageShowing = false
local initialized = false

-- ── Visual constants ──
local COLOR_GOLD = Color3.fromRGB(255, 255, 0)
local GROUND_ARROW_COUNT = 5
local GROUND_ARROW_SPACING = 8

-- ── State ──
local ftueFolder = nil
local padArrowParts = {}
local padHeartbeatConn = nil
local screenGui = nil
local playBtn = nil
local playBtnFlashTween = nil

local groundArrowParts = {}
local groundBillboard = nil
local groundHeartbeatConn = nil
local groundTargetPos = nil


-- ── FTUE Folder management ──
local function getFTUEFolder()
	if ftueFolder and ftueFolder.Parent then
		return ftueFolder
	end
	ftueFolder = Instance.new("Folder")
	ftueFolder.Name = "FTUEArrows"
	ftueFolder.Parent = Workspace
	return ftueFolder
end

local function cleanupFolderIfEmpty()
	if ftueFolder and ftueFolder.Parent and #ftueFolder:GetChildren() == 0 then
		ftueFolder:Destroy()
		ftueFolder = nil
	end
end

-- ── Pad resolution helpers ──
local FTUE_PAD_FOLDER_NAME = "1v1ArenaPad"
local BLUE_TEAM_PAD_NAME = "BlueTeamPad"
local RED_TEAM_PAD_NAME = "RedTeamPad"

local function resolve1v1PadFolder()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local arenaZone = lobby:FindFirstChild("ArenaZone")
	local arenaPads = arenaZone and arenaZone:FindFirstChild("ArenaPads")
	if not arenaPads then
		return nil
	end
	return arenaPads:FindFirstChild(FTUE_PAD_FOLDER_NAME)
end

local function getPadCenter(model)
	return model:GetPivot().Position
end

local function choosePadTeam()
	local state = LobbyServiceClient.GetState()
	if not state then
		return "Blue"
	end
	local blueCount = state.waitingCountBlue or 0
	local redCount = state.waitingCountRed or 0
	if blueCount <= redCount then
		return "Blue"
	end
	return "Red"
end

local function getTargetPad()
	local team = choosePadTeam()
	local padName = team == "Blue" and BLUE_TEAM_PAD_NAME or RED_TEAM_PAD_NAME
	local folder = resolve1v1PadFolder()
	if folder then
		return folder:FindFirstChild(padName)
	end
	return nil
end


local function destroyPadArrows()
	if padHeartbeatConn then
		padHeartbeatConn:Disconnect()
		padHeartbeatConn = nil
	end
	for _, data in ipairs(padArrowParts) do
		if data.part and data.part.Parent then
			data.part:Destroy()
		end
	end
	padArrowParts = {}
	cleanupFolderIfEmpty()
end

local function showPadArrows()
	-- Floating wedge arrows removed; ground trail arrows still guide the player.
end

-- ── PLAY button ──
local function teleportToPad()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local pad = getTargetPad()
	if not pad then
		return
	end
	local target = getPadCenter(pad) + Vector3.new(0, 3, 0)
	hrp.CFrame = CFrame.new(target)
end

local function stopPlayBtnFlash()
	if playBtnFlashTween then
		playBtnFlashTween:Cancel()
		playBtnFlashTween = nil
	end
end

local function startPlayBtnFlash()
	if not playBtn then
		return
	end
	stopPlayBtnFlash()

	local tweenA = TweenService:Create(playBtn, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.6 })
	local tweenB = TweenService:Create(playBtn, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0 })

	local pulsing = true
	local function step()
		if not playBtn or not playBtn.Parent or not pulsing then
			return
		end
		pulsing = not pulsing
		playBtnFlashTween = tweenA
		tweenA:Play()
		tweenA.Completed:Once(function()
			if not playBtn or not playBtn.Parent then
				return
			end
			pulsing = true
			playBtnFlashTween = tweenB
			tweenB:Play()
			tweenB.Completed:Once(step)
		end)
	end

	playBtnFlashTween = tweenB
	tweenB:Play()
	tweenB.Completed:Once(step)
end

local function createPlayButton()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FTUEPlayButtonGUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1
	screenGui.Enabled = true
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	playBtn = Instance.new("TextButton")
	playBtn.Name = "PlayButton"
	playBtn.Size = UDim2.fromOffset(180, 50)
	playBtn.Position = UDim2.new(0.5, 0, 1, -10)
	playBtn.AnchorPoint = Vector2.new(0.5, 1)
	playBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 90)
	playBtn.BackgroundTransparency = 0
	playBtn.BorderSizePixel = 0
	playBtn.Text = "PLAY"
	playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	playBtn.TextSize = 24
	playBtn.Font = Enum.Font.GothamBold
	playBtn.AutoButtonColor = true
	playBtn.Parent = screenGui

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 12)
	btnCorner.Parent = playBtn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.5
	stroke.Parent = playBtn

	playBtn.Activated:Connect(teleportToPad)
	startPlayBtnFlash()
end

local function destroyPlayButton()
	stopPlayBtnFlash()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
		playBtn = nil
	end
end

-- ── Generic ground arrow trail (reused for all post-match stages) ──
local function hideGroundArrows()
	if groundHeartbeatConn then
		groundHeartbeatConn:Disconnect()
		groundHeartbeatConn = nil
	end
	for _, p in ipairs(groundArrowParts) do
		if p and p.Parent then
			p:Destroy()
		end
	end
	groundArrowParts = {}
	if groundBillboard then
		groundBillboard:Destroy()
		groundBillboard = nil
	end
	groundTargetPos = nil
	cleanupFolderIfEmpty()
end

local function getModelPosition(model)
	if typeof(model) == "Instance" and model:IsA("BasePart") then
		return model.Position
	end
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position
	end
	return model:GetPivot().Position
end

local function getModelBasePart(model)
	if typeof(model) == "Instance" and model:IsA("BasePart") then
		return model
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function showGroundArrows(targetInstance, billboardText)
	hideGroundArrows()

	if not targetInstance then
		return
	end

	groundTargetPos = getModelPosition(targetInstance)

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)

	local modelsFolder = ReplicatedStorage:FindFirstChild("Imports")
		and ReplicatedStorage.Imports:FindFirstChild("3DModels")
	local arrowTemplate = modelsFolder and modelsFolder:FindFirstChild("Arrow")
	if not arrowTemplate then
		return
	end

	for _ = 1, GROUND_ARROW_COUNT do
		local arrow = arrowTemplate:Clone()
		arrow.Name = "FTUEGroundArrow"
		arrow.Parent = getFTUEFolder()

		for _, desc in ipairs(arrow:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Color = COLOR_GOLD
				desc.Material = Enum.Material.Neon
			elseif desc:IsA("GuiObject") then
				desc.BackgroundTransparency = 1
			end
		end

		table.insert(groundArrowParts, arrow)
	end

	if billboardText then
		local basePart = getModelBasePart(targetInstance)
		if basePart then
			groundBillboard = Instance.new("BillboardGui")
			groundBillboard.Name = "FTUEBillboard"
			groundBillboard.Size = UDim2.fromOffset(260, 40)
			groundBillboard.StudsOffset = Vector3.new(0, 6, 0)
			groundBillboard.AlwaysOnTop = true
			groundBillboard.Adornee = basePart
			groundBillboard.Parent = basePart

			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
			label.BackgroundTransparency = 0.35
			label.BorderSizePixel = 0
			label.Text = billboardText
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextSize = 15
			label.Font = Enum.Font.GothamBold
			label.Parent = groundBillboard

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = label
		end
	end

	local t = 0
	groundHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		local pulse = 0.1 + math.abs(math.sin(t * 2.5)) * 0.3

		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not hrp or not groundTargetPos then
			return
		end

		local gY = hrp.Position.Y - 3
		local from = Vector3.new(hrp.Position.X, gY, hrp.Position.Z)
		local to = Vector3.new(groundTargetPos.X, gY, groundTargetPos.Z)
		local dir = to - from
		local dist = dir.Magnitude

		local function setArrowTransparency(obj, tr)
			if obj:IsA("Model") then
				for _, part in ipairs(obj:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Transparency = tr
					end
				end
			elseif obj:IsA("BasePart") then
				obj.Transparency = tr
			end
		end

		local function setArrowCFrame(obj, cf)
			if obj:IsA("Model") then
				obj:PivotTo(cf)
			elseif obj:IsA("BasePart") then
				obj.CFrame = cf
			end
		end

		if dist < 2 then
			for _, p in ipairs(groundArrowParts) do
				if p and p.Parent then
					setArrowTransparency(p, 1)
				end
			end
			return
		end

		local unit = dir.Unit
		local lookCF = CFrame.lookAt(Vector3.zero, unit)
		local layFlat = CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.rad(90), 0, 0)
		local tiltForward = CFrame.Angles(0, 0, 0)
		local modelFix = tiltForward * layFlat
		local visibleCount = math.clamp(math.floor(dist / GROUND_ARROW_SPACING), 1, GROUND_ARROW_COUNT)

		for i, p in ipairs(groundArrowParts) do
			if p and p.Parent then
				if i <= visibleCount then
					local offset = i * GROUND_ARROW_SPACING
					if offset > dist - 2 then
						offset = dist - 2
					end
					local pos = from + unit * offset + Vector3.new(0, 0.2, 0)
					setArrowCFrame(p, CFrame.new(pos) * lookCF * modelFix)
					setArrowTransparency(p, pulse)
				else
					setArrowTransparency(p, 1)
				end
			end
		end
	end)
end

-- ── Target finders ──
local function findShopKeeper()
	local lobby = Workspace:WaitForChild("Lobby", 15)
	if not lobby then
		return nil
	end
	local gunShop = lobby:WaitForChild("GunShop", 10)
	if not gunShop then
		return nil
	end
	return gunShop:WaitForChild("ShopKeeper", 10)
end

local function findGachaCounter()
	local lobby = Workspace:WaitForChild("Lobby", 15)
	if not lobby then
		return nil
	end
	local gachaFolder = lobby:WaitForChild("Gacha", 15)
	if not gachaFolder then
		return nil
	end
	local counter = gachaFolder:WaitForChild("GachaCounter", 10)
	if not counter then
		return nil
	end
	if counter:IsA("Model") then
		return counter.PrimaryPart or counter:FindFirstChildWhichIsA("BasePart", true)
	end
	return counter
end

local function findWeaponStorage()
	local lobby = Workspace:WaitForChild("Lobby", 15)
	if not lobby then
		return nil
	end
	local gunShop = lobby:WaitForChild("GunShop", 10)
	if not gunShop then
		return nil
	end
	return gunShop:WaitForChild("WeaponStorage", 10)
end

-- ── PRE_MATCH ground arrows → pad ──
local preMatchGroundConn = nil
local preMatchGroundParts = {}

local function hidePreMatchGroundArrows()
	if preMatchGroundConn then
		preMatchGroundConn:Disconnect()
		preMatchGroundConn = nil
	end
	for _, p in ipairs(preMatchGroundParts) do
		if p and p.Parent then
			p:Destroy()
		end
	end
	preMatchGroundParts = {}
	cleanupFolderIfEmpty()
end

local function showPreMatchGroundArrows()
	hidePreMatchGroundArrows()

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)

	local modelsFolder = ReplicatedStorage:FindFirstChild("Imports")
		and ReplicatedStorage.Imports:FindFirstChild("3DModels")
	local arrowTemplate = modelsFolder and modelsFolder:FindFirstChild("Arrow")
	if not arrowTemplate then
		return
	end

	for _ = 1, GROUND_ARROW_COUNT do
		local arrow = arrowTemplate:Clone()
		arrow.Name = "FTUEPadGroundArrow"
		arrow.Parent = getFTUEFolder()

		for _, desc in ipairs(arrow:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Color = COLOR_GOLD
				desc.Material = Enum.Material.Neon
			elseif desc:IsA("GuiObject") then
				desc.BackgroundTransparency = 1
			end
		end

		table.insert(preMatchGroundParts, arrow)
	end

	local t = 0
	preMatchGroundConn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		local pulse = 0.1 + math.abs(math.sin(t * 2.5)) * 0.3

		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end

		local pad = getTargetPad()
		if not pad then
			return
		end

		local padPos = getPadCenter(pad)
		local gY = hrp.Position.Y - 3
		local from = Vector3.new(hrp.Position.X, gY, hrp.Position.Z)
		local to = Vector3.new(padPos.X, gY, padPos.Z)
		local dir = to - from
		local dist = dir.Magnitude

		local function setArrowTransparency(obj, tr)
			if obj:IsA("Model") then
				for _, part in ipairs(obj:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Transparency = tr
					end
				end
			elseif obj:IsA("BasePart") then
				obj.Transparency = tr
			end
		end

		local function setArrowCFrame(obj, cf)
			if obj:IsA("Model") then
				obj:PivotTo(cf)
			elseif obj:IsA("BasePart") then
				obj.CFrame = cf
			end
		end

		if dist < 2 then
			for _, p in ipairs(preMatchGroundParts) do
				if p and p.Parent then
					setArrowTransparency(p, 1)
				end
			end
			return
		end

		local unit = dir.Unit
		local lookCF = CFrame.lookAt(Vector3.zero, unit)
		local layFlat = CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.rad(90), 0, 0)
		local modelFix = layFlat
		local visibleCount = math.clamp(math.floor(dist / GROUND_ARROW_SPACING), 1, GROUND_ARROW_COUNT)

		for i, p in ipairs(preMatchGroundParts) do
			if p and p.Parent then
				if i <= visibleCount then
					local offset = i * GROUND_ARROW_SPACING
					if offset > dist - 2 then
						offset = dist - 2
					end
					local pos = from + unit * offset + Vector3.new(0, 0.2, 0)
					setArrowCFrame(p, CFrame.new(pos) * lookCF * modelFix)
					setArrowTransparency(p, pulse)
				else
					setArrowTransparency(p, 1)
				end
			end
		end
	end)
end

-- ── Stage transitions ──
local function hideFTUE()
	stageShowing = false
	destroyPadArrows()
	hideGroundArrows()
	hidePreMatchGroundArrows()
end

local function hideEverything()
	hideFTUE()
	destroyPlayButton()
end

local advanceToStage

local function showStage(stage)
	hideFTUE()
	currentStage = stage
	stageShowing = true

	if stage == STAGE.PRE_MATCH then
		showPadArrows()
		task.spawn(showPreMatchGroundArrows)

	elseif stage == STAGE.SHOP then
		task.spawn(function()
			local keeper = findShopKeeper()
			if keeper and currentStage == STAGE.SHOP then
				showGroundArrows(keeper, "Buy weapons here!")
			end
		end)

	elseif stage == STAGE.GACHA then
		task.spawn(function()
			local counter = findGachaCounter()
			if counter and currentStage == STAGE.GACHA then
				showGroundArrows(counter, "Try your luck here!")
			end
		end)

	elseif stage == STAGE.LOADOUT then
		task.spawn(function()
			local storage = findWeaponStorage()
			if storage and currentStage == STAGE.LOADOUT then
				showGroundArrows(storage, "Equip your weapons and skins here!")
			end
		end)

	elseif stage == STAGE.RETURN_PAD then
		showPadArrows()
		task.spawn(showPreMatchGroundArrows)

	end
end

advanceToStage = function(stage)
	showStage(stage)
end

-- ── Public API ──
local FTUEPadArrowsGUI = {}

function FTUEPadArrowsGUI.Init()
	if initialized then
		return
	end
	initialized = true

	CombatServiceClient.SubscribeMatchEnded(function()
		if currentStage == STAGE.PRE_MATCH then
			pendingStage = STAGE.SHOP
		elseif currentStage == STAGE.RETURN_PAD then
			pendingStage = STAGE.DONE
		end
	end)

	ShopGUI.SubscribeOnOpen(function()
		if currentStage == STAGE.SHOP then
			hideGroundArrows()
		end
	end)

	ShopGUI.SubscribeOnClose(function()
		if currentStage == STAGE.SHOP then
			advanceToStage(STAGE.GACHA)
		end
	end)

	GachaGUI.SubscribeOnClose(function()
		if currentStage == STAGE.GACHA then
			advanceToStage(STAGE.LOADOUT)
		end
	end)

	LoadoutGUI.SubscribeOnClose(function()
		if currentStage == STAGE.LOADOUT then
			advanceToStage(STAGE.RETURN_PAD)
		end
	end)

	LobbyServiceClient.Subscribe(function(state)
		if not state then
			return
		end
		if state.phase == LobbyConfig.PHASE.ARENA or state.phase == LobbyConfig.PHASE.WAITING_LOBBY then
			hideEverything()
		elseif state.phase == LobbyConfig.PHASE.LOBBY then
			if state.queuedTeam then
				hideEverything()
			else
				if pendingStage then
					local next = pendingStage
					pendingStage = nil
					advanceToStage(next)
				end
				createPlayButton()
				if currentStage ~= STAGE.DONE and not stageShowing then
					showStage(currentStage)
				end
			end
		end
	end)

	LobbyServiceClient.OnTeleportToArena(function()
		hideEverything()
	end)

	LobbyServiceClient.OnTeleportToWaiting(function()
		hideEverything()
	end)

	createPlayButton()
	if currentStage == STAGE.PRE_MATCH then
		showStage(STAGE.PRE_MATCH)
	end
end

function FTUEPadArrowsGUI.Show()
	createPlayButton()
	if currentStage ~= STAGE.DONE then
		showStage(currentStage)
	end
end

function FTUEPadArrowsGUI.Hide()
	hideEverything()
end

return FTUEPadArrowsGUI
