--[[
	React root tree for the client. Expand with real screens as needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local RootUI = {}

function RootUI.App()
	return React.createElement(
		"TextLabel",
		{
			Size = UDim2.fromOffset(320, 56),
			Position = UDim2.fromScale(0.5, 0.12),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(32, 36, 52),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Text = "Hello World (React)",
			TextSize = 22,
			Font = Enum.Font.GothamBold,
			BorderSizePixel = 0,
		},
		React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		})
	)
end

return RootUI
