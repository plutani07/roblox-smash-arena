-- Turns a plain R15 rig into one of the custom fighters: proportions, body colors,
-- cosmetic parts (hair, helmets, capes, weapons...) and elemental auras.
local Looks = {}

local PART_GROUPS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
	Arms = { "RightUpperArm", "RightLowerArm", "LeftUpperArm", "LeftLowerArm" },
	Hands = { "RightHand", "LeftHand" },
	Legs = { "RightUpperLeg", "RightLowerLeg", "LeftUpperLeg", "LeftLowerLeg" },
	Feet = { "RightFoot", "LeftFoot" },
}

local function setScale(humanoid, s)
	for _, name in ipairs({ "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }) do
		local v = humanoid:FindFirstChild(name)
		if not v then
			v = Instance.new("NumberValue")
			v.Name = name
			v.Parent = humanoid
		end
		v.Value = s
	end
end

local function makePart(spec, scale)
	local p = Instance.new("Part")
	p.Name = "Cosmetic"
	local ok = pcall(function()
		p.Shape = Enum.PartType[spec.Shape or "Block"]
	end)
	if not ok then p.Shape = Enum.PartType.Block end
	p.Size = spec.Size * scale
	p.Color = spec.Color or Color3.new(1, 1, 1)
	p.Material = spec.Material or Enum.Material.SmoothPlastic
	p.Transparency = spec.Transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	return p
end

local function addAura(part, kind, def)
	if kind == "Fire" then
		local fire = Instance.new("Fire")
		fire.Size = 2.2
		fire.Heat = 3
		fire.Color = def.Color
		fire.SecondaryColor = def.Accent
		fire.Parent = part
		local light = Instance.new("PointLight")
		light.Color = def.Color
		light.Range = 7
		light.Brightness = 1.5
		light.Parent = part
	elseif kind == "Frost" or kind == "Cosmic" or kind == "Spark" then
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(def.Color, def.Accent)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.2)
		pe.Lifetime = NumberRange.new(0.3, 0.6)
		pe.Rate = kind == "Spark" and 14 or 8
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = part
		local light = Instance.new("PointLight")
		light.Color = def.Color
		light.Range = 6
		light.Brightness = 1
		light.Parent = part
	elseif kind == "Glow" then
		local light = Instance.new("PointLight")
		light.Color = def.Accent
		light.Range = 6
		light.Brightness = 1.2
		light.Parent = part
	end
end

function Looks.Apply(model, def)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local scale = def.Scale or 1

	-- strip any avatar items
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic")
			or child:IsA("BodyColors") or child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end
	local old = model:FindFirstChild("SmashCosmetics")
	if old then old:Destroy() end

	humanoid.AutomaticScalingEnabled = true
	setScale(humanoid, scale)
	task.wait() -- let the rig rescale before we attach things to it

	for group, names in pairs(PART_GROUPS) do
		local color = def.Body[group]
		if color then
			for _, n in ipairs(names) do
				local p = model:FindFirstChild(n)
				if p and p:IsA("BasePart") then
					p.Color = color
					p.Material = Enum.Material.SmoothPlastic
				end
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "SmashCosmetics"
	folder.Parent = model
	for _, spec in ipairs(def.Cosmetics or {}) do
		local on = model:FindFirstChild(spec.On)
		if on and on:IsA("BasePart") then
			local p = makePart(spec, scale)
			local off = spec.Offset or CFrame.new()
			off = CFrame.new(off.Position * scale) * off.Rotation
			p.CFrame = on.CFrame * off
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = on
			weld.Part1 = p
			weld.Parent = p
			p.Parent = folder
		end
	end

	local aura = def.Aura or {}
	if aura.Hands then
		for _, n in ipairs({ "RightHand", "LeftHand" }) do
			local p = model:FindFirstChild(n)
			if p then addAura(p, aura.Hands, def) end
		end
	end
	if aura.Feet then
		for _, n in ipairs({ "RightFoot", "LeftFoot" }) do
			local p = model:FindFirstChild(n)
			if p then addAura(p, aura.Feet, def) end
		end
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
end

-- A copy for the character select screen. Only the root is anchored so the menu can pose the
-- joints (it animates the fighter's stance and plays their taunt when picked).
function Looks.BuildPreview(def)
	local Players = game:GetService("Players")
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Smash] could not build preview for", def.Key, model)
		return nil
	end
	model.Name = def.Key
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = true end
	model:PivotTo(CFrame.new(0, 1500, 0))
	model.Parent = workspace -- scaling only runs while parented to the world
	Looks.Apply(model, def)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	return model
end

return Looks
