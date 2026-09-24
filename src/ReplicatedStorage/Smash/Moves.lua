--[[
	Move data shared by the server (hitboxes, projectiles) and the client (animation, motion).

	Times are in seconds at AttackSpeed 1. Offsets/sizes are in studs at Scale 1, X = forward, Y = up.
	Hit fields:
		t = {start, stop}   active window
		off, size           Vector2 hitbox (center offset, size)
		dmg                 damage percent
		ang                 launch angle in degrees relative to facing (361 = Sakurai angle)
		bkb, kbg            base knockback and knockback growth (1.0 = 100)
		away                launch away from the hitbox center instead of by facing
		toward              pull toward the hitbox center (multi-hit links)
		rehit               seconds between repeated hits on the same target (multi-hit)
		hitstunMult, hitlagMult, freeze (extra freeze seconds, ice)
		fx                  effect style ("light", "fire", "ice", "heavy", "electric", "cosmic")
	Move fields: anim, dur, air (aerial), any (usable grounded or airborne), landLag, trail, hits,
		motion, teleport, gravity, intangible, armor, counter, reflect, projectile, landHit,
		endOnLand, helpless, oncePerAir, cooldown, charge, combo, fx
]]
local Fighters = require(script.Parent.Fighters)

local Moves = {}

local V2 = Vector2.new

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end

-- Normals shared by every fighter ------------------------------------------------
local Normals = {
	jab = {
		anim = "jab1", dur = 0.26, trail = { "RightHand" },
		hits = { { t = { 0.05, 0.1 }, off = V2(2.4, 0.5), size = V2(3.4, 2.8), dmg = 2.5, ang = 80, bkb = 8, kbg = 0.2, fx = "light" } },
		combo = { next = "jab2", from = 0.1, to = 0.26 },
	},
	jab2 = {
		anim = "jab2", dur = 0.26, trail = { "LeftHand" },
		hits = { { t = { 0.04, 0.09 }, off = V2(2.4, 0.5), size = V2(3.4, 2.8), dmg = 2.5, ang = 80, bkb = 8, kbg = 0.2, fx = "light" } },
		combo = { next = "jab3", from = 0.09, to = 0.26 },
	},
	jab3 = {
		anim = "jab3", dur = 0.42, trail = { "RightFoot" },
		hits = { { t = { 0.08, 0.15 }, off = V2(2.8, 0), size = V2(4, 3.2), dmg = 5, ang = 361, bkb = 32, kbg = 0.8 } },
	},
	ftilt = {
		anim = "ftilt", dur = 0.4, trail = { "RightFoot" },
		hits = { { t = { 0.1, 0.17 }, off = V2(3.0, 0.2), size = V2(4.2, 2.6), dmg = 9, ang = 361, bkb = 22, kbg = 0.9 } },
	},
	utilt = {
		anim = "utilt", dur = 0.4, trail = { "RightHand" },
		hits = { { t = { 0.08, 0.18 }, off = V2(0.6, 2.8), size = V2(4.8, 3.6), dmg = 7, ang = 95, bkb = 26, kbg = 1.0 } },
	},
	dtilt = {
		anim = "dtilt", dur = 0.32, trail = { "RightFoot" },
		hits = { { t = { 0.07, 0.13 }, off = V2(2.8, -2.1), size = V2(4, 1.8), dmg = 6, ang = 75, bkb = 20, kbg = 0.6 } },
	},
	fsmash = {
		anim = "fsmash", dur = 0.62, trail = { "RightHand" }, charge = { max = 1.0, dmgMult = 0.4, button = "smash" },
		motion = { { t = 0.2, dur = 0.08, vx = 12 } },
		hits = { { t = { 0.24, 0.32 }, off = V2(3.4, 0.4), size = V2(4.8, 3.2), dmg = 15, ang = 361, bkb = 36, kbg = 1.02, hitlagMult = 1.2 } },
	},
	usmash = {
		anim = "usmash", dur = 0.6, trail = { "RightHand", "LeftHand" }, charge = { max = 1.0, dmgMult = 0.4, button = "smash" },
		hits = { { t = { 0.18, 0.32 }, off = V2(0.4, 3.2), size = V2(5.2, 4.4), dmg = 15, ang = 88, bkb = 34, kbg = 1.02, hitlagMult = 1.2 } },
	},
	dsmash = {
		anim = "dsmash", dur = 0.58, trail = { "RightFoot", "LeftFoot" }, charge = { max = 1.0, dmgMult = 0.4, button = "smash" },
		hits = { { t = { 0.18, 0.3 }, off = V2(0, -1.8), size = V2(9.5, 2.4), dmg = 13, ang = 32, away = true, bkb = 30, kbg = 1.0, hitlagMult = 1.2 } },
	},
	nair = {
		anim = "nair", dur = 0.48, air = true, landLag = 0.1, trail = { "RightFoot", "LeftHand" },
		hits = { { t = { 0.06, 0.3 }, off = V2(0, 0), size = V2(5.4, 5.2), dmg = 8, ang = 361, away = true, bkb = 20, kbg = 0.9 } },
	},
	fair = {
		anim = "fair", dur = 0.52, air = true, landLag = 0.16, trail = { "RightHand", "LeftHand" },
		hits = { { t = { 0.16, 0.24 }, off = V2(2.6, 0.6), size = V2(4.2, 4.2), dmg = 12, ang = 40, bkb = 28, kbg = 1.0 } },
	},
	bair = {
		anim = "bair", dur = 0.44, air = true, landLag = 0.12, trail = { "LeftFoot" },
		hits = { { t = { 0.1, 0.17 }, off = V2(-2.8, 0.2), size = V2(3.8, 3.0), dmg = 12, ang = 140, bkb = 26, kbg = 1.05 } },
	},
	uair = {
		anim = "uair", dur = 0.42, air = true, landLag = 0.1, trail = { "RightFoot" },
		hits = { { t = { 0.08, 0.18 }, off = V2(0, 3.0), size = V2(4.8, 3.6), dmg = 9, ang = 85, bkb = 24, kbg = 0.95 } },
	},
	dair = {
		anim = "dair", dur = 0.56, air = true, landLag = 0.2, trail = { "RightFoot", "LeftFoot" },
		hits = { { t = { 0.16, 0.24 }, off = V2(0, -2.8), size = V2(3.6, 3.4), dmg = 13, ang = 275, bkb = 22, kbg = 0.9, hitlagMult = 1.3 } },
	},
	ledgeattack = {
		anim = "ftilt", dur = 0.45, trail = { "RightFoot" },
		hits = { { t = { 0.12, 0.22 }, off = V2(2.4, 0), size = V2(4.6, 3), dmg = 8, ang = 45, bkb = 32, kbg = 0.4 } },
	},
	taunt = { anim = "taunt", dur = 1.1 },
}

