-- Client-side juice: hit sparks, flashes, launch smoke, KO blasts, projectiles, shields,
-- name tags, revival platforms and sounds. Nothing here affects gameplay.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Fighters = require(Smash.Fighters)

local Effects = {}
Effects.CameraRig = nil
Effects.ModelFor = nil -- function(id) -> model

local folder = Instance.new("Folder")
folder.Name = "SmashFX"
folder.Parent = workspace

local FX_COLORS = {
	light = Color3.fromRGB(255, 245, 200),
	fire = Color3.fromRGB(255, 120, 30),
	ice = Color3.fromRGB(120, 220, 255),
	heavy = Color3.fromRGB(255, 200, 60),
	electric = Color3.fromRGB(255, 240, 60),
	cosmic = Color3.fromRGB(210, 110, 255),
}

-- Built-in sounds that ship with every Roblox client. Swap in asset ids if you have better ones.
local SOUNDS = {
	hit = "rbxasset://sounds/action_jump_land.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	jump = "rbxasset://sounds/action_jump.mp3",
	tick = "rbxasset://sounds/volume_slider.ogg",
	swing = "rbxasset://sounds/action_swim.mp3",
}

function Effects.Sound(name, volume, speed, at)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or name
	s.Volume = volume or 0.6
	s.PlaybackSpeed = speed or 1
	if at then
		local att = Instance.new("Attachment")
		att.WorldPosition = at
		att.Parent = workspace.Terrain
		s.Parent = att
		s.RollOffMinDistance = 60
		Debris:AddItem(att, 4)
	else
		s.Parent = SoundService
		Debris:AddItem(s, 4)
	end
	s:Play()
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = folder
	return p
end

local function tween(obj, time, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function burst(pos, color, count, speed, size, texture)
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = texture or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.8), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.2, 0.45)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)
	Debris:AddItem(att, 1.2)
end

local function ring(pos, color, fromSize, toSize, time, flat)
	local p = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, fromSize, fromSize),
		CFrame = flat and (CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))) or (CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0)),
		Color = color,
		Transparency = 0.15,
	})
	tween(p, time, { Size = Vector3.new(0.1, toSize, toSize), Transparency = 1 })
	Debris:AddItem(p, time + 0.05)
end

local function flash(model, color, time)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.1
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = folder
	tween(h, time, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, time + 0.05)
end

local function popText(pos, text, color, size)
	local anchor = part({ Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1, CFrame = CFrame.new(pos) })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 60)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.TextSize = size or 30
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb
	tween(anchor, 0.7, { CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) })
	tween(lbl, 0.7, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quint)
	Debris:AddItem(anchor, 0.8)
end

local function smokeTrail(model, duration)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 3) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.5, 0.8)
	pe.Speed = NumberRange.new(0, 1)
	pe.Rate = 45
	pe.LockedToPart = false
	pe.Parent = root
	task.delay(duration, function() pe.Enabled = false end)
	Debris:AddItem(pe, duration + 1)
end

-- Event handlers ------------------------------------------------------------------------------

function Effects.OnHit(data)
	local color = FX_COLORS[data.fx] or FX_COLORS.light
	local kb = data.kb or 0
	local strength = math.clamp(kb / 150, 0.15, 1.6)
	local pos = data.pos
	burst(pos, color, math.floor(8 + 18 * strength), 18 + 25 * strength, 0.6 + strength)
	ring(pos, color, 1, 4 + 9 * strength, 0.22 + 0.12 * strength, false)
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (1 + 2.2 * strength), CFrame = CFrame.new(pos), Color = Color3.new(1, 1, 1) })
	tween(core, 0.15, { Size = Vector3.one * (2.5 + 4 * strength), Transparency = 1 })
	Debris:AddItem(core, 0.2)
	local victim = Effects.ModelFor and Effects.ModelFor(data.v)
	if victim then
		flash(victim, data.freeze and data.freeze > 0 and FX_COLORS.ice or Color3.new(1, 1, 1), 0.18 + (data.hitlag or 0))
		if data.tumble then
			smokeTrail(victim, math.min(data.hitstun or 0.5, 1.5))
		end
	end
	if not data.armored then
		popText(pos + Vector3.new(0, 2, 0), string.format("%d%%", math.floor(data.dmg + 0.5)), color, 22 + math.floor(10 * strength))
	end
	Effects.Sound("hit", 0.5 + 0.4 * strength, 1.5 - 0.5 * math.min(strength, 1), pos)
	if kb > 110 then
		Effects.Sound("boom", 0.25 * strength, 1.6, pos)
	end
	if Effects.CameraRig then
		Effects.CameraRig.Shake(0.15 + 1.4 * math.max(0, strength - 0.3), 0.18 + 0.2 * strength)
	end
