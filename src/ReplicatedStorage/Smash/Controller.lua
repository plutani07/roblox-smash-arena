--[[
	Fighter movement controller. Runs on whichever machine simulates the character:
	the player's client for their own fighter, the server for CPU fighters.

	It owns: running, jumps (multi-jump + short hop), fast fall, air drift, facing, pass-through
	platforms, ledge grabs, shield/roll/spot dodge/air dodge, move timelines (motion, teleports,
	gravity changes), hitlag freeze and knockback flight. Hitboxes and damage live on the server.
]]
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(script.Parent.Config)
local Moves = require(script.Parent.Moves)

local Controller = {}
Controller.__index = Controller

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 end
	return 0
end

local function approach(cur, target, step)
	if cur < target then return math.min(cur + step, target) end
	return math.max(cur - step, target)
end

function Controller.BlankInput()
	return {
		x = 0, up = false, down = false, upPressed = false, downPressed = false, xPressed = 0,
		jumpPressed = false, jumpHeld = false, attackPressed = false, specialPressed = false,
		specialHeld = false, smashPressed = false, smashHeld = false, shieldHeld = false,
		shieldPressed = false, tauntPressed = false, grabPressed = false, anyPressed = false,
	}
end

function Controller.new(model, def, opts)
	local self = setmetatable({}, Controller)
	self.model = model
	self.humanoid = model:WaitForChild("Humanoid")
	self.root = model:WaitForChild("HumanoidRootPart")
	self.def = def
	self.stats = def.Stats
	self.moves = Moves.Get(def.Key)
	self.scale = def.Scale or 1
	self.opts = opts or {}
	self.hooks = self.opts.hooks or {}
	self.clock = 0
	self.facing = self.root.CFrame.LookVector.X >= 0 and 1 or -1
	self.cooldowns = {}
	self.platformState = {}
	self:Reset()
	self:_setupPhysics()
	return self
end

function Controller:Reset()
	self.jumpsLeft = self.stats.AirJumps
	self.grounded = true
	self.wasGrounded = true
	self.action = nil
	self.charging = nil
	self.hitstun = 0
	self.hitlag = 0
	self.pendingLaunch = nil
	self.launchVX = 0
	self.tumble = false
	self.ledge = nil
	self.ledgeCooldown = 0
	self.dodge = nil
	self.landLag = 0
	self.dropTimer = 0
	self.helpless = false
	self.airDodgeUsed = false
	self.sideSpecialUsed = false
	self.fastFalling = false
	self.jumpHeld = false
	self.buffer = nil
	if self.shielding and self.hooks.shield then self.hooks.shield(false) end
	self.shielding = false
	self.holding = nil
	self.grabbedBy = nil
	if self.crouching and self.hooks.crouch then self.hooks.crouch(false) end
	self.crouching = false
	self.climbing = nil
	if self.root then
		self.root.AssemblyLinearVelocity = Vector3.zero
	end
end

function Controller:_setupPhysics()
	local hum, root = self.humanoid, self.root
	hum.AutoRotate = false
	hum.UseJumpPower = false
	hum.JumpHeight = self.stats.JumpHeight * self.stats.Gravity
	hum.WalkSpeed = self.stats.RunSpeed
	hum.AutoJumpEnabled = false
	hum.RequiresNeck = false
	for _, st in ipairs({
		Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Flying,
		Enum.HumanoidStateType.StrafingNoPhysics,
	}) do
		pcall(function() hum:SetStateEnabled(st, false) end)
	end

	local att = root:FindFirstChild("SmashAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "SmashAttachment"
		att.Parent = root
	end

	local ao = root:FindFirstChild("SmashFacing") or Instance.new("AlignOrientation")
	ao.Name = "SmashFacing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(self.facing, 0, 0))
	ao.Parent = root
	self.align = ao

	local lv = root:FindFirstChild("SmashPlaneLock") or Instance.new("LinearVelocity")
	lv.Name = "SmashPlaneLock"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = Vector3.zAxis
	lv.LineVelocity = 0
	lv.MaxForce = 1e6
	lv.Parent = root
	self.planeLock = lv

	local vf = root:FindFirstChild("SmashGravity") or Instance.new("VectorForce")
	vf.Name = "SmashGravity"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = root
	self.gravityForce = vf

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Config.GetStage().Model }
	params.RespectCanCollide = true
	if self.opts.group then
		params.CollisionGroup = self.opts.group
	end
	self.rayParams = params

	-- snap to the stage plane and face the right way
	self:_face(self.facing, true)
end

-- Helpers -------------------------------------------------------------------------

