--[[
	FTUEPadArrowsGUI
	First-time user experience: 3D floating arrows above lobby pads + a flashing
	PLAY button at the bottom of the screen. The button teleports the player to
	whichever pad needs players. Everything hides after the first completed match.
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

local LocalPlayer = Players.LocalPlayer

local COLOR_BLUE = Color3.fromRGB(100, 170, 255)
local COLOR_RED = Color3.fromRGB(255, 80, 90)
local ARROW_HEIGHT_ABOVE_PAD = 12
local BOB_AMPLITUDE = 1.5
local BOB_SPEED = 2.2
local ROTATE_SPEED = 1.4

local arrowParts = {}
local heartbeatConn = nil
local hasCompletedFirstMatch = false
local screenGui = nil
local playBtn = nil
local playBtnFlashTween = nil
local initialized = false

local ftueFolder = nil
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

local function resolvePadsFolder()
	local parent = Workspace
	for _, segment in ipairs(LobbyConfig.LOBBY_PADS_FOLDER_PATH) do
		parent = parent:FindFirstChild(segment)
		if not parent then
			return nil
		end
	end
	return parent
end

local function getPadCenter(model)
	return model:GetPivot().Position
end

local function createArrow(padModel, color)
	local basePos = getPadCenter(padModel) + Vector3.new(0, ARROW_HEIGHT_ABOVE_PAD, 0)

	local arrow = Instance.new("Part")
	arrow.Name = "FTUEArrow"
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanTouch = false
	arrow.CanQuery = false
	arrow.Size = Vector3.new(3, 4, 3)
	arrow.CFrame = CFrame.new(basePos)
	arrow.Color = color
	arrow.Material = Enum.Material.Neon
	arrow.Transparency = 0.15
	arrow.Parent = getFTUEFolder()

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Wedge
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = arrow

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "ArrowLabel"
	bbg.Size = UDim2.fromOffset(160, 36)
	bbg.StudsOffset = Vector3.new(0, 4, 0)
	bbg.AlwaysOnTop = true
	bbg.Parent = arrow

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
	label.BackgroundTransparency = 0.35
	label.BorderSizePixel = 0
	label.Text = "Step here to play!"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Parent = bbg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	table.insert(arrowParts, { part = arrow, basePos = basePos })
end

local function startAnimation()
	if heartbeatConn then
		return
	end
	local t = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		for _, data in ipairs(arrowParts) do
			local yOff = math.sin(t * BOB_SPEED) * BOB_AMPLITUDE
			local angle = t * ROTATE_SPEED
			data.part.CFrame = CFrame.new(data.basePos + Vector3.new(0, yOff, 0))
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(math.rad(180), 0, 0)
		end
	end)
end

local function stopAnimation()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function destroyArrows()
	stopAnimation()
	for _, data in ipairs(arrowParts) do
		if data.part and data.part.Parent then
			data.part:Destroy()
		end
	end
	arrowParts = {}
	cleanupFolderIfEmpty()
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

local function teleportToPad()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local padsFolder = resolvePadsFolder()
	if not padsFolder then
		return
	end
	local team = choosePadTeam()
	local padName = team == "Blue" and LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME or LobbyConfig.LOBBY_RED_PAD_MODEL_NAME
	local pad = padsFolder:FindFirstChild(padName)
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

	playBtn.Activated:Connect(function()
		teleportToPad()
	end)

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

-- ── Shop arrows (phase 2: after first match) ──
local COLOR_GOLD = Color3.fromRGB(255, 255, 0)
local SHOP_ARROW_COUNT = 5
local SHOP_ARROW_SPACING = 8
local shopArrowParts = {}
local shopBillboard = nil
local shopArrowHeartbeat = nil
local hasShownShopArrows = false

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

local function getModelPosition(model)
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
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function hideShopArrows()
	if shopArrowHeartbeat then
		shopArrowHeartbeat:Disconnect()
		shopArrowHeartbeat = nil
	end
	for _, p in ipairs(shopArrowParts) do
		if p and p.Parent then
			p:Destroy()
		end
	end
	shopArrowParts = {}
	if shopBillboard then
		shopBillboard:Destroy()
		shopBillboard = nil
	end
	cleanupFolderIfEmpty()
end

local shopTargetPos = nil
local shopGroundY = nil

local function showShopArrows()
	if hasShownShopArrows then
		return
	end
	hideShopArrows()

	local keeper = findShopKeeper()
	if not keeper then
		return
	end
	shopTargetPos = getModelPosition(keeper)

	local lowestY = shopTargetPos.Y
	for _, desc in ipairs(keeper:GetDescendants()) do
		if desc:IsA("BasePart") then
			local bottomY = desc.Position.Y - desc.Size.Y * 0.5
			if bottomY < lowestY then
				lowestY = bottomY
			end
		end
	end
	shopGroundY = lowestY

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)

	local modelsFolder = ReplicatedStorage:FindFirstChild("Imports")
		and ReplicatedStorage.Imports:FindFirstChild("3DModels")
	local arrowTemplate = modelsFolder and modelsFolder:FindFirstChild("Arrow")
	if not arrowTemplate then
		return
	end

	for i = 1, SHOP_ARROW_COUNT do
		local arrow = arrowTemplate:Clone()
		arrow.Name = "FTUEShopArrow"
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

		table.insert(shopArrowParts, arrow)
	end

	local basePart = getModelBasePart(keeper)
	if basePart then
		shopBillboard = Instance.new("BillboardGui")
		shopBillboard.Name = "FTUEShopLabel"
		shopBillboard.Size = UDim2.fromOffset(240, 40)
		shopBillboard.StudsOffset = Vector3.new(0, 6, 0)
		shopBillboard.AlwaysOnTop = true
		shopBillboard.Adornee = basePart
		shopBillboard.Parent = basePart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
		label.BackgroundTransparency = 0.35
		label.BorderSizePixel = 0
		label.Text = "Buy weapons here!"
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextSize = 15
		label.Font = Enum.Font.GothamBold
		label.Parent = shopBillboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
	end

	local t = 0
	shopArrowHeartbeat = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		local pulse = 0.1 + math.abs(math.sin(t * 2.5)) * 0.3

		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not hrp or not shopTargetPos then
			return
		end

		local groundY = shopGroundY or shopTargetPos.Y
		local from = Vector3.new(hrp.Position.X, groundY, hrp.Position.Z)
		local to = Vector3.new(shopTargetPos.X, groundY, shopTargetPos.Z)
		local dir = to - from
		local dist = dir.Magnitude

		local function setArrowTransparency(obj, t)
			if obj:IsA("Model") then
				for _, part in ipairs(obj:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Transparency = t
					end
				end
			elseif obj:IsA("BasePart") then
				obj.Transparency = t
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
			for _, p in ipairs(shopArrowParts) do
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
		local visibleCount = math.clamp(math.floor(dist / SHOP_ARROW_SPACING), 1, SHOP_ARROW_COUNT)

		for i, p in ipairs(shopArrowParts) do
			if p and p.Parent then
				if i <= visibleCount then
					local offset = i * SHOP_ARROW_SPACING
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

local FTUEPadArrowsGUI = {}

function FTUEPadArrowsGUI.Init()
	if initialized then
		return
	end
	initialized = true

	CombatServiceClient.SubscribeMatchEnded(function()
		hasCompletedFirstMatch = true
		FTUEPadArrowsGUI.Hide()
	end)

	ShopGUI.SubscribeOnOpen(function()
		hasShownShopArrows = true
		hideShopArrows()
	end)

	LobbyServiceClient.Subscribe(function(state)
		if not state then
			return
		end
		if state.phase == LobbyConfig.PHASE.ARENA or state.phase == LobbyConfig.PHASE.WAITING_LOBBY then
			FTUEPadArrowsGUI.Hide()
			hideShopArrows()
		elseif state.phase == LobbyConfig.PHASE.LOBBY then
			if not hasCompletedFirstMatch then
				FTUEPadArrowsGUI.Show()
			end
			if not hasShownShopArrows then
				task.spawn(showShopArrows)
			end
		end
	end)

	FTUEPadArrowsGUI.Show()
	task.spawn(showShopArrows)
end

function FTUEPadArrowsGUI.Show()
	if hasCompletedFirstMatch then
		return
	end
	if #arrowParts == 0 then
		local padsFolder = resolvePadsFolder()
		if padsFolder then
			local bluePad = padsFolder:FindFirstChild(LobbyConfig.LOBBY_BLUE_PAD_MODEL_NAME)
			local redPad = padsFolder:FindFirstChild(LobbyConfig.LOBBY_RED_PAD_MODEL_NAME)
			if bluePad then
				createArrow(bluePad, COLOR_BLUE)
			end
			if redPad then
				createArrow(redPad, COLOR_RED)
			end
			startAnimation()
		end
	end
	createPlayButton()
end

function FTUEPadArrowsGUI.Hide()
	destroyArrows()
	destroyPlayButton()
end

return FTUEPadArrowsGUI
