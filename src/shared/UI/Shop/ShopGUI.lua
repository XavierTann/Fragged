--[[
	Client shop overlay: React tree under PlayerGui, starts disabled.
	Call ShopGUI.Show() when the player should see it (e.g. shop pad / prompt).
	Automatically hides when entering the arena so it does not cover combat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared.Modules.LobbyConfig)
local LobbyServiceClient = require(Shared.Services.LobbyServiceClient)
local ShopReactMount = require(script.Parent.ShopReactMount)

local LocalPlayer = Players.LocalPlayer

local ShopGUI = {}

local mountHandle = nil
local lastCoins = 1250

local function pushProps()
	if not mountHandle then
		return
	end
	mountHandle:renderProps({
		coins = lastCoins,
		onClose = nil,
		onPurchase = function(_item)
			-- Wire to ShopService when available
		end,
	})
end

function ShopGUI.Init()
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	mountHandle = ShopReactMount.mount({
		parent = pg,
		props = {},
	})
	pushProps()
	mountHandle:setEnabled(false)

	LobbyServiceClient.Subscribe(function(state)
		if state and state.phase == LobbyConfig.PHASE.ARENA and mountHandle then
			mountHandle:setEnabled(false)
		end
	end)
end

function ShopGUI.SetCoins(coins: number)
	lastCoins = coins
	pushProps()
end

function ShopGUI.Show()
	if mountHandle then
		mountHandle:setEnabled(true)
	end
end

function ShopGUI.Hide()
	if mountHandle then
		mountHandle:setEnabled(false)
	end
end

return ShopGUI