end

function Effects.OnShieldHit(data)
	local pos = data.pos
	burst(pos, Color3.fromRGB(150, 220, 255), 8, 14, 0.6)
	Effects.Sound("tick", 0.6, 0.6, pos)
end

function Effects.OnShieldBreak(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root then
		burst(root.Position, Color3.fromRGB(255, 255, 255), 40, 35, 1.4)
		ring(root.Position, Color3.fromRGB(255, 80, 80), 2, 18, 0.5, false)
		popText(root.Position + Vector3.new(0, 4, 0), "SHIELD BREAK!", Color3.fromRGB(255, 90, 90), 30)
		Effects.Sound("boom", 0.4, 1.3, root.Position)
	end
	if Effects.CameraRig then Effects.CameraRig.Shake(1.2, 0.4) end
end

function Effects.OnParry(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	if model then
		flash(model, Color3.fromRGB(120, 255, 255), 0.4)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			popText(root.Position + Vector3.new(0, 4, 0), "PARRY!", Color3.fromRGB(120, 255, 255), 34)
			ring(root.Position, Color3.fromRGB(120, 255, 255), 2, 14, 0.35, false)
		end
	end
	Effects.Sound("tick", 0.9, 1.7)
end

function Effects.OnCounter(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	if model then
		flash(model, Color3.fromRGB(200, 240, 255), 0.4)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			popText(root.Position + Vector3.new(0, 4, 0), "COUNTER!", Color3.fromRGB(160, 230, 255), 34)
			burst(root.Position, Color3.fromRGB(180, 240, 255), 30, 30, 1)
		end
	end
	Effects.Sound("tick", 0.9, 1.3)
end

function Effects.OnGrab(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.v)
	if model then flash(model, Color3.fromRGB(255, 160, 230), 0.25) end
	if data.pos then
		ring(data.pos, Color3.fromRGB(255, 160, 230), 1, 6, 0.2, false)
		burst(data.pos, Color3.fromRGB(255, 200, 240), 10, 12, 0.6)
	end
	Effects.Sound("hit", 0.45, 1.8, data.pos)
end

function Effects.OnPummel(data)
	local pos = data.pos
	burst(pos, Color3.fromRGB(255, 245, 200), 6, 12, 0.5)
	popText(pos + Vector3.new(0, 2, 0), string.format("%d%%", math.max(1, math.floor(data.dmg + 0.5))), Color3.fromRGB(255, 245, 200), 20)
	local victim = Effects.ModelFor and Effects.ModelFor(data.v)
	if victim then flash(victim, Color3.new(1, 1, 1), 0.12) end
	Effects.Sound("hit", 0.4, 1.6, pos)
	if Effects.CameraRig then Effects.CameraRig.Shake(0.15, 0.1) end
end

function Effects.OnKO(data)
	local pos = data.pos
	local center = data.center
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	local color = Color3.fromRGB(255, 255, 255)
	if model then
		local def = Fighters.Get(model:GetAttribute("FighterKey"))
		color = def.Color
	end
	local stage = Config.GetStage()
	local b = stage.Blast
	local clamped = Vector3.new(math.clamp(pos.X, b.Left + 2, b.Right - 2), math.clamp(pos.Y, b.Bottom + 2, b.Top - 2), stage.Z)
	local dir = (center - clamped)
	dir = dir.Magnitude > 0 and dir.Unit or Vector3.yAxis
	-- the classic KO streak: a huge colored beam from the blast zone back toward the stage
	local len = 70
	local beam = part({
		Size = Vector3.new(len, 7, 7),
		CFrame = CFrame.lookAt(clamped + dir * len / 2, clamped + dir * len) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Transparency = 0.05,
	})
	tween(beam, 0.9, { Size = Vector3.new(len * 1.2, 0.2, 0.2), Transparency = 1 }, Enum.EasingStyle.Quint)
	Debris:AddItem(beam, 1)
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, CFrame = CFrame.new(clamped), Color = Color3.new(1, 1, 1) })
	tween(ball, 0.5, { Size = Vector3.one * 34, Transparency = 1 })
	Debris:AddItem(ball, 0.6)
	ring(clamped, color, 4, 60, 0.7, false)
	burst(clamped, color, 60, 70, 3)
	local ex = Instance.new("Explosion")
	ex.Position = clamped
	ex.BlastPressure = 0
	ex.BlastRadius = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = folder
	Effects.Sound("boom", 1, 0.85)
	if Effects.CameraRig then Effects.CameraRig.Shake(3.5, 0.6) end
end

function Effects.OnShockwave(data)
	local color = FX_COLORS[data.fx] or FX_COLORS.heavy
	local pos = data.pos
	ring(pos + Vector3.new(0, 0.5, 0), color, 2, data.width * 1.3, 0.4, true)
	burst(pos, Color3.fromRGB(200, 190, 170), 25, 25, 1.6, "rbxasset://textures/particles/smoke_main.dds")
	Effects.Sound("boom", 0.45, 1.2, pos)
	if Effects.CameraRig then Effects.CameraRig.Shake(1.2, 0.3) end
end

function Effects.OnFx(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if data.kind == "airjump" then
		local def = Fighters.Get(model:GetAttribute("FighterKey"))
		ring(root.Position - Vector3.new(0, 3, 0), def.Accent, 1.5, 6, 0.3, true)
		Effects.Sound("jump", 0.35, 1.25, root.Position)
	end
end

-- Move-specific flourishes
function Effects.OnMove(data)
	local model = Effects.ModelFor and Effects.ModelFor(data.id)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local def = Fighters.Get(model:GetAttribute("FighterKey"))
	local moves = require(Smash.Moves).Get(def.Key)
	local move = moves[data.key]
	if not move then return end
	if move.hits or move.projectile then
		Effects.Sound("swing", 0.25, 2.2 + math.random() * 0.3, root.Position)
	end
	if move.fx == "blink" then
		burst(root.Position, def.Color, 25, 20, 1)
		task.delay((move.teleport and move.teleport.t or 0.15) + 0.03, function()
			if root.Parent then burst(root.Position, def.Accent, 25, 20, 1) end
		end)
	elseif move.fx == "thunderbolt" then
		task.delay(0.2, function()
			if not root.Parent then return end
			local top = root.Position + Vector3.new(0, 45, 0)
			local prevPt = top
			for i = 1, 7 do
				local pt = top:Lerp(root.Position, i / 7) + Vector3.new((math.random() - 0.5) * 4, 0, 0)
				local seg = part({
					Size = Vector3.new(0.6, 0.6, (pt - prevPt).Magnitude),
					CFrame = CFrame.lookAt((prevPt + pt) / 2, pt),
					Color = Color3.fromRGB(255, 250, 150),
				})
				tween(seg, 0.35, { Transparency = 1 })
				Debris:AddItem(seg, 0.4)
				prevPt = pt
			end
			burst(root.Position, Color3.fromRGB(255, 240, 60), 40, 40, 1.4)
			ring(root.Position, Color3.fromRGB(255, 240, 60), 3, 20, 0.35, false)
			Effects.Sound("boom", 0.5, 1.8, root.Position)
			if Effects.CameraRig then Effects.CameraRig.Shake(0.9, 0.25) end
		end)
	elseif move.fx == "star" then
		local star = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 1.2, 3.4), Color = Color3.fromRGB(255, 240, 120) })
		local light = Instance.new("PointLight")
		light.Color = star.Color
		light.Range = 12
		light.Parent = star
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not root.Parent or os.clock() - t0 > move.dur then
				conn:Disconnect()
				star:Destroy()
				return
			end
			star.CFrame = CFrame.new(root.Position - Vector3.new(0, 3.2 * (def.Scale or 1), 0)) * CFrame.Angles(0, os.clock() * 8, 0)
		end)
	elseif move.fx == "barrier" then
		local s = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = root.CFrame, Color = def.Accent, Material = Enum.Material.ForceField, Transparency = 0 })
		tween(s, 0.12, { Size = Vector3.one * 7 * (def.Scale or 1) })
		task.delay(0.45, function() tween(s, 0.15, { Transparency = 1 }) end)
		Debris:AddItem(s, 0.65)
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not s.Parent or not root.Parent then conn:Disconnect() return end
			s.CFrame = root.CFrame
		end)
	end
