--[[
	Shared React root lifecycle for PlayerGui ScreenGui or UI Labs preview target.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local ShopApp = require(script.Parent.ShopApp)

local e = React.createElement

export type ShopAppProps = {
	coins: number?,
	items: any?,
	onClose: (() -> ())?,
	onPurchase: ((any) -> ())?,
}

export type MountHandle = {
	destroy: (self: MountHandle) -> (),
	setEnabled: (self: MountHandle, enabled: boolean) -> (),
	renderProps: (self: MountHandle, props: ShopAppProps?) -> (),
}

export type MountOptions = {
	parent: Instance,
	props: ShopAppProps?,
	screenGuiName: string?,
	displayOrder: number?,
}

local Mount = {}

function Mount.mount(options: MountOptions): MountHandle
	local parent = options.parent
	local props = options.props or {}
	local screenGuiName = options.screenGuiName or "ShopReactGUI"
	local displayOrder = options.displayOrder or 25

	local host: Instance
	local screenGui: ScreenGui? = nil

	if parent:IsA("PlayerGui") then
		local sg = Instance.new("ScreenGui")
		sg.Name = screenGuiName
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = displayOrder
		sg.IgnoreGuiInset = false
		sg.Enabled = false
		sg.Parent = parent
		screenGui = sg
		host = sg
	else
		-- ScreenGui (or any Instance) used as the React root host
		host = parent
	end

	local root = ReactRoblox.createRoot(host)
	root:render(e(ShopApp, props))

	local handle = {}
	function handle:destroy()
		root:unmount()
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end
	function handle:setEnabled(enabled: boolean)
		local sg: ScreenGui? = screenGui
		if not sg and host:IsA("ScreenGui") then
			sg = host :: ScreenGui
		end
		if sg then
			sg.Enabled = enabled
		end
	end
	function handle:renderProps(newProps: ShopAppProps?)
		root:render(e(ShopApp, newProps or {}))
	end

	return handle
end

return Mount
