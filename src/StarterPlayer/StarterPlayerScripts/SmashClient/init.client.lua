--[[
	SMASH CLIENT
	Runs your fighter's movement locally (for responsive controls), sends attacks to the server,
	and draws everything: camera, animations, effects, HUD and menus.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Fighters = require(Smash.Fighters)
local Controller = require(Smash.Controller)
local remotes = Smash:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")
local Event = remotes:WaitForChild("Event")
local state = Smash:WaitForChild("State")

local Input = require(script.Input)
local CameraRig = require(script.CameraRig)
local Animator = require(script.Animator)
local Effects = require(script.Effects)
local Hud = require(script.Hud)
local Menu = require(script.Menu)
local ControlsMenu = require(script.ControlsMenu)

-- Roblox defaults we don't want in a platform fighter
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then break end
		task.wait(1)
	end
end)

local function disableDefaultControls()
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		pm:GetControls():Disable()
	end)
end

Input.Init()
CameraRig.Init()
Animator.Init()
Effects.CameraRig = CameraRig
Effects.ModelFor = Animator.ModelFor
Effects.Init()
Hud.Init(playerGui, state)
-- the View/Select button opens our menus instead of Roblox's UI-navigation mode
pcall(function() GuiService.AutoSelectGuiEnabled = false end)

local menuSound = function() Effects.Sound("tick", 0.5, 1.2) end
Menu.Input = Input
Menu.Controls = ControlsMenu
Menu.Sound = menuSound
Menu.OnSelect = function(key) Action:FireServer("Select", key) end
Menu.OnSetting = function(name, value) Action:FireServer("Setting", name, value) end
Menu.OnStart = function() Action:FireServer("StartMatch") end
Menu.OnOpenControls = function() ControlsMenu.Open() end
Menu.Init(playerGui, state)
Input.BuildTouch(Menu.Gui)

ControlsMenu.Input = Input
ControlsMenu.Sound = menuSound
ControlsMenu.OnOpenFighters = function() Menu.Open() end
ControlsMenu.CanOpenFighters = function() return state:GetAttribute("Phase") == "Lobby" end
ControlsMenu.OnClosed = function() Menu.RefreshHelp() end
ControlsMenu.Init(playerGui)

-- remapped controls are saved on the server (a couple of seconds after the last change)
local saveToken = 0
Input.OnChanged = function()
	Menu.RefreshHelp()
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken then
			Action:FireServer("SaveControls", Input.Export())
		end
	end)
end
Input.OnImported = function()
	Menu.RefreshHelp()
	ControlsMenu.Refresh()
end
Action:FireServer("LoadControls")

-- Our fighter --------------------------------------------------------------------------------
local controller = nil
local myId = nil

local function setupCharacter(char)
	if controller then
		controller:Destroy()
		controller = nil
	end
	myId = nil
	if not char:GetAttribute("FighterReady") then
		char:GetAttributeChangedSignal("FighterReady"):Wait()
	end
	if player.Character ~= char then return end
	disableDefaultControls()
	local def = Fighters.Get(char:GetAttribute("FighterKey"))
	myId = char:GetAttribute("FighterId")
	Animator.LocalModel = char
	controller = Controller.new(char, def, {
		platformMode = "local",
		hooks = {
			startMove = function(key, charge, facing)
				Action:FireServer("Move", key, charge, facing)
				return true
			end,
			localMove = function(key)
				Animator.PlayMove(char, key)
				Effects.OnMove({ id = myId, key = key })
			end,
			charge = function(key)
				Animator.LocalCharge(char, key)
				Action:FireServer("Charge", key)
			end,
			shield = function(on) Action:FireServer("Shield", on) end,
			dodge = function(kind)
				Action:FireServer("Dodge", kind)
				Animator.OnDodge({ id = myId, kind = kind })
			end,
			ledge = function(on) Action:FireServer("Ledge", on) end,
			leaveRevival = function() Action:FireServer("LeaveRevival") end,
			fx = function(kind) Action:FireServer("Fx", kind) end,
		},
	})
	Animator.LocalState = function()
		return controller and controller:GetState()
	end
end

player.CharacterAdded:Connect(function(char)
	task.spawn(setupCharacter, char)
end)
if player.Character then
	task.spawn(setupCharacter, player.Character)
