-- Keyboard / mouse / gamepad / touch -> one input snapshot per frame for the Controller.
-- Bindings are plain data (Input.Bindings) so players can remap them in the Controls menu.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controller = require(ReplicatedStorage:WaitForChild("Smash"):WaitForChild("Controller"))

local Input = {}
Input.TapJump = false         -- when true, Up (W / stick up) also jumps
Input.RightStickSmash = true  -- flicking the right stick does a smash attack
Input.Blocked = false
Input.OnChanged = nil         -- called after the player changes a binding or setting (used to save)
Input.OnImported = nil        -- called after saved bindings are loaded (used to refresh menus)
Input.MaxPerAction = 4

-- Order here is the order the Controls menu lists them in
Input.Actions = { "jump", "attack", "special", "smash", "shield", "grab", "taunt", "left", "right", "up", "down" }
Input.ActionNames = {
	jump = "JUMP", attack = "ATTACK", special = "SPECIAL", smash = "SMASH ATTACK", shield = "SHIELD / DODGE",
	grab = "GRAB", taunt = "TAUNT", left = "MOVE LEFT", right = "MOVE RIGHT", up = "UP / AIM UP", down = "DOWN / FAST FALL",
}

-- Controller defaults follow Smash Ultimate: triggers shield, bumpers grab
Input.Defaults = {
	keyboard = {
		jump = { "Space" }, attack = { "J", "MouseButton1" }, special = { "K", "MouseButton2" },
		smash = { "L" }, shield = { "Q", "LeftShift", "RightShift" }, grab = { "E" }, taunt = { "T" },
		left = { "A", "Left" }, right = { "D", "Right" }, up = { "W", "Up" }, down = { "S", "Down" },
	},
	gamepad = {
		jump = { "ButtonX", "ButtonY" }, attack = { "ButtonA" }, special = { "ButtonB" },
		smash = {}, shield = { "ButtonR2", "ButtonL2" }, grab = { "ButtonR1", "ButtonL1" }, taunt = { "DPadUp" },
		left = { "DPadLeft" }, right = { "DPadRight" }, up = {}, down = { "DPadDown" },
	},
}

-- Keys Roblox or our own menus already use; these can't be bound
Input.Reserved = {
	Escape = true, Slash = true, Tab = true, Backquote = true, F9 = true, Return = true, Backspace = true,
	M = true, H = true, C = true, Unknown = true,
	ButtonStart = true, ButtonSelect = true, Thumbstick1 = true, Thumbstick2 = true,
}

local NICE = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT",
	ButtonL3 = "L-Stick Click", ButtonR3 = "R-Stick Click",
	DPadUp = "D-Pad Up", DPadDown = "D-Pad Down", DPadLeft = "D-Pad Left", DPadRight = "D-Pad Right",
	MouseButton1 = "Left Click", MouseButton2 = "Right Click",
	LeftShift = "L-Shift", RightShift = "R-Shift", LeftControl = "L-Ctrl", RightControl = "R-Ctrl",
	LeftAlt = "L-Alt", RightAlt = "R-Alt", Left = "Left Arrow", Right = "Right Arrow", Up = "Up Arrow", Down = "Down Arrow",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", LeftBracket = "[", RightBracket = "]", Minus = "-", Equals = "=",
}

function Input.Nice(key)
	return NICE[key] or key
end

function Input.DeviceOf(key)
	if string.sub(key, 1, 6) == "Button" or string.sub(key, 1, 4) == "DPad" or string.sub(key, 1, 10) == "Thumbstick" then
		return "gamepad"
	end
	return "keyboard"
end

-- The binding name for an input event ("J", "ButtonA", "MouseButton1"...), or nil for things like mouse movement
function Input.NameOf(io)
	local t = io.UserInputType
	if t == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
	if t == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
	if t == Enum.UserInputType.Keyboard or string.sub(t.Name, 1, 7) == "Gamepad" then
		if io.KeyCode == Enum.KeyCode.Unknown then return nil end
		return io.KeyCode.Name
	end
	return nil