function Controller:_face(dir, force)
	if dir == 0 then return end
	if dir == self.facing and not force then return end
	self.facing = dir
	local root = self.root
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(dir, 0, 0))
	if self.align then
		self.align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(dir, 0, 0))
	end
end

-- Sets horizontal velocity and keeps the Humanoid's own controller agreeing with it
function Controller:_setVX(vx)
	local root, hum = self.root, self.humanoid
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(vx, v.Y, 0)
	hum.WalkSpeed = math.abs(vx)
	hum:Move(Vector3.new(sign(vx), 0, 0), false)
end

function Controller:_drive(target, accel, dt)
	local vx = self.root.AssemblyLinearVelocity.X
	self:_setVX(approach(vx, target, accel * dt))
end

function Controller:_setVY(vy)
	local v = self.root.AssemblyLinearVelocity
	self.root.AssemblyLinearVelocity = Vector3.new(v.X, vy, 0)
end

function Controller:_gravity(scale)
	local mass = self.root.AssemblyMass
	self.gravityForce.Force = Vector3.new(0, mass * workspace.Gravity * (1 - scale), 0)
end

function Controller:_feetY()
	return self.root.Position.Y - (self.humanoid.HipHeight + self.root.Size.Y / 2)
end

function Controller:_checkGrounded()
	local root = self.root
	if root.AssemblyLinearVelocity.Y > 6 then return false, nil end
	local reach = self.humanoid.HipHeight + root.Size.Y / 2 + 0.45
	local best
	for _, dx in ipairs({ 0, -0.7 * self.scale, 0.7 * self.scale }) do
		local origin = root.Position + Vector3.new(dx, 0, 0)
		local r = workspace:Raycast(origin, Vector3.new(0, -reach, 0), self.rayParams)
		if r then
			best = r
			break
		end
	end
	return best ~= nil, best and best.Instance
end

function Controller:_inputDir(input, default)
	local x = input.x
	local y = (input.up and 1 or 0) - (input.down and 1 or 0)
	local d = Vector2.new(x, y)
	if d.Magnitude < 0.2 then return default end
	return d.Unit
end

function Controller:_dirName(input)
	if input.up then return "up" end
	if input.down then return "down" end
	if math.abs(input.x) > 0.3 then return "side" end
	return "neutral"
end

function Controller:_updatePlatforms()
	local stage = Config.GetStage()
	local feet = self:_feetY()
	for i, plat in ipairs(stage.Platforms) do
		local top = plat.Position.Y + plat.Size.Y / 2
		local solid = self.dropTimer <= 0 and feet >= top - 0.45
		if self.platformState[i] ~= solid then
			self.platformState[i] = solid
			if self.opts.platformMode == "group" and self.opts.group then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable(self.opts.group, "SoftPlatform" .. i, solid)
				end)
			else
				plat.CanCollide = solid
			end
		end
	end
end

function Controller:_planeLock()
	local stage = Config.GetStage()
	local p = self.root.Position
	if math.abs(p.Z - stage.Z) > 0.25 then
		self.root.CFrame = self.root.CFrame + Vector3.new(0, 0, stage.Z - p.Z)
	end
end

-- Events from combat --------------------------------------------------------------

-- info = { vel = Vector2, hitstun = seconds, hitlag = seconds, freeze = seconds, tumble = bool }
function Controller:ApplyHit(info)
	if self.ledge then
		self.ledge = nil
		self.ledgeCooldown = Config.LedgeRegrabCooldown
		if self.hooks.ledge then self.hooks.ledge(false) end
	end
	if self.shielding then
		self.shielding = false
		if self.hooks.shield then self.hooks.shield(false) end
	end
	self.action = nil
	self.charging = nil
	self.dodge = nil
	self.holding = nil
	self.grabbedBy = nil
	self.climbing = nil
	self.landLag = 0
	self.helpless = false
	self.fastFalling = false
	self.hitlag = (info.hitlag or 0) + (info.freeze or 0)
	self.hitstun = info.hitstun or 0
	self.tumble = info.tumble
	self.pendingLaunch = info
	self.hitlagVel = nil
	if self.hitlag <= 0 then
		self:_launch(info, nil)
	end
end

function Controller:ApplyAttackerHitlag(sec)
	if self.hitlag <= 0 then
		self.hitlagVel = self.root.AssemblyLinearVelocity
	end
	self.hitlag = math.max(self.hitlag, sec)
end

function Controller:ApplyPush(vx)
	self.pushVX = vx
end

-- Grabs -----------------------------------------------------------------------------------------

