--[[
	Minimal Tool instances for guns not provided by StarterPack (e.g. shop unlocks).
	Specific guns clone from ReplicatedStorage.Imports.3DModels when a template exists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinsConfig = require(ReplicatedStorage:WaitForChild("Shared").Modules.SkinsConfig)

-- First match wins; keep names aligned with Instances under Imports.3DModels.
local IMPORTED_GUN_TOOL_TEMPLATE_NAMES: { [string]: { string } } = {
	PlasmaCarbine = {
		"PlasmaCarbineTool",
		"Plasma Carbine",
		"PlasmaCarbine",
		"plasma carbine",
	},
	HeliosThread = {
		"HeliosThreadTool",
		"Helios Thread",
		"HeliosThread",
		"helios thread",
	},
	PrismRipper = {
		"PrismRipperTool",
		"Prism Ripper",
		"PrismRipper",
		"prism ripper",
	},
}

local function findImportedGunToolTemplate(gunId: string): Tool?
	local names = IMPORTED_GUN_TOOL_TEMPLATE_NAMES[gunId]
	if not names then
		return nil
	end
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	if not models3D then
		return nil
	end
	for _, name in ipairs(names) do
		local inst = models3D:FindFirstChild(name)
		if inst and inst:IsA("Tool") then
			return inst
		end
		if inst and inst:IsA("Model") then
			local inner = inst:FindFirstChildWhichIsA("Tool", true)
			if inner then
				return inner
			end
		end
	end
	return nil
end

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

local function findSkinToolTemplate(skinId: string): Tool?
	local skinDef = SkinsConfig.getSkin(skinId)
	if not skinDef then
		return nil
	end
	local imports = ReplicatedStorage:FindFirstChild("Imports")
	local models3D = imports and imports:FindFirstChild("3DModels")
	if not models3D then
		return nil
	end
	local skinsFolder = models3D:FindFirstChild("SkinTools")
	if not skinsFolder then
		return nil
	end
	local templateName = skinDef.toolTemplateName
	local inst = skinsFolder:FindFirstChild(templateName)
	if inst and inst:IsA("Tool") then
		return inst
	end
	if inst and inst:IsA("Model") then
		local inner = inst:FindFirstChildWhichIsA("Tool", true)
		if inner then
			return inner
		end
	end
	return nil
end

local WeaponToolServer = {}

function WeaponToolServer.giveGunToolIfMissing(player, gunId: string, skinId: string?)
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

	if skinId then
		local skinTemplate = findSkinToolTemplate(skinId)
		if skinTemplate then
			local tool = skinTemplate:Clone()
			tool.Name = gunId
			tool.CanBeDropped = false
			tool.Parent = backpack
			return
		end
	end

	local template = findImportedGunToolTemplate(gunId)
	if template then
		local tool = template:Clone()
		tool.Name = gunId
		tool.CanBeDropped = false
		tool.Parent = backpack
		return
	end
	local tool = createMinimalGunTool(gunId)
	tool.Parent = backpack
end

return WeaponToolServer
