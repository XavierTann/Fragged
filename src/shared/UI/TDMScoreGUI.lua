--[[
	TDMScoreGUI
	Drives the Studio-built TDM score UI: PlayerGui.ScreenGui.TDMScore with
	BlueTeamScore and RedTeamScore (TextLabels). Updates when TeamScoreUpdate fires.
	Clicks on the ImageButton child "Background" open the live K/D leaderboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		local data = CombatServiceClient.RequestLiveLeaderboard()
		if data then
			LeaderboardGUI.Show(data)
		end
	end)
end

local function bindRefs()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("ScreenGui")
	tdmScoreFrame = screenGui:WaitForChild("TDMScore")
	blueScoreLabel = tdmScoreFrame:WaitForChild("BlueTeamScore")
	redScoreLabel = tdmScoreFrame:WaitForChild("RedTeamScore")
	wireBackgroundButton()
end

-- After respawn, ScreenGui may be re-cloned if ResetOnSpawn is true; recover labels.
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
	local frame = sg:FindFirstChild("TDMScore")
	if not frame then
		return false
	end
	local blue = frame:FindFirstChild("BlueTeamScore")
	local red = frame:FindFirstChild("RedTeamScore")
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
				sg.Enabled = true
			end
			tdmScoreFrame.Visible = true
			updateScore(0, 0)
		end
	end,
	Hide = function()
		if ensureRefs() then
			tdmScoreFrame.Visible = false
		end
	end,
	UpdateScore = updateScore,
}
