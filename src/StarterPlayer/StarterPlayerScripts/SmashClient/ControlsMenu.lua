--[[
	In-game controls remapping. Fully usable with a controller (D-Pad/stick to move, A to change,
	X to remove, Y to reset, LB/RB to switch tabs, B to close) or with mouse and keyboard.
	Changes apply instantly and are saved to the player's profile by the server.
]]
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ControlsMenu = {}
ControlsMenu.Input = nil
ControlsMenu.Sound = nil
ControlsMenu.OnClosed = nil
ControlsMenu.OnOpenFighters = nil   -- when set (and CanOpenFighters() is true) a FIGHTERS button appears
ControlsMenu.CanOpenFighters = nil

local DARK = Color3.fromRGB(16, 16, 24)
local ROW = Color3.fromRGB(28, 28, 42)
local CHIP = Color3.fromRGB(48, 48, 68)
local FOCUS = Color3.fromRGB(255, 205, 60)
local LISTEN = Color3.fromRGB(235, 64, 52)

local gui, overlay, panel, body, statusLabel, hintLabel, scale
local tabs = {}
local device = "gamepad"
local focus = { row = 1, col = 1 }
local grid = {}            -- grid[row][col] = item { gui, kind, run }
local listening = nil      -- { action, index (nil = add), t0 }
local resetArmedUntil = 0
local ignoreClicksUntil = 0
local openedAt, closedAt = 0, 0 -- so the press that opens/closes the menu isn't handled twice
local stickHeld, stickNext = nil, 0

local function sound()
	if ControlsMenu.Sound then ControlsMenu.Sound() end
end

local function corner(o, r)
	Instance.new("UICorner", o).CornerRadius = UDim.new(0, r or 8)
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 15
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = CHIP
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 14
	for k, v in pairs(props) do b[k] = v end
	b.Parent = parent
	corner(b, 6)
	local s = Instance.new("UIStroke", b)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = FOCUS
	s.Thickness = 0
	return b
end

local function setStatus(msg, color)
	statusLabel.Text = msg
	statusLabel.TextColor3 = color or Color3.fromRGB(220, 220, 235)
end

local function defaultStatus()
	if device == "gamepad" then
		setStatus("Pick a button with the D-Pad or stick, press A, then press the new button.")
	else
		setStatus("Click a key, then press the new key or mouse button.")
	end
end

local function deviceLabel()
	return device == "gamepad" and "CONTROLLER" or "KEYBOARD & MOUSE"
end

-- Focus -------------------------------------------------------------------------------------

