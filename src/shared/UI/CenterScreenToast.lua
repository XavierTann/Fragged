--[[
	CenterScreenToast
	Reusable center-screen message: hold, then fade. Used by TeamIndicator (arena team)
	and lobby queue hints (e.g. unbalanced team pads).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local DEFAULT_HOLD = 2.85
local DEFAULT_FADE = 0.55
local DEFAULT_TEXT_SIZE = 22

local screenGui = nil
local toastContainer = nil
local toastLabel = nil
local toastStroke = nil
local sequenceToken = 0
local fadeTweens = {}

local function cancelFadeTweens()
	for _, tw in ipairs(fadeTweens) do
		tw:Cancel()
	end
	fadeTweens = {}
end

local function ensureGui()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CenterScreenToast"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 12
	screenGui.Enabled = true
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	toastContainer = Instance.new("Frame")
	toastContainer.Name = "Toast"
	toastContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	toastContainer.Position = UDim2.fromScale(0.5, 0.5)
	toastContainer.Size = UDim2.fromOffset(600, 80)
	toastContainer.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	toastContainer.BackgroundTransparency = 1
	toastContainer.BorderSizePixel = 0
	toastContainer.Visible = false
	toastContainer.ZIndex = 2
	toastContainer.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = toastContainer

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = toastContainer

	toastLabel = Instance.new("TextLabel")
	toastLabel.BackgroundTransparency = 1
	toastLabel.Size = UDim2.fromScale(1, 1)
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.TextSize = DEFAULT_TEXT_SIZE
	toastLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	toastLabel.TextTransparency = 1
	toastLabel.TextWrapped = true
	toastLabel.TextXAlignment = Enum.TextXAlignment.Center
	toastLabel.TextYAlignment = Enum.TextYAlignment.Center
	toastLabel.Text = ""
	toastLabel.ZIndex = 2
	toastLabel.Parent = toastContainer

	toastStroke = Instance.new("UIStroke")
	toastStroke.Thickness = 1.8
	toastStroke.Color = Color3.fromRGB(0, 0, 0)
	toastStroke.Transparency = 1
	toastStroke.Parent = toastLabel
end

return {
	Init = function()
		ensureGui()
	end,

	--[[
		opts: { text: string, textColor: Color3?, holdSeconds?, fadeSeconds?, textSize? }
	]]
	Show = function(opts)
		opts = opts or {}
		local text = opts.text
		if type(text) ~= "string" or text == "" then
			return
		end
		ensureGui()
		local color = opts.textColor or Color3.fromRGB(255, 255, 255)
		local holdSec = opts.holdSeconds or DEFAULT_HOLD
		local fadeSec = opts.fadeSeconds or DEFAULT_FADE
		local textSize = opts.textSize or DEFAULT_TEXT_SIZE

		sequenceToken = sequenceToken + 1
		local token = sequenceToken
		cancelFadeTweens()

		toastLabel.Text = text
		toastLabel.TextColor3 = color
		toastLabel.TextSize = textSize
		toastContainer.BackgroundTransparency = 0.62
		toastLabel.TextTransparency = 0.06
		toastStroke.Transparency = 0.35
		toastContainer.Visible = true

		task.delay(holdSec, function()
			if token ~= sequenceToken then
				return
			end
			local ti = TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local t1 = TweenService:Create(toastLabel, ti, { TextTransparency = 1 })
			local t2 = TweenService:Create(toastStroke, ti, { Transparency = 1 })
			local t3 = TweenService:Create(toastContainer, ti, { BackgroundTransparency = 1 })
			fadeTweens = { t1, t2, t3 }
			t1:Play()
			t2:Play()
			t3:Play()
			t1.Completed:Connect(function()
				if token ~= sequenceToken then
					return
				end
				toastContainer.Visible = false
				cancelFadeTweens()
			end)
		end)
	end,

	Cancel = function()
		sequenceToken = sequenceToken + 1
		cancelFadeTweens()
		if toastContainer then
			toastContainer.Visible = false
		end
		if toastLabel then
			toastLabel.TextTransparency = 1
		end
		if toastStroke then
			toastStroke.Transparency = 1
		end
		if toastContainer then
			toastContainer.BackgroundTransparency = 1
		end
	end,
}
