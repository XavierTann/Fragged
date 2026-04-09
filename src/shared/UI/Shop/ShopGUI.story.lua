--[[
	UI Labs / story-style preview: Rojo syncs this ModuleScript; open in UI Labs (or run the
	helper below in the Command Bar) to view the shop without playing a full match.

	UI Labs: point the plugin at this module. Many versions expect a function (target) -> cleanup:
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local ShopApp = require(script.Parent.ShopApp)

local e = React.createElement

return function(target: Instance)
	local root = ReactRoblox.createRoot(target)
	root:render(e(ShopApp, {
		coins = 2840,
		onClose = function()
			-- Preview only
		end,
		onPurchase = function(item)
			print("[Shop preview] purchase", item.name)
		end,
	}))
	return function()
		root:unmount()
	end
end