local function clearForGrab(self)
	self.climbing = nil
	if self.ledge then
		self.ledge = nil
		self.ledgeCooldown = Config.LedgeRegrabCooldown
		if self.hooks.ledge then self.hooks.ledge(false) end
	end
	if self.shielding then
		self.shielding = false
		if self.hooks.shield then self.hooks.shield(false) end
	end
	self.action = nil
	self.charging = nil
	self.dodge = nil
	self.landLag = 0
	self.hitstun = 0
	self.pendingLaunch = nil
end

-- We caught someone: stand still, attack = pummel, a direction = throw
function Controller:EnterHold(victimModel)
	clearForGrab(self)
	self.grabbedBy = nil
	self.holding = { victim = victimModel, t = 0, nextPummel = 0 }
end

function Controller:ExitHold(pushVX)
	if not self.holding then return end
	self.holding = nil
	if pushVX then
		self.pushVX = pushVX
		self.landLag = 0.2
	end
end

-- Someone caught us: follow their hands and mash to break out
function Controller:EnterGrabbed(attackerModel, attackerScale)
	clearForGrab(self)
	self.holding = nil
	self.grabbedBy = { model = attackerModel, scale = attackerScale or 1, t = 0 }
end

function Controller:ExitGrabbed(pushVX)
	if not self.grabbedBy then return end
	self.grabbedBy = nil
	if pushVX then
		self.launchVX = pushVX
		self.hitstun = 0.22
		self.root.AssemblyLinearVelocity = Vector3.new(pushVX, 24, 0)
	end
end

function Controller:_throw(dir)
	local key = dir .. "throw"
	local move = self.moves[key]
	if not move then return end
	self.holding = nil
	if self.hooks.throw then self.hooks.throw(dir) end
	self.action = { key = key, move = move, t = 0, charge = 0, motion = {}, dirs = {}, teleported = false, startGrounded = true }
	if self.hooks.localMove then self.hooks.localMove(key, 0) end
end

function Controller:_updateHold(dt, input)
	local h = self.holding
	h.t += dt
	self:_drive(0, 200, dt)
	self:_gravity(self.stats.Gravity)
	if h.t < 0.1 then return end
	local dir
	if input.upPressed then dir = "u"
	elseif input.downPressed then dir = "d"
	elseif input.xPressed ~= 0 then dir = input.xPressed == self.facing and "f" or "b" end
	if dir then
		self:_throw(dir)
	elseif (input.attackPressed or input.grabPressed) and h.t >= h.nextPummel then
		h.nextPummel = h.t + 0.32
		if self.hooks.pummel then self.hooks.pummel() end
		if self.hooks.localMove then self.hooks.localMove("pummel", 0) end
	end
end

function Controller:_updateGrabbed(dt, input)
	local g = self.grabbedBy
	g.t += dt
	local aroot = g.model and g.model.Parent and g.model:FindFirstChild("HumanoidRootPart")
	if not aroot then
		self.grabbedBy = nil
		return
	end
	local f = aroot.CFrame.LookVector.X >= 0 and 1 or -1
	local target = aroot.Position + Vector3.new(f * 2.4 * g.scale, 0.3 * g.scale, 0)
	local err = target - self.root.Position
	self:_setVX(err.X * 18)
	self:_setVY(err.Y * 18)
	self:_gravity(0)
	self:_face(-f)
	if input.anyPressed or input.xPressed ~= 0 or input.upPressed or input.downPressed then
		if self.hooks.mash then self.hooks.mash() end
	end
end

function Controller:_setCrouch(on)
	if on == self.crouching then return end
	self.crouching = on
	if self.hooks.crouch then self.hooks.crouch(on) end
end

function Controller:CancelAction()
	self.action = nil
	self.charging = nil
end

function Controller:_launch(info, input)
	local v = info.vel or Vector2.zero
	-- directional influence: steer the launch a little
	if input and v.Magnitude > 20 then
		local di = Vector2.new(input.x, (input.up and 1 or 0) - (input.down and 1 or 0))
		if di.Magnitude > 0.2 then
			local perp = Vector2.new(-v.Y, v.X).Unit
			local amount = di.Unit:Dot(perp)
			local ang = math.rad(Config.DIAngle) * amount
			local c, s = math.cos(ang), math.sin(ang)
			v = Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
		end
	end
	-- spiking a grounded fighter bounces them off the floor
	if self.grounded and v.Y < 0 then
		v = Vector2.new(v.X, -v.Y * 0.7)
	end
	self.launchVX = v.X
	self.root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
	if v.Y > 1 then
		self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		self.grounded = false
		self.wasGrounded = false
	end
	if self.hitstun > 0.25 then
		-- getting launched refreshes your double jump like in Smash
		self.jumpsLeft = math.max(self.jumpsLeft, 1)
		self.airDodgeUsed = false
		self.sideSpecialUsed = false
	end
