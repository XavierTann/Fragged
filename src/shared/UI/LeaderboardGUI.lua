--[[
	LeaderboardGUI
	Uses the StarterGui template: ScreenGui > Leaderboard > LeaderboardBG > BlueTeam / OrangeTeam
	(OrangeTeam preferred; RedTeam is still found for older templates.)
	Each team may include a Title header Frame (left untouched), UIListLayout, and Player1..PlayerN row Frames
	(cloned from one kept template; interior Name, Kills, Deaths, Assists on text controls).
	Optional CloseButton (GuiButton, e.g. ImageButton) under Leaderboard closes the overlay.
	Shown when MatchEnded fires, or mid-match from TDMScore > Background (isLiveLeaderboard).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamDisplayUtils = require(ReplicatedStorage.Shared.Modules.TeamDisplayUtils)

local LocalPlayer = Players.LocalPlayer

local screenGui = nil
local leaderboardFrame = nil
local blueTeamFrame = nil
local redTeamFrame = nil
local playerRowTemplate = nil
local closeLiveButton = nil
local templateCloseBoundFrame = nil

local BACKGROUND_TRANSPARENCY = 0.45

local function findLeaderboardRefs()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") then
			local root = sg:FindFirstChild("Leaderboard")
			if root and root:IsA("GuiObject") then
				local bg = root:FindFirstChild("LeaderboardBG")
				if bg then
					local blue = bg:FindFirstChild("BlueTeam")
					local red = bg:FindFirstChild("OrangeTeam") or bg:FindFirstChild("RedTeam")
					if blue and red then
						screenGui = sg
						leaderboardFrame = root
						blueTeamFrame = blue
						redTeamFrame = red
						return true
					end
				end
			end
		end
	end
	return false
end

local function waitForLeaderboardRefs()
	local deadline = os.clock() + 45
	while os.clock() < deadline do
		if findLeaderboardRefs() then
			return true
		end
		task.wait(0.25)
	end
	warn("[LeaderboardGUI] No leaderboard found under PlayerGui (ScreenGui > Leaderboard > LeaderboardBG > BlueTeam / OrangeTeam or RedTeam).")
	return false
end

local function playerSlotIndex(frame)
	if not frame:IsA("Frame") then
		return nil
	end
	return tonumber(string.match(frame.Name, "^Player(%d+)$"))
end

local function isTeamHeaderFrame(guiObject)
	return guiObject.Name == "Title"
end

local function ensurePlayerRowTemplate()
	if playerRowTemplate then
		return playerRowTemplate
	end
	if not blueTeamFrame or not redTeamFrame then
		return nil
	end
	local template = nil
	local function consumeTeam(teamFrame)
		local slots = {}
		for _, c in ipairs(teamFrame:GetChildren()) do
			local idx = playerSlotIndex(c)
			if idx then
				table.insert(slots, { frame = c, index = idx })
			end
		end
		table.sort(slots, function(a, b)
			return a.index < b.index
		end)
		for _, item in ipairs(slots) do
			local c = item.frame
			if not template then
				template = c
			else
				c:Destroy()
			end
		end
	end
	consumeTeam(blueTeamFrame)
	consumeTeam(redTeamFrame)
	if template then
		template.Parent = nil
		playerRowTemplate = template
	end
	return playerRowTemplate
end

local function clearTeamList(teamFrame)
	if not teamFrame then
		return
	end
	for _, c in ipairs(teamFrame:GetChildren()) do
		local keepLayoutOrHeader = c:IsA("UIListLayout")
			or (c:IsA("GuiObject") and isTeamHeaderFrame(c))
		if (not keepLayoutOrHeader) and c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function setTextIfAny(guiObject, text)
	if not guiObject then
		return
	end
	if
		guiObject:IsA("TextLabel")
		or guiObject:IsA("TextBox")
		or guiObject:IsA("TextButton")
	then
		guiObject.Text = ""
		guiObject.Text = text
	end
end

local NAME_FIELD_INST_NAMES = {
	Name = true,
	name = true,
	PlayerName = true,
	playerName = true,
	Username = true,
	DisplayName = true,
}

local function rowDisplayName(entry)
	local n = entry.playerName or entry.name or entry.displayName or entry.DisplayName
	if type(n) == "string" and n ~= "" then
		return n
	end
	return "Player"
end

local function populateRow(row, entry)
	local nameText = rowDisplayName(entry)
	local kills = tostring(entry.kills or 0)
	local deaths = tostring(entry.deaths or 0)
	local assists = tostring(entry.assists or 0)

	for _, inst in ipairs(row:GetDescendants()) do
		local isText = inst:IsA("TextLabel") or inst:IsA("TextBox") or inst:IsA("TextButton")
		if isText then
			if NAME_FIELD_INST_NAMES[inst.Name] then
				setTextIfAny(inst, nameText)
			elseif inst.Name == "Kills" then
				setTextIfAny(inst, kills)
			elseif inst.Name == "Deaths" then
				setTextIfAny(inst, deaths)
			elseif inst.Name == "Assists" then
				setTextIfAny(inst, assists)
			end
		end
	end
end

local function fillTeam(teamFrame, players)
	if not teamFrame or not playerRowTemplate then
		return
	end
	clearTeamList(teamFrame)
	for _, entry in ipairs(players or {}) do
		local row = playerRowTemplate:Clone()
		row.Name = "PlayerRow"
		row.Visible = true
		row.Parent = teamFrame
		populateRow(row, entry)
	end
end

local function hideLeaderboard()
	-- Do not set screenGui.Enabled = false: TDMScore and other HUD may share this ScreenGui.
	if leaderboardFrame and leaderboardFrame:IsA("GuiObject") then
		leaderboardFrame.Visible = false
	end
	if closeLiveButton then
		closeLiveButton.Visible = false
	end
end

local function ensureCloseLiveButton()
	if not leaderboardFrame then
		return nil
	end
	if closeLiveButton and closeLiveButton.Parent then
		return closeLiveButton
	end
	closeLiveButton = Instance.new("TextButton")
	closeLiveButton.Name = "CloseLiveLeaderboard"
	closeLiveButton.Size = UDim2.fromOffset(140, 40)
	closeLiveButton.Position = UDim2.new(0.5, -70, 1, -16)
	closeLiveButton.AnchorPoint = Vector2.new(0.5, 1)
	closeLiveButton.BackgroundColor3 = Color3.fromRGB(55, 65, 90)
	closeLiveButton.BackgroundTransparency = BACKGROUND_TRANSPARENCY
	closeLiveButton.BorderSizePixel = 0
	closeLiveButton.Text = "Close"
	closeLiveButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	closeLiveButton.TextSize = 16
	closeLiveButton.Font = Enum.Font.GothamBold
	closeLiveButton.AutoButtonColor = true
	closeLiveButton.ZIndex = 10
	closeLiveButton.Visible = false
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeLiveButton
	closeLiveButton.MouseButton1Click:Connect(hideLeaderboard)
	closeLiveButton.Parent = leaderboardFrame
	return closeLiveButton
end

local function bindTemplateCloseButton()
	if not leaderboardFrame then
		return
	end
	local closeBtn = leaderboardFrame:FindFirstChild("CloseButton")
	if not closeBtn or not closeBtn:IsA("GuiButton") then
		return
	end
	if templateCloseBoundFrame == leaderboardFrame then
		return
	end
	templateCloseBoundFrame = leaderboardFrame
	closeBtn.Activated:Connect(hideLeaderboard)
end

local function applyOptionalTitleAndWinner(payload)
	if not leaderboardFrame then
		return
	end
	local isLive = payload.isLiveLeaderboard == true
	-- Direct child only: avoid picking up BlueTeam/OrangeTeam "Title" header frames.
	local titleInst = leaderboardFrame:FindFirstChild("Title")
	if titleInst and titleInst:IsA("TextLabel") then
		titleInst.Text = isLive and "Leaderboard" or "Match Results"
	end
	local winnerInst = leaderboardFrame:FindFirstChild("WinnerText", true)
	if winnerInst and winnerInst:IsA("TextLabel") then
		local wt = payload.winningTeam
		if wt and not isLive then
			winnerInst.Visible = true
			winnerInst.Text = TeamDisplayUtils.teamVictoryPhrase(wt)
		else
			winnerInst.Visible = false
			winnerInst.Text = ""
		end
	end
end

local function showLeaderboard(payload)
	if not waitForLeaderboardRefs() then
		return
	end
	ensurePlayerRowTemplate()
	if not playerRowTemplate then
		warn("[LeaderboardGUI] No Player1..PlayerN row template under BlueTeam or OrangeTeam/RedTeam.")
		return
	end

	fillTeam(blueTeamFrame, payload.bluePlayers)
	fillTeam(redTeamFrame, payload.redPlayers)
	applyOptionalTitleAndWinner(payload)

	if screenGui then
		screenGui.Enabled = true
	end
	if leaderboardFrame and leaderboardFrame:IsA("GuiObject") then
		leaderboardFrame.Visible = true
	end

	bindTemplateCloseButton()
	local templateCloseBtn = leaderboardFrame and leaderboardFrame:FindFirstChild("CloseButton")
	local hasTemplateClose = templateCloseBtn and templateCloseBtn:IsA("GuiButton")

	if hasTemplateClose then
		if closeLiveButton then
			closeLiveButton.Visible = false
		end
	else
		local btn = ensureCloseLiveButton()
		if btn then
			btn.Visible = payload.isLiveLeaderboard == true
		end
	end
end

local function init()
	task.defer(function()
		if waitForLeaderboardRefs() then
			ensurePlayerRowTemplate()
			bindTemplateCloseButton()
			if leaderboardFrame and leaderboardFrame:IsA("GuiObject") then
				leaderboardFrame.Visible = false
			end
		end
	end)
end

return {
	Init = init,
	Show = function(payload)
		if payload then
			showLeaderboard(payload)
		elseif screenGui then
			screenGui.Enabled = true
			if leaderboardFrame and leaderboardFrame:IsA("GuiObject") then
				leaderboardFrame.Visible = true
			end
		end
	end,
	Hide = hideLeaderboard,
}
