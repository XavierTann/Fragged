--[[
	Minimal Tool instances for guns not provided by StarterPack (e.g. shop unlocks).
]]

local function playerHasToolNamed(player, gunId: string): boolean
	local bp = player:FindFirstChild("Backpack")
	if bp and bp:FindFirstChild(gunId) then
		return true
	end
	local ch = player.Character
	return ch ~= nil and ch:FindFirstChild(gunId) ~= nil
end

local function createMinimalGunTool(gunId: string): Tool
	local t = Instance.new("Tool")
	t.Name = gunId
	t.CanBeDropped = false
	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Size = Vector3.new(0.25, 0.25, 1)
	h.Transparency = 1
	h.Massless = true
	h.CanCollide = false
	h.Parent = t
	return t
end

local WeaponToolServer = {}

function WeaponToolServer.giveGunToolIfMissing(player, gunId: string)
	if not player or not player.Parent then
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end
	if playerHasToolNamed(player, gunId) then
		return
	end
	local tool = createMinimalGunTool(gunId)
	tool.Parent = backpack
end

return WeaponToolServer