-- Specials per fighter ----------------------------------------------------------
local Specials = {}

Specials.Blaze = {
	nspecial = {
		anim = "throw", dur = 0.5, any = true, cooldown = 0.55, trail = { "RightHand" },
		projectile = { t = 0.16, off = V2(2.2, 0.6), speed = 55, life = 1.1, size = 1.8, style = "fireball",
			hit = { dmg = 6, ang = 361, bkb = 16, kbg = 0.45, fx = "fire" } },
	},
	sspecial = {
		anim = "dash", dur = 0.55, any = true, oncePerAir = true, trail = { "RightHand", "LeftHand" },
		motion = { { t = 0.08, dur = 0.25, vx = 62, vy = 0 } },
		gravity = { t0 = 0.08, t1 = 0.35, scale = 0 },
		hits = { { t = { 0.08, 0.33 }, off = V2(1.6, 0), size = V2(4.4, 4.4), dmg = 10, ang = 40, bkb = 34, kbg = 0.8, fx = "fire" } },
	},
	uspecial = {
		anim = "uppercut", dur = 0.75, any = true, helpless = true, trail = { "RightHand" },
		motion = { { t = 0.06, dur = 0.34, vy = 78, vx = 4, steer = 12 } },
		hits = {
			{ t = { 0.06, 0.3 }, off = V2(0.8, 1.2), size = V2(4.4, 5.2), dmg = 1.5, ang = 90, bkb = 100, kbg = 0, rehit = 0.07, hitstunMult = 0.35, hitlagMult = 0.4, fx = "fire" },
			{ t = { 0.32, 0.42 }, off = V2(0.8, 2.4), size = V2(4.8, 4.8), dmg = 6, ang = 75, bkb = 45, kbg = 0.95, fx = "fire" },
		},
	},
	dspecial = {
		anim = "slam", dur = 1.3, any = true, endOnLand = true, landLag = 0.25, trail = { "RightFoot", "LeftFoot" },
		motion = { { t = 0, dur = 0.14, vy = 40, vx = 0 }, { t = 0.22, dur = 1.1, vy = -125, vx = 0 } },
		hits = { { t = { 0.22, 1.3 }, off = V2(0, -1.5), size = V2(3.8, 3.6), dmg = 9, ang = 275, bkb = 30, kbg = 0.6, fx = "fire" } },
		landHit = { minT = 0.22, hit = { off = V2(0, -2), size = V2(12, 3.2), dmg = 8, ang = 50, away = true, bkb = 38, kbg = 0.6, fx = "fire" } },
	},
}

