-- CPU fighters: server-simulated rigs driven by the same Controller players use, plus an AI brain.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Controller = require(Smash.Controller)

local Combat = require(script.Parent.Combat)
local Looks = require(script.Parent.Looks)

local Bots = {}
Bots.Active = {} -- fighter -> bot record
Bots.MaxGroups = 4

local usedGroups = {}

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 end
	return 0
end

-- Default R15 animations (Roblox-owned, usable in any experience)
local ANIMS = {
	idle = "rbxassetid://507766666",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}

-- AI -----------------------------------------------------------------------------------

local Brain = {}
Brain.__index = Brain

local LEVELS = {
	[0] = { reaction = 0.5, aggression = 0, defense = 0, recovery = 0.9, smash = 0 },
	[1] = { reaction = 0.42, aggression = 0.35, defense = 0.1, recovery = 0.6, smash = 0.15 },
	[2] = { reaction = 0.26, aggression = 0.6, defense = 0.3, recovery = 0.85, smash = 0.3 },
	[3] = { reaction = 0.14, aggression = 0.85, defense = 0.5, recovery = 1, smash = 0.45 },
}

function Brain.new(fighter, controller, level)
	local self = setmetatable({}, Brain)
	self.f = fighter
	self.c = controller
	self.level = level
	self.p = LEVELS[level] or LEVELS[2]
	self.think = 0
	self.moveX = 0
	self.hold = {}
	return self
end

local function nearestOpponent(f)
	local best, bestD
	for _, o in pairs(Combat.Fighters) do
		if o ~= f and Combat.InPlay(o) and not o.reviving and o.root and not o.root.Anchored then
			local d = (o.root.Position - f.root.Position).Magnitude
			if not bestD or d < bestD then
				best, bestD = o, d
			end
		end
	end
	return best
end