local function applyFocus()
	if #grid == 0 then return end
	focus.row = math.clamp(focus.row, 1, #grid)
	focus.col = math.clamp(focus.col, 1, #grid[focus.row])
	for r, items in ipairs(grid) do
		for c, item in ipairs(items) do
			local stroke = item.gui:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = (r == focus.row and c == focus.col) and 3 or 0
			end
		end
	end
end

local function move(dr, dc)
	if #grid == 0 then return end
	if dr ~= 0 then
		focus.row = math.clamp(focus.row + dr, 1, #grid)
	end
	if dc ~= 0 then
		focus.col = math.clamp(focus.col + dc, 1, #grid[focus.row])
	end
	applyFocus()
	sound()
end

-- Rendering ------------------------------------------------------------------------------------

local render

local function startListening(action, index)
	listening = { action = action, index = index, t0 = os.clock() }
	local Input = ControlsMenu.Input
	local what = device == "gamepad" and "Press a controller button" or "Press a key or mouse button"
	setStatus(what .. " for " .. Input.ActionNames[action] .. "...   ("
		.. (device == "gamepad" and "View/Select cancels" or (index and "Backspace removes it" or "Backspace cancels")) .. ")", FOCUS)
	render()
end

local function stopListening()
	listening = nil
	render()
end

local function switchDevice(dev)
	if dev == device then return end
	device = dev
	listening = nil
	focus.row, focus.col = 1, 1
	defaultStatus()
	render()
	sound()
end

local function addItem(row, item)
	grid[row] = grid[row] or {}
	table.insert(grid[row], item)
	local r, c = row, #grid[row]
	item.gui.MouseButton1Click:Connect(function()
		if os.clock() < ignoreClicksUntil then return end
		focus.row, focus.col = r, c
		sound()
		item.run()
	end)
	return item
end

local function rowFrame(order, labelText)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 34)
	f.BackgroundColor3 = ROW
	f.LayoutOrder = order
	f.Parent = body
	corner(f, 6)
	text(f, {
		Size = UDim2.fromOffset(210, 34), Position = UDim2.fromOffset(14, 0), Text = labelText,
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, TextSize = 14,
	})
	return f
end

function render()
	local Input = ControlsMenu.Input
	for _, c in ipairs(body:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	grid = {}
	for name, t in pairs(tabs) do
		t.BackgroundColor3 = name == device and Color3.fromRGB(52, 120, 235) or CHIP
	end

	local r = 0
	for _, action in ipairs(Input.Actions) do
		r += 1
		local row = r
		local f = rowFrame(row, Input.ActionNames[action])
		local keys = Input.GetKeys(device, action)
		local x = 232
		for i, k in ipairs(keys) do
			local waiting = listening and listening.action == action and listening.index == i
			local b = button(f, {
				Size = UDim2.fromOffset(112, 26), Position = UDim2.fromOffset(x, 4),
				Text = waiting and "PRESS..." or Input.Nice(k), BackgroundColor3 = waiting and LISTEN or CHIP,
				TextScaled = false, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local idx = i
			addItem(row, { gui = b, kind = "chip", action = action, index = idx, run = function() startListening(action, idx) end })
			b.MouseButton2Click:Connect(function()
				if listening then return end
				Input.Unbind(device, action, idx)
				setStatus("Removed " .. Input.Nice(k) .. " from " .. Input.ActionNames[action] .. ".")
				render()
			end)
			x += 118
		end
		if #keys < Input.MaxPerAction then
			local waiting = listening and listening.action == action and listening.index == nil
			local b = button(f, {
				Size = UDim2.fromOffset(#keys == 0 and 112 or 60, 26), Position = UDim2.fromOffset(x, 4),
				Text = waiting and "PRESS..." or (#keys == 0 and "+ SET" or "+"), BackgroundColor3 = waiting and LISTEN or Color3.fromRGB(34, 60, 44),
			})
			addItem(row, { gui = b, kind = "add", action = action, run = function() startListening(action, nil) end })
		end
	end

	-- options
	local function toggleRow(label, get, set)
		r += 1
		local f = rowFrame(r, label)
		local on = get()
		local b = button(f, {
			Size = UDim2.fromOffset(112, 26), Position = UDim2.fromOffset(232, 4), Text = on and "ON" or "OFF",
			BackgroundColor3 = on and Color3.fromRGB(46, 150, 80) or CHIP,
		})
		addItem(r, { gui = b, kind = "toggle", run = function()
			set(not get())
			render()
		end })
	end
	if device == "gamepad" then
		toggleRow("RIGHT STICK = SMASH", function() return Input.RightStickSmash end, function(v) Input.SetOption("RightStickSmash", v) end)
	end
	toggleRow("TAP JUMP (UP JUMPS)", function() return Input.TapJump end, function(v) Input.SetOption("TapJump", v) end)

	-- bottom buttons
	r += 1
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = r
	bar.Parent = body
	local list = Instance.new("UIListLayout", bar)
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	local barRow = r
	if ControlsMenu.OnOpenFighters and (not ControlsMenu.CanOpenFighters or ControlsMenu.CanOpenFighters()) then
		local b = button(bar, { Size = UDim2.fromOffset(150, 36), Text = "FIGHTERS", LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(52, 120, 235) })
		addItem(barRow, { gui = b, kind = "button", run = function()
			ControlsMenu.Close()
			ControlsMenu.OnOpenFighters()
		end })
	end
	local armed = os.clock() < resetArmedUntil
	local reset = button(bar, {
		Size = UDim2.fromOffset(200, 36), LayoutOrder = 2,
		Text = armed and "PRESS AGAIN TO RESET" or "RESET TO DEFAULT", BackgroundColor3 = armed and LISTEN or CHIP,
	})
	addItem(barRow, { gui = reset, kind = "button", run = function() ControlsMenu.Reset() end })
	local done = button(bar, { Size = UDim2.fromOffset(130, 36), Text = "DONE", LayoutOrder = 3, BackgroundColor3 = Color3.fromRGB(235, 64, 52) })
	addItem(barRow, { gui = done, kind = "button", run = function() ControlsMenu.Close() end })

	if device == "gamepad" then
		hintLabel.Text = "A change   X remove   Y reset   LB/RB switch tab   B done       (the left stick always moves)"
	else
		hintLabel.Text = "Click to change   Right-click to remove   Arrow keys + Enter also work   C to close"
	end
	applyFocus()
end

function ControlsMenu.Reset()
	local now = os.clock()
	if now < resetArmedUntil then
		resetArmedUntil = 0
		ControlsMenu.Input.ResetDefaults(device)
		setStatus(deviceLabel() .. " controls reset to default.", Color3.fromRGB(120, 230, 140))
	else
		resetArmedUntil = now + 2.5
		setStatus("Press RESET again to put all " .. deviceLabel() .. " controls back to default.", FOCUS)
		task.delay(2.6, function()
			if ControlsMenu.IsOpen() then render() end
		end)
	end
	render()
end

-- Open / close ----------------------------------------------------------------------------------

function ControlsMenu.IsOpen()
	return overlay ~= nil and overlay.Visible
end

local function guessDevice()
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then return "gamepad" end
	if last == Enum.UserInputType.Keyboard or string.sub(last.Name, 1, 5) == "Mouse" then return "keyboard" end
	return UserInputService.GamepadEnabled and "gamepad" or "keyboard"
end

function ControlsMenu.Open(dev)
	if not overlay then return end
	device = dev or guessDevice()
	listening = nil
	focus.row, focus.col = 1, 1
	local vp = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.clamp(math.min((vp.Y - 30) / 700, (vp.X - 20) / 800), 0.55, 1)
	overlay.Visible = true
	openedAt = os.clock()
	defaultStatus()
	render()
end

function ControlsMenu.Close()
	if not ControlsMenu.IsOpen() then return end
	listening = nil
	overlay.Visible = false
	closedAt = os.clock()
	if ControlsMenu.OnClosed then ControlsMenu.OnClosed() end
end

-- True right after the menu closed (other menus use this to ignore the same button press)
function ControlsMenu.JustClosed()
	return os.clock() - closedAt < 0.25
end

function ControlsMenu.Refresh()
	if ControlsMenu.IsOpen() then render() end
end

-- Input handling ---------------------------------------------------------------------------------

local function onInput(io)
	local Input = ControlsMenu.Input
	local name = Input.NameOf(io)
	if not name or string.sub(name, 1, 10) == "Thumbstick" then return end
	if os.clock() - openedAt < 0.2 then return end

	if listening then
		if os.clock() - listening.t0 < 0.15 then return end
		if name == "ButtonSelect" then
			stopListening()
			defaultStatus()
			return
		end
		if name == "Backspace" then
			local a, i = listening.action, listening.index
			listening = nil
			if i then
				Input.Unbind(device, a, i)
				setStatus("Removed from " .. Input.ActionNames[a] .. ".")
			else
				defaultStatus()
			end
			render()
			return
		end
		if Input.DeviceOf(name) ~= device then
			setStatus(device == "gamepad" and "That's a keyboard key - press a controller button (or switch to the KEYBOARD tab)."
				or "That's a controller button - press a key (or switch to the CONTROLLER tab).", FOCUS)
			return
		end
		if Input.Reserved[name] then
			setStatus(Input.Nice(name) .. " is used by the game's menus. Pick another.", LISTEN)
			return
		end
		local a = listening.action
		local stolen = Input.Bind(device, a, name, listening.index)
		listening = nil
		ignoreClicksUntil = os.clock() + 0.3
		local msg = Input.ActionNames[a] .. " = " .. Input.Nice(name)
		if stolen and stolen ~= a then
			msg ..= "   (taken off " .. Input.ActionNames[stolen] .. ")"
		end
		setStatus(msg, Color3.fromRGB(120, 230, 140))
		sound()
		render()
		return
	end

	if name == "ButtonB" or name == "ButtonSelect" or name == "C" then
		ControlsMenu.Close()
		sound()
	elseif name == "DPadUp" or name == "Up" then
		move(-1, 0)
	elseif name == "DPadDown" or name == "Down" then
		move(1, 0)
	elseif name == "DPadLeft" or name == "Left" then
		move(0, -1)
	elseif name == "DPadRight" or name == "Right" then
		move(0, 1)
	elseif name == "ButtonA" or name == "Return" then
		local item = grid[focus.row] and grid[focus.row][focus.col]
		if item then
			sound()
			item.run()
		end
	elseif name == "ButtonX" or name == "Delete" then
		local item = grid[focus.row] and grid[focus.row][focus.col]
		if item and item.kind == "chip" then
			local k = Input.GetKeys(device, item.action)[item.index]
			Input.Unbind(device, item.action, item.index)
			setStatus("Removed " .. Input.Nice(k or "") .. " from " .. Input.ActionNames[item.action] .. ".")
			render()
			sound()
		end
	elseif name == "ButtonY" then
		ControlsMenu.Reset()
	elseif name == "ButtonL1" then
		switchDevice("gamepad")
	elseif name == "ButtonR1" then
		switchDevice("keyboard")
	end
end

function ControlsMenu.Init(playerGui)
	gui = Instance.new("ScreenGui")
	gui.Name = "SmashControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = playerGui

	overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
	overlay.BackgroundTransparency = 0.25
	overlay.Visible = false
	overlay.Parent = gui

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(760, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = DARK
	panel.Parent = overlay
	corner(panel, 16)
	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = Color3.fromRGB(255, 200, 60)
	stroke.Thickness = 2
	scale = Instance.new("UIScale", panel)
	local pad = Instance.new("UIPadding", panel)
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	local layout = Instance.new("UIListLayout", panel)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)

	text(panel, {
		Size = UDim2.new(1, 0, 0, 44), Text = "CONTROLS", LayoutOrder = 1,
		Font = Enum.Font.LuckiestGuy, TextSize = 44, TextColor3 = Color3.fromRGB(255, 200, 60), TextStrokeTransparency = 0,
	})

	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, 0, 0, 34)
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 2
	tabRow.Parent = panel
	tabs.gamepad = button(tabRow, { Size = UDim2.fromOffset(220, 32), Position = UDim2.fromOffset(0, 1), Text = "CONTROLLER  (LB)", TextSize = 15 })
	tabs.keyboard = button(tabRow, { Size = UDim2.fromOffset(250, 32), Position = UDim2.fromOffset(230, 1), Text = "KEYBOARD & MOUSE  (RB)", TextSize = 15 })
	tabs.gamepad.MouseButton1Click:Connect(function() switchDevice("gamepad") end)
	tabs.keyboard.MouseButton1Click:Connect(function() switchDevice("keyboard") end)
	text(tabRow, {
		Size = UDim2.fromOffset(230, 32), Position = UDim2.new(1, -230, 0, 1), Text = "Saved automatically",
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(150, 150, 170), Font = Enum.Font.Gotham, TextSize = 13,
	})

	body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.LayoutOrder = 3
	body.Parent = panel
	local bl = Instance.new("UIListLayout", body)
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Padding = UDim.new(0, 4)

	statusLabel = text(panel, {
		Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4, Text = "", TextWrapped = true, TextSize = 14,
	})
	hintLabel = text(panel, {
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 5, Text = "", Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = Color3.fromRGB(160, 160, 180),
	})

	UserInputService.InputBegan:Connect(function(io)
		if ControlsMenu.IsOpen() then onInput(io) end
	end)

	-- left stick navigation with key-repeat
	RunService.RenderStepped:Connect(function()
		if not ControlsMenu.IsOpen() or listening then
			stickHeld = nil
			return
		end
		local s = ControlsMenu.Input.Stick()
		local dir
		if math.abs(s.Y) > 0.6 and math.abs(s.Y) >= math.abs(s.X) then
			dir = s.Y > 0 and "up" or "down"
		elseif math.abs(s.X) > 0.6 then
			dir = s.X > 0 and "right" or "left"
		end
		local now = os.clock()
		if dir ~= stickHeld then
			stickHeld = dir
			stickNext = now + 0.35
			if not dir then return end
		elseif not dir or now < stickNext then
			return
		else
			stickNext = now + 0.12
		end
		if dir == "up" then move(-1, 0)
		elseif dir == "down" then move(1, 0)
		elseif dir == "left" then move(0, -1)
		else move(0, 1) end
	end)
end

return ControlsMenu