Specials.Frost = {
	nspecial = {
		anim = "throw", dur = 0.36, any = true, cooldown = 0.35, trail = { "RightHand" },
		projectile = { t = 0.1, off = V2(2, 0.6), speed = 85, life = 0.7, size = 1.2, style = "shuriken",
			hit = { dmg = 4, ang = 361, bkb = 10, kbg = 0.3, fx = "ice", freeze = 0.35 } },
	},
	sspecial = {
		anim = "slash", dur = 0.5, any = true, oncePerAir = true, trail = { "RightHand" },
		teleport = { t = 0.14, dist = 14, dir = "forward" },
		gravity = { t0 = 0, t1 = 0.4, scale = 0 },
		hits = { { t = { 0.14, 0.22 }, fromStart = true, off = V2(7, 0.3), size = V2(15.5, 4.2), dmg = 8, ang = 45, bkb = 30, kbg = 0.75, fx = "ice", freeze = 0.2 } },
		fx = "blink",
	},
	uspecial = {
		anim = "warp", dur = 0.62, any = true, helpless = true,
		teleport = { t = 0.2, dist = 17, dir = "input" },
		gravity = { t0 = 0, t1 = 0.24, scale = 0 },
		intangible = { t0 = 0.08, t1 = 0.3 },
		fx = "blink",
	},
	dspecial = {
		anim = "counter", dur = 0.75, any = true, trail = { "RightHand" },
		gravity = { t0 = 0, t1 = 0.6, scale = 0.3 },
		counter = { t0 = 0.06, t1 = 0.5, mult = 1.3, hit = { off = V2(2.4, 0.5), size = V2(6.4, 5.2), dmg = 8, ang = 40, bkb = 45, kbg = 0.9, fx = "ice", freeze = 0.25 } },
	},
}

Specials.Titan = {
	nspecial = {
		anim = "bigpunch", dur = 0.72, any = true, trail = { "RightHand" },
		charge = { max = 1.6, dmgMult = 0.65, button = "special" },
		armor = { t0 = 0, t1 = 0.3, kb = 120 },
		motion = { { t = 0.2, dur = 0.1, vx = 26 } },
		hits = { { t = { 0.22, 0.3 }, off = V2(3.2, 0.5), size = V2(4.8, 3.8), dmg = 14, ang = 361, bkb = 40, kbg = 1.05, fx = "heavy", hitlagMult = 1.3 } },
	},
	sspecial = {
		anim = "dash", dur = 0.72, any = true, oncePerAir = true, trail = { "RightHand" },
		motion = { { t = 0.12, dur = 0.35, vx = 46 } },
		gravity = { t0 = 0.12, t1 = 0.5, scale = 0.3 },
		armor = { t0 = 0.1, t1 = 0.47, kb = 100 },
		hits = { { t = { 0.12, 0.47 }, off = V2(2, 0.3), size = V2(4.6, 5.2), dmg = 12, ang = 38, bkb = 38, kbg = 0.85, fx = "heavy" } },
	},
	uspecial = {
		anim = "uppercut", dur = 0.72, any = true, helpless = true, trail = { "RightHand" },
		motion = { { t = 0.1, dur = 0.3, vy = 70, vx = 6, steer = 10 } },
		hits = { { t = { 0.1, 0.3 }, off = V2(1.2, 1.8), size = V2(4.2, 5.2), dmg = 11, ang = 80, bkb = 40, kbg = 0.9, fx = "heavy" } },
	},
	dspecial = {
		anim = "stomp", dur = 1.2, any = true, endOnLand = true, landLag = 0.3,
		armor = { t0 = 0.05, t1 = 0.45, kb = 80 },
		motion = { { t = 0.1, dur = 1.1, vy = -100, vx = 0 } },
		landHit = { minT = 0.35, hit = { off = V2(0, -2), size = V2(17, 3.4), dmg = 13, ang = 70, away = true, bkb = 45, kbg = 0.8, fx = "heavy", hitlagMult = 1.2 } },
	},
}

