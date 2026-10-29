--[[
	WaterServer  (Script — lives in ServerScriptService)

	Runs the flowing water in the TestArena:
	  * the tap fills the arena to WaterConfig.FillLevel when the game starts,
	  * the water spreads, sloshes and levels out (WaterSim does the maths),
	  * when the drain gate opens (Z), water rushes out of the hole; when it shuts, the tap
	    refills the arena,
	  * the result is written into Roblox terrain water, so you get Roblox's real water look,
	    underwater view and swimming,
	  * every player gets a small flow update for drawing splashes, the waterfall and foam.

	Settings: ReplicatedStorage > WaterConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WaterConfig = require(ReplicatedStorage:WaitForChild("WaterConfig"))
local WaterSim = require(ReplicatedStorage:WaitForChild("WaterSim"))

if not WaterConfig.Enabled then
	return
end

local function complain(message: string)
	warn("[WaterServer] " .. message)
end

local arena = Workspace:WaitForChild(WaterConfig.ArenaName, 15)
if not arena then
	complain("no " .. WaterConfig.ArenaName .. " in Workspace, so there's nowhere to put water")
	return
end

local layout, why = WaterSim.Layout(arena)
if not layout then
	complain(why)
	return
end
if layout.Misaligned then
	complain(
		"the arena isn't lined up with Roblox's 4-stud terrain grid (or is turned), so the water may poke into the walls. "
			.. "Keep the arena's floor-top centre on whole multiples of 4 studs and don't rotate it."
	)
end
if #layout.Gates == 0 then
	complain("couldn't find the drain hole (a part called GateOpening in the arena) — the water won't be able to drain")
end
if #layout.Inlet == 0 then
	complain("couldn't find the tap (a part called InletMouth in the arena) — the water won't fill")
end

local C = layout.Cell
local terrain = Workspace.Terrain

-- the simulation
local active = table.create(layout.NX * layout.NZ, false)
for k, inside in layout.Interior do
	active[k] = inside
end
for _, k in layout.Gates do
	active[k] = true
end
local sim = WaterSim.new({
	NX = layout.NX,
	NZ = layout.NZ,
	Active = active,
	Gravity = WaterConfig.Gravity,
	Friction = WaterConfig.Friction,
	PipeDepth = WaterConfig.PipeDepth,
	Smoothing = WaterConfig.Smoothing,
	DrainSpeed = WaterConfig.DrainSpeed,
	DrainDip = WaterConfig.DrainDip,
})
local cap = {}
for _, k in layout.Gates do
	sim.Openness[k] = 0
	sim:AddDrain(k, C, layout.GateHeight)
	cap[k] = 0
end
local taps = {}
for _, entry in layout.Inlet do
	local source = { Index = entry.Index, Rate = 0, Weight = entry.Weight }
	table.insert(sim.Sources, source)
	table.insert(taps, source)
end
local interiorArea = layout.InteriorCount * C * C
local fullRate = WaterConfig.FillLevel * interiorArea / math.max(WaterConfig.FillSeconds, 1)
local function isInterior(k)
	return layout.Interior[k]
end

-- tell the clients how the grid is laid out
arena:SetAttribute("WaterOrigin", layout.Origin)
arena:SetAttribute("WaterGrid", Vector3.new(layout.NX, layout.Layers, layout.NZ))
arena:SetAttribute("WaterLevel", 0)
arena:SetAttribute("TapOn", false)

local stateEvent = ReplicatedStorage:FindFirstChild("WaterState")
if not stateEvent then
	stateEvent = Instance.new("RemoteEvent")
	stateEvent.Name = "WaterState"
	stateEvent.Parent = ReplicatedStorage
end

-- the water's look
if WaterConfig.ApplyWaterLook then
	terrain.WaterColor = WaterConfig.WaterColor
	terrain.WaterTransparency = WaterConfig.WaterTransparency
	terrain.WaterReflectance = WaterConfig.WaterReflectance
	terrain.WaterWaveSize = WaterConfig.WaterWaveSize
	terrain.WaterWaveSpeed = WaterConfig.WaterWaveSpeed
end

-- terrain writing: the box of 4-stud cubes covering the grid, plus one layer inside the floor
local region = Region3.new(
	layout.Origin - Vector3.new(0, C, 0),
	layout.Origin + Vector3.new(layout.NX * C, layout.Layers * C, layout.NZ * C)
)
local liquid = WaterSim.NewLiquidArray(layout, 0)
local useChannels = true
local legacyMaterials, legacyOccupancy

local function writeTerrain()
	sim:FillLiquid(layout, liquid, cap)
	if useChannels then
		local ok, err = pcall(function()
			terrain:WriteVoxelChannels(region, 4, { LiquidOccupancy = liquid })
		end)
		if ok then
			return
		end
		complain("WriteVoxelChannels failed (" .. tostring(err) .. "), switching to the older WriteVoxels method")
		useChannels = false
	end
	-- older terrain water: one material per cube
	legacyMaterials = legacyMaterials or WaterSim.NewLiquidArray(layout, Enum.Material.Air)
	legacyOccupancy = legacyOccupancy or WaterSim.NewLiquidArray(layout, 0)
	for i = 1, layout.NX do
		for y = 1, layout.Layers + 1 do
			local src, mats, occ = liquid[i][y], legacyMaterials[i][y], legacyOccupancy[i][y]
			for j = 1, layout.NZ do
				local o = src[j]
				mats[j] = o > 0 and Enum.Material.Water or Enum.Material.Air
				occ[j] = o
			end
		end
	end
	terrain:WriteVoxels(region, 4, legacyMaterials, legacyOccupancy)
end

-- the gate: how far open it is, read from where the Gate part has slid to
local gate = arena:FindFirstChild("Gate", true)
local gateClosedY = gate and gate:IsA("BasePart") and gate.CFrame.Position.Y or nil
local function gateOpenness(): number
	if not gateClosedY then
		return arena:GetAttribute("GateOpen") and 1 or 0
	end
	return math.clamp((gate.CFrame.Position.Y - gateClosedY) / gate.Size.Y, 0, 1)
end

-- start dry
writeTerrain()

local step = 1 / WaterConfig.SimRate
local terrainEvery = 1 / WaterConfig.TerrainRate
local networkEvery = 1 / WaterConfig.NetworkRate
local accum, terrainClock, networkClock, levelClock = 0, 0, 0, 0
local tapOn = false
local gateShutAt = -math.huge
local lastGateOpen = false
local lastWritten = table.create(sim.N, 0)

local function terrainNeedsWrite(): boolean
	for k = 1, sim.N do
		if math.abs(sim.Depth[k] - lastWritten[k]) > 0.02 then
			return true
		end
	end
	return false
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.25)
	local now = os.clock()

	-- the gate
	local openness = gateOpenness()
	local gateOpen = arena:GetAttribute("GateOpen") == true
	if lastGateOpen and not gateOpen then
		gateShutAt = now
	end
	lastGateOpen = gateOpen
	for _, k in layout.Gates do
		sim.Openness[k] = openness
		cap[k] = layout.GateHeight * openness
	end

	-- the tap
	local level = sim:Volume(isInterior) / interiorArea
	if gateOpen and not WaterConfig.TapWhileGateOpen then
		tapOn = false
	elseif WaterConfig.AutoFill then
		if level >= WaterConfig.FillLevel then
			tapOn = false
		elseif level < WaterConfig.FillLevel - 0.25 and now - gateShutAt > WaterConfig.RefillDelay then
			tapOn = true
		end
	end
	-- ease off as it gets close to full so it doesn't overshoot
	local rate = tapOn and fullRate * math.clamp((WaterConfig.FillLevel - level) / 0.5, 0.15, 1) or 0
	for _, source in taps do
		source.Rate = rate * source.Weight
	end

	-- simulate in fixed slices
	accum += dt
	local steps = 0
	while accum >= step and steps < 8 do
		accum -= step
		steps += 1
		sim:Step(step)
		sim:ClearInactive()
	end

	-- terrain (only when something visibly changed)
	terrainClock += dt
	if terrainClock >= terrainEvery then
		terrainClock = 0
		if terrainNeedsWrite() then
			writeTerrain()
			table.move(sim.Depth, 1, sim.N, 1, lastWritten)
		end
	end

	-- players
	networkClock += dt
	if networkClock >= networkEvery then
		networkClock = 0
		local flags = (tapOn and WaterSim.FLAG_TAP or 0) + (openness > 0 and WaterSim.FLAG_GATE or 0)
		stateEvent:FireAllClients(sim:Encode(flags))
	end

	levelClock += dt
	if levelClock >= 0.2 then
		levelClock = 0
		arena:SetAttribute("WaterLevel", math.floor(level * 20 + 0.5) / 20)
		arena:SetAttribute("TapOn", tapOn)
	end
end)
