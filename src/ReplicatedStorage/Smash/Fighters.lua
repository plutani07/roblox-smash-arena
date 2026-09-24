-- The roster. Each fighter has stats, a look (colors + cosmetic parts) and a moveset
-- (normals are shared templates tuned by Power/Speed; specials are unique, see Moves).
local Fighters = {}

local rgb = Color3.fromRGB

-- Cosmetic part spec:
-- { On = body part, Shape = "Block"|"Ball"|"Cylinder"|"Wedge", Size = Vector3, Offset = CFrame,
--   Color = Color3, Material = Enum.Material, Transparency = number }
-- Offsets are relative to the body part and scale with the fighter.

Fighters.List = {
	{
		Key = "Blaze",
		Name = "BLAZE",
		Title = "The Blazing Brawler",
		Description = "A hot-headed street fighter with burning fists. Great all-rounder with a killer uppercut.",
		Color = rgb(255, 92, 38),
		Accent = rgb(255, 204, 64),
		Element = "fire",
		Scale = 1.0,
		Stats = {
			Weight = 100, RunSpeed = 27, AirSpeed = 22, JumpHeight = 15, AirJumps = 1,
			Gravity = 1.0, FallSpeed = 70, FastFall = 105, Power = 1.0, AttackSpeed = 1.0,
		},
		Ratings = { Speed = 3, Power = 4, Weight = 3, Recovery = 4 },
		Body = {
			Head = rgb(234, 184, 146), Torso = rgb(200, 40, 30), Arms = rgb(234, 184, 146),
			Hands = rgb(60, 30, 25), Legs = rgb(40, 36, 44), Feet = rgb(25, 22, 28),
		},
		Cosmetics = {
			-- headband + trailing tails
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.3, 0.28, 1.3), Offset = CFrame.new(0, 0.28, 0), Color = rgb(255, 204, 64), Material = Enum.Material.SmoothPlastic },
			{ On = "Head", Shape = "Block", Size = Vector3.new(0.18, 0.2, 1.1), Offset = CFrame.new(0.25, 0.2, 0.95) * CFrame.Angles(math.rad(-25), 0, 0), Color = rgb(255, 204, 64), Material = Enum.Material.SmoothPlastic },
			{ On = "Head", Shape = "Block", Size = Vector3.new(0.18, 0.2, 0.9), Offset = CFrame.new(-0.15, 0.1, 0.85) * CFrame.Angles(math.rad(-40), 0, 0), Color = rgb(255, 204, 64), Material = Enum.Material.SmoothPlastic },
			-- spiky red hair
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(1.25, 0.6, 1.2), Offset = CFrame.new(0, 0.72, 0.05), Color = rgb(170, 20, 20), Material = Enum.Material.SmoothPlastic },
			-- belt
			{ On = "LowerTorso", Shape = "Block", Size = Vector3.new(2.1, 0.3, 1.15), Offset = CFrame.new(0, 0.25, 0), Color = rgb(20, 20, 20), Material = Enum.Material.Fabric },
			-- gauntlets
			{ On = "RightLowerArm", Shape = "Block", Size = Vector3.new(1.1, 0.7, 1.1), Offset = CFrame.new(0, -0.35, 0), Color = rgb(255, 120, 40), Material = Enum.Material.Metal },
			{ On = "LeftLowerArm", Shape = "Block", Size = Vector3.new(1.1, 0.7, 1.1), Offset = CFrame.new(0, -0.35, 0), Color = rgb(255, 120, 40), Material = Enum.Material.Metal },
		},
		Aura = { Hands = "Fire" },
		Specials = {
			Neutral = { Name = "Fireball", Text = "Throws a blazing fireball." },
			Side = { Name = "Flame Dash", Text = "Charges forward wrapped in fire." },
			Up = { Name = "Rising Phoenix", Text = "Spinning flame uppercut. Huge recovery." },
			Down = { Name = "Magma Slam", Text = "Slams the ground. Spikes in the air!" },
		},
	},
	{
		Key = "Frost",
		Name = "FROST",
		Title = "The Ice Ninja",
		Description = "Lightning-fast and light as snow. Triple jump, teleports and a deadly counter.",
		Color = rgb(90, 200, 255),
		Accent = rgb(230, 250, 255),
		Element = "ice",
		Scale = 0.95,
		Stats = {
			Weight = 84, RunSpeed = 33, AirSpeed = 25, JumpHeight = 14, AirJumps = 2,
			Gravity = 1.1, FallSpeed = 76, FastFall = 115, Power = 0.88, AttackSpeed = 1.15,
		},
		Ratings = { Speed = 5, Power = 2, Weight = 2, Recovery = 4 },
		Body = {
			Head = rgb(240, 225, 210), Torso = rgb(28, 40, 70), Arms = rgb(28, 40, 70),
			Hands = rgb(200, 240, 255), Legs = rgb(22, 30, 55), Feet = rgb(200, 240, 255),
		},
		Cosmetics = {
			-- ninja mask
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.28, 0.55, 1.28), Offset = CFrame.new(0, -0.3, 0), Color = rgb(20, 28, 50), Material = Enum.Material.Fabric },
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.3, 0.3, 1.3), Offset = CFrame.new(0, 0.45, 0), Color = rgb(20, 28, 50), Material = Enum.Material.Fabric },
			-- long scarf
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(1.6, 0.4, 1.3), Offset = CFrame.new(0, 0.85, 0), Color = rgb(90, 200, 255), Material = Enum.Material.Fabric },
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(0.5, 0.2, 2.2), Offset = CFrame.new(0.35, 0.7, 1.4) * CFrame.Angles(math.rad(-15), 0, 0), Color = rgb(90, 200, 255), Material = Enum.Material.Fabric },
			-- ice crystal shoulder guards
			{ On = "RightUpperArm", Shape = "Wedge", Size = Vector3.new(0.9, 0.7, 1.1), Offset = CFrame.new(0.15, 0.45, 0), Color = rgb(170, 235, 255), Material = Enum.Material.Glass, Transparency = 0.15 },
			{ On = "LeftUpperArm", Shape = "Wedge", Size = Vector3.new(0.9, 0.7, 1.1), Offset = CFrame.new(-0.15, 0.45, 0), Color = rgb(170, 235, 255), Material = Enum.Material.Glass, Transparency = 0.15 },
			-- katana on back
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(0.18, 3.2, 0.2), Offset = CFrame.new(0, 0.2, 0.65) * CFrame.Angles(0, 0, math.rad(35)), Color = rgb(200, 245, 255), Material = Enum.Material.Neon },
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(0.3, 0.9, 0.3), Offset = CFrame.new(0.85, 1.35, 0.65) * CFrame.Angles(0, 0, math.rad(35)), Color = rgb(25, 25, 30), Material = Enum.Material.SmoothPlastic },
		},
		Aura = { Hands = "Frost" },
		Specials = {
			Neutral = { Name = "Ice Shuriken", Text = "Fast shuriken that freezes briefly." },
			Side = { Name = "Blink Strike", Text = "Teleport slash through enemies." },
			Up = { Name = "Frost Warp", Text = "Warps in any direction you hold." },
			Down = { Name = "Glacier Counter", Text = "Counters any attack with a big slash." },
		},
	},
	{
		Key = "Titan",
		Name = "TITAN",
		Title = "The Iron Colossus",
		Description = "A walking fortress. Slow and heavy, but every hit is a home run. Armored smashes.",
		Color = rgb(120, 125, 140),
		Accent = rgb(255, 190, 50),
		Element = "heavy",
		Scale = 1.22,
		Stats = {
			Weight = 132, RunSpeed = 21, AirSpeed = 18, JumpHeight = 12.5, AirJumps = 1,
			Gravity = 1.15, FallSpeed = 78, FastFall = 110, Power = 1.25, AttackSpeed = 0.85,
		},
		Ratings = { Speed = 1, Power = 5, Weight = 5, Recovery = 2 },
		Body = {
			Head = rgb(95, 100, 112), Torso = rgb(75, 78, 88), Arms = rgb(95, 100, 112),
			Hands = rgb(60, 62, 70), Legs = rgb(60, 62, 70), Feet = rgb(45, 46, 52),
		},
		Cosmetics = {
			-- horned helmet
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.4, 0.75, 1.4), Offset = CFrame.new(0, 0.35, 0), Color = rgb(70, 72, 80), Material = Enum.Material.DiamondPlate },
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.3, 0.14, 0.2), Offset = CFrame.new(0, 0.05, -0.62), Color = rgb(255, 120, 30), Material = Enum.Material.Neon },
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(0.3, 1.1, 0.5), Offset = CFrame.new(0.72, 0.95, 0) * CFrame.Angles(0, 0, math.rad(-20)), Color = rgb(255, 190, 50), Material = Enum.Material.Metal },
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(0.3, 1.1, 0.5), Offset = CFrame.new(-0.72, 0.95, 0) * CFrame.Angles(0, 0, math.rad(20)), Color = rgb(255, 190, 50), Material = Enum.Material.Metal },
			-- huge pauldrons
			{ On = "RightUpperArm", Shape = "Ball", Size = Vector3.new(1.6, 1.3, 1.6), Offset = CFrame.new(0.15, 0.45, 0), Color = rgb(255, 190, 50), Material = Enum.Material.Metal },
			{ On = "LeftUpperArm", Shape = "Ball", Size = Vector3.new(1.6, 1.3, 1.6), Offset = CFrame.new(-0.15, 0.45, 0), Color = rgb(255, 190, 50), Material = Enum.Material.Metal },
			-- chest plate + belt
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(2.1, 1.4, 1.25), Offset = CFrame.new(0, 0.1, 0), Color = rgb(88, 92, 104), Material = Enum.Material.DiamondPlate },
			{ On = "UpperTorso", Shape = "Cylinder", Size = Vector3.new(0.2, 0.7, 0.7), Offset = CFrame.new(0, 0.15, -0.66) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(255, 120, 30), Material = Enum.Material.Neon },
			{ On = "LowerTorso", Shape = "Block", Size = Vector3.new(2.15, 0.45, 1.2), Offset = CFrame.new(0, 0.2, 0), Color = rgb(255, 190, 50), Material = Enum.Material.Metal },
			-- big fists
			{ On = "RightHand", Shape = "Block", Size = Vector3.new(0.9, 0.8, 0.9), Offset = CFrame.new(0, -0.1, 0), Color = rgb(70, 72, 80), Material = Enum.Material.Metal },
			{ On = "LeftHand", Shape = "Block", Size = Vector3.new(0.9, 0.8, 0.9), Offset = CFrame.new(0, -0.1, 0), Color = rgb(70, 72, 80), Material = Enum.Material.Metal },
		},
		Aura = { Hands = "Glow" },
		Specials = {
			Neutral = { Name = "Titan Punch", Text = "Hold to charge a devastating punch." },
			Side = { Name = "Iron Charge", Text = "Armored shoulder tackle." },
			Up = { Name = "Rocket Uppercut", Text = "Rocket-powered rising punch." },
			Down = { Name = "Earthquake", Text = "Stomp that sends a shockwave both ways." },
		},
	},
	{
		Key = "Volt",
		Name = "VOLT",
		Title = "The Lightning Racer",
		Description = "The fastest fighter alive. Zips around the stage and strings electric combos.",
		Color = rgb(255, 225, 40),
		Accent = rgb(30, 30, 36),
		Element = "electric",
		Scale = 0.9,
		Stats = {
			Weight = 90, RunSpeed = 36, AirSpeed = 24, JumpHeight = 16, AirJumps = 1,
			Gravity = 1.0, FallSpeed = 72, FastFall = 108, Power = 0.92, AttackSpeed = 1.2,
		},
		Ratings = { Speed = 5, Power = 3, Weight = 2, Recovery = 5 },
		Body = {
			Head = rgb(245, 205, 165), Torso = rgb(30, 30, 36), Arms = rgb(245, 205, 165),
			Hands = rgb(255, 225, 40), Legs = rgb(30, 30, 36), Feet = rgb(255, 225, 40),
		},
		Cosmetics = {
			-- spiky lightning hair
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(0.5, 0.9, 1.2), Offset = CFrame.new(0.35, 0.75, 0.1) * CFrame.Angles(0, 0, math.rad(-15)), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(0.5, 1.1, 1.2), Offset = CFrame.new(0, 0.85, 0.1), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(0.5, 0.9, 1.2), Offset = CFrame.new(-0.35, 0.75, 0.1) * CFrame.Angles(0, 0, math.rad(15)), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
			-- goggles
			{ On = "Head", Shape = "Block", Size = Vector3.new(1.3, 0.35, 1.3), Offset = CFrame.new(0, 0.2, 0), Color = rgb(25, 25, 30), Material = Enum.Material.SmoothPlastic },
			{ On = "Head", Shape = "Cylinder", Size = Vector3.new(0.12, 0.42, 0.42), Offset = CFrame.new(0.26, 0.2, -0.64) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(80, 220, 255), Material = Enum.Material.Neon },
			{ On = "Head", Shape = "Cylinder", Size = Vector3.new(0.12, 0.42, 0.42), Offset = CFrame.new(-0.26, 0.2, -0.64) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(80, 220, 255), Material = Enum.Material.Neon },
			-- lightning bolt emblem
			{ On = "UpperTorso", Shape = "Wedge", Size = Vector3.new(0.12, 0.9, 0.5), Offset = CFrame.new(0, 0.2, -0.56) * CFrame.Angles(0, math.rad(90), math.rad(20)), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
			-- racing stripes
			{ On = "RightUpperLeg", Shape = "Block", Size = Vector3.new(0.2, 1.4, 1.02), Offset = CFrame.new(0.42, 0, 0), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
			{ On = "LeftUpperLeg", Shape = "Block", Size = Vector3.new(0.2, 1.4, 1.02), Offset = CFrame.new(-0.42, 0, 0), Color = rgb(255, 225, 40), Material = Enum.Material.Neon },
		},
		Aura = { Feet = "Spark" },
		Specials = {
			Neutral = { Name = "Thunder Orb", Text = "Slow orb that zaps over and over." },
			Side = { Name = "Lightning Dash", Text = "Blitz straight through the enemy." },
			Up = { Name = "Thunder Zip", Text = "Two quick zips in the direction you hold." },
			Down = { Name = "Thunderbolt", Text = "Calls lightning down around you." },
		},
	},
	{
		Key = "Nova",
		Name = "NOVA",
		Title = "The Cosmic Mage",
		Description = "A floaty star mage who controls space. Charged star bolts and many jumps.",
		Color = rgb(170, 90, 255),
		Accent = rgb(255, 130, 220),
		Element = "cosmic",
		Scale = 1.0,
		Stats = {
			Weight = 88, RunSpeed = 23, AirSpeed = 21, JumpHeight = 12, AirJumps = 4,
			Gravity = 0.72, FallSpeed = 52, FastFall = 82, Power = 0.95, AttackSpeed = 0.95,
		},
		Ratings = { Speed = 2, Power = 3, Weight = 2, Recovery = 5 },
		Body = {
			Head = rgb(250, 225, 235), Torso = rgb(70, 30, 120), Arms = rgb(70, 30, 120),
			Hands = rgb(250, 225, 235), Legs = rgb(50, 20, 95), Feet = rgb(255, 130, 220),
		},
		Cosmetics = {
			-- wizard hat
			{ On = "Head", Shape = "Cylinder", Size = Vector3.new(0.18, 2.1, 2.1), Offset = CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(60, 25, 110), Material = Enum.Material.Fabric },
			{ On = "Head", Shape = "Wedge", Size = Vector3.new(1.1, 1.3, 1.1), Offset = CFrame.new(0, 1.25, 0.1), Color = rgb(60, 25, 110), Material = Enum.Material.Fabric },
			-- floating halo ring
			{ On = "Head", Shape = "Cylinder", Size = Vector3.new(0.1, 1.9, 1.9), Offset = CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(255, 130, 220), Material = Enum.Material.Neon, Transparency = 0.25 },
			-- star cape
			{ On = "UpperTorso", Shape = "Block", Size = Vector3.new(1.9, 2.6, 0.12), Offset = CFrame.new(0, -0.35, 0.62) * CFrame.Angles(math.rad(8), 0, 0), Color = rgb(40, 15, 80), Material = Enum.Material.Fabric },
			{ On = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.35, 0.35, 0.35), Offset = CFrame.new(0.4, -0.2, 0.7), Color = rgb(255, 240, 150), Material = Enum.Material.Neon },
			{ On = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.25, 0.25, 0.25), Offset = CFrame.new(-0.5, -0.9, 0.72), Color = rgb(255, 240, 150), Material = Enum.Material.Neon },
			{ On = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), Offset = CFrame.new(0.2, -1.4, 0.74), Color = rgb(255, 240, 150), Material = Enum.Material.Neon },
			-- robe skirt
			{ On = "LowerTorso", Shape = "Block", Size = Vector3.new(2.2, 1.2, 1.3), Offset = CFrame.new(0, -0.45, 0), Color = rgb(70, 30, 120), Material = Enum.Material.Fabric },
		},
		Aura = { Hands = "Cosmic" },
		Specials = {
			Neutral = { Name = "Star Bolt", Text = "Hold to charge a giant star blast." },
			Side = { Name = "Gravity Well", Text = "A slow vortex that drags foes in." },
			Up = { Name = "Warp Star", Text = "Rides a star high into the sky." },
			Down = { Name = "Reflect Nova", Text = "Barrier that reflects projectiles." },
		},
	},
}

Fighters.ByKey = {}
for i, def in ipairs(Fighters.List) do
	def.Index = i
	Fighters.ByKey[def.Key] = def
end

function Fighters.Get(key)
	return Fighters.ByKey[key] or Fighters.List[1]
end

return Fighters