end

-- Projectiles ------------------------------------------------------------------------------------
local projectiles = {}

local function projectileVisual(data)
	local ownerModel = Effects.ModelFor and Effects.ModelFor(data.owner)
	local def = ownerModel and Fighters.Get(ownerModel:GetAttribute("FighterKey")) or Fighters.List[1]
	local size = data.size
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(data.pos), Color = def.Color })
	local style = data.style
	if style == "shuriken" then
		p.Shape = Enum.PartType.Block
		p.Size = Vector3.new(size * 1.3, size * 1.3, 0.2)
		p.Color = Color3.fromRGB(200, 245, 255)
	elseif style == "vortex" then
		p.Material = Enum.Material.ForceField
		p.Color = def.Accent
	elseif style == "orb" then
		p.Material = Enum.Material.ForceField
		p.Color = Color3.fromRGB(255, 240, 80)
	elseif style == "star" then
		p.Color = Color3.fromRGB(255, 230, 120)
	end
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 10
	light.Brightness = 2
	light.Parent = p
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = style == "fireball" and "rbxasset://textures/particles/fire_main.dds" or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(p.Color, def.Accent)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.8), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.2, 0.35)
	pe.Rate = 60
	pe.Speed = NumberRange.new(0.5, 2)
	pe.Parent = p
	return p
