-- Character select screen, lobby panel (CPUs / level / stocks / start) and the controls card.
-- Everything here works with a controller too: View/Select opens menus, D-Pad or stick moves.
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Fighters = require(Smash.Fighters)
local Config = require(Smash.Config)

local Menu = {}
Menu.OnSelect = nil
Menu.OnSetting = nil
Menu.OnStart = nil
Menu.OnOpenControls = nil
Menu.Input = nil
Menu.Controls = nil -- the ControlsMenu module

local gui, selectFrame, lobbyPanel, helpFrame, helpText
local detail = {}
local chosenKey = Fighters.List[1].Key
local chosenIndex = 1
local state
local stickHeld, stickNext = nil, 0
local openedAt = 0

local DARK = Color3.fromRGB(16, 16, 24)

local function corner(obj, r)
	Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r or 10)
end

local function stroke(obj, color, thick)
	local s = Instance.new("UIStroke", obj)
	s.Color = color
	s.Thickness = thick or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function button(parent, props, onClick)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 16
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 56)
	for k, v in pairs(props) do b[k] = v end
	b.Parent = parent
	corner(b, 8)
	b.MouseButton1Click:Connect(function()
		if Menu.Sound then Menu.Sound() end
		onClick()
	end)
	return b
end

function Menu.IsOpen()
	return selectFrame and selectFrame.Visible
end

-- Character select --------------------------------------------------------------------------

local function showDetail(def)
	chosenKey = def.Key
	chosenIndex = def.Index or table.find(Fighters.List, def) or 1
	detail.name.Text = def.Name
	detail.name.TextColor3 = def.Accent
	detail.title.Text = def.Title
	detail.desc.Text = def.Description
	detail.panel.BackgroundColor3 = def.Color:Lerp(DARK, 0.7)
	for stat, bar in pairs(detail.bars) do
		local v = def.Ratings[stat] or 1
		TweenService:Create(bar, TweenInfo.new(0.25), { Size = UDim2.fromScale(v / 5, 1) }):Play()
		bar.BackgroundColor3 = def.Color
	end
	local sp = def.Specials
	detail.specials.Text = string.format(
		"<b>NEUTRAL</b>  %s — %s\n<b>SIDE</b>  %s — %s\n<b>UP</b>  %s — %s\n<b>DOWN</b>  %s — %s",
		sp.Neutral.Name, sp.Neutral.Text, sp.Side.Name, sp.Side.Text, sp.Up.Name, sp.Up.Text, sp.Down.Name, sp.Down.Text
	)
	detail.lock.BackgroundColor3 = def.Color
	for key, card in pairs(detail.cards) do
		local on = key == def.Key
		card.stroke.Color = on and def.Accent or Color3.fromRGB(60, 60, 80)
		card.stroke.Thickness = on and 4 or 2
		TweenService:Create(card.frame, TweenInfo.new(0.12), { Size = on and UDim2.fromOffset(180, 250) or UDim2.fromOffset(170, 240) }):Play()
	end
end

local function cycleFighter(step)
	local n = #Fighters.List
	local i = ((chosenIndex - 1 + step) % n) + 1
	showDetail(Fighters.List[i])
	if Menu.Sound then Menu.Sound() end
end

local function lockIn()
	if Menu.OnSelect then Menu.OnSelect(chosenKey) end
	Menu.Close()
end

local function lockInAndFight()
	if Menu.OnSelect then Menu.OnSelect(chosenKey) end
	Menu.Close()
	-- give the server a moment to spawn the new fighter before the countdown starts
	task.delay(0.3, function()
		if Menu.OnStart then Menu.OnStart() end
	end)
end

local function openControls()
	if Menu.OnOpenControls then Menu.OnOpenControls() end
end