end

-- Bindings -----------------------------------------------------------------------------------

local function defaultsFor(device)
	local out = {}
	for _, a in ipairs(Input.Actions) do
		out[a] = table.clone(Input.Defaults[device][a] or {})
	end
	return out
end

Input.Bindings = { keyboard = defaultsFor("keyboard"), gamepad = defaultsFor("gamepad") }

local lookup = {} -- key name -> action
local function rebuild()
	table.clear(lookup)
	for _, map in pairs(Input.Bindings) do
		for action, keys in pairs(map) do
			for _, k in ipairs(keys) do lookup[k] = action end
		end
	end
end
rebuild()

local function changed()
	rebuild()
	if Input.OnChanged then Input.OnChanged() end
end

function Input.GetKeys(device, action)
	return Input.Bindings[device][action]
end

function Input.Describe(device, action, sep)
	local keys = Input.Bindings[device][action]
	if #keys == 0 then return "none" end
	local names = {}
	for _, k in ipairs(keys) do table.insert(names, Input.Nice(k)) end
	return table.concat(names, sep or " / ")
end

function Input.CanBind(device, key)
	return not Input.Reserved[key] and Input.DeviceOf(key) == device
end

-- Puts `key` on `action` (replacing slot `index`, or adding it when index is nil).
-- A key only does one thing, so it's taken off whatever action had it; that action is returned.
function Input.Bind(device, action, key, index)
	local map = Input.Bindings[device]
	local keys = map[action]
	local stolenFrom = nil
	local here = table.find(keys, key)
	if here then
		if index and index <= #keys and index ~= here then
			keys[here], keys[index] = keys[index], keys[here]
		end
	else
		for a, other in pairs(map) do
			local i = table.find(other, key)
			if i then
				table.remove(other, i)
				stolenFrom = a
			end
		end
		if index and index <= #keys then
			keys[index] = key
		elseif #keys < Input.MaxPerAction then
			table.insert(keys, key)
		else
			keys[#keys] = key
		end
	end
	changed()
	return stolenFrom
end

function Input.Unbind(device, action, index)
	local keys = Input.Bindings[device][action]
	if keys[index] then
		table.remove(keys, index)
		changed()
	end
end

function Input.ResetDefaults(device)
	Input.Bindings[device] = defaultsFor(device)
	if device == "gamepad" then Input.RightStickSmash = true end
	changed()
end

function Input.SetOption(name, value)
	if name == "TapJump" then Input.TapJump = value == true end
	if name == "RightStickSmash" then Input.RightStickSmash = value == true end
	changed()
end

function Input.Export()
	return {
		v = 1,
		keyboard = Input.Bindings.keyboard,
		gamepad = Input.Bindings.gamepad,
		tapJump = Input.TapJump,
		rsSmash = Input.RightStickSmash,
	}
end

local function validKey(device, k)
	if type(k) ~= "string" or Input.Reserved[k] or Input.DeviceOf(k) ~= device then return false end
	if k == "MouseButton1" or k == "MouseButton2" then return true end
	local ok, code = pcall(function() return Enum.KeyCode[k] end)
	return ok and code ~= nil
end

-- Loads bindings saved on a previous visit
function Input.Import(data)
	if type(data) ~= "table" then return end
	for _, device in ipairs({ "keyboard", "gamepad" }) do
		local src = data[device]
		if type(src) == "table" then
			local seen = {}
			-- 1) what the player saved wins
			for _, action in ipairs(Input.Actions) do
				local list = src[action]
				if type(list) == "table" then
					local keys = {}
					for _, k in ipairs(list) do
						if validKey(device, k) and not seen[k] and #keys < Input.MaxPerAction then
							seen[k] = true
							table.insert(keys, k)
						end
					end
					Input.Bindings[device][action] = keys
				end
			end
			-- 2) actions added after they saved (e.g. Grab) get whichever defaults are still free
			for _, action in ipairs(Input.Actions) do
				if type(src[action]) ~= "table" then
					local keys = {}
					for _, k in ipairs(Input.Defaults[device][action] or {}) do
						if not seen[k] then
							seen[k] = true
							table.insert(keys, k)
						end
					end
					Input.Bindings[device][action] = keys
				end
			end
		end
	end
	if data.tapJump ~= nil then Input.TapJump = data.tapJump == true end
	if data.rsSmash ~= nil then Input.RightStickSmash = data.rsSmash == true end
	rebuild()
	if Input.OnImported then Input.OnImported() end
