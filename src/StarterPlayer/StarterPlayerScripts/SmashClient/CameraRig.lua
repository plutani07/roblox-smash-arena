-- Smash-style 2.5D camera: frames every fighter, zooms with their spread, shakes on big hits.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Smash"):WaitForChild("Config"))

local CameraRig = {}

local shakeAmount = 0
local shakeTime = 0
local focusModel = nil
local center, dist

function CameraRig.Shake(amount, duration)
	shakeAmount = math.max(shakeAmount, amount)
	shakeTime = math.max(shakeTime, duration or 0.25)
end

function CameraRig.Focus(model)
	focusModel = model
end

local function fighterPoints(stage)
	local pts = {}
	local b = stage.Blast
	for _, m in ipairs(CollectionService:GetTagged("SmashFighter")) do
		local root = m:FindFirstChild("HumanoidRootPart")
		if root and m.Parent and not m:GetAttribute("Eliminated") then
			local p = root.Position
			-- skip fighters parked far above the stage after a KO
			if p.Y < b.Top + 30 then
				table.insert(pts, Vector3.new(math.clamp(p.X, b.Left + 8, b.Right - 8), math.clamp(p.Y, b.Bottom + 6, b.Top - 6), stage.Z))
			end
		end
	end
	return pts
end

function CameraRig.Init()
	local cam = workspace.CurrentCamera
	local stage = Config.GetStage()
	center = Vector3.new(stage.CenterX, stage.Top + 6, stage.Z)
	dist = 60
	RunService:BindToRenderStep("SmashCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 40
		local wantCenter, wantDist
		if focusModel and focusModel.Parent and focusModel:FindFirstChild("HumanoidRootPart") then
			local p = focusModel.HumanoidRootPart.Position
			wantCenter = Vector3.new(p.X, p.Y + 1, stage.Z)
			wantDist = 17
		else
			local pts = fighterPoints(stage)
			if #pts == 0 then
				table.insert(pts, Vector3.new(stage.CenterX, stage.Top, stage.Z))
			end
			local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(pts) do
				minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
				minY = math.min(minY, p.Y); maxY = math.max(maxY, p.Y)
			end
			-- always keep a good chunk of the stage in view
			minX = math.min(minX, stage.CenterX - 16); maxX = math.max(maxX, stage.CenterX + 16)
			minY = math.min(minY, stage.Top - 4)
			minX -= 10; maxX += 10; maxY += 9; minY -= 5
			wantCenter = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2 + 1, stage.Z)
			local vp = cam.ViewportSize
			local aspect = vp.X / math.max(vp.Y, 1)
			local vfov = math.rad(cam.FieldOfView)
			local hfov = 2 * math.atan(math.tan(vfov / 2) * aspect)
			local needW = (maxX - minX) / 2 / math.tan(hfov / 2)
			local needH = (maxY - minY) / 2 / math.tan(vfov / 2)
			wantDist = math.clamp(math.max(needW, needH), 42, 150)
		end
		local a = 1 - math.exp(-dt * 4.5)
		center = center:Lerp(wantCenter, a)
		dist += (wantDist - dist) * (1 - math.exp(-dt * 2.5))
		local shake = Vector3.zero
		if shakeTime > 0 then
			shakeTime -= dt
			local s = shakeAmount * math.clamp(shakeTime / 0.25, 0, 1)
			shake = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			if shakeTime <= 0 then shakeAmount = 0 end
		end
		local eye = center + Vector3.new(0, 3 + dist * 0.07, dist) + shake
		cam.CFrame = CFrame.lookAt(eye, center + Vector3.new(0, 1, 0) + shake * 0.5)
	end)
end

return CameraRig