local function buildViewport(parent, def)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, -34)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 190)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	task.spawn(function()
		local previews = Smash:WaitForChild("Previews", 30)
		local src = previews and previews:WaitForChild(def.Key, 10)
		if not src then return end
		local m = src:Clone()
		local cf, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() - cf.Position) -- center the fighter on the origin
		m.Parent = vp
		local h = size.Y
		local look = Vector3.zero
		local angle = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not vp.Parent then conn:Disconnect() return end
			if not vp.Visible or not selectFrame.Visible then return end
			angle += dt * 0.6
			local d = h * 1.9
			cam.CFrame = CFrame.lookAt(look + Vector3.new(math.sin(angle) * d, h * 0.1, -math.cos(angle) * d), look)
		end)
	end)
	return vp
end

local function buildSelect()
	selectFrame = Instance.new("Frame")
	selectFrame.Name = "FighterSelect"
	selectFrame.Size = UDim2.fromScale(1, 1)
	selectFrame.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
	selectFrame.BackgroundTransparency = 0.12
	selectFrame.Visible = false
	selectFrame.ZIndex = 5
	selectFrame.Parent = gui

	text(selectFrame, {
		Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 20), Text = "CHOOSE YOUR FIGHTER",
		Font = Enum.Font.LuckiestGuy, TextSize = 58, TextStrokeTransparency = 0,
	})

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -40, 0, 250)
	row.Position = UDim2.fromOffset(20, 100)
	row.BackgroundTransparency = 1
	row.Parent = selectFrame
	local layout = Instance.new("UIListLayout", row)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)

	detail.cards = {}
	for i, def in ipairs(Fighters.List) do
		local card = Instance.new("TextButton")
		card.Text = ""
		card.AutoButtonColor = false
		card.Size = UDim2.fromOffset(170, 240)
		card.BackgroundColor3 = def.Color:Lerp(DARK, 0.55)
		card.LayoutOrder = i
		card.Parent = row
		corner(card, 14)
		local s = stroke(card, Color3.fromRGB(60, 60, 80), 2)
		local grad = Instance.new("UIGradient", card)
		grad.Color = ColorSequence.new(def.Color:Lerp(DARK, 0.3), DARK)
		grad.Rotation = 90
		buildViewport(card, def)
		text(card, {
			Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -36), Text = def.Name,
			Font = Enum.Font.LuckiestGuy, TextSize = 30, TextColor3 = def.Accent, TextStrokeTransparency = 0,
		})
		card.MouseButton1Click:Connect(function()
			if Menu.Sound then Menu.Sound() end
			showDetail(def)
		end)
		detail.cards[def.Key] = { frame = card, stroke = s }
	end

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 900, 0, 250)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 370)
	panel.BackgroundColor3 = DARK
	panel.Parent = selectFrame
	corner(panel, 16)
	stroke(panel, Color3.fromRGB(255, 255, 255), 2)
	detail.panel = panel
	local sizeLimit = Instance.new("UISizeConstraint", panel)
	sizeLimit.MaxSize = Vector2.new(900, 250)

	detail.name = text(panel, { Size = UDim2.fromOffset(300, 50), Position = UDim2.fromOffset(24, 12), Text = "", Font = Enum.Font.LuckiestGuy, TextSize = 46, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0 })
	detail.title = text(panel, { Size = UDim2.fromOffset(300, 22), Position = UDim2.fromOffset(26, 60), Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 220, 230) })
	detail.desc = text(panel, { Size = UDim2.fromOffset(300, 60), Position = UDim2.fromOffset(26, 86), Text = "", TextSize = 14, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

	detail.bars = {}
	for i, stat in ipairs({ "Speed", "Power", "Weight", "Recovery" }) do
		local y = 150 + (i - 1) * 22
		text(panel, { Size = UDim2.fromOffset(90, 18), Position = UDim2.fromOffset(26, y), Text = string.upper(stat), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left })
		local back = Instance.new("Frame")
		back.Size = UDim2.fromOffset(200, 12)
		back.Position = UDim2.fromOffset(120, y + 3)
		back.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
		back.Parent = panel
		corner(back, 6)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(0.5, 1)
		bar.Parent = back
		corner(bar, 6)
		detail.bars[stat] = bar
	end

	text(panel, { Size = UDim2.fromOffset(400, 22), Position = UDim2.fromOffset(360, 16), Text = "SPECIAL MOVES", Font = Enum.Font.GothamBlack, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
	detail.specials = text(panel, {
		Size = UDim2.fromOffset(520, 130), Position = UDim2.fromOffset(360, 42), Text = "", RichText = true,
		Font = Enum.Font.Gotham, TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.35,
	})
	-- bottom row: CONTROLS (Y) · BACK (B) · LOCK IN (A) · FIGHT! (X)
	button(panel, { Size = UDim2.fromOffset(110, 46), Position = UDim2.fromOffset(360, 188), Text = "CONTROLS", TextSize = 14 }, openControls)
	button(panel, { Size = UDim2.fromOffset(90, 46), Position = UDim2.fromOffset(482, 188), Text = "BACK" }, function()
		Menu.Close()
	end)
	detail.lock = button(panel, {
		Size = UDim2.fromOffset(140, 46), Position = UDim2.fromOffset(584, 188), Text = "LOCK IN",
		Font = Enum.Font.LuckiestGuy, TextSize = 28,
	}, lockIn)
	button(panel, {
		Size = UDim2.fromOffset(140, 46), Position = UDim2.fromOffset(736, 188), Text = "FIGHT!",
		Font = Enum.Font.LuckiestGuy, TextSize = 28, BackgroundColor3 = Color3.fromRGB(235, 64, 52),
	}, lockInAndFight)

	detail.hint = text(selectFrame, {
		Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 630), Font = Enum.Font.GothamBold, TextSize = 15,
		TextColor3 = Color3.fromRGB(190, 190, 210), TextStrokeTransparency = 0.5,
		Text = "Controller:  D-Pad / stick  pick     A  lock in     X  lock in & fight     Y  controls     B  back",
	})

	showDetail(Fighters.List[1])
end

function Menu.Open()
	if not selectFrame then return end
	selectFrame.Visible = true
	openedAt = os.clock()
	showDetail(Fighters.List[chosenIndex])
end

function Menu.Close()
	if not selectFrame then return end
	selectFrame.Visible = false
end

-- Lobby panel ---------------------------------------------------------------------------------

local function stepper(parent, y, labelText, attr, min, max)
	text(parent, { Size = UDim2.fromOffset(110, 30), Position = UDim2.fromOffset(14, y), Text = labelText, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15 })
	local value = text(parent, { Size = UDim2.fromOffset(40, 30), Position = UDim2.fromOffset(170, y), Text = "", Font = Enum.Font.LuckiestGuy, TextSize = 24 })
	button(parent, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(134, y), Text = "-" }, function()
		local v = (state:GetAttribute(attr) or 0) - 1
		if v >= min and Menu.OnSetting then Menu.OnSetting(attr, v) end
	end)
	button(parent, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(214, y), Text = "+" }, function()
		local v = (state:GetAttribute(attr) or 0) + 1
		if v <= max and Menu.OnSetting then Menu.OnSetting(attr, v) end
	end)
	local function refresh()
		local v = state:GetAttribute(attr) or 0
		if attr == "CPULevel" then
			value.Text = ({ "EASY", "MED", "HARD" })[v] or tostring(v)
			value.TextSize = 16
		else
			value.Text = tostring(v)
		end
	end
	state:GetAttributeChangedSignal(attr):Connect(refresh)
	refresh()
end

local function buildLobby()
	lobbyPanel = Instance.new("Frame")
	lobbyPanel.Name = "Lobby"
	lobbyPanel.Size = UDim2.fromOffset(262, 272)
	lobbyPanel.Position = UDim2.new(1, -278, 0, 60)
	lobbyPanel.BackgroundColor3 = DARK
	lobbyPanel.BackgroundTransparency = 0.1
	lobbyPanel.Parent = gui
	corner(lobbyPanel, 14)
	stroke(lobbyPanel, Color3.fromRGB(255, 200, 60), 2)

	text(lobbyPanel, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 6), Text = "SMASH ARENA", Font = Enum.Font.LuckiestGuy, TextSize = 30, TextColor3 = Color3.fromRGB(255, 200, 60) })
	button(lobbyPanel, { Size = UDim2.new(1, -28, 0, 36), Position = UDim2.fromOffset(14, 44), Text = "FIGHTERS  [M]", BackgroundColor3 = Color3.fromRGB(52, 120, 235) }, function()
		Menu.Open()
	end)
	stepper(lobbyPanel, 88, "CPUs", "CPUs", 0, Config.MaxCPUs)
	stepper(lobbyPanel, 122, "CPU LEVEL", "CPULevel", 1, 3)
	stepper(lobbyPanel, 156, "STOCKS", "Stocks", 1, Config.MaxStocks)
	button(lobbyPanel, { Size = UDim2.new(1, -28, 0, 26), Position = UDim2.fromOffset(14, 192), Text = "CONTROLS  [C]", TextSize = 13 }, openControls)
	button(lobbyPanel, { Size = UDim2.new(1, -28, 0, 42), Position = UDim2.fromOffset(14, 224), Text = "START MATCH!", Font = Enum.Font.LuckiestGuy, TextSize = 26, BackgroundColor3 = Color3.fromRGB(235, 64, 52) }, function()
		if Menu.OnStart then Menu.OnStart() end
	end)

	local function refresh()
		lobbyPanel.Visible = state:GetAttribute("Phase") == "Lobby"
		if not lobbyPanel.Visible then Menu.Close() end
	end
	state:GetAttributeChangedSignal("Phase"):Connect(refresh)
	refresh()