Specials.Volt = {
	nspecial = {
		anim = "throw", dur = 0.5, any = true, cooldown = 1.1, trail = { "RightHand" },
		projectile = { t = 0.16, off = V2(2.2, 0.4), speed = 22, life = 2.0, size = 2.4, style = "orb", pierce = true,
			multi = { interval = 0.14, max = 5 },
			hit = { dmg = 1.6, toward = true, ang = 0, bkb = 18, kbg = 0, fx = "electric" } },
	},
	sspecial = {
		anim = "dash", dur = 0.5, any = true, oncePerAir = true, trail = { "RightFoot", "LeftFoot" },
		motion = { { t = 0.06, dur = 0.2, vx = 95, vy = 0, stopAfter = true } },
		gravity = { t0 = 0.06, t1 = 0.3, scale = 0 },
		hits = { { t = { 0.06, 0.26 }, off = V2(0, 0.2), size = V2(4.8, 4.8), dmg = 9, ang = 45, bkb = 34, kbg = 0.75, fx = "electric", hitlagMult = 1.6 } },
	},
	uspecial = {
		anim = "zip", dur = 0.62, any = true, helpless = true, trail = { "RightFoot", "LeftFoot" },
		motion = {
			{ t = 0.06, dur = 0.1, dirInput = 105, stopAfter = true },
			{ t = 0.3, dur = 0.1, dirInput = 105, stopAfter = true },
		},
		gravity = { t0 = 0, t1 = 0.45, scale = 0 },
		hits = { { t = { 0.06, 0.4 }, off = V2(0, 0), size = V2(3.8, 4.6), dmg = 2, ang = 80, bkb = 30, kbg = 0.2, rehit = 0.2, fx = "electric" } },
	},
	dspecial = {
		anim = "summon", dur = 0.9, any = true, cooldown = 1.2,
		gravity = { t0 = 0, t1 = 0.6, scale = 0.2 },
		hits = { { t = { 0.25, 0.4 }, off = V2(0, 1), size = V2(8.5, 8.5), dmg = 15, ang = 80, away = true, bkb = 40, kbg = 1.0, fx = "electric", hitlagMult = 1.5 } },
		fx = "thunderbolt",
	},
}

Specials.Nova = {
	nspecial = {
		anim = "throw", dur = 0.5, any = true, cooldown = 0.4, trail = { "RightHand", "LeftHand" },
		charge = { max = 1.4, dmgMult = 1.7, button = "special" },
		projectile = { t = 0.14, off = V2(2.2, 0.6), speed = 60, life = 1.2, size = 1.6, chargeSize = 1.3, style = "star",
			hit = { dmg = 5, ang = 361, bkb = 18, kbg = 0.8, fx = "cosmic" } },
	},
	sspecial = {
		anim = "throw", dur = 0.55, any = true, cooldown = 2.0, trail = { "RightHand" },
		projectile = { t = 0.2, off = V2(3, 0.5), speed = 12, life = 2.2, size = 4.6, style = "vortex", pierce = true,
			multi = { interval = 0.2, max = 8 },
			hit = { dmg = 1.2, toward = true, ang = 0, bkb = 14, kbg = 0, fx = "cosmic" } },
	},
	uspecial = {
		anim = "ride", dur = 1.0, any = true, helpless = true,
		motion = { { t = 0.1, dur = 0.65, vy = 52, vx = 0, steer = 18 } },
		gravity = { t0 = 0.1, t1 = 0.8, scale = 0 },
		hits = { { t = { 0.72, 0.82 }, off = V2(0, 0), size = V2(5.4, 5.4), dmg = 8, ang = 60, away = true, bkb = 40, kbg = 0.7, fx = "cosmic" } },
		fx = "star",
	},
	dspecial = {
		anim = "barrier", dur = 0.6, any = true,
		gravity = { t0 = 0, t1 = 0.5, scale = 0.3 },
		reflect = { t0 = 0.05, t1 = 0.45, size = V2(6.4, 6.4) },
		hits = { { t = { 0.05, 0.12 }, off = V2(0, 0), size = V2(5.6, 5.6), dmg = 5, ang = 361, away = true, bkb = 30, kbg = 0.3, fx = "cosmic" } },
		fx = "barrier",
	},
}

