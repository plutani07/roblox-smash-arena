-- Global tunables for the platform fighter. Everything that "feels" like Smash lives here.
local Config = {}

-- World ------------------------------------------------------------------
Config.Gravity = 160            -- workspace gravity while the game runs
Config.StageModelName = "SmashStage"

-- Blast zones, measured from the main platform (studs)
Config.BlastSide = 64           -- past the ledge
Config.BlastTop = 88            -- above the main platform surface
Config.BlastBottom = 58         -- below the main platform surface

-- Knockback (Smash-style formula, see Combat.computeKnockback) -----------
Config.KnockbackToSpeed = 0.72  -- knockback units -> studs/second
Config.HitstunPerKnockback = 1 / 140
Config.MinHitstun = 0.12
Config.TumbleThreshold = 70     -- knockback above this puts the victim into tumble (launch smoke, spin)
Config.LaunchDecay = 42         -- studs/s^2 of horizontal slowdown while launched
Config.TumbleGravity = 0.85     -- gravity multiplier while launched
Config.DIAngle = 14             -- max degrees a victim can steer their launch

-- Hitlag (freeze frames on hit): seconds = (damage * a + b) / 60
Config.HitlagA = 0.35
Config.HitlagB = 3
Config.HitlagMax = 0.22

-- Shield / dodge ----------------------------------------------------------
Config.ShieldMax = 50
Config.ShieldDecay = 8          -- per second while held
Config.ShieldRegen = 7          -- per second while released
Config.ShieldDamageMult = 1.2
Config.ParryWindow = 0.1        -- seconds after raising shield that count as a parry
Config.ShieldBreakStun = 2.4

Config.SpotDodge = { Duration = 0.36, IntangibleFrom = 0.04, IntangibleTo = 0.3 }
Config.Roll = { Duration = 0.44, Distance = 15, IntangibleFrom = 0.04, IntangibleTo = 0.34 }
Config.AirDodge = { Duration = 0.36, Speed = 44, BurstTime = 0.14, IntangibleFrom = 0.02, IntangibleTo = 0.28 }

-- Ledges ------------------------------------------------------------------
Config.LedgeGrabIntangible = 0.6
Config.LedgeMaxHang = 5
Config.LedgeRegrabCooldown = 0.7

-- Match -------------------------------------------------------------------
Config.DefaultStocks = 3
Config.MaxStocks = 5
Config.MatchTime = 300          -- seconds
Config.MaxFighters = 4          -- CPUs fill up to this many
Config.MaxCPUs = 3
Config.RespawnDelay = 1.6
Config.RevivalMaxTime = 3
Config.RespawnInvincible = 2
Config.LobbyRespawnDelay = 1
Config.ResultsTime = 7

-- Slot colors (P1 red, P2 blue, P3 yellow, P4 green, then more)
Config.SlotColors = {
	Color3.fromRGB(235, 64, 52),
	Color3.fromRGB(52, 120, 235),
	Color3.fromRGB(245, 200, 40),
	Color3.fromRGB(60, 190, 90),
	Color3.fromRGB(230, 120, 30),
	Color3.fromRGB(40, 200, 200),
	Color3.fromRGB(200, 90, 220),
	Color3.fromRGB(240, 110, 160),
}
Config.CPUColor = Color3.fromRGB(150, 150, 160)

Config.ShowHitboxes = false     -- set true to see hitboxes while testing

-- Stage helpers ------------------------------------------------------------
local cachedStage
function Config.GetStage()
	if cachedStage and cachedStage.Main and cachedStage.Main.Parent then
		return cachedStage
	end
	local model = workspace:FindFirstChild(Config.StageModelName) or workspace:WaitForChild(Config.StageModelName)
	local main = model:WaitForChild("Main")
	local top = main.Position.Y + main.Size.Y / 2
	local left = main.Position.X - main.Size.X / 2
	local right = main.Position.X + main.Size.X / 2
	local platforms = {}
	local platFolder = model:FindFirstChild("Platforms")
	if platFolder then
		for _, p in ipairs(platFolder:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(platforms, p)
			end
		end
		table.sort(platforms, function(a, b) return a.Name < b.Name end)
	end
	local spawns = {}
	local spawnFolder = model:FindFirstChild("Spawns")
	if spawnFolder then
		for _, s in ipairs(spawnFolder:GetChildren()) do
			if s:IsA("BasePart") then
				table.insert(spawns, s)
			end
		end
		table.sort(spawns, function(a, b) return a.Name < b.Name end)
	end
	cachedStage = {
		Model = model,
		Main = main,
		Top = top,
		Left = left,
		Right = right,
		CenterX = (left + right) / 2,
		Z = main.Position.Z,
		Platforms = platforms,
		Spawns = spawns,
		Blast = {
			Left = left - Config.BlastSide,
			Right = right + Config.BlastSide,
			Top = top + Config.BlastTop,
			Bottom = top - Config.BlastBottom,
		},
	}
	return cachedStage
end

return Config
