-- Plays the procedural Poses on every fighter (runs on each client, after the default animations).
-- Layers, highest priority first: victory, grabbed, ledge, hitstun, attacks, charging, dodges, holding,
-- shield, helpless, revival, then movement (landing squash, double-jump flip, rise/fall, crouch and
-- each fighter's idle fighting stance). Switching between any two poses blends smoothly.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Poses = require(Smash.Poses)
local Moves = require(Smash.Moves)
local Fighters = require(Smash.Fighters)

local Animator = {}
Animator.LocalModel = nil
Animator.LocalState = nil -- function() -> controller state for our own fighter

local records = {}  -- model -> record
local byId = {}     -- fighter id -> model

local TRAIL_LIMBS = { "RightHand", "LeftHand", "RightFoot", "LeftFoot" }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = false

local function clock() return os.clock() end

local function makeTrails(model, def)
	local trails = {}
	for _, limb in ipairs(TRAIL_LIMBS) do
		local part = model:FindFirstChild(limb)
		if part then
			local a0 = Instance.new("Attachment")
			a0.Name = "SmashTrailA"
			a0.Position = Vector3.new(0, 0.4, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Name = "SmashTrailB"
			a1.Position = Vector3.new(0, -0.4, 0)
			a1.Parent = part
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0
			tr.Attachment1 = a1
			tr.Color = ColorSequence.new(def.Accent, def.Color)
			tr.LightEmission = 0.8
			tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			tr.Lifetime = 0.16
			tr.MinLength = 0.05
			tr.WidthScale = NumberSequence.new(1, 0.2)
			tr.FaceCamera = true
			tr.Enabled = false
			tr.Parent = part
			trails[limb] = tr
		end
	end
	return trails
end

local function track(model)
	if records[model] then return end
	local key = model:GetAttribute("FighterKey")
	if not key then return end
	local def = Fighters.Get(key)
	local lower = string.lower(def.Key)
	local rec = {
		model = model,
		def = def,
		moves = Moves.Get(key),
		scale = def.Scale or 1,
		stance = "stance_" .. lower,
		stancePeriod = Poses.StancePeriod[lower] or 1.2,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		root = model:FindFirstChild("HumanoidRootPart"),
		joints = {},
		trails = makeTrails(model, def),
		anim = nil,       -- { move, start, paused, pauseUntil }
		hitstunUntil = 0,
		tumble = false,
		hitlagUntil = 0,
		dodge = nil,      -- { kind, start, dur }
		charging = nil,   -- { key, start }
		flipStart = -10,
		landUntil = 0,
		wasGrounded = true,
		prevVy = 0,
		src = nil,
		from = {},
		out = {},
		blendStart = 0,
		blendDur = 0,
	}
	for joint, info in pairs(Poses.Joints) do
		local part = model:FindFirstChild(info[1])
		local motor = part and part:FindFirstChild(info[2])
		if motor and motor:IsA("Motor6D") then
			rec.joints[joint] = motor
		end
	end
	records[model] = rec
	local id = model:GetAttribute("FighterId")
	if id then byId[id] = model end
end

local function untrack(model)
	records[model] = nil
	for id, m in pairs(byId) do
		if m == model then byId[id] = nil end
	end
end

function Animator.ModelFor(id)
	local m = byId[id]
	if m and m.Parent then return m end
	for _, model in ipairs(CollectionService:GetTagged("SmashFighter")) do
		if model:GetAttribute("FighterId") == id then
			byId[id] = model
			if not records[model] then track(model) end
			return model
		end
	end
	return nil
end

local function recFor(id)
	local m = Animator.ModelFor(id)
	return m and records[m], m
end

-- Events -------------------------------------------------------------------------------------

function Animator.PlayMove(model, key)
	local rec = records[model]
	if not rec then return end
	local move = rec.moves[key]
	if not move then return end
	rec.anim = { move = move, start = clock(), paused = 0, pauseUntil = 0 }
	rec.charging = nil
	for _, tr in pairs(rec.trails) do tr.Enabled = false end
	for _, limb in ipairs(move.trail or {}) do
		if rec.trails[limb] then rec.trails[limb].Enabled = true end
	end
end

function Animator.OnMove(data)
	local rec, model = recFor(data.id)
	if not rec then return end
	-- our own moves already started locally the moment we pressed the button
	if model == Animator.LocalModel and rec.anim and rec.anim.move.key == data.key and clock() - rec.anim.start < 0.5 then
		return
	end
	Animator.PlayMove(model, data.key)
end

function Animator.OnCharge(data)
	local rec, model = recFor(data.id)
	if not rec or model == Animator.LocalModel then return end
	rec.charging = { key = data.key, start = clock() }
	rec.anim = nil
end

function Animator.LocalCharge(model, key)
	local rec = records[model]
	if rec then
		rec.charging = { key = key, start = clock() }
		rec.anim = nil
	end
end

function Animator.OnAirJump(model)
	local rec = records[model]
	if rec then rec.flipStart = clock() end
end

local function pause(rec, sec)
	local t = clock()
	rec.hitlagUntil = math.max(rec.hitlagUntil, t + sec)
	local a = rec.anim
	if a then
		local newUntil = t + sec
		if newUntil > a.pauseUntil then
			a.paused += newUntil - math.max(a.pauseUntil, t)
			a.pauseUntil = newUntil
		end
	end
end

function Animator.OnHit(data)
	local vrec = recFor(data.v)
	local arec = recFor(data.a)
	if arec and (data.attackerLag or 0) > 0 then pause(arec, data.attackerLag) end
	if vrec then
		if data.armored then
			pause(vrec, data.hitlag or 0.05)
			return
		end
		local lag = (data.hitlag or 0) + (data.freeze or 0)
		vrec.anim = nil
		vrec.charging = nil
		vrec.dodge = nil
		vrec.hitlagUntil = clock() + lag
		vrec.hitstunUntil = clock() + lag + (data.hitstun or 0)
		vrec.tumble = data.tumble
		for _, tr in pairs(vrec.trails) do tr.Enabled = false end
	end
end

function Animator.OnDodge(data)
	local rec = recFor(data.id)
	if not rec then return end
	local cfg = data.kind == "roll" and Config.Roll or data.kind == "air" and Config.AirDodge or Config.SpotDodge
	rec.dodge = { kind = data.kind, start = clock(), dur = cfg.Duration }
	rec.anim = nil
end

function Animator.OnCounter(data)
	local rec = recFor(data.id)
	if not rec then return end
	rec.anim = { move = { key = "counterhit", anim = "counterhit", dur = 0.4 }, start = clock(), paused = 0, pauseUntil = 0 }
end

function Animator.OnStun(id, sec)
	local rec = recFor(id)
	if rec then
		rec.anim = nil
		rec.hitstunUntil = clock() + sec
		rec.tumble = false
	end
end

function Animator.Reset(id)
	local rec = recFor(id)
	if rec then
		rec.anim = nil
		rec.charging = nil
		rec.dodge = nil
		rec.hitstunUntil = 0
		rec.hitlagUntil = 0
		for _, tr in pairs(rec.trails) do tr.Enabled = false end
	end
end

local victoryModel = nil
function Animator.SetVictory(model)
	victoryModel = model
end

-- Per frame -------------------------------------------------------------------------------------

local function toCF(v, scale, joint)
	local rot = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
	local pos = Vector3.new(v[4] or 0, v[5] or 0, v[6] or 0) * scale
	if joint == "Root" then
		-- spin around the middle of the body instead of the hips
		local h = 0.9 * scale
		return CFrame.new(pos) * CFrame.new(0, h, 0) * rot * CFrame.new(0, -h, 0)
	end
	return CFrame.new(pos) * rot
end

local function isGrounded(rec, localState)
	if localState then return localState.grounded end
	local root, hum = rec.root, rec.humanoid
	if not root or not hum then return true end
	if root.AssemblyLinearVelocity.Y > 6 then return false end
	local reach = hum.HipHeight + root.Size.Y / 2 + 0.6
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function loopU(t, period)
	return (t % period) / period
end

-- Returns pose, source id (a change triggers a blend), blend time
local function choosePose(rec, t)
	local model = rec.model
	local S = Poses.States
	local localState = (model == Animator.LocalModel and Animator.LocalState) and Animator.LocalState() or nil

	-- track landings every frame so the squash only plays on a real touchdown
	local root = rec.root
	if not root then return nil end
	local v = root.AssemblyLinearVelocity
	local grounded = isGrounded(rec, localState)
	if grounded and not rec.wasGrounded and rec.prevVy < -25 then
		rec.landUntil = t + 0.12
	end
	rec.wasGrounded = grounded
	rec.prevVy = v.Y

	if model == victoryModel then
		return Poses.Sample(rec.moves.taunt.anim, loopU(t, rec.moves.taunt.dur)), "victory", 0.2
	end

	local grabbed = localState and localState.grabbed or (not localState and model:GetAttribute("Grabbed"))
	if grabbed and t >= rec.hitstunUntil then
		local pose = table.clone(S.grabbed)
		local s1, s2 = math.sin(t * 16), math.sin(t * 12)
		pose.RS = { 150 + s1 * 22, 0, 30 }
		pose.LS = { 150 - s1 * 22, 0, -30 }
		pose.RH = { 20 + s2 * 28, 0, 6 }
		pose.LH = { 20 - s2 * 28, 0, -6 }
		return pose, "grabbed", 0.08
	end

	if localState and localState.ledge or (not localState and model:GetAttribute("OnLedge")) then
		return S.ledge, "ledge", 0.08
	end

	if t < rec.hitstunUntil then
		if rec.tumble and t >= rec.hitlagUntil then
			local pose = table.clone(S.tumble)
			pose.Root = { (t * 620) % 360, 0, 0 }
			return pose, "tumble", 0.05
		end
		local pose = table.clone(S.flinch)
		if t < rec.hitlagUntil then
			-- shake in place during hitlag
			pose.Root = { 0, 0, 0, (math.random() - 0.5) * 0.5, 0, (math.random() - 0.5) * 0.5 }
		end
		return pose, "flinch", 0.03
	end

	if rec.anim then
		local a = rec.anim
		local elapsed = t - a.start - a.paused
		if t < a.pauseUntil then elapsed = a.pauseUntil - a.start - a.paused end
		local u = elapsed / a.move.dur
		if u <= 1 then
			return Poses.Sample(a.move.anim, u), "move:" .. a.move.key .. a.start, 0.05
		end
		rec.anim = nil
		for _, tr in pairs(rec.trails) do tr.Enabled = false end
	end

	if rec.charging then
		local move = rec.moves[rec.charging.key]
		if move and t - rec.charging.start < 3 then
			local u = Poses.ChargeU[move.anim] or 0.2
			local pose = Poses.Sample(move.anim, u) or {}
			local shake = (math.random() - 0.5) * 0.12
			pose.Root = { 0, 0, 0, shake, 0, shake }
			return pose, "charge", 0.08
		end
		rec.charging = nil
	end

	if rec.dodge then
		local d = rec.dodge
		local u = (t - d.start) / d.dur
		if u <= 1 then
			local id = "dodge:" .. d.kind .. d.start
			if d.kind == "roll" then
				local pose = table.clone(S.spotdodge)
				pose.Root = { -360 * u, 0, 0, 0, -1, 0 }
				return pose, id, 0.04
			elseif d.kind == "air" then
				return S.airdodge, id, 0.05
			end
			return S.spotdodge, id, 0.04
		end
		rec.dodge = nil
	end

	local holding = localState and localState.holding or (not localState and model:GetAttribute("Holding"))
	if holding then return S.hold, "hold", 0.08 end

	if localState then
		if localState.shielding then return S.shield, "shield", 0.08 end
		if localState.helpless then return S.helpless, "helpless", 0.15 end
	elseif model:GetAttribute("Shielding") then
		return S.shield, "shield", 0.08
	end
	if model:GetAttribute("Reviving") then
		return S.revive, "revive", 0.15
	end

	-- movement layer -------------------------------------------------------------------------
	if t < rec.landUntil then
		return S.land, "land", 0.04
	end
	if not grounded then
		local fu = (t - rec.flipStart) / 0.34
		if fu >= 0 and fu <= 1 then
			return Poses.Sample("flip", fu), "flip" .. rec.flipStart, 0.04
		end
		if v.Y > 8 then return S.rise, "rise", 0.12 end
		return S.fall, "fall", 0.15
	end
	local crouching = localState and localState.crouching or (not localState and model:GetAttribute("Crouching"))
	if crouching then return S.crouch, "crouch", 0.08 end
	if math.abs(v.X) < 3 then
		return Poses.Sample(rec.stance, loopU(t, rec.stancePeriod)), "stance", 0.18
	end
	return nil, nil, 0.15
end

-- Blends from whatever we showed last frame to the new pose over `blendDur`
local function apply(rec, pose, src, blendDur, t)
	if src ~= rec.src then
		rec.src = src
		rec.blendStart = t
		rec.blendDur = blendDur or 0.1
		rec.from = rec.out
	end
	local alpha = 1
	if rec.blendDur > 0 then
		alpha = math.clamp((t - rec.blendStart) / rec.blendDur, 0, 1)
	end
	alpha = alpha * alpha * (3 - 2 * alpha)
	local out = {}
	for joint, motor in pairs(rec.joints) do
		local v = pose and pose[joint]
		local from = rec.from[joint]
		if v then
			local target = toCF(v, rec.scale, joint)
			local cf = target
			if alpha < 1 then
				cf = (from or motor.Transform):Lerp(target, alpha)
			end
			motor.Transform = cf
			out[joint] = cf
		elseif from and alpha < 1 then
			-- easing back into the default animation
			local cf = from:Lerp(motor.Transform, alpha)
			motor.Transform = cf
			out[joint] = cf
		end
	end
	rec.out = out
end

function Animator.Init()
	for _, m in ipairs(CollectionService:GetTagged("SmashFighter")) do track(m) end
	CollectionService:GetInstanceAddedSignal("SmashFighter"):Connect(function(m)
		-- wait for the server to finish dressing the fighter
		task.delay(0.2, function()
			if m.Parent then track(m) end
		end)
	end)
	CollectionService:GetInstanceRemovedSignal("SmashFighter"):Connect(untrack)

	task.spawn(function()
		rayParams.FilterDescendantsInstances = { Config.GetStage().Model }
	end)

	RunService.Stepped:Connect(function()
		local t = clock()
		for model, rec in pairs(records) do
			if not model.Parent then
				records[model] = nil
				continue
			end
			local pose, src, blend = choosePose(rec, t)
			apply(rec, pose, src, blend, t)
		end
	end)
end

return Animator