end

-- Actions ---------------------------------------------------------------------------

function Controller:_startAction(key, charge)
	local move = self.moves[key]
	if not move then return false end
	if self.hooks.startMove then
		local ok = self.hooks.startMove(key, charge or 0, self.facing)
		if ok == false then return false end
	end
	self.action = {
		key = key,
		move = move,
		t = 0,
		charge = charge or 0,
		motion = {},
		dirs = {},
		teleported = false,
		startGrounded = self.grounded,
	}
	if move.oncePerAir and not self.grounded then
		self.sideSpecialUsed = true
	end
	if move.cooldown then
		self.cooldowns[key] = move.cooldown
	end
	if self.hooks.localMove then self.hooks.localMove(key, charge or 0) end
	return true
end

function Controller:_endAction()
	local a = self.action
	self.action = nil
	if a and a.move.helpless and not self.grounded then
		self.helpless = true
	end
end

function Controller:_canUse(key)
	local move = self.moves[key]
	if not move then return false end
	if self.helpless then return false end
	if (self.cooldowns[key] or 0) > 0 then return false end
	if move.oncePerAir and not self.grounded and self.sideSpecialUsed then return false end
	return true
end

function Controller:_tryPress(button, input)
	local dir = self:_dirName(input)
	local forward = sign(input.x) == self.facing
	local key = Moves.Resolve(button, dir, self.grounded, forward)
	-- attacking out of a full sprint becomes a dash attack instead of stopping dead
	if button == "attack" and self.grounded and (dir == "side" or dir == "neutral") then
		local vx = self.root.AssemblyLinearVelocity.X
		if math.abs(vx) > self.stats.RunSpeed * 0.75 and sign(vx) == self.facing and (dir == "neutral" or forward) then
			key = "dashattack"
		end
	end
	if not self:_canUse(key) then return false end
	-- ground moves and side specials turn toward the stick
	if dir == "side" and (self.grounded or button == "special") then
		self:_face(sign(input.x))
	end
	local move = self.moves[key]
	if move.charge and move.charge.button == button then
		self.charging = { key = key, t = 0, button = button }
		if self.hooks.charge then self.hooks.charge(key) end
		return true
	end
	return self:_startAction(key, 0)
end

-- Remember a press made while busy so it comes out on the first free frame (input buffer)
function Controller:_recordPress(input)
	local button
	if input.specialPressed then button = "special"
	elseif input.smashPressed then button = "smash"
	elseif input.grabPressed then button = "grab"
	elseif input.attackPressed then button = "attack" end
	if button then
		self.buffer = { button = button, t = self.clock }
	end
end

function Controller:_consumePress(input)
	local now = self.clock
	self:_recordPress(input)
	if self.buffer and now - self.buffer.t <= 0.14 then
		local b = self.buffer.button
		self.buffer = nil
		return b
	end
	self.buffer = nil
	return nil
end

