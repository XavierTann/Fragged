--[[
	Sci-fi shop shell built with jsdotlua React + react-roblox host components.
	Parent should be a ScreenGui or Frame sized to the preview area.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.ShopTheme)

local e = React.createElement

export type ShopItem = {
	id: string,
	name: string,
	price: number,
	tag: string?,
	accent: Color3?,
	-- Roblox image/decal asset id for the shop icon (rbxassetid://…)
	imageAssetId: number?,
	buyLabel: string?,
	buyDisabled: boolean?,
	statusNote: string?,
}

local ICON_SIZE = 76
local ICON_PAD_X = 12
local TEXT_LEFT = ICON_PAD_X + ICON_SIZE + 10

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

local HEADER_H = 52
local BODY_PAD = 12

local function getShopModalLayout(): (number, number, number, number)
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	local topInset = 0
	pcall(function()
		topInset = GuiService:GetGuiInset().Y
	end)
	-- Tighter bottom/top margin + higher fraction so the panel uses almost all usable height.
	local bottomSafe = if UserInputService.TouchEnabled then 32 else 12
	local availH = math.max(80, vp.Y - topInset - bottomSafe - 4)
	local heightFraction = 0.98
	local h = math.max(240, math.floor(availH * heightFraction))
	if UserInputService.TouchEnabled then
		local chatPad = 14
		local w = math.floor(math.clamp(vp.X * 0.92, 280, 520))
		return w, h, chatPad, 28
	end
	local w = 520
	return w, h, 72, 8
end

local function itemCard(item: ShopItem, layoutOrder: number, onBuy: (ShopItem) -> ())
	local accent = item.accent or Theme.NeonCyan
	local buyLabel = item.buyLabel or "BUY"
	local buyDisabled = item.buyDisabled == true
	local statusNote = item.statusNote
	local cardHeight = if statusNote then 122 else 108
	local rowChildren: { any } = {
		corner(10),
		e("UIStroke", {
			Color = accent,
			Thickness = 1.5,
			Transparency = 0.35,
		}),
		e("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		item.imageAssetId and e("ImageLabel", {
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			Position = UDim2.fromOffset(ICON_PAD_X, 14),
			BackgroundColor3 = Theme.PanelDeep,
			BorderSizePixel = 0,
			Image = "rbxassetid://" .. tostring(item.imageAssetId),
			ScaleType = Enum.ScaleType.Fit,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			e("UIStroke", {
				Color = accent,
				Thickness = 1,
				Transparency = 0.4,
			}),
		}) or e("Frame", {
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			Position = UDim2.fromOffset(ICON_PAD_X, 14),
			BackgroundColor3 = Theme.PanelDeep,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, 8) }),
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
				TextSize = 28,
				Font = Theme.FontBody,
			}),
		}),
		e("TextLabel", {
			Size = UDim2.new(1, -(TEXT_LEFT + 100), 0, 22),
			Position = UDim2.fromOffset(TEXT_LEFT, 10),
			BackgroundTransparency = 1,
			Text = item.name,
			TextColor3 = Theme.TextBright,
			TextSize = 18,
			Font = Theme.FontDisplay,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	}

	if item.tag then
		table.insert(
			rowChildren,
			e("TextLabel", {
				Size = UDim2.fromOffset(64, 20),
				Position = UDim2.new(1, -76, 0, 0),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.5,
				Text = item.tag,
				TextColor3 = Theme.BgVoid,
				TextSize = 12,
				Font = Theme.FontBody,
			}, {
				corner(6),
			})
		)
	end

	table.insert(
		rowChildren,
		e("TextLabel", {
			Size = UDim2.new(1, -(TEXT_LEFT + 100), 0, 20),
			Position = UDim2.fromOffset(TEXT_LEFT, 36),
			BackgroundTransparency = 1,
			Text = string.format("◆ %d credits", item.price),
			TextColor3 = Theme.NeonAmber,
			TextSize = 15,
			Font = Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	)

	if statusNote then
		table.insert(
			rowChildren,
			e("TextLabel", {
				Size = UDim2.new(1, -(TEXT_LEFT + 100), 0, 16),
				Position = UDim2.fromOffset(TEXT_LEFT, 56),
				BackgroundTransparency = 1,
				Text = statusNote,
				TextColor3 = Theme.TextMuted,
				TextSize = 12,
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
			Size = UDim2.fromOffset(88, 34),
			Position = UDim2.new(1, -88, 1, -34),
			BackgroundColor3 = btnBg,
			BorderSizePixel = 0,
			Text = buyLabel,
			TextColor3 = btnText,
			TextSize = 14,
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
			corner(8),
		})
	)

	return e(
		"Frame",
		{
			Size = UDim2.new(1, -12, 0, cardHeight),
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

	local panelW, panelH, chatPad, listBottomPad = getShopModalLayout()
	local touchUi = UserInputService.TouchEnabled
	local listChildren: { any } = {
		e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
		e("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, listBottomPad),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}

	for i, it in ipairs(items) do
		table.insert(listChildren, itemCard(it, i, onPurchase))
	end

	-- Credits sit left of title; chatPad is larger on desktop (chat), smaller on touch.
	local CREDITS_TO_TITLE_GAP = 10
	local headerRightInset = if onClose then 50 else 14
	local creditStr = string.format("CR %s", tostring(coins))
	local creditTextSize = TextService:GetTextSize(creditStr, 17, Theme.FontBody, Vector2.new(4096, 256))
	local creditPadX = 12
	local creditPadY = 6
	local creditPillW = math.ceil(creditTextSize.X + creditPadX * 2)
	local creditPillH = math.max(30, math.ceil(creditTextSize.Y + creditPadY * 2))
	local titleLeftPx = chatPad + creditPillW + CREDITS_TO_TITLE_GAP

	local headerChildren: { any } = {
		e("TextLabel", {
			Size = UDim2.new(1, -(titleLeftPx + headerRightInset), 1, 0),
			Position = UDim2.fromOffset(titleLeftPx, 0),
			BackgroundTransparency = 1,
			Text = "ORBITAL SUPPLY",
			TextColor3 = Theme.TextBright,
			TextSize = 20,
			Font = Theme.FontDisplay,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 1,
		}),
		e("Frame", {
			Size = UDim2.fromOffset(creditPillW, creditPillH),
			Position = UDim2.new(0, chatPad, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Theme.Card,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			e("UIStroke", {
				Color = Theme.NeonAmber,
				Thickness = 1,
				Transparency = 0.35,
			}),
			e("UIPadding", {
				PaddingLeft = UDim.new(0, creditPadX),
				PaddingRight = UDim.new(0, creditPadX),
				PaddingTop = UDim.new(0, creditPadY),
				PaddingBottom = UDim.new(0, creditPadY),
			}),
			e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				Text = creditStr,
				TextColor3 = Theme.NeonAmber,
				TextSize = 17,
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
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = Theme.PanelDeep,
				BorderSizePixel = 0,
				Text = "X",
				TextColor3 = Theme.TextBright,
				TextSize = 16,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = false,
				ZIndex = 4,
				[React.Event.Activated] = function()
					onClose()
				end,
			}, {
				e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				e("UIStroke", {
					Color = Theme.NeonMagenta,
					Thickness = 1,
					Transparency = 0.2,
				}),
			})
		)
	end

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
			Size = UDim2.fromOffset(panelW, panelH),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 2,
		}, {
			corner(14),
			e("UIStroke", {
				Color = Theme.NeonCyan,
				Thickness = 2,
				Transparency = 0.2,
			}),
			e("Frame", {
				Size = UDim2.new(1, 0, 0, HEADER_H),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, headerChildren),
			e("ScrollingFrame", {
				Size = UDim2.new(1, -BODY_PAD * 2, 1, -(HEADER_H + BODY_PAD * 2)),
				Position = UDim2.fromOffset(BODY_PAD, HEADER_H + BODY_PAD),
				BackgroundColor3 = Theme.PanelDeep,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ScrollBarThickness = if touchUi then 14 else 6,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarImageColor3 = Theme.NeonCyan,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(0, 0, 0, 0),
			}, {
				corner(10),
				e("Frame", {
					Size = UDim2.new(1, -12, 0, 0),
					Position = UDim2.fromOffset(6, 6),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}, listChildren),
			}),
		}),
	})
end

return ShopApp