end

-- Live input state --------------------------------------------------------------------------

local held = {}      -- action -> bool
local pressed = {}   -- action -> pressed this frame
local keysDown = {}  -- key name -> bool (so two keys on one action release correctly)
local stick = Vector2.zero
local rstick = Vector2.zero
local rstickWasOut = false
local smashDir = nil
local touchMove = Vector2.zero
local prev = { up = false, down = false, xs = 0, stickUp = false }

local function press(action)
	if not held[action] then
		pressed[action] = true
	end
	held[action] = true
	if action == "up" and Input.TapJump then
		pressed.jump = true
		held.tapjump = true
	end
end

local function releaseAction(action)
	held[action] = false
	if action == "up" then held.tapjump = false end
end

local function releaseKey(name)
	keysDown[name] = nil
	local action = lookup[name]
	if not action then return end
	for k, a in pairs(lookup) do
		if a == action and keysDown[k] then return end -- another key for this action is still held
	end
	releaseAction(action)
end

-- exposed for the touch buttons
Input.Press = press
Input.Release = releaseAction
function Input.SetTouchMove(v)
	touchMove = v
end

-- Drops presses made while a menu was open, so closing a menu doesn't also attack/jump
function Input.Flush()
	table.clear(pressed)
	smashDir = nil
end

function Input.Init()
	UserInputService.InputBegan:Connect(function(io, gameProcessed)
		local name = Input.NameOf(io)
		if not name then return end
		local isPad = Input.DeviceOf(name) == "gamepad"
		if gameProcessed and not isPad then return end
		keysDown[name] = true
		local action = lookup[name]
		if action then press(action) end
	end)
	UserInputService.InputEnded:Connect(function(io)
		local name = Input.NameOf(io)
		if name then releaseKey(name) end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = Vector2.new(io.Position.X, io.Position.Y)
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			rstick = Vector2.new(io.Position.X, io.Position.Y)
			local out = rstick.Magnitude > 0.7
			if Input.RightStickSmash then
				if out and not rstickWasOut then
					smashDir = rstick
					press("smash")
				elseif not out and rstickWasOut then
					releaseAction("smash")
				end
			end
			rstickWasOut = out
		end
	end)
	-- lose all held keys when the window loses focus so nobody gets stuck shielding
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
		table.clear(keysDown)
	end)
end

function Input.Stick()
	return stick
end

local function sign(x)
	if x > 0.35 then return 1 elseif x < -0.35 then return -1 end
	return 0
end

