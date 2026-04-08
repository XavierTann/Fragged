--[[
	LobbyPadScreens (server)
	Updates SurfaceGui text under SpawnPads/BluePadScreen and RedPadScreen (Glass/SurfaceGui/Frame):
	PlayerCount per team, Alert per team — independent copy from that team's queue count.
]]

local Workspace = game:GetService("Workspace")

local LobbyConfig = require(game:GetService("ReplicatedStorage").Shared.Modules.LobbyConfig)
local TeamDisplayUtils = require(game:GetService("ReplicatedStorage").Shared.Modules.TeamDisplayUtils)

local T = LobbyConfig.TEXT

local function getSpawnPadsFolder()
	local inst = Workspace
	for _, name in ipairs(LobbyConfig.LOBBY_PADS_FOLDER_PATH) do
		inst = inst and inst:FindFirstChild(name)
	end
	return inst
end

local function resolvePath(parent, segments)
	local p = parent
	for _, name in ipairs(segments) do
		p = p and p:FindFirstChild(name)
	end
	return p
end

local function findFrameUnderScreen(spawnPads, screenName)
	if not spawnPads then
		return nil
	end
	local root = spawnPads:FindFirstChild(screenName)
	if not root then
		return nil
	end
	local frame = resolvePath(root, LobbyConfig.LOBBY_PAD_SCREEN_FRAME_SEGMENTS)
	if frame and frame:IsA("GuiObject") then
		return frame
	end
	return nil
end

local function findTextChild(frame, name)
	if not frame then
		return nil
	end
	local c = frame:FindFirstChild(name)
	if c and (c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox")) then
		return c
	end
	return nil
end

local function teamLowerKey(team)
	return team == "Blue" and "blue" or "red"
end

local function playerCountLine(count, screenTeam)
	local key = teamLowerKey(screenTeam)
	if count == 1 then
		return string.format(T.PAD_SCREEN_PLAYER_COUNT_ONE, count, key)
	end
	return string.format(T.PAD_SCREEN_PLAYER_COUNT_MANY, count, key)
end

--[[
	Alert for one pad only. Priority: fill minimum per team, then rebalance if the other team is larger.
]]
local function alertTextForTeam(screenTeam, blueCount, redCount)
	local minTeam = LobbyConfig.MIN_PLAYERS_PER_TEAM or 2
	local c = screenTeam == "Blue" and blueCount or redCount
	local o = screenTeam == "Blue" and redCount or blueCount
	local name = TeamDisplayUtils.displayName(screenTeam)

	if c < minTeam then
		local need = minTeam - c
		if need == 1 then
			return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_ONE, name)
		end
		return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_MANY, need, name)
	end

	if o > c then
		local need = o - c
		if need == 1 then
			return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_ONE, name)
		end
		return string.format(T.PAD_SCREEN_TEAM_NEED_MORE_MANY, need, name)
	end

	return string.format(T.PAD_SCREEN_TEAM_HAS_ENOUGH, name)
end

local function setTextIfChanged(guiObject, text)
	if not guiObject then
		return
	end
	if (guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox")) and guiObject.RichText ~= nil then
		guiObject.RichText = true
	end
	if guiObject.Text ~= text then
		guiObject.Text = text
	end
end

local function sync(state)
	local spawnPads = getSpawnPadsFolder()
	local blueFrame = findFrameUnderScreen(spawnPads, LobbyConfig.LOBBY_BLUE_PAD_SCREEN_NAME)
	local redFrame = findFrameUnderScreen(spawnPads, LobbyConfig.LOBBY_RED_PAD_SCREEN_NAME)

	local b = #state.waitingQueueBlue
	local r = #state.waitingQueueRed

	local bluePlayerLine = playerCountLine(b, "Blue")
	local redPlayerLine = playerCountLine(r, "Red")
	local blueAlert = alertTextForTeam("Blue", b, r)
	local redAlert = alertTextForTeam("Red", b, r)

	if blueFrame then
		setTextIfChanged(findTextChild(blueFrame, LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_COUNT_NAME), bluePlayerLine)
		setTextIfChanged(findTextChild(blueFrame, LobbyConfig.LOBBY_PAD_SCREEN_ALERT_NAME), blueAlert)
	end
	if redFrame then
		setTextIfChanged(findTextChild(redFrame, LobbyConfig.LOBBY_PAD_SCREEN_PLAYER_COUNT_NAME), redPlayerLine)
		setTextIfChanged(findTextChild(redFrame, LobbyConfig.LOBBY_PAD_SCREEN_ALERT_NAME), redAlert)
	end
end

return {
	sync = sync,
}
