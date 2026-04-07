--[[
	DirectionIndicatorClient
	Orchestrates move-direction dot + weapon aim overlays. Implementation under
	Shared/Services/DirectionIndicator/.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatServiceClient = require(Shared.Services.CombatServiceClient)
local Config = require(Shared.Services.DirectionIndicator.Config)
local MovementDot = require(Shared.Services.DirectionIndicator.MovementDot)
local WeaponAimOverlays = require(Shared.Services.DirectionIndicator.WeaponAimOverlays)

local LocalPlayer = Players.LocalPlayer

local renderConnection = nil
local smoothedAimOffsetXZ = Vector3.zero
local cachedWeapon = "Pistol"
-- Movement dot + aim beam are arena-only; lobby / shop keep these off.
local indicatorsEnabled = false

local function onRenderStep(dt)
	if not indicatorsEnabled then
		MovementDot.destroy()
		WeaponAimOverlays.destroyAll()
		smoothedAimOffsetXZ = Vector3.zero
		return
	end

	local character = LocalPlayer.Character
	if not character or not character.Parent then
		MovementDot.destroy()
		WeaponAimOverlays.destroyAll()
		smoothedAimOffsetXZ = Vector3.zero
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	if humanoid.Health <= 0 then
		MovementDot.destroy()
		WeaponAimOverlays.destroyAll()
		smoothedAimOffsetXZ = Vector3.zero
		MovementDot.resetSmoothed()
		return
	end

	MovementDot.update(dt, character, humanoid, root)

	local weapon = cachedWeapon
	local targetAim = WeaponAimOverlays.getAimOffsetTargetXZ(weapon)
	-- Smooth while aiming so the beam eases; when input drops to zero (e.g. joystick
	-- released after a shot), snap immediately — otherwise showAim stays true until the
	-- lerp decays past the threshold and the indicator feels laggy.
	local aimAlpha = 1 - math.exp(-Config.AIM_SMOOTH_RATE * dt)
	if targetAim.Magnitude < 1e-4 then
		smoothedAimOffsetXZ = Vector3.zero
	else
		smoothedAimOffsetXZ = smoothedAimOffsetXZ:Lerp(targetAim, aimAlpha)
	end

	local showAim = smoothedAimOffsetXZ.Magnitude > 0.08
	local startPos = root.Position + Vector3.new(0, Config.AIM_Y_ABOVE_ROOT, 0)

	WeaponAimOverlays.updateForWeapon({
		character = character,
		root = root,
		weapon = weapon,
		showAim = showAim,
		smoothedAimOffsetXZ = smoothedAimOffsetXZ,
		startPos = startPos,
	})
end

return {
	Init = function()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		MovementDot.destroy()
		WeaponAimOverlays.destroyAll()
		smoothedAimOffsetXZ = Vector3.zero
		cachedWeapon = CombatServiceClient.GetCurrentWeapon()

		CombatServiceClient.SubscribeWeaponChanged(function()
			cachedWeapon = CombatServiceClient.GetCurrentWeapon()
		end)

		LocalPlayer.CharacterRemoving:Connect(function()
			MovementDot.destroy()
			WeaponAimOverlays.destroyAll()
			smoothedAimOffsetXZ = Vector3.zero
			MovementDot.resetSmoothed()
		end)

		renderConnection = RunService.RenderStepped:Connect(onRenderStep)
	end,

	SetEnabled = function(enabled)
		indicatorsEnabled = enabled == true
		if not indicatorsEnabled then
			MovementDot.destroy()
			WeaponAimOverlays.destroyAll()
			smoothedAimOffsetXZ = Vector3.zero
			MovementDot.resetSmoothed()
		end
	end,
}
