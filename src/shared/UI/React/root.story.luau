--[[
	UI Labs (or similar) story: mounts Shared.UI.RootUI into the preview parent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RootUI = require(script.Parent.RootUI)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local e = React.createElement

return function(parent)
	local root = ReactRoblox.createRoot(parent)
	local app = e(RootUI.App)
	root:render(app)

	return function()
		root:unmount()
	end
end
