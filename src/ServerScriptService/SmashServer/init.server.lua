--[[
	SMASH SERVER
	Lobby (free play + training dummy) -> READY/3/2/1/GO -> stock match -> GAME! -> results -> lobby.
	Fighters, moves and tuning live in ReplicatedStorage.Smash (Fighters / Moves / Config).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local StarterPlayer = game:GetService("StarterPlayer")

local Smash = ReplicatedStorage:WaitForChild("Smash")
local Config = require(Smash.Config)
local Fighters = require(Smash.Fighters)

local Combat = require(script.Combat)
local Bots = require(script.Bots)
local Looks = require(script.Looks)

workspace.Gravity = Config.Gravity
Players.CharacterAutoLoads = false
StarterPlayer.LoadCharacterAppearance = false

-- Networking --------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "Action"
actionRemote.Parent = remotes
local eventRemote = Instance.new("RemoteEvent")
eventRemote.Name = "Event"
eventRemote.Parent = remotes
remotes.Parent = Smash
Combat.Event = eventRemote

local state = Instance.new("Configuration")
state.Name = "State"
state:SetAttribute("Phase", "Lobby")
state:SetAttribute("TimeLeft", Config.MatchTime)
state:SetAttribute("CPUs", 1)
state:SetAttribute("CPULevel", 2)
state:SetAttribute("Stocks", Config.DefaultStocks)
state.Parent = Smash

local function announce(text, color, duration, sub)
	eventRemote:FireAllClients("Announce", { text = text, color = color, dur = duration, sub = sub })
end

-- Collision groups ---------------------------------------------------------------------
pcall(function() PhysicsService:RegisterCollisionGroup("SmashFighters") end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("SmashFighters", "SmashFighters", false) end)

local stage = Config.GetStage()
for i, plat in ipairs(stage.Platforms) do
	local g = "SoftPlatform" .. i
	pcall(function() PhysicsService:RegisterCollisionGroup(g) end)
	plat.CollisionGroup = g
end

-- Character select previews ---------------------------------------------------------------
task.spawn(function()
	local previews = Instance.new("Folder")
	previews.Name = "Previews"
	for _, def in ipairs(Fighters.List) do
		local m = Looks.BuildPreview(def)
		if m then m.Parent = previews end
	end
	previews.Parent = Smash
end)

-- Players ----------------------------------------------------------------------------------
local selection = {}   -- player -> fighter key
local joinOrder = {}
local lobbyDummy = nil

local function playerSlot(player)
	for i, p in ipairs(joinOrder) do
		if p == player then return i end
	end
	return #joinOrder + 1
end

local function spawnPoint(i)
	local spawns = stage.Spawns
	if #spawns == 0 then
		return Vector3.new(stage.CenterX + (i - 2.5) * 12, stage.Top + 3.5, stage.Z)
	end
	local s = spawns[((i - 1) % #spawns) + 1]
	return Vector3.new(s.Position.X, stage.Top + 3.5, stage.Z)
end

local function spawnPlayer(player, pos, opts)
	opts = opts or {}
	local old = Combat.ForPlayer(player)
	if old then Combat.Unregister(old) end
	local def = Fighters.Get(selection[player])
	if not player.Parent or not pcall(function() player:LoadCharacter() end) then return nil end
	local char = player.Character
	if not char then return nil end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return nil end
	root.Anchored = true
	local facing = pos.X > stage.CenterX and -1 or 1
	char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(facing, 0, 0)))
	Looks.Apply(char, def)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "SmashFighters" end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CollisionGroup = "SmashFighters" end
	end)
	-- percent-based game: the engine should never kill anyone
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	local f = Combat.Register(char, def, {
		player = player,
		name = player.DisplayName,
		slot = opts.slot or playerSlot(player),
		inMatch = opts.inMatch,
		stocks = opts.stocks or 0,
	})
	char:SetAttribute("FighterReady", true)
	if not opts.frozen then
		Combat.Freeze(f, false)
	end
	return f
end

local function spawnDummy()
	if lobbyDummy then return end
	local def = Fighters.Get("Titan")
	lobbyDummy = Bots.Spawn(def, {
		name = "Training Dummy",
		slot = 8,
		level = 0,
		pos = Vector3.new(stage.CenterX + 12, stage.Top + 3.5, stage.Z),
		facing = -1,
		inMatch = false,
	})
end

local function removeDummy()
	if lobbyDummy then
		Bots.Remove(lobbyDummy)
		lobbyDummy = nil
	end
end

Players.PlayerAdded:Connect(function(player)
	table.insert(joinOrder, player)
	selection[player] = Fighters.List[1].Key
	if state:GetAttribute("Phase") == "Lobby" then
		task.wait(1)
		if player.Parent then
			spawnPlayer(player, spawnPoint(playerSlot(player)), { inMatch = false })
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local f = Combat.ForPlayer(player)
	if f then
		f.eliminated = true
		f.model:SetAttribute("Eliminated", true)
		Combat.Unregister(f)
	end
	local idx = table.find(joinOrder, player)
	if idx then table.remove(joinOrder, idx) end
	selection[player] = nil
end)

-- Match flow ---------------------------------------------------------------------------------
local matchFighters = {}

local function aliveCount()
	local n, last = 0, nil
	for _, f in ipairs(matchFighters) do
		if not f.eliminated and Combat.Fighters[f.id] then
			n += 1
			last = f
		end
	end
	return n, last
end

Combat.OnKO = function(f)
	local phase = state:GetAttribute("Phase")
	if phase == "Match" and f.inMatch then
		f.stocks -= 1
		f.model:SetAttribute("Stocks", f.stocks)
		if f.stocks <= 0 then
			f.eliminated = true
			f.model:SetAttribute("Eliminated", true)
			announce(string.upper(f.name) .. " IS OUT!", f.def.Color, 1.4)
			return
		end
		task.wait(Config.RespawnDelay)
		if state:GetAttribute("Phase") == "Match" and Combat.Fighters[f.id] then
			Combat.Respawn(f, true)
		end
	elseif phase == "Lobby" then
		task.wait(Config.LobbyRespawnDelay)
		if Combat.Fighters[f.id] then
			Combat.Respawn(f, true)
		end
	end
end

local function standings()
	local list = {}
	for _, f in ipairs(matchFighters) do
		table.insert(list, f)
	end
	table.sort(list, function(a, b)
		if a.eliminated ~= b.eliminated then return not a.eliminated end
		if a.stocks ~= b.stocks then return a.stocks > b.stocks end
		return a.percent < b.percent
	end)
	return list
end

local function goToLobby()
	Bots.RemoveAll()
	lobbyDummy = nil
	matchFighters = {}
	table.clear(Combat.Projectiles)
	state:SetAttribute("Phase", "Lobby")
	state:SetAttribute("TimeLeft", Config.MatchTime)
	for i, player in ipairs(joinOrder) do
		task.spawn(spawnPlayer, player, spawnPoint(i), { inMatch = false })
	end
	spawnDummy()
end

local matchRunning = false

local function runMatch()
	if matchRunning then return end
	matchRunning = true
	local players = {}
	for _, p in ipairs(joinOrder) do
		if p.Parent then table.insert(players, p) end
	end
	local cpuCount = math.clamp(state:GetAttribute("CPUs") or 0, 0, Config.MaxCPUs)
	cpuCount = math.min(cpuCount, math.max(0, Config.MaxFighters - #players))
	if #players + cpuCount < 2 then
		announce("ADD A CPU TO FIGHT!", Color3.fromRGB(255, 220, 90), 2, "Use the + next to CPUs, or invite a friend")
		matchRunning = false
		return
	end

	state:SetAttribute("Phase", "Countdown")
	removeDummy()
	Bots.RemoveAll()
	for _, f in pairs(Combat.Fighters) do
		if f.player then Combat.Unregister(f) end
	end
	local stocks = math.clamp(state:GetAttribute("Stocks") or Config.DefaultStocks, 1, Config.MaxStocks)
	local level = math.clamp(state:GetAttribute("CPULevel") or 2, 1, 3)
	matchFighters = {}

	local slot = 0
	local spawnThreads = {}
	for _, player in ipairs(players) do
		slot += 1
		local mySlot = slot
		table.insert(spawnThreads, task.spawn(function()
			local f = spawnPlayer(player, spawnPoint(mySlot), { inMatch = true, stocks = stocks, slot = mySlot, frozen = true })
			if f then table.insert(matchFighters, f) end
		end))
	end
	-- CPUs pick fighters nobody else is using when possible
	local taken = {}
	for _, p in ipairs(players) do taken[selection[p]] = true end
	local pool = {}
	for _, def in ipairs(Fighters.List) do
		if not taken[def.Key] then table.insert(pool, def) end
	end
	for i = 1, cpuCount do
		slot += 1
		local def
		if #pool > 0 then
			def = table.remove(pool, math.random(1, #pool))
		else
			def = Fighters.List[math.random(1, #Fighters.List)]
		end
		local pos = spawnPoint(slot)
		local f = Bots.Spawn(def, {
			name = "CPU " .. i, slot = slot, level = level, pos = pos,
			facing = pos.X > stage.CenterX and -1 or 1, inMatch = true, stocks = stocks, frozen = true,
		})
		if f then table.insert(matchFighters, f) end
	end

	-- wait for player characters to finish loading
	local deadline = os.clock() + 8
	while #matchFighters < #players + cpuCount and os.clock() < deadline do
		task.wait(0.1)
	end
	for _, f in ipairs(matchFighters) do Combat.Freeze(f, true) end

	announce("READY?", Color3.fromRGB(255, 255, 255), 1.1)
	task.wait(1.3)
	for _, n in ipairs({ "3", "2", "1" }) do
		announce(n, Color3.fromRGB(255, 220, 80), 0.7)
		task.wait(0.8)
	end
	announce("GO!", Color3.fromRGB(255, 80, 60), 0.9)
	for _, f in ipairs(matchFighters) do Combat.Freeze(f, false) end
	state:SetAttribute("Phase", "Match")

	local timeLeft = Config.MatchTime
	while true do
		task.wait(0.25)
		timeLeft -= 0.25
		state:SetAttribute("TimeLeft", math.max(0, math.ceil(timeLeft)))
		local alive = aliveCount()
		if alive <= 1 or timeLeft <= 0 then break end
	end

	state:SetAttribute("Phase", "Results")
	announce(timeLeft <= 0 and "TIME!" or "GAME!", Color3.fromRGB(255, 255, 255), 1.8)
	task.wait(0.35)
	for _, f in ipairs(matchFighters) do
		if Combat.Fighters[f.id] and not f.koed then Combat.Freeze(f, true) end
	end
	task.wait(1.8)

	local ranked = standings()
	local winner = ranked[1]
	local list = {}
	for i, f in ipairs(ranked) do
		table.insert(list, { id = f.id, name = f.name, key = f.def.Key, stocks = f.stocks, kos = f.koCount, falls = f.falls, place = i })
	end
	eventRemote:FireAllClients("Results", {
		winner = winner and winner.id,
		name = winner and winner.name or "NOBODY",
		key = winner and winner.def.Key,
		standings = list,
	})
	task.wait(Config.ResultsTime)
	goToLobby()
	matchRunning = false
end

-- Client requests ---------------------------------------------------------------------------
local lastFx = {}

actionRemote.OnServerEvent:Connect(function(player, kind, a, b, c)
	local f = Combat.ForPlayer(player)
	if kind == "Move" then
		if f and f.model == player.Character then
			local ok = Combat.StartMove(f, tostring(a), tonumber(b) or 0, tonumber(c) or 1)
			if not ok then
				eventRemote:FireClient(player, "MoveRejected", { key = a })
			end
		end
	elseif kind == "Charge" then
		if f then Combat.Broadcast("Charge", { id = f.id, key = tostring(a) }) end
	elseif kind == "Shield" then
		if f then Combat.SetShield(f, a == true) end
	elseif kind == "Dodge" then
		if f and (a == "spot" or a == "roll" or a == "air") then Combat.Dodge(f, a) end
	elseif kind == "Ledge" then
		if f then Combat.Ledge(f, a == true) end
	elseif kind == "LeaveRevival" then
		if f and f.reviving then Combat.EndRevival(f) end
	elseif kind == "Fx" then
		if f and os.clock() - (lastFx[player] or 0) > 0.1 then
			lastFx[player] = os.clock()
			Combat.Broadcast("Fx", { id = f.id, kind = tostring(a) })
		end
	elseif kind == "Select" then
		local key = tostring(a)
		if Fighters.ByKey[key] then
			selection[player] = key
			if state:GetAttribute("Phase") == "Lobby" then
				task.spawn(spawnPlayer, player, spawnPoint(playerSlot(player)), { inMatch = false })
			end
		end
	elseif kind == "Setting" then
		if state:GetAttribute("Phase") ~= "Lobby" then return end
		local n = tonumber(b)
		if not n then return end
		if a == "CPUs" then state:SetAttribute("CPUs", math.clamp(math.floor(n), 0, Config.MaxCPUs))
		elseif a == "CPULevel" then state:SetAttribute("CPULevel", math.clamp(math.floor(n), 1, 3))
		elseif a == "Stocks" then state:SetAttribute("Stocks", math.clamp(math.floor(n), 1, Config.MaxStocks)) end
	elseif kind == "StartMatch" then
		if state:GetAttribute("Phase") == "Lobby" then
			task.spawn(runMatch)
		end
	end
end)

Combat.Start()
Bots.Start()
spawnDummy()
for _, player in ipairs(Players:GetPlayers()) do
	if not table.find(joinOrder, player) then
		table.insert(joinOrder, player)
		selection[player] = Fighters.List[1].Key
		task.spawn(spawnPlayer, player, spawnPoint(playerSlot(player)), { inMatch = false })
	end
end
print("[Smash] server ready -", #Fighters.List, "fighters loaded")