function Controller:_updateAction(dt, input)
	local a = self.action
	local move = a.move
	local root = self.root
	a.t += dt

	-- gravity windows
	local gscale = self.stats.Gravity
	if move.gravity and a.t >= move.gravity.t0 and a.t <= move.gravity.t1 then
		gscale = self.stats.Gravity * move.gravity.scale
		if not a.gravityStarted then
			a.gravityStarted = true
			if move.gravity.scale <= 0.35 and root.AssemblyLinearVelocity.Y < 0 then
				self:_setVY(0)
			end
		end
	end
	self:_gravity(gscale)

	-- horizontal control: aerials drift, grounded moves plant
	local drifting = not self.grounded
	local motionX = false
	for i, m in ipairs(move.motion or {}) do
		if a.t >= m.t and a.t <= m.t + m.dur then
			local v = root.AssemblyLinearVelocity
			local vx, vy = v.X, v.Y
			if m.dirInput then
				if not a.dirs[i] then
					a.dirs[i] = self:_inputDir(input, Vector2.new(0, 1))
					if a.dirs[i].X ~= 0 then self:_face(sign(a.dirs[i].X)) end
				end
				vx = a.dirs[i].X * m.dirInput
				vy = a.dirs[i].Y * m.dirInput
			else
				if m.vx then vx = m.vx * self.facing + (m.steer or 0) * input.x end
				if m.vy then vy = m.vy end
			end
			root.AssemblyLinearVelocity = Vector3.new(vx, vy, 0)
			self:_setVX(vx)
			if vy > 1 then
				self.grounded = false
			end
			a.motion[i] = true
			motionX = true
		elseif a.motion[i] and a.t > m.t + m.dur then
			a.motion[i] = nil
			if m.stopAfter then
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.25
			end
		end
	end
	if not motionX then
		if drifting then
			local speed = self.stats.AirSpeed * (move.air and 1 or 0.6)
			self:_drive(input.x * speed, 70, dt)
		else
			self:_drive(0, 160, dt)
		end
	end

	-- teleports (blink strikes / warps)
	local tp = move.teleport
	if tp and not a.teleported and a.t >= tp.t then
		a.teleported = true
		local dir
		if tp.dir == "input" then
			dir = self:_inputDir(input, Vector2.new(0, 1))
		else
			dir = Vector2.new(self.facing, 0)
		end
		local offset = Vector3.new(dir.X, dir.Y, 0) * tp.dist
		local from = root.Position
		local hit = workspace:Raycast(from, offset, self.rayParams)
		if hit then
			local d = (hit.Position - from).Magnitude - 2.5
			offset = offset.Unit * math.max(0, d)
		end
		root.CFrame = root.CFrame + offset
		root.AssemblyLinearVelocity = Vector3.new(dir.X * 10, dir.Y * 10, 0)
		if dir.X ~= 0 then self:_face(sign(dir.X)) end
	end

	-- jab combos
	if move.combo then
		local pressed = input.attackPressed and self:_dirName(input) == "neutral"
		if pressed then
			a.comboQueued = true
		else
			-- a tilt/special pressed during the jab comes out right after it
			self:_recordPress(input)
		end
		if a.comboQueued and a.t >= move.combo.from then
			self.action = nil
			self:_startAction(move.combo.next, 0)
			return
		end
	else
		self:_recordPress(input)
	end
	-- fast-falling aerials
	if move.air and not self.grounded and input.downPressed and root.AssemblyLinearVelocity.Y < 12 then
		self.fastFalling = true
	end
	a.motionActive = motionX

	if move.endOnLand and self.grounded and a.t >= ((move.landHit and move.landHit.minT) or 0.08) then
		self:_endAction()
		self.landLag = move.landLag or 0.1
		return
	end
	if a.t >= move.dur then
		self:_endAction()
	end
end

-- Dodges ----------------------------------------------------------------------------

function Controller:_startDodge(kind, dir)
	local cfg = kind == "roll" and Config.Roll or kind == "air" and Config.AirDodge or Config.SpotDodge
	self.dodge = { kind = kind, t = 0, dur = cfg.Duration, dir = dir, cfg = cfg }
	if kind == "air" then
		self.airDodgeUsed = true
		self.dodge.vel = (dir and dir.Magnitude > 0.2) and dir.Unit * cfg.Speed or Vector2.zero
	end
	if self.hooks.dodge then self.hooks.dodge(kind) end
end

function Controller:_updateDodge(dt, input)
	local d = self.dodge
	d.t += dt
	if d.kind == "roll" then
		local speed = d.cfg.Distance / (d.cfg.Duration * 0.8)
		if d.t < d.cfg.Duration * 0.8 then
			self:_setVX(d.dir.X * speed)
		else
			self:_drive(0, 200, dt)
		end
		self:_gravity(self.stats.Gravity)
	elseif d.kind == "air" then
		if d.t < d.cfg.BurstTime and d.vel.Magnitude > 0 then
			self.root.AssemblyLinearVelocity = Vector3.new(d.vel.X, d.vel.Y, 0)
			self:_setVX(d.vel.X)
			self:_gravity(0)
		else
			self:_drive(input.x * self.stats.AirSpeed * 0.5, 40, dt)
			self:_gravity(self.stats.Gravity)
		end
	else
		self:_drive(0, 200, dt)
		self:_gravity(self.stats.Gravity)
	end
	if d.t >= d.dur then
		self.dodge = nil
		if d.kind == "air" and not self.grounded then
			self.landLag = 0
		end
	end
end

-- Ledges ------------------------------------------------------------------------------

function Controller:_tryLedge()
	if self.grounded or self.ledgeCooldown > 0 or self.hitstun > 0 then return false end
	if self.action and not self.action.move.helpless and not self.helpless then
		-- let aerials finish, but specials used to recover can snap to the ledge
		if not (self.action.key == "uspecial" or self.action.key == "sspecial") then return false end
	end
	local root = self.root
	if root.AssemblyLinearVelocity.Y > 4 then return false end
	local stage = Config.GetStage()
	local p = root.Position
	local s = self.scale
	for _, side in ipairs({ -1, 1 }) do
		local lx = side < 0 and stage.Left or stage.Right
		local dx = (p.X - lx) * side
		local dy = stage.Top - p.Y
		if dx > -0.8 and dx < 3.8 * s and dy > 0.3 and dy < 6.8 * s then
			self.ledge = { side = side, x = lx, t = 0 }
			self.action = nil
			self.charging = nil
			self.dodge = nil
			self.helpless = false
			self.fastFalling = false
			self.jumpsLeft = self.stats.AirJumps
			self.airDodgeUsed = false
			self.sideSpecialUsed = false
			self:_face(-side)
			root.AssemblyLinearVelocity = Vector3.zero
			if self.hooks.ledge then self.hooks.ledge(true) end
			return true
		end
	end
	return false
