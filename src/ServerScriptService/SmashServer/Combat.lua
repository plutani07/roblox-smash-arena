--[[
	Server-authoritative combat: fighter registry, move timelines, hitboxes vs hurtboxes,
	damage percent, Smash-style knockback, shields/parries/counters/armor, projectiles and KOs.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Moves = require(Smash.Moves)

local Combat = {}
Combat.Fighters = {}      -- id -> fighter
Combat.ByModel = {}       -- model -> fighter
Combat.Projectiles = {}
Combat.Event = nil        -- RemoteEvent, set by the main script
Combat.OnKO = nil         -- callback(fighter)

local nextId = 0
local nextProjectile = 0

local function now()
	return os.clock()
end

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 end
	return 0
end

function Combat.Broadcast(kind, data)
	if Combat.Event then
		Combat.Event:FireAllClients(kind, data)
	end
end

-- Registry -----------------------------------------------------------------------

function Combat.Register(model, def, opts)
	nextId += 1
	local f = {
		id = nextId,
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		root = model:FindFirstChild("HumanoidRootPart"),
		def = def,
		moves = Moves.Get(def.Key),
		scale = def.Scale or 1,
		player = opts.player,
		isBot = opts.isBot or false,
		controller = opts.controller,
		name = opts.name or model.Name,
		slot = opts.slot or 1,
		inMatch = opts.inMatch or false,
		stocks = opts.stocks or 0,
		percent = 0,
		shieldHP = Config.ShieldMax,
		shielding = false,
		shieldStart = 0,
		action = nil,
		hitstunUntil = 0,
		intangibleUntil = 0,
		invincibleUntil = 0,
		koed = false,
		eliminated = false,
		reviving = false,
		cooldowns = {},
		lastAttr = {},
		koCount = 0,
		falls = 0,
	}
	Combat.Fighters[f.id] = f
	Combat.ByModel[model] = f
	model:SetAttribute("FighterId", f.id)
	model:SetAttribute("FighterKey", def.Key)
	model:SetAttribute("DisplayName", f.name)
	model:SetAttribute("Slot", f.slot)
	model:SetAttribute("IsCPU", f.isBot)
	model:SetAttribute("InMatch", f.inMatch)
	model:SetAttribute("Stocks", f.stocks)
	model:SetAttribute("Percent", 0)
	model:SetAttribute("ShieldHP", Config.ShieldMax)
	model:SetAttribute("Shielding", false)
	model:SetAttribute("Reviving", false)
	model:SetAttribute("Eliminated", false)
	CollectionService:AddTag(model, "SmashFighter")
	return f
end

function Combat.Unregister(f)
	if not f then return end
	if f.holding then Combat.ReleaseGrab(f, "ko") end
	if f.grabbedBy then Combat.ReleaseGrab(f.grabbedBy, "ko") end
	Combat.Fighters[f.id] = nil
	Combat.ByModel[f.model] = nil
	if f.model and f.model.Parent then
		CollectionService:RemoveTag(f.model, "SmashFighter")
	end
end

function Combat.ForPlayer(player)
	for _, f in pairs(Combat.Fighters) do
		if f.player == player then return f end
	end
	return nil
end

function Combat.InPlay(f)
	return f and not f.koed and not f.eliminated and f.root and f.root.Parent ~= nil
end

-- Geometry -------------------------------------------------------------------------

local function hurtbox(f)
	local s = f.scale
	if f.model:GetAttribute("Crouching") then
		-- crouching makes you shorter, so some high attacks whiff
		return f.root.Position + Vector3.new(0, -1.05 * s, 0), Vector2.new(3.4 * s, 4.0 * s)
	end
	local c = f.root.Position + Vector3.new(0, -0.35 * s, 0)
	return c, Vector2.new(3.2 * s, 5.4 * s)
end

local function overlaps(c1, s1, c2, s2)
	return math.abs(c1.X - c2.X) * 2 < (s1.X + s2.X) and math.abs(c1.Y - c2.Y) * 2 < (s1.Y + s2.Y)
end

local function hitboxWorld(f, a, hit)
	local base = hit.fromStart and a.startPos or f.root.Position
	local s = f.scale
	local center = base + Vector3.new(hit.off.X * a.facing * s, hit.off.Y * s, 0)
	return center, hit.size * s
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

function Combat.IsGrounded(f)
	local stage = Config.GetStage()
	rayParams.FilterDescendantsInstances = { stage.Model }
	local reach = f.humanoid.HipHeight + f.root.Size.Y / 2 + 0.6
	return workspace:Raycast(f.root.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function debugBox(center, size, color)
	if not Config.ShowHitboxes then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.ForceField
	p.Color = color or Color3.new(1, 0, 0)
	p.Transparency = 0.3
	p.Size = Vector3.new(size.X, size.Y, 2)
	p.CFrame = CFrame.new(center)
	p.Parent = workspace
	game:GetService("Debris"):AddItem(p, 0.06)
end

-- Rules -------------------------------------------------------------------------------

function Combat.Knockback(p, d, w, bkb, kbg)
	return ((((p / 10) + (p * d / 20)) * (200 / (w + 100)) * 1.4) + 18) * kbg + bkb
end

local function hitlagFor(dmg, mult)
	return math.clamp((dmg * Config.HitlagA + Config.HitlagB) / 60, 0.04, Config.HitlagMax) * (mult or 1)
end

function Combat.CanBeHit(v)
	if not Combat.InPlay(v) or v.reviving then return false end
	local t = now()
	if t < v.intangibleUntil or t < v.invincibleUntil then return false end
	local a = v.action
	if a and a.move.intangible then
		local at = t - a.start - a.paused
		if at >= a.move.intangible.t0 and at <= a.move.intangible.t1 then return false end
	end
	return true
end

local function actionTime(a)
	return now() - a.start - a.paused
end

function Combat.Hitlag(f, sec)
	local t = now()
	local a = f.action
	if a then
		local newUntil = t + sec
		if newUntil > a.pauseUntil then
			local extra = newUntil - math.max(a.pauseUntil, t)
			a.paused += extra
			a.pauseUntil = newUntil
		end
	end
	if f.controller then
		f.controller:ApplyAttackerHitlag(sec)
	end
end

-- Applies a launch to whoever simulates this fighter. Player clients get it from the broadcast.
local function applyToOwner(f, info)
	if f.controller then
		f.controller:ApplyHit(info)
	end
end

function Combat.SetShield(f, on)
	if on then
		if not Combat.InPlay(f) or now() < f.hitstunUntil - 0.05 or f.shieldHP <= 0 then return end
		if f.shielding then return end
		local a = f.action
		if a then
			-- the owner may have finished (or landed out of) the move a moment before we did
			if not a.move.air and now() - a.start - a.paused < a.move.dur - 0.2 then return end
			f.action = nil
		end
		f.shielding = true
		f.shieldStart = now()
	else
		f.shielding = false
	end
	f.model:SetAttribute("Shielding", f.shielding)
end

function Combat.ShieldBreak(f)
	f.shielding = false
	f.shieldHP = 0
	f.model:SetAttribute("Shielding", false)
	f.model:SetAttribute("ShieldHP", 0)
	f.hitstunUntil = now() + Config.ShieldBreakStun
	local info = { vel = Vector2.new(0, 58), hitstun = Config.ShieldBreakStun, hitlag = 0.12, tumble = false }
	applyToOwner(f, info)
	Combat.Broadcast("ShieldBreak", { id = f.id, vx = 0, vy = 58, hitstun = Config.ShieldBreakStun, hitlag = 0.12 })
	task.delay(Config.ShieldBreakStun + 0.5, function()
		if f.shieldHP <= 0 then f.shieldHP = Config.ShieldMax * 0.4 end
	end)
end

-- The heart of it: one hitbox connecting with one fighter.
-- opts: charge, move, facing (forced direction), projectile (bool), throw (bool)
function Combat.ApplyHit(attacker, victim, hit, center, opts)
	opts = opts or {}
	local t = now()

	-- getting hit breaks grabs (yours, or the one you're stuck in)
	if not opts.throw then
		if victim.holding then Combat.ReleaseGrab(victim, "hit") end
		if victim.grabbedBy and victim.grabbedBy ~= attacker then Combat.ReleaseGrab(victim.grabbedBy, "hit") end
	end

	-- counters (throws can't be countered)
	local va = victim.action
	if va and va.move.counter and not opts.isCounter and not opts.throw then
		local c = va.move.counter
		local vt = actionTime(va)
		if vt >= c.t0 and vt <= c.t1 and not va.countered then
			va.countered = true
			local chit = table.clone(c.hit)
			chit.dmg = math.max(c.hit.dmg, hit.dmg * c.mult)
			local dir = sign(attacker.root.Position.X - victim.root.Position.X)
			if dir == 0 then dir = va.facing end
			va.facing = dir
			local cc = victim.root.Position + Vector3.new(c.hit.off.X * dir * victim.scale, c.hit.off.Y * victim.scale, 0)
			Combat.Broadcast("Counter", { id = victim.id, a = attacker.id, facing = dir })
			if not opts.projectile then
				Combat.ApplyHit(victim, attacker, chit, cc, { facing = dir, isCounter = true })
			end
			return
		end
	end

	local charge = opts.charge or 0
	local move = opts.move
	local dmgMult = 1 + charge * ((move and move.charge and move.charge.dmgMult) or 0)
	local dmg = hit.dmg * dmgMult
	local facingDir = opts.facing or (attacker.action and attacker.action.facing) or 1

	-- shields & parries
	if victim.shielding and not opts.throw then
		if t - victim.shieldStart <= Config.ParryWindow then
			local stun = 0.45
			if not opts.projectile then
				attacker.action = nil
				attacker.hitstunUntil = t + stun
				applyToOwner(attacker, { vel = Vector2.zero, hitstun = stun, hitlag = 0.15 })
			end
			Combat.Broadcast("Parry", { id = victim.id, a = attacker.id, stun = opts.projectile and 0 or stun, pos = center })
			return
		end
		victim.shieldHP -= dmg * Config.ShieldDamageMult + 1
		local lag = hitlagFor(dmg, 0.6)
		local push = sign(victim.root.Position.X - center.X)
		if push == 0 then push = facingDir end
		local pushVX = push * (5 + dmg * 0.7)
		if victim.controller then victim.controller:ApplyPush(pushVX) end
		if not opts.projectile then Combat.Hitlag(attacker, lag) end
		Combat.Broadcast("ShieldHit", { v = victim.id, a = attacker.id, pos = center, dmg = dmg, push = pushVX, hitlag = opts.projectile and 0 or lag })
		victim.model:SetAttribute("ShieldHP", math.max(0, victim.shieldHP))
		if victim.shieldHP <= 0 then
			Combat.ShieldBreak(victim)
		end
		return
	end

	victim.percent = math.min(999, victim.percent + dmg)
	local kb = Combat.Knockback(victim.percent, dmg, victim.def.Stats.Weight, hit.bkb, hit.kbg)

	-- super armor: take the damage, ignore the launch
	if va and va.move.armor and not opts.throw then
		local ar = va.move.armor
		local vt = actionTime(va)
		if vt >= ar.t0 and vt <= ar.t1 and kb < ar.kb then
			local lag = hitlagFor(dmg, 0.8)
			if not opts.projectile then Combat.Hitlag(attacker, lag) end
			Combat.Hitlag(victim, lag)
			victim.model:SetAttribute("Percent", victim.percent)
			Combat.Broadcast("Hit", {
				a = attacker.id, v = victim.id, pos = center, dmg = dmg, kb = 0, fx = hit.fx, hitlag = lag,
				percent = victim.percent, vx = 0, vy = 0, hitstun = 0, armored = true,
				attackerLag = opts.projectile and 0 or lag,
			})
			return
		end
	end

	local vpos = victim.root.Position
	local dir
	if hit.toward then
		local d = Vector2.new(center.X - vpos.X, center.Y - vpos.Y + 0.4)
		dir = d.Magnitude > 0.4 and d.Unit or Vector2.new(0, 1)
	else
		local side = facingDir
		if hit.away then
			side = sign(vpos.X - center.X)
			if side == 0 then side = facingDir end
		end
		local ang = hit.ang or 361
		if ang == 361 then
			ang = (Combat.IsGrounded(victim) and kb < 60) and 0 or 40
		end
		local r = math.rad(ang)
		dir = Vector2.new(math.cos(r) * side, math.sin(r))
	end
	local speed = kb * Config.KnockbackToSpeed
	if hit.toward then speed = math.min(speed, 22) end
	local vel = dir * speed
	local hitstun = math.max(Config.MinHitstun, kb * Config.HitstunPerKnockback) * (hit.hitstunMult or 1)
	local lag = hitlagFor(dmg, hit.hitlagMult)
	local freeze = hit.freeze or 0
	local tumble = kb >= Config.TumbleThreshold and not hit.toward

	victim.hitstunUntil = t + lag + freeze + hitstun
	victim.action = nil
	if victim.shielding then Combat.SetShield(victim, false) end
	victim.lastHitBy = attacker
	victim.lastHitTime = t
	if not opts.projectile then
		Combat.Hitlag(attacker, lag)
	end
	applyToOwner(victim, { vel = vel, hitstun = hitstun, hitlag = lag, freeze = freeze, tumble = tumble })
	victim.model:SetAttribute("Percent", victim.percent)
	Combat.Broadcast("Hit", {
		a = attacker.id, v = victim.id, pos = (center + vpos) / 2, dmg = dmg, kb = kb, fx = hit.fx or "light",
		hitlag = lag, freeze = freeze, percent = victim.percent, vx = vel.X, vy = vel.Y, hitstun = hitstun,
		tumble = tumble, attackerLag = opts.projectile and 0 or lag,
	})
end

-- Moves ---------------------------------------------------------------------------------

function Combat.StartMove(f, key, charge, facing)
	local move = f.moves[key]
	if not move or not Combat.InPlay(f) or f.reviving then return false end
	-- throws and pummels only come from Combat.Throw / Combat.Pummel while holding someone
	if move.throw or move.pummel or f.holding or f.grabbedBy then return false end
	local t = now()
	if t < f.hitstunUntil - 0.2 then return false end
	local a = f.action
	if a then
		local elapsed = actionTime(a)
		local allowed = (a.move.combo and a.move.combo.next == key) or elapsed >= a.move.dur - 0.15 or key == "ledgeattack"
			or (a.move.endOnLand and elapsed >= ((a.move.landHit and a.move.landHit.minT) or 0))
			or (a.move.air and not f.moves[key].air)
		if not allowed then return false end
	end
	if move.cooldown and (f.cooldowns[key] or 0) > t + 0.15 then return false end
	f.cooldowns[key] = t + (move.cooldown or 0) - 0.05
	if f.shielding then Combat.SetShield(f, false) end
	f.action = {
		key = key,
		move = move,
		start = t,
		paused = 0,
		pauseUntil = 0,
		charge = math.clamp(tonumber(charge) or 0, 0, 1),
		facing = (facing == -1) and -1 or 1,
		hitVictims = {},
		projectileFired = false,
		landFired = false,
		startPos = f.root.Position,
	}
	Combat.Broadcast("Move", { id = f.id, key = key, charge = f.action.charge, facing = f.action.facing })
	return true
end

-- Grabs -----------------------------------------------------------------------------------------

local THROWS = { f = "fthrow", b = "bthrow", u = "uthrow", d = "dthrow" }

function Combat.StartGrab(a, v, facing)
	local t = now()
	a.action = nil
	v.action = nil
	if v.shielding then Combat.SetShield(v, false) end
	if v.holding then Combat.ReleaseGrab(v, "hit") end
	-- the more damage you have, the longer you're stuck
	local hold = math.clamp(1.1 + v.percent / 110, 1.1, 3.2)
	a.holding = v
	a.grabFacing = facing or 1
	a.grabUntil = t + hold
	a.throwing = nil
	v.grabbedBy = a
	v.hitstunUntil = math.max(v.hitstunUntil, t + hold + 0.3)
	a.model:SetAttribute("Holding", true)
	v.model:SetAttribute("Grabbed", true)
	Combat.Broadcast("Grab", { a = a.id, v = v.id, hold = hold, scale = a.scale, facing = a.grabFacing, pos = v.root.Position })
	if a.controller then a.controller:EnterHold(v.model) end
	if v.controller then v.controller:EnterGrabbed(a.model, a.scale) end
end

-- reason: "throw" (the throw's hit takes over), "timeout", "mash", "hit", "ko"
function Combat.ReleaseGrab(a, reason)
	local v = a.holding
	if not v then return end
	a.holding = nil
	a.throwing = nil
	if a.model then a.model:SetAttribute("Holding", false) end
	v.grabbedBy = nil
	if v.model then v.model:SetAttribute("Grabbed", false) end
	local facing = a.grabFacing or 1
	local vPush, aPush
	if reason ~= "throw" then
		-- grab release: both fighters get pushed apart
		v.hitstunUntil = now() + 0.22
		vPush = facing * 20
		aPush = -facing * 8
		a.action = nil
	end
	Combat.Broadcast("GrabEnd", { a = a.id, v = v.id, reason = reason, push = vPush, apush = aPush })
	if a.controller then a.controller:ExitHold(aPush) end
	if v.controller then v.controller:ExitGrabbed(vPush) end
end

function Combat.Throw(a, dir)
	local key = THROWS[dir]
	if not key or not a.holding or a.throwing then return end
	local move = a.moves[key]
	if not move then return end
	a.throwing = true
	a.action = {
		key = key, move = move, start = now(), paused = 0, pauseUntil = 0, charge = 0,
		facing = a.grabFacing or 1, hitVictims = {}, startPos = a.root.Position,
	}
	Combat.Broadcast("Move", { id = a.id, key = key, charge = 0, facing = a.action.facing })
end

function Combat.Pummel(a)
	local v = a.holding
	if not v or a.throwing then return end
	local t = now()
	if t - (a.lastPummel or 0) < 0.3 then return end
	a.lastPummel = t
	local p = a.moves.pummel and a.moves.pummel.pummel
	local dmg = p and p.dmg or 1.5
	v.percent = math.min(999, v.percent + dmg)
	v.model:SetAttribute("Percent", v.percent)
	Combat.Broadcast("Pummel", { a = a.id, v = v.id, dmg = dmg, pos = v.root.Position, percent = v.percent })
end

-- Every button the grabbed fighter presses shortens the hold
function Combat.Mash(v)
	local a = v.grabbedBy
	if not a or a.throwing then return end
	local t = now()
	if t - (v.lastMash or 0) < 0.06 then return end
	v.lastMash = t
	a.grabUntil -= 0.07
end

function Combat.SetCrouch(f, on)
	if f.model then f.model:SetAttribute("Crouching", on == true) end
end

function Combat.Dodge(f, kind)
	if not Combat.InPlay(f) then return end
	local cfg = kind == "roll" and Config.Roll or kind == "air" and Config.AirDodge or Config.SpotDodge
	local t = now()
	if t < f.hitstunUntil - 0.1 then return end
	if f.shielding then Combat.SetShield(f, false) end
	f.action = nil
	f.intangibleUntil = math.max(f.intangibleUntil, t + cfg.IntangibleTo)
	Combat.Broadcast("Dodge", { id = f.id, kind = kind })
end

function Combat.Ledge(f, on)
	if not Combat.InPlay(f) then return end
	f.model:SetAttribute("OnLedge", on and true or false)
	if on then
		f.action = nil
		f.intangibleUntil = math.max(f.intangibleUntil, now() + Config.LedgeGrabIntangible)
	end
end

local function fireProjectile(f, a)
	local pr = a.move.projectile
	local charge = a.charge
	local size = pr.size * (1 + charge * (pr.chargeSize or 0)) * f.scale
	local pos = f.root.Position + Vector3.new(pr.off.X * a.facing * f.scale, pr.off.Y * f.scale, 0)
	local hit = table.clone(pr.hit)
	local mult = 1 + charge * ((a.move.charge and a.move.charge.dmgMult) or 0)
	hit.dmg = hit.dmg * mult
	hit.bkb = hit.bkb + charge * 18
	nextProjectile += 1
	local p = {
		id = nextProjectile,
		owner = f,
		pos = pos,
		vel = Vector3.new(pr.speed * a.facing, 0, 0),
		size = size,
		hit = hit,
		life = pr.life,
		t = 0,
		pierce = pr.pierce,
		multi = pr.multi,
		hits = {},
		hitCount = 0,
		style = pr.style,
	}
	Combat.Projectiles[p.id] = p
	Combat.Broadcast("Proj", { op = "spawn", id = p.id, pos = pos, vel = p.vel, size = size, style = pr.style, owner = f.id, life = pr.life })
end

local function destroyProjectile(p, burst)
	Combat.Projectiles[p.id] = nil
	Combat.Broadcast("Proj", { op = "destroy", id = p.id, pos = p.pos, burst = burst })
end

local function updateAction(f, dt)
	local a = f.action
	local t = now()
	if t < a.pauseUntil then return end
	local at = t - a.start - a.paused
	local move = a.move

	-- landing cancels aerials (the owner's controller does the same). Only once we've actually
	-- seen them airborne, since our copy of a player's position lags behind their client.
	if move.air then
		local grounded = Combat.IsGrounded(f)
		if not grounded then
			a.sawAir = true
		elseif a.sawAir then
			f.action = nil
			return
		end
	end

	for i, hit in ipairs(move.hits or {}) do
		if at >= hit.t[1] and at <= hit.t[2] and hit.grab then
			-- grab box: catches the first fighter it touches, straight through shields
			local center, size = hitboxWorld(f, a, hit)
			debugBox(center, size, Color3.fromRGB(160, 80, 255))
			for _, v in pairs(Combat.Fighters) do
				if v ~= f and Combat.CanBeHit(v) and not v.grabbedBy and not v.holding then
					local hc, hs = hurtbox(v)
					if overlaps(center, size, hc, hs) then
						Combat.StartGrab(f, v, a.facing)
						return
					end
				end
			end
		elseif at >= hit.t[1] and at <= hit.t[2] then
			local center, size = hitboxWorld(f, a, hit)
			debugBox(center, size)
			for _, v in pairs(Combat.Fighters) do
				if v ~= f and Combat.CanBeHit(v) then
					local key = v.id .. ":" .. i
					local last = a.hitVictims[key]
					local can = (not last) or (hit.rehit and t - last >= hit.rehit)
					if can then
						local hc, hs = hurtbox(v)
						if overlaps(center, size, hc, hs) then
							a.hitVictims[key] = t
							Combat.ApplyHit(f, v, hit, center, { charge = a.charge, move = move })
							if f.action ~= a then return end
						end
					end
				end
			end
		end
	end

	-- throws let go at their release frame and launch the victim
	if move.throw and not a.thrown and at >= move.throw.t then
		a.thrown = true
		local v = f.holding
		Combat.ReleaseGrab(f, "throw")
		if v and Combat.InPlay(v) then
			Combat.ApplyHit(f, v, move.throw.hit, v.root.Position, { throw = true, facing = a.facing })
		end
	end

	if move.reflect then
		a.reflecting = at >= move.reflect.t0 and at <= move.reflect.t1
	end

	if move.projectile and not a.projectileFired and at >= move.projectile.t then
		a.projectileFired = true
		fireProjectile(f, a)
	end

	if move.landHit and not a.landFired and at >= move.landHit.minT and Combat.IsGrounded(f) then
		a.landFired = true
		local hit = move.landHit.hit
		local center, size = hitboxWorld(f, a, hit)
		debugBox(center, size, Color3.new(1, 0.5, 0))
		Combat.Broadcast("Shockwave", { pos = center, width = size.X, fx = hit.fx, id = f.id })
		for _, v in pairs(Combat.Fighters) do
			if v ~= f and Combat.CanBeHit(v) then
				local hc, hs = hurtbox(v)
				if overlaps(center, size, hc, hs) then
					Combat.ApplyHit(f, v, hit, center, { move = move })
				end
			end
		end
		if f.action == a then f.action = nil end
		return
	end

	if at >= move.dur then
		f.action = nil
	end
end

local projParams = RaycastParams.new()
projParams.FilterType = Enum.RaycastFilterType.Include

local function updateProjectiles(dt)
	local stage = Config.GetStage()
	projParams.FilterDescendantsInstances = { stage.Main }
	local t = now()
	for id, p in pairs(Combat.Projectiles) do
		p.t += dt
		if p.t > p.life or not p.owner then
			destroyProjectile(p, false)
			continue
		end
		local step = p.vel * dt
		local r = workspace:Raycast(p.pos, step, projParams)
		if r then
			p.pos = r.Position
			destroyProjectile(p, true)
			continue
		end
		p.pos += step
		local box = Vector2.new(p.size, p.size)
		-- reflectors
		for _, v in pairs(Combat.Fighters) do
			if v ~= p.owner and v.action and v.action.reflecting then
				local rs = v.action.move.reflect.size * v.scale
				if overlaps(p.pos, box, v.root.Position, rs) then
					p.vel = -p.vel * 1.25
					p.owner = v
					p.hits = {}
					p.t = 0
					Combat.Broadcast("Proj", { op = "reflect", id = p.id, pos = p.pos, vel = p.vel, owner = v.id })
					break
				end
			end
		end
		local destroyed = false
		for _, v in pairs(Combat.Fighters) do
			if v ~= p.owner and Combat.CanBeHit(v) then
				local hc, hs = hurtbox(v)
				if overlaps(p.pos, box, hc, hs) then
					local last = p.hits[v.id]
					local interval = p.multi and p.multi.interval or math.huge
					if not last or t - last >= interval then
						p.hits[v.id] = t
						p.hitCount += 1
						Combat.ApplyHit(p.owner, v, p.hit, p.pos, { projectile = true, facing = sign(p.vel.X) })
						if (not p.pierce and not p.multi) or (p.multi and p.hitCount >= p.multi.max) then
							destroyProjectile(p, true)
							destroyed = true
							break
						end
					end
				end
			end
		end
		if destroyed then continue end
		-- let the clients re-sync slow projectiles every so often
		p.syncT = (p.syncT or 0) + dt
		if p.syncT > 0.5 then
			p.syncT = 0
			Combat.Broadcast("Proj", { op = "sync", id = p.id, pos = p.pos, vel = p.vel })
		end
	end
end

-- KOs and respawns ------------------------------------------------------------------------

function Combat.KO(f)
	if f.koed then return end
	if f.holding then Combat.ReleaseGrab(f, "ko") end
	if f.grabbedBy then Combat.ReleaseGrab(f.grabbedBy, "ko") end
	f.koed = true
	f.action = nil
	f.shielding = false
	f.model:SetAttribute("Shielding", false)
	f.model:SetAttribute("OnLedge", false)
	local stage = Config.GetStage()
	local pos = f.root.Position
	Combat.Broadcast("KO", { id = f.id, pos = pos, center = Vector3.new(stage.CenterX, stage.Top + 10, stage.Z) })
	if f.lastHitBy and f.lastHitBy ~= f and now() - (f.lastHitTime or 0) < 8 then
		f.lastHitBy.koCount += 1
	end
	f.falls += 1
	f.root.Anchored = true
	f.model:PivotTo(CFrame.new(stage.CenterX, stage.Top + 400, stage.Z))
	if Combat.OnKO then
		task.spawn(Combat.OnKO, f)
	end
end

function Combat.Respawn(f, revival)
	local stage = Config.GetStage()
	f.koed = false
	f.percent = 0
	f.shieldHP = Config.ShieldMax
	f.action = nil
	f.hitstunUntil = 0
	f.lastHitBy = nil
	f.model:SetAttribute("Percent", 0)
	f.model:SetAttribute("ShieldHP", Config.ShieldMax)
	local pos = Vector3.new(stage.CenterX, stage.Top + (revival and 24 or 3.5), stage.Z)
	f.root.Anchored = true
	f.model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)))
	f.root.AssemblyLinearVelocity = Vector3.zero
	if f.controller then f.controller:Reset() end
	Combat.Broadcast("Respawn", { id = f.id })
	if revival then
		f.reviving = true
		f.reviveUntil = now() + Config.RevivalMaxTime
		f.model:SetAttribute("Reviving", true)
	else
		Combat.EndRevival(f)
	end
end

function Combat.EndRevival(f)
	if f.koed or f.eliminated then return end
	f.reviving = false
	f.model:SetAttribute("Reviving", false)
	f.root.Anchored = false
	f.invincibleUntil = now() + Config.RespawnInvincible
	f.model:SetAttribute("InvincibleUntil", workspace:GetServerTimeNow() + Config.RespawnInvincible)
	if f.player and f.root:CanSetNetworkOwnership() then
		pcall(function() f.root:SetNetworkOwner(f.player) end)
	elseif f.isBot then
		pcall(function() f.root:SetNetworkOwner(nil) end)
	end
end

function Combat.Freeze(f, frozen)
	if not f.root then return end
	f.root.Anchored = frozen
	if not frozen then
		if f.player then
			pcall(function() f.root:SetNetworkOwner(f.player) end)
		elseif f.isBot then
			pcall(function() f.root:SetNetworkOwner(nil) end)
		end
	end
end

-- Main loop ---------------------------------------------------------------------------

local function step(dt)
	local stage = Config.GetStage()
	local b = stage.Blast
	local t = now()
	for _, f in pairs(Combat.Fighters) do
		if not f.root or not f.root.Parent then continue end
		if f.action then updateAction(f, dt) end

		-- shield decay / regen
		if f.shielding then
			f.shieldHP -= Config.ShieldDecay * dt
			if f.shieldHP <= 0 then
				Combat.ShieldBreak(f)
			end
		elseif f.shieldHP < Config.ShieldMax and f.shieldHP > 0 then
			f.shieldHP = math.min(Config.ShieldMax, f.shieldHP + Config.ShieldRegen * dt)
		end
		if math.abs((f.lastAttr.shield or -1) - f.shieldHP) >= 1 then
			f.lastAttr.shield = f.shieldHP
			f.model:SetAttribute("ShieldHP", math.max(0, f.shieldHP))
		end

		if f.reviving and t >= (f.reviveUntil or 0) then
			Combat.EndRevival(f)
		end

		-- grab holds run out (faster the more the victim mashes)
		if f.holding then
			local v = f.holding
			if not Combat.Fighters[v.id] or not Combat.InPlay(v) then
				Combat.ReleaseGrab(f, "ko")
			elseif f.throwing then
				if not f.action then Combat.ReleaseGrab(f, "timeout") end
			elseif t >= f.grabUntil then
				Combat.ReleaseGrab(f, "timeout")
			end
		end

		-- blast zones
		if Combat.InPlay(f) and not f.reviving and not f.root.Anchored then
			local p = f.root.Position
			local launched = t < f.hitstunUntil
			if p.X < b.Left or p.X > b.Right or p.Y < b.Bottom or (p.Y > b.Top and launched) or p.Y > b.Top + 45 then
				Combat.KO(f)
			end
		end
	end
	updateProjectiles(dt)
end

function Combat.Start()
	RunService.Heartbeat:Connect(step)
end

return Combat