function Brain:Think(dt)
	local input = Controller.BlankInput()
	local f, c = self.f, self.c
	for k, t in pairs(self.hold) do
		self.hold[k] = t - dt
		if self.hold[k] <= 0 then
			self.hold[k] = nil
		else
			input[k] = true
		end
	end
	input.x = self.moveX

	if not Combat.InPlay(f) then return input end
	if f.root.Anchored then
		if f.reviving and math.random() < dt * 1.5 then
			input.anyPressed = true
		end
		return input
	end

	local root = f.root
	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	local stage = Config.GetStage()
	local center = stage.CenterX

	-- hitstun: hold toward the stage (DI) every frame
	if c.hitstun > 0 or c.hitlag > 0 then
		input.x = sign(center - pos.X)
		input.up = true
		return input
	end

	self.think -= dt
	local offstage = pos.X < stage.Left - 0.5 or pos.X > stage.Right + 0.5 or pos.Y < stage.Top - 1.5
	-- recovery needs quick reactions regardless of level
	if offstage and not c.ledge then
		local towardStage = sign(center - pos.X)
		local under = pos.X > stage.Left - 1 and pos.X < stage.Right + 1 and pos.Y < stage.Top - 1
		if under then
			towardStage = pos.X < center and -1 or 1 -- get out from under the stage first
		end
		self.moveX = towardStage
		input.x = towardStage
		if self.think <= 0 then
			self.think = 0.12
			local below = stage.Top - pos.Y
			if c.jumpsLeft > 0 and vel.Y < 4 and below > -4 then
				input.jumpPressed = true
				self.hold.jumpHeld = 0.3
			elseif not c.helpless and c.jumpsLeft == 0 and vel.Y < 2 and below > 1 and math.random() < self.p.recovery then
				input.specialPressed = true
				input.up = true
			elseif not c.helpless and not c.sideSpecialUsed and math.abs(pos.X - center) - (stage.Right - center) > 14 and below < 5 and math.random() < self.p.recovery * 0.5 then
				input.specialPressed = true
				input.x = sign(center - pos.X)
			end
		end
		return input
	end

	if c.ledge then
		if self.think <= 0 then
			self.think = 0.3 + math.random() * 0.4
			local r = math.random()
			if r < 0.55 then input.upPressed = true
			elseif r < 0.8 then input.jumpPressed = true
			else input.attackPressed = true end
		end
		return input
	end

	if self.think > 0 then return input end
	self.think = self.p.reaction * (0.7 + math.random() * 0.6)

	local target = nearestOpponent(f)
	if self.level == 0 or not target then
		-- training dummy: wander back to the middle and stand there
		local off = pos.X - (center + 8)
		self.moveX = math.abs(off) > 3 and -sign(off) * 0.6 or 0
		input.x = self.moveX
		return input
	end

	local tp = target.root.Position
	local dx, dy = tp.X - pos.X, tp.Y - pos.Y
	local adx = math.abs(dx)
	local toward = sign(dx)

	-- defense
	if target.action and adx < 8 and math.abs(dy) < 6 and math.random() < self.p.defense then
		if c.grounded then
			local r = math.random()
			if r < 0.55 then
				self.hold.shieldHeld = 0.25 + math.random() * 0.25
				input.shieldHeld = true
			elseif r < 0.8 then
				input.jumpPressed = true
				self.hold.jumpHeld = 0.2
			else
				input.shieldHeld = true
				input.xPressed = -toward
				input.x = -toward
			end
		elseif not c.airDodgeUsed then
			input.shieldPressed = true
		end
		self.moveX = 0
		return input
	end

	local reachX = 4.2 * f.scale + 1.2
	local inRange = adx < reachX and math.abs(dy) < 3.8 * f.scale
	if inRange and math.random() < self.p.aggression then
		self.moveX = 0
		input.x = 0
		if c.grounded then
			if c.facing ~= toward then
				input.x = toward -- turn around first, attack on the next think
				self.think = 0.05
				return input
			end
			local r = math.random()
			if target.percent > 85 and r < self.p.smash then
				input.smashPressed = true
				input.x = toward
				self.hold.smashHeld = 0.1 + math.random() * 0.45
			elseif dy > 2.5 then
				input.up = true
				input.attackPressed = true
			elseif r < 0.35 then
				input.attackPressed = true
			elseif r < 0.6 then
				input.x = toward
				input.attackPressed = true
			elseif r < 0.75 then
				input.down = true
				input.attackPressed = true
			elseif r < 0.88 then
				input.x = toward
				input.specialPressed = true
			else
				input.jumpPressed = true
				self.hold.jumpHeld = 0.12
			end
		else
			if dy < -1.5 then
				input.down = true
			elseif dy > 2 then
				input.up = true
			else
				input.x = toward
			end
			input.attackPressed = true
		end
		return input
	end

	-- zoning with projectiles at mid range
	if adx > 12 and adx < 38 and math.abs(dy) < 5 and c.grounded and math.random() < 0.18 * self.p.aggression then
		if c.facing ~= toward then
			input.x = toward
		else
			input.specialPressed = true
		end
		self.moveX = 0
		return input
	end

	-- approach
	self.moveX = adx > 2.5 and toward or 0
	if c.grounded then
		local nextX = pos.X + self.moveX * 4
		local targetOff = tp.X < stage.Left or tp.X > stage.Right
		if not targetOff and (nextX < stage.Left + 1.5 or nextX > stage.Right - 1.5) then
			self.moveX = 0
		end
		if dy > 5 and math.random() < 0.6 then
			input.jumpPressed = true
			self.hold.jumpHeld = 0.35
		end
	else
		if dy > 3 and c.jumpsLeft > 0 and vel.Y < 0 and math.random() < 0.4 then
			input.jumpPressed = true
			self.hold.jumpHeld = 0.3
		elseif dy < -6 and math.random() < 0.3 then
			input.downPressed = true
		end
	end
	input.x = self.moveX
	return input
end

-- Spawning ---------------------------------------------------------------------------------

local function claimGroup()
	for i = 1, Bots.MaxGroups do
		if not usedGroups[i] then
			usedGroups[i] = true
			return i
		end
	end
	return nil
end

