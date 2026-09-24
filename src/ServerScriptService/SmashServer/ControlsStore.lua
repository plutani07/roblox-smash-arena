-- Remembers each player's remapped controls between visits (DataStore).
-- In a place that isn't published, or in Studio without API access, controls still work for the
-- session; they just aren't saved.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ControlsStore = {}

local ACTIONS = {
	jump = true, attack = true, special = true, smash = true, shield = true,
	taunt = true, left = true, right = true, up = true, down = true,
}

local store, storeError
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("SmashControls_v1")
	end)
	if ok then store = result else storeError = result end
end

local cache = {}      -- player -> cleaned data
local dirty = {}      -- player -> needs saving
local saveToken = {}  -- player -> latest pending save
local warned = false

local function warnOnce(err)
	if warned then return end
	warned = true
	warn("[Smash] Remapped controls can't be saved between sessions right now:", tostring(err),
		"- in Studio, turn on Game Settings > Security > Enable Studio Access to API Services (the place must be published).")
end

-- Only keep what a client could legitimately send
local function clean(data)
	if type(data) ~= "table" then return nil end
	local out = { v = 1, tapJump = data.tapJump == true, rsSmash = data.rsSmash ~= false }
	for _, device in ipairs({ "keyboard", "gamepad" }) do
		local src = data[device]
		local dst = {}
		if type(src) == "table" then
			local count = 0
			for action, list in pairs(src) do
				count += 1
				if count > 20 then break end
				if ACTIONS[action] and type(list) == "table" then
					local keys = {}
					for i = 1, math.min(#list, 4) do
						local k = list[i]
						if type(k) == "string" and #k <= 24 and string.match(k, "^%w+$") then
							table.insert(keys, k)
						end
					end
					dst[action] = keys
				end
			end
		end
		out[device] = dst
	end
	return out
end

local function keyFor(player)
	return "u" .. player.UserId
end

function ControlsStore.Load(player)
	if cache[player] then return cache[player] end
	if not store then
		warnOnce(storeError)
		return nil
	end
	local ok, data = pcall(function()
		return store:GetAsync(keyFor(player))
	end)
	if not ok then
		warnOnce(data)
		return nil
	end
	data = clean(data)
	if data and player.Parent then
		cache[player] = data
	end
	return data
end

local function flush(player)
	if not dirty[player] or not store then return end
	dirty[player] = nil
	local data = cache[player]
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), data)
	end)
	if not ok then warnOnce(err) end
end

-- Saves a few seconds after the last change so remapping many buttons is one write
function ControlsStore.Save(player, data)
	data = clean(data)
	if not data then return end
	cache[player] = data
	dirty[player] = true
	local token = (saveToken[player] or 0) + 1
	saveToken[player] = token
	task.delay(6, function()
		if saveToken[player] == token then flush(player) end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	flush(player)
	cache[player] = nil
	dirty[player] = nil
	saveToken[player] = nil
end)

game:BindToClose(function()
	for player in pairs(dirty) do
		flush(player)
	end
end)

return ControlsStore
