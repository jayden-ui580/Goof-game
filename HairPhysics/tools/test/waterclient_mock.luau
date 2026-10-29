-- Runs the real WaterServer + WaterClient scripts together against the real arena, with stub
-- engine services, and checks the tap stream, waterfall and foam behave.
-- usage (from the HairPhysics folder): lune run tools/test/waterclient_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local V3, CF = roblox.Vector3, roblox.CFrame

local arena = luau.load(fs.readFile("tools/arena.luau"), { injectGlobals = true })()()
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	function s:Wait() end
	return s
end
local heartbeat, render = signal(), signal()
local clientEvent = signal()
local terrain = { WriteVoxelChannels = function() end }
local remote = { Name = "WaterState", FireAllClients = function(_, b) clientEvent:Fire(b) end, OnClientEvent = clientEvent }
local fxRoot = roblox.Instance.new("Folder")
local workspace = {
	Terrain = terrain,
	WaitForChild = function(_, n) return n == "TestArena" and arena or nil end,
	Raycast = function(_, from, dir, params) assert(params.IgnoreWater, "raycast should ignore water"); return { Position = V3.new(from.X, 0, from.Z) } end,
	BulkMoveTo = function(_, parts, cfs) for i, p in parts do p.CFrame = cfs[i] end end,
}
local clock = 0
local base = {
	Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, Region3 = roblox.Region3,
	ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange, Vector2 = roblox.Vector2,
	RaycastParams = { new = function() return {} end },
	warn = function(...) print("WARN", ...) end, print = print, typeof = typeof, buffer = buffer, bit32 = bit32,
	os = { clock = function() return clock end },
	Random = { new = function() local r = { s = 7 }; function r:NextNumber(a, b) a = a or 0; b = b or 1; self.s = (self.s * 1103515245 + 12345) % 2147483648; return a + (b - a) * self.s / 2147483648 end; return r end },
}
local function newEnv(extra)
	local e = table.clone(base)
	for k, v in extra do e[k] = v end
	return e
end
local modules = {}
modules.WaterConfig = luau.load(fs.readFile("src/ReplicatedStorage/WaterConfig.luau"), { environment = newEnv({}) })()
modules.WaterSim = luau.load(fs.readFile("src/ReplicatedStorage/WaterSim.luau"), { environment = newEnv({}) })()
local replicated = {
	FindFirstChild = function(_, n) return n == "WaterState" and remote or nil end,
	WaitForChild = function(_, n) if n == "WaterState" then return remote end return { Name = n } end,
}
local game = { GetService = function(_, n)
	if n == "ReplicatedStorage" then return replicated end
	if n == "RunService" then return { Heartbeat = heartbeat, RenderStepped = render } end
	if n == "Workspace" then return workspace end
end }
local req = function(m) return modules[m.Name] end
local instanceStub = { new = function(cls)
	local inst = roblox.Instance.new(cls)
	return inst
end }
luau.load(fs.readFile("src/ServerScriptService/WaterServer.server.luau"), { environment = newEnv({ game = game, require = req, Instance = instanceStub }) })()
-- the client parents its FX folder to Workspace; give it a real instance to hold children
local clientWorkspace = setmetatable({}, { __index = workspace })
local folderParented
local clientInstance = { new = function(cls)
	local inst = roblox.Instance.new(cls)
	if cls == "Folder" then folderParented = inst end
	return inst
end }
local clientGame = { GetService = function(_, n)
	if n == "Workspace" then return clientWorkspace end
	return game:GetService(n)
end }
-- Folder.Parent = Workspace stub: Lune instances can't be parented to a table, so intercept
local src = fs.readFile("src/StarterPlayerScripts/WaterClient.client.luau"):gsub("fx%.Parent = Workspace", "-- (parent skipped in test)")
luau.load(src, { environment = newEnv({ game = clientGame, require = req, Instance = clientInstance }) })()
local fx = folderParented
local stream = fx:FindFirstChild("TapStream")
local waterfall = fx:FindFirstChild("Waterfall")
local function visibleFoam()
	local n = 0
	for _, p in fx:GetChildren() do if p.Name == "Foam" and p.Transparency < 0.99 then n += 1 end end
	return n
end
local gate = arena:FindFirstChild("Gate", true)
local closedY = gate.CFrame.Position.Y
local function run(seconds, gateOpen)
	local dt = 1 / 60
	for _ = 1, math.floor(seconds / dt) do
		clock += dt
		if gateOpen ~= nil then
			local y = gate.CFrame.Position.Y - closedY
			local goal = gateOpen and (gate.Size.Y + 0.1) or 0
			gate.CFrame = gate.CFrame + V3.new(0, math.clamp(goal - y, -dt * 3.4, dt * 3.4), 0)
		end
		heartbeat:Fire(dt)
		render:Fire(dt)
	end
end
local function show(tag)
	print(("%-20s stream: len %5.2f transp %.2f bottom %6.2f | waterfall: len %5.2f transp %.2f | foam visible %d | level %.2f"):format(
		tag, stream.Size.X, stream.Transparency, stream.CFrame.Position.Y - stream.Size.X / 2,
		waterfall.Size.Y, waterfall.Transparency, visibleFoam(), arena:GetAttribute("WaterLevel")))
end
run(0.15); show("0.15s (front falling)")
run(1); show("1.15s")
run(20); show("21s filling")
run(35); show("56s full")
run(2); show("58s tap tail gone")
arena:SetAttribute("GateOpen", true)
run(1.5, true); show("gate +1.5s")
run(10, true); show("gate +11.5s")
local wf = waterfall.CFrame
print("waterfall centre", wf.Position, "faces outward along", wf.LookVector, "width axis", wf.RightVector)
run(80, true); show("gate +91s drained")
