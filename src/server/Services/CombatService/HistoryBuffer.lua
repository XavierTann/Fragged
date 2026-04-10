--[[
	HistoryBuffer
	Per-player ring buffer of HumanoidRootPart transforms recorded every Heartbeat.
	Used by the rewind system to interpolate historical positions for lag compensation.
]]

local HistoryBuffer = {}
HistoryBuffer.__index = HistoryBuffer

function HistoryBuffer.new(maxDurationSeconds: number)
	return setmetatable({
		maxDuration = maxDurationSeconds or 0.6,
		playerHistory = {},
	}, HistoryBuffer)
end

function HistoryBuffer:record(players: { Player }, now: number)
	local cutoff = now - self.maxDuration
	for _, player in ipairs(players) do
		local uid = player.UserId
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local history = self.playerHistory[uid]
			if not history then
				history = {}
				self.playerHistory[uid] = history
			end
			history[#history + 1] = {
				time = now,
				position = hrp.Position,
				cframe = hrp.CFrame,
			}
			local pruneCount = 0
			for i = 1, #history do
				if history[i].time < cutoff then
					pruneCount = i
				else
					break
				end
			end
			if pruneCount > 0 then
				local newHistory = {}
				for i = pruneCount + 1, #history do
					newHistory[#newHistory + 1] = history[i]
				end
				self.playerHistory[uid] = newHistory
			end
		end
	end
end

function HistoryBuffer:getStateAtTime(userId: number, targetTime: number)
	local history = self.playerHistory[userId]
	if not history or #history == 0 then
		return nil
	end
	if targetTime <= history[1].time then
		return history[1]
	end
	if targetTime >= history[#history].time then
		return history[#history]
	end
	for i = 2, #history do
		if history[i].time >= targetTime then
			local a = history[i - 1]
			local b = history[i]
			local span = b.time - a.time
			if span < 1e-6 then
				return b
			end
			local t = (targetTime - a.time) / span
			return {
				time = targetTime,
				position = a.position:Lerp(b.position, t),
				cframe = a.cframe:Lerp(b.cframe, t),
			}
		end
	end
	return history[#history]
end

function HistoryBuffer:clearPlayer(userId: number)
	self.playerHistory[userId] = nil
end

function HistoryBuffer:clearAll()
	table.clear(self.playerHistory)
end

function HistoryBuffer:entryCount(userId: number): number
	local h = self.playerHistory[userId]
	return h and #h or 0
end

return HistoryBuffer