end

function Effects.OnProjectile(data)
	if data.op == "spawn" then
		projectiles[data.id] = { part = projectileVisual(data), pos = data.pos, vel = data.vel, born = os.clock(), life = data.life or 3, style = data.style }
	elseif data.op == "destroy" then
		local pr = projectiles[data.id]
		if pr then
			projectiles[data.id] = nil
			if data.burst then burst(data.pos, pr.part.Color, 16, 20, 1) end
			pr.part:Destroy()
		end
	elseif data.op == "reflect" or data.op == "sync" then
		local pr = projectiles[data.id]
		if pr then
			pr.pos = data.pos
			pr.vel = data.vel
			if data.op == "reflect" then
				burst(data.pos, Color3.new(1, 1, 1), 14, 18, 0.8)
				Effects.Sound("tick", 0.8, 1.9, data.pos)
			end
		end
	end
end

-- Persistent per-fighter visuals: shield bubble, name tag, revival platform, respawn flashing -------
local visuals = {}

local function buildVisuals(model)
	local key = model:GetAttribute("FighterKey")
	if not key or visuals[model] then return end
	local def = Fighters.Get(key)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	local head = model:FindFirstChild("Head")
	if not root then return end
	local v = { def = def }

	local shield = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Color = def.Color, Material = Enum.Material.ForceField, Transparency = 1 })
	v.shield = shield

	local plat = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7, 7), Color = def.Accent, Transparency = 1 })
	v.platform = plat

	local slot = model:GetAttribute("Slot") or 1
	local isCPU = model:GetAttribute("IsCPU")
	local tagColor = isCPU and Config.CPUColor or (Config.SlotColors[slot] or Color3.new(1, 1, 1))
	local bb = Instance.new("BillboardGui")
	bb.Name = "SmashTag"
	bb.Size = UDim2.fromOffset(120, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4 * (def.Scale or 1), 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head or root
	bb.Parent = folder
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.TextSize = 20
	lbl.TextColor3 = tagColor
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = isCPU and "CPU" or ("P" .. slot)
	lbl.Parent = bb
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 0, 14)
	arrow.Position = UDim2.fromOffset(0, 18)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 14
	arrow.TextColor3 = tagColor
	arrow.Text = "▼"
	arrow.Parent = bb
	v.tag = bb
	visuals[model] = v
