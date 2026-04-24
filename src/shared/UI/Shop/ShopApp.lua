--[[
	Sci-fi shop shell built with jsdotlua React + react-roblox host components.
	Parent should be a ScreenGui or Frame sized to the preview area.
	All sizing and positioning uses Scale (UDim2.fromScale) for cross-device responsiveness.
	Layout constants come from ShopGUIConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent.ShopTheme)
local UIConfig = require(Shared.Modules.ShopGUIConfig)

local e = React.createElement

export type ShopItem = {
	id: string,
	name: string,
	price: number,
	tag: string?,
	accent: Color3?,
	imageAssetId: number?,
	buyLabel: string?,
	buyDisabled: boolean?,
	statusNote: string?,
}

local DEFAULT_ITEMS: { ShopItem } = {
	{
		id = "PlasmaCarbine",
		name = "Plasma Carbine",
		price = 1200,
		tag = "RIFLE",
		accent = Theme.NeonMagenta,
		imageAssetId = 85001511160443,
	},
	{
		id = "HeliosThread",
		name = "Helios Thread",
		price = 980,
		tag = "BEAM",
		accent = Theme.NeonCyan,
		imageAssetId = 14826766010,
	},
	{
		id = "PrismRipper",
		name = "Prism Ripper",
		price = 750,
		tag = "RICO",
		accent = Theme.NeonLime,
		imageAssetId = 117104799815404,
	},
}

local function corner(radius: number)
	return e("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function itemCard(item: ShopItem, layoutOrder: number, onBuy: (ShopItem) -> ())
	local accent = item.accent or Theme.NeonCyan
	local buyLabel = item.buyLabel or "BUY"
	local buyDisabled = item.buyDisabled == true
	local statusNote = item.statusNote
	local cardH = if statusNote then UIConfig.Card.HeightWithNote else UIConfig.Card.HeightNormal
	local C = UIConfig.Card
	local CI = UIConfig.CardIcon

	local rowChildren: { any } = {
		corner(C.CornerRadius),
		e("UIStroke", {
			Color = accent,
			Thickness = C.StrokeThickness,
			Transparency = 0.35,
		}),
		e("UIPadding", {
			PaddingTop = UDim.new(C.PadTop, 0),
			PaddingBottom = UDim.new(C.PadBottom, 0),
			PaddingLeft = UDim.new(C.PadLeft, 0),
			PaddingRight = UDim.new(C.PadRight, 0),
		}),
		item.imageAssetId and e("ImageLabel", {
			Size = UDim2.fromScale(CI.Width, CI.Height),
			Position = UDim2.fromScale(CI.PosX, CI.PosY),
			BackgroundColor3 = Theme.PanelDeep,
			BorderSizePixel = 0,
			Image = "rbxassetid://" .. tostring(item.imageAssetId),
			ScaleType = Enum.ScaleType.Fit,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, CI.CornerRadius) }),
			e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
			e("UIStroke", {
				Color = accent,
				Thickness = 1,
				Transparency = 0.4,
			}),
		}) or e("Frame", {
			Size = UDim2.fromScale(CI.Width, CI.Height),
			Position = UDim2.fromScale(CI.PosX, CI.PosY),
			BackgroundColor3 = Theme.PanelDeep,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, CI.CornerRadius) }),
			e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
			e("UIStroke", {
				Color = accent,
				Thickness = 1,
				Transparency = 0.55,
			}),
			e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "◇",
				TextColor3 = Theme.TextMuted,
				TextScaled = true,
				Font = Theme.FontBody,
			}),
		}),
		e("TextLabel", {
			Size = UDim2.fromScale(1 - UIConfig.CardName.PosX - UIConfig.CardName.RightInset, UIConfig.CardName.Height),
			Position = UDim2.fromScale(UIConfig.CardName.PosX, UIConfig.CardName.PosY),
			BackgroundTransparency = 1,
			Text = item.name,
			TextColor3 = Theme.TextBright,
			TextScaled = true,
			Font = Theme.FontDisplay,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	}

	if item.tag then
		table.insert(
			rowChildren,
			e("TextLabel", {
				Size = UDim2.fromScale(UIConfig.CardTag.Width, UIConfig.CardTag.Height),
				Position = UDim2.fromScale(1 - UIConfig.CardTag.PosXFromRight, UIConfig.CardTag.PosY),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.5,
				Text = item.tag,
				TextColor3 = Theme.BgVoid,
				TextScaled = true,
				Font = Theme.FontBody,
			}, {
				corner(UIConfig.CardTag.CornerRadius),
			})
		)
	end

	table.insert(
		rowChildren,
		e("TextLabel", {
			Size = UDim2.fromScale(1 - UIConfig.CardPrice.PosX - UIConfig.CardPrice.RightInset, UIConfig.CardPrice.Height),
			Position = UDim2.fromScale(UIConfig.CardPrice.PosX, UIConfig.CardPrice.PosY),
			BackgroundTransparency = 1,
			Text = string.format("◆ %d credits", item.price),
			TextColor3 = Theme.NeonAmber,
			TextScaled = true,
			Font = Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	)

	if statusNote then
		table.insert(
			rowChildren,
			e("TextLabel", {
				Size = UDim2.fromScale(1 - UIConfig.CardStatus.PosX - UIConfig.CardStatus.RightInset, UIConfig.CardStatus.Height),
				Position = UDim2.fromScale(UIConfig.CardStatus.PosX, UIConfig.CardStatus.PosY),
				BackgroundTransparency = 1,
				Text = statusNote,
				TextColor3 = Theme.TextMuted,
				TextScaled = true,
				Font = Theme.FontBody,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		)
	end

	local btnBg = if buyDisabled then Theme.PanelDeep else accent
	local btnText = if buyDisabled then Theme.TextMuted else Theme.BgVoid

	table.insert(
		rowChildren,
		e("TextButton", {
			Size = UDim2.fromScale(UIConfig.CardBuyBtn.Width, UIConfig.CardBuyBtn.Height),
			Position = UDim2.fromScale(1 - UIConfig.CardBuyBtn.Width, 1 - UIConfig.CardBuyBtn.Height),
			BackgroundColor3 = btnBg,
			BorderSizePixel = 0,
			Text = buyLabel,
			TextColor3 = btnText,
			TextScaled = true,
			Font = Theme.FontDisplay,
			AutoButtonColor = not buyDisabled,
			Active = not buyDisabled,
			Selectable = not buyDisabled,
			[React.Event.Activated] = function()
				if not buyDisabled then
					onBuy(item)
				end
			end,
		}, {
			corner(UIConfig.CardBuyBtn.CornerRadius),
			e("UIPadding", {
				PaddingLeft = UDim.new(UIConfig.CardBuyBtn.TextPadX, 0),
				PaddingRight = UDim.new(UIConfig.CardBuyBtn.TextPadX, 0),
				PaddingTop = UDim.new(UIConfig.CardBuyBtn.TextPadY, 0),
				PaddingBottom = UDim.new(UIConfig.CardBuyBtn.TextPadY, 0),
			}),
		})
	)

	return e(
		"Frame",
		{
			Size = UDim2.fromScale(UIConfig.Card.Width, cardH),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			LayoutOrder = layoutOrder,
		},
		rowChildren
	)
end

export type ShopAppProps = {
	coins: number?,
	items: { ShopItem }?,
	onClose: (() -> ())?,
	onPurchase: ((ShopItem) -> ())?,
}

local function ShopApp(props: ShopAppProps)
	local coins = props.coins or 0
	local items = props.items or DEFAULT_ITEMS
	local onClose = props.onClose
	local onPurchase = props.onPurchase or function(_item: ShopItem) end

	local modalW = UIConfig.Modal.Width
	local modalH = UIConfig.Modal.Height
	local headerH = UIConfig.Header.Height
	local creditPosX = UIConfig.CreditPill.PosX

	local listChildren: { any } = {
		e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(UIConfig.List.Spacing, 0),
		}),
		e("UIPadding", {
			PaddingTop = UDim.new(UIConfig.List.PadTop, 0),
			PaddingBottom = UDim.new(UIConfig.List.PadBottom, 0),
			PaddingLeft = UDim.new(UIConfig.List.PadX, 0),
			PaddingRight = UDim.new(UIConfig.List.PadX, 0),
		}),
	}

	for i, it in ipairs(items) do
		table.insert(listChildren, itemCard(it, i, onPurchase))
	end

	local creditStr = string.format("CR %s", tostring(coins))

	local headerChildren: { any } = {
		e("TextLabel", {
			Size = UDim2.fromScale(0.6, 1),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Text = "ORBITAL SUPPLY",
			TextColor3 = Theme.TextBright,
			TextScaled = true,
			Font = Theme.FontDisplay,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 1,
		}),
		e("Frame", {
			Size = UDim2.fromScale(UIConfig.CreditPill.Width, UIConfig.CreditPill.Height),
			Position = UDim2.fromScale(creditPosX, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Theme.Card,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 2,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, UIConfig.CreditPill.CornerRadius) }),
			e("UIStroke", {
				Color = Theme.NeonAmber,
				Thickness = 1,
				Transparency = 0.35,
			}),
			e("UIPadding", {
				PaddingLeft = UDim.new(UIConfig.CreditPill.PadX, 0),
				PaddingRight = UDim.new(UIConfig.CreditPill.PadX, 0),
				PaddingTop = UDim.new(UIConfig.CreditPill.PadY, 0),
				PaddingBottom = UDim.new(UIConfig.CreditPill.PadY, 0),
			}),
			e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				Text = creditStr,
				TextColor3 = Theme.NeonAmber,
				TextScaled = true,
				Font = Theme.FontBody,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
			}),
		}),
	}

	if onClose then
		table.insert(
			headerChildren,
			e("TextButton", {
				Size = UDim2.fromScale(UIConfig.CloseBtn.Width, 1),
				Position = UDim2.fromScale(UIConfig.CloseBtn.PosX, 0.5),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = Theme.PanelDeep,
				BorderSizePixel = 0,
				Text = "X",
				TextColor3 = Theme.TextBright,
				TextScaled = true,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = false,
				ZIndex = 4,
				[React.Event.Activated] = function()
					onClose()
				end,
			}, {
				e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
				e("UIStroke", {
					Color = Theme.NeonMagenta,
					Thickness = UIConfig.CloseBtn.StrokeThickness,
					Transparency = 0.2,
				}),
			})
		)
	end

	local scrollBarThickness = UIConfig.Body.ScrollBarThickness

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Overlay,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 1,
			[React.Event.Activated] = function() end,
		}),
		e("Frame", {
			Size = UDim2.fromScale(modalW, modalH),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 2,
		}, {
			corner(UIConfig.Modal.CornerRadius),
			e("UIStroke", {
				Color = Theme.NeonCyan,
				Thickness = UIConfig.Modal.StrokeThickness,
				Transparency = 0.2,
			}),
			e("ImageLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = "rbxassetid://95341433832521",
				ScaleType = Enum.ScaleType.Crop,
				ImageTransparency = 0.3,
				ZIndex = 0,
			}, {
				corner(UIConfig.Modal.CornerRadius),
			}),
			e("Frame", {
				Size = UDim2.fromScale(1, headerH),
				Position = UDim2.fromScale(0, UIConfig.Header.PosY),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, headerChildren),
			e("ScrollingFrame", {
				Size = UDim2.fromScale(UIConfig.Body.Width, UIConfig.Body.Height),
				Position = UDim2.fromScale(UIConfig.Body.PosX, UIConfig.Body.PosY),
				BackgroundColor3 = Theme.PanelDeep,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ScrollBarThickness = scrollBarThickness,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarImageColor3 = Theme.NeonCyan,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.fromScale(0, 0),
			}, {
				corner(UIConfig.Body.CornerRadius),
				e("Frame", {
					Size = UDim2.fromScale(1 - UIConfig.Body.InnerPadX * 2, 0),
					Position = UDim2.fromScale(UIConfig.Body.InnerPadX, UIConfig.Body.InnerPadY),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}, listChildren),
			}),
		}),
	})
end

return ShopApp