end

function Controller:_releaseLedge()
	self.ledge = nil
	self.ledgeCooldown = Config.LedgeRegrabCooldown
	if self.hooks.ledge then self.hooks.ledge(false) end
end

function Controller:_updateLedge(dt, input)
	local L = self.ledge
	local stage = Config.GetStage()
	local root = self.root
	local s = self.scale
	L.t += dt
	local target = Vector3.new(L.x + L.side * 0.9 * s, stage.Top - 2.7 * s, stage.Z)
	local err = target - root.Position
	root.AssemblyLinearVelocity = Vector3.new(err.X * 15, err.Y * 15, 0)
	self.humanoid.WalkSpeed = 0
	self.humanoid:Move(Vector3.zero, false)
	self:_gravity(0)
	if L.t < 0.18 then return end
	local inward = -L.side
	local function climb(attack)
		self:_releaseLedge()
		self.climbing = {
			t = 0,
			from = root.Position,
			to = Vector3.new(L.x + inward * 2.2 * s, stage.Top + 3.2 * s, stage.Z),
			inward = inward,
			attack = attack,
		}
		if self.hooks.fx then self.hooks.fx("climb") end
	end
	if input.jumpPressed then
		self:_releaseLedge()
		local vy = math.sqrt(2 * workspace.Gravity * self.stats.Gravity * self.stats.JumpHeight) * 1.05
		root.AssemblyLinearVelocity = Vector3.new(inward * 10, vy, 0)
		self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		self.jumpHeld = true
		if self.hooks.fx then self.hooks.fx("airjump") end
	elseif input.attackPressed or input.smashPressed then
		climb(true)
	elseif input.upPressed or (input.xPressed ~= 0 and input.xPressed == inward) then
		climb(false)
	elseif input.downPressed or (input.xPressed ~= 0 and input.xPressed == -inward) or L.t > Config.LedgeMaxHang then
		self:_releaseLedge()
		root.AssemblyLinearVelocity = Vector3.new(-inward * 4, -10, 0)
	end
end

-- Pulling up over the ledge: rise above the edge first, then step onto the stage
local CLIMB_TIME = 0.24
function Controller:_updateClimb(dt)
	local c = self.climbing
	c.t += dt
	local a = math.clamp(c.t / CLIMB_TIME, 0, 1)
	local up = math.clamp(a / 0.6, 0, 1)
	local over = math.clamp((a - 0.4) / 0.6, 0, 1)
	local pos = Vector3.new(
		c.from.X + (c.to.X - c.from.X) * (over * over * (3 - 2 * over)),
		c.from.Y + (c.to.Y - c.from.Y) * (1 - (1 - up) * (1 - up)),
		c.to.Z
	)
	self.root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(c.inward, 0, 0))
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.humanoid.WalkSpeed = 0
	self.humanoid:Move(Vector3.zero, false)
	self:_gravity(0)
	if a >= 1 then
		self.climbing = nil
		self.grounded = true
		if c.attack then self:_startAction("ledgeattack", 0) end
	end
end

-- Main step ---------------------------------------------------------------------------