end

local function clearVisuals(model)
	local v = visuals[model]
	if not v then return end
	visuals[model] = nil
	v.shield:Destroy()
	v.platform:Destroy()
	v.tag:Destroy()
end

function Effects.Init()
	for _, m in ipairs(CollectionService:GetTagged("SmashFighter")) do task.spawn(buildVisuals, m) end
	CollectionService:GetInstanceAddedSignal("SmashFighter"):Connect(function(m)
		task.delay(0.25, function()
			if m.Parent then buildVisuals(m) end
		end)
	end)
	CollectionService:GetInstanceRemovedSignal("SmashFighter"):Connect(clearVisuals)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for model, v in pairs(visuals) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if not model.Parent or not root then
				clearVisuals(model)
				continue
			end
			local s = v.def.Scale or 1
			-- shield bubble shrinks as it takes damage
			if model:GetAttribute("Shielding") then
				local hp = (model:GetAttribute("ShieldHP") or Config.ShieldMax) / Config.ShieldMax
				local size = (2.5 + 5 * hp) * s
				v.shield.Size = Vector3.one * size
				v.shield.CFrame = CFrame.new(root.Position + Vector3.new(0, -0.3, 0))
				v.shield.Transparency = 0.1
				v.shield.Color = v.def.Color:Lerp(Color3.fromRGB(255, 60, 60), 1 - hp)
			else
				v.shield.Transparency = 1
				v.shield.CFrame = CFrame.new(0, -1000, 0)
			end
			-- revival platform
			if model:GetAttribute("Reviving") then
				v.platform.Transparency = 0.2
				v.platform.CFrame = CFrame.new(root.Position - Vector3.new(0, 3.2 * s, 0)) * CFrame.Angles(0, 0, math.rad(90))
			else
				v.platform.Transparency = 1
				v.platform.CFrame = CFrame.new(0, -1000, 0)
			end
			-- respawn invincibility: flash white
			local inv = model:GetAttribute("InvincibleUntil")
			local flashing = inv and serverNow < inv
			local alpha = flashing and (math.sin(t * 30) > 0 and 0.45 or 0) or 0
			if alpha ~= (v.alpha or 0) then
				v.alpha = alpha
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
						d.LocalTransparencyModifier = alpha
					end
				end
			end
			v.tag.Enabled = not model:GetAttribute("Eliminated") and root.Position.Y < Config.GetStage().Blast.Top + 20
		end
		-- projectiles
		for id, pr in pairs(projectiles) do
			if t - pr.born > pr.life + 0.5 then
				pr.part:Destroy()
				projectiles[id] = nil
			else
				pr.pos += pr.vel * dt
				local spin = pr.style == "shuriken" and CFrame.Angles(0, 0, t * 25) or CFrame.Angles(t * 3, t * 4, 0)
				pr.part.CFrame = CFrame.new(pr.pos) * spin
			end
		end
	end)
end

return Effects
