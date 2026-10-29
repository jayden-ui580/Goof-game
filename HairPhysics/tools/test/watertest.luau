-- Runs the real WaterSim on the arena grid: fill from the tap, then open the gate and drain.
-- usage (from the HairPhysics folder): lune run tools/test/watertest.luau [dumpPath] [overridesJson]
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local WaterSim = luau.load(fs.readFile("src/ReplicatedStorage/WaterSim.luau"))()
local dump = process.args[1]
if dump == "" then dump = nil end
local ov = process.args[2] and serde.decode("json", process.args[2]) or {}
-- defaults come from the real WaterConfig
local roblox = require("@lune/roblox")
local cfg = luau.load(fs.readFile("src/ReplicatedStorage/WaterConfig.luau"), { environment = { Color3 = roblox.Color3 } })()
for _, key in { "Gravity", "Friction", "PipeDepth", "Smoothing", "DrainSpeed", "DrainDip", "FillLevel" } do
	if ov[key] == nil then ov[key] = cfg[key] end
end
ov.Rate = ov.Rate or cfg.FillLevel * 4096 / cfg.FillSeconds

local NX, NZ = 17, 16 -- 16 interior columns + the gate column
local active = table.create(NX * NZ, false)
local sim
local function idx(i, j) return (j - 1) * NX + i end
for j = 1, NZ do for i = 1, 16 do active[idx(i, j)] = true end end
active[idx(17, 8)] = true
active[idx(17, 9)] = true
sim = WaterSim.new({ NX = NX, NZ = NZ, Active = active, Smoothing = ov.Smoothing, Gravity = ov.Gravity, Friction = ov.Friction, PipeDepth = ov.PipeDepth, DrainSpeed = ov.DrainSpeed, DrainDip = ov.DrainDip })
for _, j in { 8, 9 } do
	sim.Openness[idx(17, j)] = 0
	sim:AddDrain(idx(17, j), 4, 4)
end
-- the stream lands on the line between cells 8 and 9, near the -Z wall: spread over 2x2 cells
local taps = {}
for _, c in { { 8, 1 }, { 9, 1 }, { 8, 2 }, { 9, 2 } } do
	local s = { Index = idx(c[1], c[2]), Rate = 0 }
	table.insert(sim.Sources, s); table.insert(taps, s)
end
local tap = taps[1]
local FILL, RATE = ov.FillLevel or 10, ov.Rate or (10 * 4096 / 45)
local interior = function(k) return ((k - 1) % NX) + 1 <= 16 end

local dt, t = 1 / 30, 0
local filledAt, drainedAt, gateAt, halfAt
local maxMound, minDepth, nan = 0, 0, false
local rough = 0
local injected, drained = 0, 0
local frames = {}
local phase = "fill"
while t < 400 do
	t += dt
	local avg = sim:Volume(interior) / 4096
	if phase == "fill" then
		for _, s in taps do s.Rate = (avg < FILL and RATE or 0) / #taps end
		if avg >= FILL then phase = "settle"; filledAt = t end
	elseif phase == "settle" and t > filledAt + 8 then
		phase = "drain"; gateAt = t
	end
	if phase == "drain" then
		local f = math.clamp((t - gateAt) / 1.2, 0, 1)
		sim.Openness[idx(17, 8)] = f
		sim.Openness[idx(17, 9)] = f
		if avg < 0.01 and not drainedAt then drainedAt = t end
		if avg < 1 and not halfAt then halfAt = t end
	end
	sim:Step(dt)
	injected += sim.InflowRate * dt
	drained += (sim.OutflowRate + sim.SoakedRate) * dt
	for k = 1, sim.N do
		local d = sim.Depth[k]
		if d ~= d then nan = true end
		minDepth = math.min(minDepth, d)
	end
	if phase == "fill" and tap.Rate > 0 then
		for k = 1, sim.N do
			if interior(k) then maxMound = math.max(maxMound, sim.Depth[k] - avg) end
		end
	end
	-- zigzag check: how far each cell sits from the average of its 4 neighbours (away from the tap)
	for j = 4, NZ - 1 do
		for i = 2, 15 do
			local k = idx(i, j)
			local d = sim.Depth[k]
			if d > 0.05 then
				local nb = (sim.Depth[k - 1] + sim.Depth[k + 1] + sim.Depth[k - NX] + sim.Depth[k + NX]) / 4
				rough = math.max(rough, math.abs(d - nb) - 0.0)
			end
		end
	end
	if dump and math.floor(t * 30 + 0.5) % 15 == 0 then
		local row = { t = t, phase = phase, depth = table.clone(sim.Depth), vx = table.clone(sim.VelX), vz = table.clone(sim.VelZ), out = sim.OutflowRate }
		table.insert(frames, row)
	end
	if drainedAt and t > drainedAt + 2 then break end
end
local volNow = sim:Volume()
print(serde.encode("json", {
	fillSeconds = filledAt and math.floor(filledAt * 10) / 10,
	drainSeconds = drainedAt and gateAt and math.floor((drainedAt - gateAt) * 10) / 10,
	drainTo1StudSeconds = halfAt and gateAt and math.floor((halfAt - gateAt) * 10) / 10,
	tapMoundStuds = math.floor(maxMound * 100) / 100,
	zigzagStuds = math.floor(rough * 1000) / 1000,
	volumeError = math.floor((injected - drained - volNow) * 1000) / 1000,
	nan = nan,
	minDepth = minDepth,
}, false))
if dump then fs.writeFile(dump, serde.encode("json", frames, false)) end
