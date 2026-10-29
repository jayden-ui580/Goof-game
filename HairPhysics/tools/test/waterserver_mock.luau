-- Runs the real WaterServer script against the real TestArena model, with a fake Terrain that
-- records writes and a fake network. Fills, opens the gate, closes it, and checks the results.
-- usage (from the HairPhysics folder): lune run tools/test/waterserver_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local V3, CF = roblox.Vector3, roblox.CFrame

local arena = luau.load(fs.readFile("tools/arena.luau"), { injectGlobals = true })()()
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn) end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end
local heartbeat = signal()
local writes, lastLiquid, lastRegion = 0, nil, nil
local terrain = setmetatable({}, { __index = function(t, k)
	if k == "WriteVoxelChannels" then
		return function(_, region, res, channels)
			assert(res == 4, "resolution must be 4")
			writes += 1; lastLiquid = channels.LiquidOccupancy; lastRegion = region
		end
	end
	return rawget(t, k)
end, __newindex = function(t, k, v) rawset(t, k, v) end })
local packets = {}
local remote = { Name = "", FireAllClients = function(self, b) table.insert(packets, b) end }
local workspace = { Terrain = terrain, WaitForChild = function(_, n) return n == "TestArena" and arena or nil end }
local modules = {
	WaterConfig = luau.load(fs.readFile("src/ReplicatedStorage/WaterConfig.luau"), { environment = { Color3 = roblox.Color3, Vector3 = V3 } })(),
}
local env = {
	Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, Region3 = roblox.Region3,
	warn = function(...) print("WARN", ...) end, print = print, typeof = typeof,
	buffer = buffer, bit32 = bit32,
}
modules.WaterSim = luau.load(fs.readFile("src/ReplicatedStorage/WaterSim.luau"), { environment = env })()
local replicated = { FindFirstChild = function() return nil end, WaitForChild = function(_, n) return { Name = n } end }
env.game = { GetService = function(_, n)
	if n == "ReplicatedStorage" then return replicated end
	if n == "RunService" then return { Heartbeat = heartbeat } end
	if n == "Workspace" then return workspace end
end }
env.require = function(m) return modules[m.Name] end
env.Instance = { new = function(cls) if cls == "RemoteEvent" then return remote end return roblox.Instance.new(cls) end }
local clock = 0
env.os = { clock = function() return clock end }
luau.load(fs.readFile("src/ServerScriptService/WaterServer.server.luau"), { environment = env })()

local gate = arena:FindFirstChild("Gate", true)
local closedCF = gate.CFrame
local function run(seconds, gateTarget)
	local dt = 1 / 60
	for _ = 1, math.floor(seconds / dt) do
		clock += dt
		-- emulate ArenaSetup's 1.2 s gate tween
		if gateTarget ~= nil then
			local y = gate.CFrame.Position.Y - closedCF.Position.Y
			local goal = gateTarget and (gate.Size.Y + 0.1) or 0
			local move = math.clamp(goal - y, -dt * (gate.Size.Y / 1.2), dt * (gate.Size.Y / 1.2))
			gate.CFrame = gate.CFrame + V3.new(0, move, 0)
		end
		heartbeat:Fire(dt)
	end
end
local report = {}
local function snap(tag)
	local level = arena:GetAttribute("WaterLevel")
	local st = modules.WaterSim.Decode(packets[#packets])
	table.insert(report, ("%-22s level %5.2f  tap %-5s  inflow %6.0f  outflow %6.0f  terrainWrites %4d  packets %4d"):format(
		tag, level, tostring(arena:GetAttribute("TapOn")), st.Inflow, st.Outflow, writes, #packets))
end
run(5); snap("5s filling")
run(45); snap("50s")
run(10); snap("60s (should be full)")
local writesBeforeIdle = writes
run(5); snap("65s idle")
local idleWrites = writes - writesBeforeIdle
arena:SetAttribute("GateOpen", true)
run(20, true); snap("gate open +20s")
run(60, true); snap("gate open +80s")
arena:SetAttribute("GateOpen", false)
run(10, false); snap("gate shut +10s (refill)")
for _, line in report do print(line) end
print("terrain writes while full and still:", idleWrites)

-- check the terrain array: shape and a wet column
local layout = modules.WaterSim.Layout(arena)
print("grid", layout.NX, layout.NZ, "layers", layout.Layers, "origin", layout.Origin, "misaligned", layout.Misaligned)
local gateList = {}
for _, k in layout.Gates do table.insert(gateList, ("(%d,%d)"):format((k - 1) % layout.NX + 1, (k - 1) // layout.NX + 1)) end
print("gate cells", table.concat(gateList, " "), "height", layout.GateHeight)
local inl = {}
for _, e in layout.Inlet do table.insert(inl, ("(%d,%d)=%.2f"):format((e.Index - 1) % layout.NX + 1, (e.Index - 1) // layout.NX + 1, e.Weight)) end
print("tap cells", table.concat(inl, " "))
print("region", lastRegion)
print("array size", #lastLiquid, #lastLiquid[1], #lastLiquid[1][1])
local col = {}
for y = 1, #lastLiquid[1] do table.insert(col, ("%.2f"):format(lastLiquid[9][y][9])) end
print("middle column fill by layer (bottom = hidden layer in the floor):", table.concat(col, " "))
local wall = {}
for y = 1, #lastLiquid[1] do table.insert(wall, ("%.2f"):format(lastLiquid[1][y][9])) end
print("outside-wall column (should be empty):", table.concat(wall, " "))
