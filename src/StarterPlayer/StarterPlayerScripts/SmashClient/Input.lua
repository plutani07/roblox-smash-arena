-- Keyboard / mouse / gamepad / touch -> one input snapshot per frame for the Controller.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controller = require(ReplicatedStorage:WaitForChild("Smash"):WaitForChild("Controller"))

local Input = {}
Input.TapJump = false   -- when true, W / stick-up also jumps
Input.Blocked = false   -- menus set this

local held = {}
local pressed = {}
local stick = Vector2.zero
local rstick = Vector2.zero
local rstickWasOut = false
local smashDir = nil
local touchMove = Vector2.zero
local prev = { up = false, down = false, xs = 0, stickUp = false }

local KEYS = {
	[Enum.KeyCode.A] = "left", [Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.D] = "right", [Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.W] = "up", [Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.S] = "down", [Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.Space] = "jump",
	[Enum.KeyCode.J] = "attack",
	[Enum.KeyCode.K] = "special",
	[Enum.KeyCode.L] = "smash",
	[Enum.KeyCode.Q] = "shield", [Enum.KeyCode.LeftShift] = "shield", [Enum.KeyCode.RightShift] = "shield",
	[Enum.KeyCode.T] = "taunt",
	[Enum.KeyCode.ButtonA] = "attack", [Enum.KeyCode.ButtonB] = "special",
	[Enum.KeyCode.ButtonX] = "jump", [Enum.KeyCode.ButtonY] = "jump",
	[Enum.KeyCode.ButtonR1] = "shield", [Enum.KeyCode.ButtonL1] = "shield",
	[Enum.KeyCode.ButtonR2] = "shield", [Enum.KeyCode.ButtonL2] = "shield",
	[Enum.KeyCode.DPadLeft] = "left", [Enum.KeyCode.DPadRight] = "right",
	[Enum.KeyCode.DPadDown] = "down", [Enum.KeyCode.DPadUp] = "taunt",
}

local function press(button)
	if not held[button] then
		pressed[button] = true
	end
	held[button] = true
	if button == "up" and Input.TapJump then
		pressed.jump = true
		held.tapjump = true
	end
end

local function release(button)
	held[button] = false
	if button == "up" then held.tapjump = false end
end

-- exposed for the touch buttons
Input.Press = press
Input.Release = release
function Input.SetTouchMove(v)
	touchMove = v
end

function Input.Init()
	UserInputService.InputBegan:Connect(function(io, gameProcessed)
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			if not gameProcessed then press("attack") end
			return
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
			if not gameProcessed then press("special") end
			return
		end
		if gameProcessed and io.UserInputType == Enum.UserInputType.Keyboard then return end
		local b = KEYS[io.KeyCode]
		if b then press(b) end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			release("attack")
			return
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
			release("special")
			return
		end
		local b = KEYS[io.KeyCode]
		if b then release(b) end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = Vector2.new(io.Position.X, io.Position.Y)
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			rstick = Vector2.new(io.Position.X, io.Position.Y)
			local out = rstick.Magnitude > 0.7
			if out and not rstickWasOut then
				smashDir = rstick
				press("smash")
			elseif not out and rstickWasOut then
				release("smash")
			end
			rstickWasOut = out
		end
	end)
	-- lose all held keys when the window loses focus so nobody gets stuck shielding
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
	end)
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
			if io.UserInputType == Enum.UserInputType.Touch then release(b[2]) end
		end)
	end
end

return Input