function Bots.Spawn(def, opts)
	local groupIndex = claimGroup()
	if not groupIndex then
		warn("[Smash] too many CPU fighters")
		return nil
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		usedGroups[groupIndex] = nil
		warn("[Smash] could not create CPU rig:", model)
		return nil
	end
	model.Name = opts.name
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("LocalScript") or d:IsA("Script")) then d:Destroy() end
	end
	local root = model:WaitForChild("HumanoidRootPart")
	root.Anchored = true
	model:PivotTo(CFrame.lookAt(opts.pos, opts.pos + Vector3.new(opts.facing or -1, 0, 0)))
	model.Parent = workspace
	Looks.Apply(model, def)

	local group = "SmashBot" .. groupIndex
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = group end
	end

	local fighter = Combat.Register(model, def, {
		isBot = true, name = opts.name, slot = opts.slot, inMatch = opts.inMatch, stocks = opts.stocks,
	})
	local controller
	controller = Controller.new(model, def, {
		platformMode = "group",
		group = group,
		hooks = {
			startMove = function(key, charge, facing)
				return Combat.StartMove(fighter, key, charge, facing)
			end,
			shield = function(on) Combat.SetShield(fighter, on) end,
			dodge = function(kind) Combat.Dodge(fighter, kind) end,
			ledge = function(on) Combat.Ledge(fighter, on) end,
			leaveRevival = function() Combat.EndRevival(fighter) end,
			charge = function(key) Combat.Broadcast("Charge", { id = fighter.id, key = key }) end,
			fx = function(kind) Combat.Broadcast("Fx", { id = fighter.id, kind = kind }) end,
		},
	})
	fighter.controller = controller

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local tracks = {}
	for name, id in pairs(ANIMS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local okLoad, track = pcall(function() return animator:LoadAnimation(anim) end)
		if okLoad and track then
			track.Looped = name ~= "jump"
			tracks[name] = track
		end
	end

	local record = {
		fighter = fighter,
		controller = controller,
		brain = Brain.new(fighter, controller, opts.level or 2),
		tracks = tracks,
		current = nil,
		group = groupIndex,
	}
	Bots.Active[fighter] = record
	if not opts.frozen then
		root.Anchored = false
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	return fighter
end

function Bots.Remove(fighter)
	local rec = Bots.Active[fighter]
	if not rec then return end
	Bots.Active[fighter] = nil
	usedGroups[rec.group] = nil
	Combat.Unregister(fighter)
	if fighter.model then fighter.model:Destroy() end
end

function Bots.RemoveAll()
	for f in pairs(Bots.Active) do
		Bots.Remove(f)
	end
end

local function updateAnim(rec)
	local c = rec.controller
	local root = rec.fighter.root
	local v = root.AssemblyLinearVelocity
	local want
	if c.grounded then
		want = math.abs(v.X) > 2 and "run" or "idle"
	else
		want = v.Y > 0 and "jump" or "fall"
	end
	if want ~= rec.current then
		if rec.current and rec.tracks[rec.current] then rec.tracks[rec.current]:Stop(0.15) end
		if rec.tracks[want] then rec.tracks[want]:Play(0.15) end
		rec.current = want
	end
	if want == "run" and rec.tracks.run then
		rec.tracks.run:AdjustSpeed(math.clamp(math.abs(v.X) / 18, 0.6, 2.2))
	end
end

function Bots.Start()
	-- groups: one per CPU so each can pass through soft platforms independently
	local stage = Config.GetStage()
	for i = 1, Bots.MaxGroups do
		local g = "SmashBot" .. i
		pcall(function() PhysicsService:RegisterCollisionGroup(g) end)
	end
	for i = 1, Bots.MaxGroups do
		local g = "SmashBot" .. i
		pcall(function() PhysicsService:CollisionGroupSetCollidable(g, "SmashFighters", false) end)
		for j = 1, Bots.MaxGroups do
			pcall(function() PhysicsService:CollisionGroupSetCollidable(g, "SmashBot" .. j, false) end)
		end
	end

	RunService.Stepped:Connect(function(_, dt)
		for f, rec in pairs(Bots.Active) do
			if f.model.Parent and f.root.Parent then
				local input = rec.brain:Think(dt)
				local okStep, err = pcall(rec.controller.Step, rec.controller, dt, input)
				if not okStep then warn("[Smash] CPU step error:", err) end
				updateAnim(rec)
			end
		end
	end)
end

return Bots