function Controller:Step(dt, input)
	local hum, root = self.humanoid, self.root
	if not root.Parent or not hum.Parent then return end
	dt = math.min(dt, 0.05)
	self.clock += dt
	self.ledgeCooldown -= dt
	self.dropTimer -= dt
	for k, v in pairs(self.cooldowns) do
		self.cooldowns[k] = v - dt
	end

	if root.Anchored then
		-- frozen for the countdown, KO'd, or waiting on the revival platform
		if self.model:GetAttribute("Reviving") and input.anyPressed and self.hooks.leaveRevival then
			self.hooks.leaveRevival()
		end
		return
	end

	local grounded, floorPart = self:_checkGrounded()
	self.grounded = grounded
	if grounded and not self.wasGrounded then
		self:_onLand()
	end
	self.wasGrounded = grounded

	-- hitlag: everyone involved in a hit freezes for a few frames
	if self.hitlag > 0 then
		self.hitlag -= dt
		root.AssemblyLinearVelocity = Vector3.zero
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
		self:_gravity(0)
		if self.hitlag <= 0 then
			if self.pendingLaunch then
				local info = self.pendingLaunch
				self.pendingLaunch = nil
				self:_launch(info, input)
			elseif self.hitlagVel then
				root.AssemblyLinearVelocity = self.hitlagVel
				self.hitlagVel = nil
			end
		end
		self:_planeLock()
		return
	end

	-- crouch whenever we're standing free and holding down
	local free = grounded and not self.action and not self.charging and not self.dodge and not self.ledge and not self.climbing
		and self.hitstun <= 0 and not self.holding and not self.grabbedBy and self.landLag <= 0 and not input.shieldHeld
	self:_setCrouch(free and input.down and math.abs(input.x) < 0.3)

	-- grabs
	if self.grabbedBy then
		self:_updateGrabbed(dt, input)
		self:_planeLock()
		return
	end
	if self.holding then
		self:_updateHold(dt, input)
		self:_planeLock()
		return
	end

	-- knockback flight
	if self.hitstun > 0 then
		self.hitstun -= dt
		local decay = Config.LaunchDecay * (grounded and 4 or 1) * dt
		self.launchVX = approach(self.launchVX, 0, decay)
		self:_setVX(self.launchVX)
		local v = root.AssemblyLinearVelocity
		if v.Y < -self.stats.FallSpeed * 1.4 then
			self:_setVY(-self.stats.FallSpeed * 1.4)
		end
		self:_gravity(self.stats.Gravity * Config.TumbleGravity)
		if self.hitstun <= 0 then
			self.tumble = false
			if not grounded then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end
		self:_updatePlatforms()
		self:_planeLock()
		return
	end

	-- shield pushback from the server
	if self.pushVX then
		self:_setVX(self.pushVX)
		self.pushVX = nil
	end

	if self.climbing then
		self:_updateClimb(dt)
		self:_recordPress(input)
		return
	end
	if self.ledge then
		self:_updateLedge(dt, input)
		self:_planeLock()
		return
	end
	if not grounded and self:_tryLedge() then
		self:_planeLock()
		return
	end

	if self.dodge then
		self:_updateDodge(dt, input)
		self:_updatePlatforms()
		self:_planeLock()
		return
	end

	if self.landLag > 0 then
		self.landLag -= dt
		self:_drive(0, 160, dt)
		self:_gravity(self.stats.Gravity)
		self:_updatePlatforms()
		self:_planeLock()
		self:_recordPress(input)
		return
	end

	if self.action then
		local a = self.action
		self:_updateAction(dt, input)
		-- moves that drive vertical motion (slams, dashes) skip the fall-speed cap
		if self.action == a and not a.motionActive and not (a.move.gravity and a.t <= a.move.gravity.t1) then
			self:_clampFall(input)
		end
		self:_updatePlatforms()
		self:_planeLock()
		return
	end

	-- charging a smash / chargeable special
	if self.charging then
		local c = self.charging
		local move = self.moves[c.key]
		c.t += dt
		local held = (c.button == "smash" and input.smashHeld) or (c.button == "special" and input.specialHeld)
		if grounded then
			self:_drive(0, 160, dt)
		else
			self:_drive(input.x * self.stats.AirSpeed * 0.6, 50, dt)
		end
		self:_gravity(self.stats.Gravity)
		if not held or c.t >= move.charge.max then
			self.charging = nil
			self:_startAction(c.key, math.clamp(c.t / move.charge.max, 0, 1))
		end
		self:_updatePlatforms()
		self:_planeLock()
		return
	end

	-- shield (ground) and its options
	if input.shieldHeld and grounded and not self.helpless then
		if not self.shielding then
			self.shielding = true
			if self.hooks.shield then self.hooks.shield(true) end
		end
		self:_drive(0, 200, dt)
		self:_gravity(self.stats.Gravity)
		if input.attackPressed or input.grabPressed then
			-- shield + attack = grab, like Smash
			self.shielding = false
			if self.hooks.shield then self.hooks.shield(false) end
			self:_startAction("grab", 0)
		elseif input.jumpPressed then
			self.shielding = false
			if self.hooks.shield then self.hooks.shield(false) end
			self:_groundJump()
		elseif input.downPressed then
			self.shielding = false
			if self.hooks.shield then self.hooks.shield(false) end
			self:_startDodge("spot")
		elseif input.xPressed ~= 0 then
			self.shielding = false
			if self.hooks.shield then self.hooks.shield(false) end
			self:_startDodge("roll", Vector2.new(input.xPressed, 0))
		end
		self:_planeLock()
		return
	elseif self.shielding then
		self.shielding = false
		if self.hooks.shield then self.hooks.shield(false) end
	end

	-- air dodge
	if input.shieldPressed and not grounded and not self.airDodgeUsed and not self.helpless then
		self:_startDodge("air", self:_inputDir(input, Vector2.zero))
		self:_planeLock()
		return
	end

	-- attacks & specials
	local pressed = self:_consumePress(input)
	if pressed and self:_tryPress(pressed, input) then
		self:_planeLock()
		return
	end
	if input.tauntPressed and grounded then
		self:_startAction("taunt", 0)
		return
	end

	-- jumping
	if input.jumpPressed then
		if grounded then
			self:_groundJump()
		elseif self.jumpsLeft > 0 and not self.helpless then
			self.jumpsLeft -= 1
			local vy = math.sqrt(2 * workspace.Gravity * self.stats.Gravity * self.stats.JumpHeight) * 0.95
			root.AssemblyLinearVelocity = Vector3.new(input.x * self.stats.AirSpeed, vy, 0)
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
			self.jumpHeld = true
			self.fastFalling = false
			if self.hooks.fx then self.hooks.fx("airjump") end
		end
	end
	-- short hop: letting go of jump early cuts the rise
	if self.jumpHeld and not input.jumpHeld then
		self.jumpHeld = false
		local v = root.AssemblyLinearVelocity
		if v.Y > 22 then
			self:_setVY(22)
		end
	end

	-- running / drifting
	if grounded then
		if math.abs(input.x) > 0.15 then
			self:_face(sign(input.x))
		end
		self:_drive(input.x * self.stats.RunSpeed, 260, dt)
		-- drop through soft platforms
		if input.downPressed and floorPart and floorPart.Parent and floorPart.Parent.Name == "Platforms" then
			self.dropTimer = 0.28
			self:_setVY(-12)
		end
	else
		local accel = math.abs(input.x) > 0.1 and 90 or 25
		self:_drive(input.x * self.stats.AirSpeed, accel, dt)
		if input.downPressed and root.AssemblyLinearVelocity.Y < 12 then
			self.fastFalling = true
		end
	end
	self:_gravity(self.stats.Gravity)
	self:_clampFall(input)
	self:_updatePlatforms()
	self:_planeLock()