function Input.Poll()
	local input = Controller.BlankInput()
	local x = (held.right and 1 or 0) - (held.left and 1 or 0)
	if math.abs(stick.X) > 0.35 then x = stick.X end
	if math.abs(touchMove.X) > 0.25 then x = touchMove.X end
	x = math.clamp(x, -1, 1)
	local stickUp = stick.Y > 0.55 or touchMove.Y > 0.55
	local up = held.up or stickUp
	local down = held.down or stick.Y < -0.55 or touchMove.Y < -0.55

	if smashDir then
		-- right stick: smash attack in the flicked direction
		if math.abs(smashDir.Y) > math.abs(smashDir.X) then
			up = smashDir.Y > 0
			down = smashDir.Y < 0
		else
			x = smashDir.X > 0 and 1 or -1
		end
	end

	input.x = x
	input.up = up
	input.down = down
	input.upPressed = up and not prev.up
	input.downPressed = down and not prev.down
	local xs = sign(x)
	input.xPressed = (xs ~= 0 and xs ~= prev.xs) and xs or 0
	local tapJump = Input.TapJump and stickUp and not prev.stickUp
	input.jumpPressed = pressed.jump == true or tapJump
	input.jumpHeld = held.jump == true or (Input.TapJump and (held.tapjump == true or stickUp))
	input.attackPressed = pressed.attack == true
	input.specialPressed = pressed.special == true
	input.specialHeld = held.special == true
	input.smashPressed = pressed.smash == true
	input.smashHeld = held.smash == true
	input.shieldHeld = held.shield == true
	input.shieldPressed = pressed.shield == true
	input.tauntPressed = pressed.taunt == true
	input.grabPressed = pressed.grab == true
	input.anyPressed = next(pressed) ~= nil

	prev.up, prev.down, prev.xs, prev.stickUp = up, down, xs, stickUp
	table.clear(pressed)
	smashDir = nil
	if Input.Blocked then
		return Controller.BlankInput()
	end
	return input
end

-- On-screen controls for phones/tablets ----------------------------------------------------
function Input.BuildTouch(gui)
	if not UserInputService.TouchEnabled then return end
	local pad = Instance.new("Frame")
	pad.Name = "MovePad"
	pad.Size = UDim2.fromOffset(170, 170)
	pad.Position = UDim2.new(0, 30, 1, -220)
	pad.BackgroundColor3 = Color3.new(0, 0, 0)
	pad.BackgroundTransparency = 0.6
	pad.Parent = gui
	Instance.new("UICorner", pad).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(64, 64)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.3
	knob.Parent = pad
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local activeTouch
	pad.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch and not activeTouch then
			activeTouch = io
		end
	end)
	UserInputService.TouchMoved:Connect(function(io)
		if io ~= activeTouch then return end
		local center = pad.AbsolutePosition + pad.AbsoluteSize / 2
		local d = Vector2.new(io.Position.X, io.Position.Y) - center
		local r = pad.AbsoluteSize.X / 2
		if d.Magnitude > r then d = d.Unit * r end
		knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
		Input.SetTouchMove(Vector2.new(d.X / r, -d.Y / r))
	end)
	UserInputService.TouchEnded:Connect(function(io)
		if io ~= activeTouch then return end
		activeTouch = nil
		knob.Position = UDim2.fromScale(0.5, 0.5)
		Input.SetTouchMove(Vector2.zero)
	end)

	local buttons = {
		{ "JUMP", "jump", UDim2.new(1, -110, 1, -130), Color3.fromRGB(60, 190, 90) },
		{ "ATK", "attack", UDim2.new(1, -200, 1, -90), Color3.fromRGB(235, 64, 52) },
		{ "SPC", "special", UDim2.new(1, -200, 1, -190), Color3.fromRGB(52, 120, 235) },
		{ "SMASH", "smash", UDim2.new(1, -110, 1, -230), Color3.fromRGB(245, 160, 40) },
		{ "SHLD", "shield", UDim2.new(1, -290, 1, -140), Color3.fromRGB(150, 90, 230) },
		{ "GRAB", "grab", UDim2.new(1, -290, 1, -240), Color3.fromRGB(230, 90, 170) },
	}
	for _, b in ipairs(buttons) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(78, 78)
		btn.Position = b[3]
		btn.BackgroundColor3 = b[4]
		btn.BackgroundTransparency = 0.25
		btn.Text = b[1]
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBlack
		btn.TextSize = 16
		btn.AutoButtonColor = false
		btn.Parent = gui
		Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
		btn.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then press(b[2]) end
		end)
		btn.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then releaseAction(b[2]) end
		end)
	end
end

return Input