end

local menuWasOpen = false
RunService.Stepped:Connect(function(_, dt)
	-- while a menu is open your fighter stands still; the press that closes it is thrown away
	local menuOpen = Menu.IsOpen() or ControlsMenu.IsOpen()
	local input = Input.Poll()
	if menuOpen then
		input = Controller.BlankInput()
	elseif menuWasOpen then
		Input.Flush()
		input = Controller.BlankInput()
	end
	menuWasOpen = menuOpen
	if controller and controller.model.Parent then
		local ok, err = pcall(controller.Step, controller, dt, input)
		if not ok then warn("[Smash] controller error:", err) end
	end
end)

-- Server events -----------------------------------------------------------------------------
Event.OnClientEvent:Connect(function(kind, data)
	if kind == "Move" then
		if data.id ~= myId then
			Animator.OnMove(data)
			Effects.OnMove(data)
		end
	elseif kind == "Charge" then
		Animator.OnCharge(data)
	elseif kind == "Hit" then
		Animator.OnHit(data)
		Effects.OnHit(data)
		if controller then
			if data.v == myId and not data.armored then
				controller:ApplyHit({
					vel = Vector2.new(data.vx, data.vy), hitstun = data.hitstun, hitlag = data.hitlag,
					freeze = data.freeze, tumble = data.tumble,
				})
			elseif data.v == myId and data.armored then
				controller:ApplyAttackerHitlag(data.hitlag)
			end
			if data.a == myId and (data.attackerLag or 0) > 0 then
				controller:ApplyAttackerHitlag(data.attackerLag)
			end
		end
	elseif kind == "ShieldHit" then
		Effects.OnShieldHit(data)
		if controller then
			if data.v == myId then controller:ApplyPush(data.push) end
			if data.a == myId and data.hitlag > 0 then controller:ApplyAttackerHitlag(data.hitlag) end
		end
	elseif kind == "ShieldBreak" then
		Effects.OnShieldBreak(data)
		Animator.OnStun(data.id, data.hitstun)
		if controller and data.id == myId then
			controller:ApplyHit({ vel = Vector2.new(data.vx, data.vy), hitstun = data.hitstun, hitlag = data.hitlag })
		end
	elseif kind == "Parry" then
		Effects.OnParry(data)
		if data.stun and data.stun > 0 then
			Animator.OnStun(data.a, data.stun)
			if controller and data.a == myId then
				controller:ApplyHit({ vel = Vector2.zero, hitstun = data.stun, hitlag = 0.15 })
			end
		end
	elseif kind == "Counter" then
		Effects.OnCounter(data)
		Animator.OnCounter(data)
	elseif kind == "Dodge" then
		if data.id ~= myId then Animator.OnDodge(data) end
	elseif kind == "Proj" then
		Effects.OnProjectile(data)
	elseif kind == "Shockwave" then
		Effects.OnShockwave(data)
	elseif kind == "Fx" then
		Effects.OnFx(data)
	elseif kind == "KO" then
		Effects.OnKO(data)
		Animator.Reset(data.id)
	elseif kind == "Respawn" then
		Animator.Reset(data.id)
		if controller and data.id == myId then controller:Reset() end
	elseif kind == "MoveRejected" then
		if controller then controller:CancelAction() end
	elseif kind == "Controls" then
		Input.Import(data)
	elseif kind == "Announce" then
		Hud.Announce(data.text, data.color, data.dur, data.sub)
		if data.text == "GO!" then
			Effects.Sound("boom", 0.4, 1.4)
		elseif #data.text <= 2 then
			Effects.Sound("tick", 0.8, 0.9)
		end
	elseif kind == "Results" then
		local model = data.winner and Animator.ModelFor(data.winner)
		CameraRig.Focus(model)
		Animator.SetVictory(model)
		Hud.ShowResults(data)
		task.delay(Config.ResultsTime, function()
			CameraRig.Focus(nil)
			Animator.SetVictory(nil)
		end)
	end
end)

-- first time in: show the character select
task.delay(1.5, function()
	if state:GetAttribute("Phase") == "Lobby" then
		Menu.Open()
	end
end)