-- Per-fighter tweaks to the normals (on top of Power / AttackSpeed scaling)
local NormalTweaks = {
	Titan = {
		fsmash = { armor = { t0 = 0.05, t1 = 0.28, kb = 90 } },
		usmash = { armor = { t0 = 0.05, t1 = 0.22, kb = 90 } },
	},
	Volt = {
		nair = { hits = { { t = { 0.04, 0.3 }, off = V2(0, 0), size = V2(5, 5), dmg = 2, ang = 361, toward = true, bkb = 20, kbg = 0, rehit = 0.08, hitstunMult = 0.6, fx = "electric" } } },
	},
	Nova = {
		uair = { hits = { { t = { 0.08, 0.24 }, off = V2(0, 3.2), size = V2(5.4, 4), dmg = 10, ang = 88, bkb = 28, kbg = 1.0, fx = "cosmic" } } },
	},
}

-- Build ---------------------------------------------------------------------------
local TIME_KEYS = { dur = true, landLag = true, t = true, t0 = true, t1 = true, from = true, to = true, minT = true, rehit = true, interval = true, cooldown = true }

local function scaleTimes(tbl, speed)
	for k, v in pairs(tbl) do
		if type(v) == "number" and TIME_KEYS[k] then
			tbl[k] = v / speed
		elseif type(v) == "table" then
			if k == "t" and #v == 2 and type(v[1]) == "number" then
				v[1] = v[1] / speed
				v[2] = v[2] / speed
			else
				scaleTimes(v, speed)
			end
		end
	end
end

local function scaleDamage(move, power)
	local function scaleHit(h)
		if h and h.dmg then h.dmg = h.dmg * power end
	end
	if move.hits then for _, h in ipairs(move.hits) do scaleHit(h) end end
	if move.projectile then scaleHit(move.projectile.hit) end
	if move.landHit then scaleHit(move.landHit.hit) end
	if move.counter then scaleHit(move.counter.hit) end
end

local cache = {}

function Moves.Get(fighterKey)
	if cache[fighterKey] then return cache[fighterKey] end
	local def = Fighters.Get(fighterKey)
	local set = {}
	for key, move in pairs(Normals) do
		set[key] = deepCopy(move)
	end
	local tweaks = NormalTweaks[def.Key]
	if tweaks then
		for key, tweak in pairs(tweaks) do
			for field, value in pairs(tweak) do
				set[key][field] = deepCopy(value)
			end
		end
	end
	for key, move in pairs(Specials[def.Key] or Specials.Blaze) do
		set[key] = deepCopy(move)
	end
	for key, move in pairs(set) do
		move.key = key
		scaleTimes(move, def.Stats.AttackSpeed)
		scaleDamage(move, def.Stats.Power)
		-- normals inherit the fighter's element for their effects
		local function tagFx(h)
			if h and not h.fx then h.fx = def.Element end
		end
		if move.hits then for _, h in ipairs(move.hits) do tagFx(h) end end
		if move.landHit then tagFx(move.landHit.hit) end
	end
	cache[fighterKey] = set
	return set
end

-- Which move a button press maps to.
-- dir: "neutral" | "side" | "up" | "down"; forward: true when the side input points the way we face
function Moves.Resolve(button, dir, grounded, forward)
	if button == "special" then
		if dir == "up" then return "uspecial" end
		if dir == "down" then return "dspecial" end
		if dir == "side" then return "sspecial" end
		return "nspecial"
	end
	if grounded then
		if button == "smash" then
			if dir == "up" then return "usmash" end
			if dir == "down" then return "dsmash" end
			return "fsmash"
		end
		if dir == "up" then return "utilt" end
		if dir == "down" then return "dtilt" end
		if dir == "side" then return "ftilt" end
		return "jab"
	end
	if dir == "up" then return "uair" end
	if dir == "down" then return "dair" end
	if dir == "side" then return forward and "fair" or "bair" end
	return "nair"
end

return Moves