end

-- Controls card (always shows the player's current bindings) -----------------------------------

local function usingGamepad()
	local last = UserInputService:GetLastInputType()
	return string.sub(last.Name, 1, 7) == "Gamepad"
end

function Menu.RefreshHelp()
	if not helpText or not Menu.Input then return end
	local Input = Menu.Input
	local lines
	if usingGamepad() then
		local d = function(a) return Input.Describe("gamepad", a) end
		local smash = d("smash")
		if Input.RightStickSmash then
			smash = smash == "none" and "Right stick" or ("Right stick / " .. smash)
		end
		lines = {
			"<b>CONTROLS</b>  (View button = menus)",
			"<b>MOVE</b>  Left stick     <b>JUMP</b>  " .. d("jump"),
			"<b>ATTACK</b>  " .. d("attack") .. "  (+ direction = tilts & aerials)",
			"<b>SMASH</b>  " .. smash .. "  (hold to charge)",
			"<b>SPECIAL</b>  " .. d("special") .. "  (+ up / down / side)",
			"<b>SHIELD</b>  " .. d("shield") .. "  (+ side roll, + down dodge, in air = air dodge)",
			"<b>GRAB</b>  " .. d("grab") .. "  (or shield + attack) - then a direction throws, attack pummels",
			"<b>TAUNT</b>  " .. d("taunt"),
			"Stick down in air = fast fall, on a platform = drop",
			"Knocked past the edges = <b>KO!</b>  Higher % = you fly farther.",
		}
	else
		local d = function(a) return Input.Describe("keyboard", a) end
		lines = {
			"<b>CONTROLS</b>  (H hide · C change)",
			"<b>MOVE</b>  " .. d("left") .. " · " .. d("right") .. "     <b>JUMP</b>  " .. d("jump"),
			"<b>AIM</b>  " .. d("up") .. " · " .. d("down") .. "  (down in air = fast fall, on a platform = drop)",
			"<b>ATTACK</b>  " .. d("attack") .. "  (+ direction = tilts & aerials)",
			"<b>SMASH</b>  " .. d("smash") .. "  (hold to charge)",
			"<b>SPECIAL</b>  " .. d("special") .. "  (+ up / down / side)",
			"<b>SHIELD</b>  " .. d("shield") .. "  (+ side roll, + down dodge, in air = air dodge)",
			"<b>GRAB</b>  " .. d("grab") .. "  (or shield + attack) - then a direction throws, attack pummels",
			"<b>TAUNT</b>  " .. d("taunt"),
			"Knocked past the edges = <b>KO!</b>  Higher % = you fly farther.",
		}
	end
	helpText.Text = table.concat(lines, "\n")
end

local function buildHelp()
	helpFrame = Instance.new("Frame")
	helpFrame.Name = "Controls"
	helpFrame.Size = UDim2.fromOffset(340, 0)
	helpFrame.AutomaticSize = Enum.AutomaticSize.Y
	helpFrame.AnchorPoint = Vector2.new(0, 0.5)
	helpFrame.Position = UDim2.new(0, 16, 0.5, 0) -- left edge, clear of the chat window
	helpFrame.BackgroundColor3 = DARK
	helpFrame.BackgroundTransparency = 0.2
	helpFrame.Parent = gui
	corner(helpFrame, 12)
	local pad = Instance.new("UIPadding", helpFrame)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	helpText = text(helpFrame, {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true,
		Text = "", Font = Enum.Font.Gotham, TextSize = 13, LineHeight = 1.25,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	})
	Menu.RefreshHelp()
	UserInputService.LastInputTypeChanged:Connect(function()
		Menu.RefreshHelp()
	end)
end

-- Input -----------------------------------------------------------------------------------------

local function controlsBusy()
	local c = Menu.Controls
	return c and (c.IsOpen() or c.JustClosed())
end

local function onInput(io, gameProcessed)
	if controlsBusy() then return end
	local key = io.KeyCode
	local isPad = string.sub(io.UserInputType.Name, 1, 7) == "Gamepad"
	if gameProcessed and not isPad then return end
	local lobby = state:GetAttribute("Phase") == "Lobby"

	if Menu.IsOpen() then
		if os.clock() - openedAt < 0.15 then return end
		if key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Return then
			lockIn()
		elseif key == Enum.KeyCode.ButtonX then
			lockInAndFight()
		elseif key == Enum.KeyCode.ButtonY or key == Enum.KeyCode.C then
			openControls()
		elseif key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.ButtonSelect or key == Enum.KeyCode.M then
			Menu.Close()
		elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Left then
			cycleFighter(-1)
		elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.Right then
			cycleFighter(1)
		end
		return
	end

	if key == Enum.KeyCode.ButtonSelect then
		if lobby then Menu.Open() else openControls() end
	elseif key == Enum.KeyCode.M then
		if lobby then Menu.Open() end
	elseif key == Enum.KeyCode.C then
		openControls()
	elseif key == Enum.KeyCode.H then
		helpFrame.Visible = not helpFrame.Visible
	end
end

function Menu.Init(playerGui, stateObj)
	state = stateObj
	gui = Instance.new("ScreenGui")
	gui.Name = "SmashMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	buildSelect()
	buildLobby()
	buildHelp()
	Menu.Gui = gui

	UserInputService.InputBegan:Connect(onInput)

	-- left stick browses fighters on the select screen
	RunService.RenderStepped:Connect(function()
		if not Menu.IsOpen() or controlsBusy() or not Menu.Input then
			stickHeld = nil
			return
		end
		local x = Menu.Input.Stick().X
		local dir = x > 0.6 and 1 or (x < -0.6 and -1 or nil)
		local now = os.clock()
		if dir ~= stickHeld then
			stickHeld = dir
			stickNext = now + 0.35
			if dir then cycleFighter(dir) end
		elseif dir and now >= stickNext then
			stickNext = now + 0.15
			cycleFighter(dir)
		end
	end)
end

return Menu
