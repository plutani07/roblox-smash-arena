-- Damage cards (percent + stocks), timer, big announcements and the results screen.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Fighters = require(Smash.Fighters)

local Hud = {}
local gui, cardsFrame, announceLabel, subLabel, timerLabel, modeLabel, resultsFrame
local cards = {} -- model -> card
local state

local function percentColor(p)
	-- white -> yellow -> orange -> red -> dark red, like Smash
	local stops = {
		{ 0, Color3.fromRGB(255, 255, 255) },
		{ 40, Color3.fromRGB(255, 240, 120) },
		{ 80, Color3.fromRGB(255, 160, 50) },
		{ 120, Color3.fromRGB(240, 60, 40) },
		{ 200, Color3.fromRGB(150, 10, 20) },
	}
	for i = 1, #stops - 1 do
		local a, b = stops[i], stops[i + 1]
		if p <= b[1] then
			return a[2]:Lerp(b[2], (p - a[1]) / (b[1] - a[1]))
		end
	end
	return stops[#stops][2]
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBlack
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function buildCard(model)
	local key = model:GetAttribute("FighterKey")
	if not key then return end
	local def = Fighters.Get(key)
	local slot = model:GetAttribute("Slot") or 1
	local isCPU = model:GetAttribute("IsCPU")
	local tagColor = isCPU and Config.CPUColor or (Config.SlotColors[slot] or Color3.new(1, 1, 1))

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(190, 92)
	card.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	card.BackgroundTransparency = 0.15
	card.LayoutOrder = slot
	card.Parent = cardsFrame
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = tagColor
	stroke.Thickness = 3
	local grad = Instance.new("UIGradient", card)
	grad.Color = ColorSequence.new(def.Color:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(18, 18, 26))
	grad.Rotation = 90

	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.fromOffset(46, 46)
	portrait.Position = UDim2.fromOffset(10, 10)
	portrait.BackgroundColor3 = def.Color
	portrait.Parent = card
	Instance.new("UICorner", portrait).CornerRadius = UDim.new(1, 0)
	label(portrait, { Size = UDim2.fromScale(1, 1), Text = string.sub(def.Name, 1, 1), TextSize = 26, Font = Enum.Font.LuckiestGuy, TextColor3 = def.Accent })

	local nameL = label(card, {
		Size = UDim2.new(1, -66, 0, 18), Position = UDim2.fromOffset(62, 6),
		Text = string.upper(model:GetAttribute("DisplayName") or def.Name), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local tagL = label(card, {
		Size = UDim2.fromOffset(40, 16), Position = UDim2.new(1, -44, 0, 6),
		Text = isCPU and "CPU" or ("P" .. slot), TextSize = 13, TextColor3 = tagColor, TextXAlignment = Enum.TextXAlignment.Right,
	})
	local pct = label(card, {
		Size = UDim2.new(1, -66, 0, 46), Position = UDim2.fromOffset(62, 22),
		Text = "0%", TextSize = 42, Font = Enum.Font.LuckiestGuy, TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local scale = Instance.new("UIScale", pct)
	local stocks = Instance.new("Frame")
	stocks.Size = UDim2.new(1, -20, 0, 14)
	stocks.Position = UDim2.fromOffset(12, 70)
	stocks.BackgroundTransparency = 1
	stocks.Parent = card
	local layout = Instance.new("UIListLayout", stocks)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)

	cards[model] = {
		frame = card, pct = pct, scale = scale, stocks = stocks, def = def, name = nameL, tag = tagL,
		lastPct = -1, lastStocks = -1, shake = 0,
	}
end

local function refreshStocks(c, n, inMatch)
	for _, ch in ipairs(c.stocks:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
	if not inMatch then return end
	for i = 1, n do
		local s = Instance.new("Frame")
		s.Size = UDim2.fromOffset(12, 12)
		s.BackgroundColor3 = c.def.Color
		s.Parent = c.stocks
		Instance.new("UICorner", s).CornerRadius = UDim.new(1, 0)
		local st = Instance.new("UIStroke", s)
		st.Color = c.def.Accent
		st.Thickness = 1.5
	end
end

function Hud.Announce(text, color, duration, sub)
	announceLabel.Text = text
	announceLabel.TextColor3 = color or Color3.new(1, 1, 1)
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0
	subLabel.Text = sub or ""
	subLabel.TextTransparency = 0
	local sc = announceLabel:FindFirstChildOfClass("UIScale")
	sc.Scale = 1.6
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local token = {}
	Hud._token = token
	task.delay(duration or 1, function()
		if Hud._token ~= token then return end
		TweenService:Create(announceLabel, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subLabel, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
	end)
end

function Hud.ShowResults(data, modelFor)
	resultsFrame.Visible = true
	for _, ch in ipairs(resultsFrame.List:GetChildren()) do
		if ch:IsA("TextLabel") then ch:Destroy() end
	end
	local def = data.key and Fighters.Get(data.key)
	resultsFrame.Winner.Text = string.upper(data.name) .. " WINS!"
	resultsFrame.Winner.TextColor3 = def and def.Accent or Color3.new(1, 1, 1)
	resultsFrame.BackgroundColor3 = def and def.Color:Lerp(Color3.new(0, 0, 0), 0.6) or Color3.new(0, 0, 0)
	for _, row in ipairs(data.standings or {}) do
		label(resultsFrame.List, {
			Size = UDim2.new(1, 0, 0, 26), LayoutOrder = row.place,
			Text = string.format("#%d  %s (%s)   KOs %d   Falls %d", row.place, row.name, row.key, row.kos, row.falls),
			TextSize = 18, Font = Enum.Font.GothamBold,
		})
	end
	resultsFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	TweenService:Create(resultsFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.42, 0) }):Play()
	task.delay(Config.ResultsTime - 0.5, function()
		resultsFrame.Visible = false
	end)
end

function Hud.Init(playerGui, stateObj)
	state = stateObj
	gui = Instance.new("ScreenGui")
	gui.Name = "SmashHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	cardsFrame = Instance.new("Frame")
	cardsFrame.Size = UDim2.new(1, 0, 0, 100)
	cardsFrame.Position = UDim2.new(0, 0, 1, -112)
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Parent = gui
	local layout = Instance.new("UIListLayout", cardsFrame)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)

	announceLabel = label(gui, {
		Size = UDim2.new(1, 0, 0, 140), Position = UDim2.new(0, 0, 0.3, 0), Text = "",
		TextSize = 110, Font = Enum.Font.LuckiestGuy, TextTransparency = 1, TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
	Instance.new("UIScale", announceLabel)
	subLabel = label(gui, {
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.3, 140), Text = "",
		TextSize = 24, Font = Enum.Font.GothamBold, TextTransparency = 1,
	})

	timerLabel = label(gui, {
		Size = UDim2.fromOffset(200, 50), Position = UDim2.new(0.5, -100, 0, 44), Text = "",
		TextSize = 40, Font = Enum.Font.LuckiestGuy, TextStrokeTransparency = 0,
	})
	modeLabel = label(gui, {
		Size = UDim2.fromOffset(420, 26), Position = UDim2.new(0.5, -210, 0, 90), Text = "",
		TextSize = 16, Font = Enum.Font.GothamBold, TextStrokeTransparency = 0.4,
	})

	resultsFrame = Instance.new("Frame")
	resultsFrame.Name = "Results"
	resultsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultsFrame.Size = UDim2.fromOffset(560, 300)
	resultsFrame.Position = UDim2.new(0.5, 0, 0.42, 0)
	resultsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	resultsFrame.BackgroundTransparency = 0.1
	resultsFrame.Visible = false
	resultsFrame.Parent = gui
	Instance.new("UICorner", resultsFrame).CornerRadius = UDim.new(0, 18)
	local rs = Instance.new("UIStroke", resultsFrame)
	rs.Color = Color3.new(1, 1, 1)
	rs.Thickness = 3
	label(resultsFrame, { Name = "Winner", Size = UDim2.new(1, 0, 0, 80), Text = "", TextSize = 56, Font = Enum.Font.LuckiestGuy, TextStrokeTransparency = 0 })
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, -40, 1, -100)
	list.Position = UDim2.fromOffset(20, 90)
	list.BackgroundTransparency = 1
	list.Parent = resultsFrame
	local ll = Instance.new("UIListLayout", list)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 6)

	RunService.RenderStepped:Connect(function(dt)
		-- keep one card per fighter
		local phase = state:GetAttribute("Phase")
		local seen = {}
		for _, m in ipairs(CollectionService:GetTagged("SmashFighter")) do
			if m.Parent and m:GetAttribute("FighterKey") then
				seen[m] = true
				if not cards[m] then buildCard(m) end
			end
		end
		for m, c in pairs(cards) do
			if not seen[m] then
				c.frame:Destroy()
				cards[m] = nil
			end
		end
		for m, c in pairs(cards) do
			local p = math.floor((m:GetAttribute("Percent") or 0) + 0.5)
			if p ~= c.lastPct then
				if p > c.lastPct and c.lastPct >= 0 then
					c.shake = 0.3
					c.scale.Scale = 1.35
				end
				c.lastPct = p
				c.pct.Text = p .. "%"
				c.pct.TextColor3 = percentColor(p)
			end
			if c.shake > 0 then
				c.shake -= dt
				c.pct.Position = UDim2.fromOffset(62 + (math.random() - 0.5) * 8 * c.shake / 0.3, 22 + (math.random() - 0.5) * 8 * c.shake / 0.3)
			else
				c.pct.Position = UDim2.fromOffset(62, 22)
			end
			c.scale.Scale += (1 - c.scale.Scale) * math.clamp(dt * 10, 0, 1)
			local stocks = m:GetAttribute("Stocks") or 0
			local inMatch = m:GetAttribute("InMatch")
			local key = stocks .. tostring(inMatch)
			if key ~= c.lastStocks then
				c.lastStocks = key
				refreshStocks(c, stocks, inMatch)
			end
			local out = m:GetAttribute("Eliminated")
			c.frame.BackgroundTransparency = out and 0.7 or 0.15
			c.pct.TextTransparency = out and 0.7 or 0
		end

		if phase == "Match" or phase == "Countdown" then
			local tl = state:GetAttribute("TimeLeft") or 0
			timerLabel.Text = string.format("%d:%02d", math.floor(tl / 60), tl % 60)
			timerLabel.TextColor3 = tl <= 10 and Color3.fromRGB(255, 80, 60) or Color3.new(1, 1, 1)
			modeLabel.Text = ""
		elseif phase == "Lobby" then
			timerLabel.Text = ""
			modeLabel.Text = "FREE PLAY  •  pick a fighter and hit START MATCH"
		else
			timerLabel.Text = ""
			modeLabel.Text = ""
		end
	end)
end

return Hud
