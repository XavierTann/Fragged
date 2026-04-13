--[[
	TDMScoreGUI
	Drives the Studio-built TDM score UI: PlayerGui.ScreenGui.TDMScore with
	BlueTeamScore and RedTeamScore (TextLabels; OrangeTeamScore still supported for older UI).
	Updates when TeamScoreUpdate fires.
	Clicks on the ImageButton child "Background" open the live K/D leaderboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Modules.CombatConfig)
local TDMConfig = require(Shared.Modules.TDMConfig)
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local LeaderboardGUI = require(Shared.UI.LeaderboardGUI)

local KILL_LIMIT = TDMConfig.KILL_LIMIT

local tdmScoreFrame = nil
local blueScoreLabel = nil
local redScoreLabel = nil

local backgroundClickConn = nil
local wiredBackgroundButton = nil
local hasShownFlashHint = false
local flashHighlight = nil
local flashTween = nil

local function stopFlashHint()
	if flashTween then
		flashTween:Cancel()
		flashTween = nil
	end
	if flashHighlight then
		flashHighlight:Destroy()
		flashHighlight = nil
	end
end

local FLASH_HALF_PERIOD = 0.45

local function startFlashHint(button)
	if not button then
		return
	end
	stopFlashHint()

	flashHighlight = Instance.new("Frame")
	flashHighlight.Name = "FlashHint"
	flashHighlight.Size = UDim2.fromScale(1, 1)
	flashHighlight.Position = UDim2.fromScale(0, 0)
	flashHighlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flashHighlight.BackgroundTransparency = 1
	flashHighlight.BorderSizePixel = 0
	flashHighlight.ZIndex = button.ZIndex + 1
	flashHighlight.Parent = button

	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = corner.CornerRadius
		c.Parent = flashHighlight
	end

	local tweenIn = TweenService:Create(flashHighlight, TweenInfo.new(FLASH_HALF_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.55 })
	local tweenOut = TweenService:Create(flashHighlight, TweenInfo.new(FLASH_HALF_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 })

	local fadingIn = true
	local function step()
		if not flashHighlight or not flashHighlight.Parent then
			return
		end
		fadingIn = not fadingIn
		if fadingIn then
			flashTween = tweenIn
			tweenIn:Play()
			tweenIn.Completed:Once(step)
		else
			flashTween = tweenOut
			tweenOut:Play()
			tweenOut.Completed:Once(step)
		end
	end

	flashTween = tweenIn
	tweenIn:Play()
	tweenIn.Completed:Once(step)
end

local function configureTdmScreenGui(sg)
	if sg and sg:IsA("ScreenGui") then
		sg.IgnoreGuiInset = true
		sg.ResetOnSpawn = false
	end
end

local function findBackgroundButton(frame)
	if not frame then
		return nil
	end
	local b = frame:FindFirstChild("Background") or frame:FindFirstChild("background")
	if b and b:IsA("GuiButton") then
		return b
	end
	return nil
end

local function wireBackgroundButton()
	if not tdmScoreFrame then
		return
	end
	local bg = findBackgroundButton(tdmScoreFrame)
	if bg == wiredBackgroundButton then
		return
	end
	if backgroundClickConn then
		backgroundClickConn:Disconnect()
		backgroundClickConn = nil
	end
	wiredBackgroundButton = bg
	if not bg then
		return
	end
	backgroundClickConn = bg.Activated:Connect(function()
		stopFlashHint()
		hasShownFlashHint = true
		local data = CombatServiceClient.RequestLiveLeaderboard()
		if data then
			LeaderboardGUI.Show(data)
		end
	end)
end

local function bindRefs()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui")
	configureTdmScreenGui(screenGui)
	tdmScoreFrame = screenGui:WaitForChild("TDMScore")
	blueScoreLabel = tdmScoreFrame:WaitForChild("BlueTeamScore")
	local redScore = tdmScoreFrame:FindFirstChild("RedTeamScore")
	redScoreLabel = redScore or tdmScoreFrame:WaitForChild("OrangeTeamScore")
	wireBackgroundButton()
end

-- Recover refs if the TDM tree was re-parented or replaced.
local function ensureRefs()
	if tdmScoreFrame and tdmScoreFrame.Parent and blueScoreLabel and blueScoreLabel.Parent and redScoreLabel and redScoreLabel.Parent then
		wireBackgroundButton()
		return true
	end
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	local sg = pg:FindFirstChild("ScreenGui")
	if not sg then
		return false
	end
	configureTdmScreenGui(sg)
	local frame = sg:FindFirstChild("TDMScore")
	if not frame then
		return false
	end
	local blue = frame:FindFirstChild("BlueTeamScore")
	local red = frame:FindFirstChild("RedTeamScore") or frame:FindFirstChild("OrangeTeamScore")
	if not (blue and red) then
		return false
	end
	tdmScoreFrame = frame
	blueScoreLabel = blue
	redScoreLabel = red
	wireBackgroundButton()
	return true
end

local function updateScore(blueKills, redKills)
	if not ensureRefs() then
		return
	end
	blueKills = blueKills or 0
	redKills = redKills or 0
	blueScoreLabel.Text = tostring(blueKills) .. "/" .. tostring(KILL_LIMIT)
	redScoreLabel.Text = tostring(redKills) .. "/" .. tostring(KILL_LIMIT)
end

local function init()
	bindRefs()
	tdmScoreFrame.Visible = false

	local folder = ReplicatedStorage:WaitForChild(CombatConfig.REMOTE_FOLDER_NAME)
	local teamScoreRE = folder:WaitForChild(CombatConfig.REMOTES.TEAM_SCORE_UPDATE)
	teamScoreRE.OnClientEvent:Connect(updateScore)
end

return {
	Init = init,
	Show = function()
		if ensureRefs() then
			local sg = tdmScoreFrame:FindFirstAncestorOfClass("ScreenGui")
			if sg then
				configureTdmScreenGui(sg)
				sg.Enabled = true
			end
			tdmScoreFrame.Visible = true
			updateScore(0, 0)
			if not hasShownFlashHint then
				hasShownFlashHint = true
				task.delay(1.5, function()
					startFlashHint(findBackgroundButton(tdmScoreFrame))
				end)
			end
		end
	end,
	Hide = function()
		stopFlashHint()
		if ensureRefs() then
			tdmScoreFrame.Visible = false
		end
	end,
	UpdateScore = updateScore,
}