end

function Controller:_groundJump()
	local hum = self.humanoid
	hum.JumpHeight = self.stats.JumpHeight * self.stats.Gravity
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	local vy = math.sqrt(2 * workspace.Gravity * self.stats.Gravity * self.stats.JumpHeight)
	self:_setVY(vy)
	self.grounded = false
	self.wasGrounded = false
	self.jumpHeld = true
	self.fastFalling = false
end

function Controller:_clampFall(input)
	local root = self.root
	local v = root.AssemblyLinearVelocity
	if self.fastFalling and not self.grounded then
		if v.Y < 10 then
			self:_setVY(-self.stats.FastFall)
		end
	elseif v.Y < -self.stats.FallSpeed then
		self:_setVY(-self.stats.FallSpeed)
	end
end

function Controller:_onLand()
	self.jumpsLeft = self.stats.AirJumps
	self.airDodgeUsed = false
	self.sideSpecialUsed = false
	self.helpless = false
	self.fastFalling = false
	local a = self.action
	if a and a.move.air then
		self.action = nil
		self.landLag = a.move.landLag or 0.08
	end
	if self.dodge and self.dodge.kind == "air" then
		self.dodge = nil
		self.landLag = 0.1
	end
	if self.hooks.landed then self.hooks.landed() end
end

-- Snapshot used by the animator and the CPU brain
function Controller:GetState()
	return {
		grounded = self.grounded,
		action = self.action and self.action.key,
		actionT = self.action and self.action.t,
		charging = self.charging and self.charging.key,
		ledge = self.ledge ~= nil,
		hitstun = self.hitstun > 0,
		hitlag = self.hitlag > 0,
		tumble = self.tumble,
		shielding = self.shielding,
		dodge = self.dodge and self.dodge.kind,
		dodgeT = self.dodge and self.dodge.t,
		helpless = self.helpless,
		facing = self.facing,
		holding = self.holding ~= nil,
		grabbed = self.grabbedBy ~= nil,
		crouching = self.crouching == true,
		landLag = self.landLag > 0,
	}
end

function Controller:Destroy()
	for _, name in ipairs({ "SmashFacing", "SmashPlaneLock", "SmashGravity" }) do
		local c = self.root and self.root:FindFirstChild(name)
		if c then c:Destroy() end
	end
	-- give soft platforms back their normal collision on this machine
	if self.opts.platformMode ~= "group" then
		for _, plat in ipairs(Config.GetStage().Platforms) do
			plat.CanCollide = true
		end
	end
end

return Controller
