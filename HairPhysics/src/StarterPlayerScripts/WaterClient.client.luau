--[[
	WaterClient  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Draws the moving parts of the water on this player's screen (the water itself is Roblox
	terrain water, made by WaterServer):
	  * the stream pouring from the tap — when the tap turns on, the front of the water falls
	    from the pipe; when it turns off, the tail falls after it,
	  * mist and droplets where the stream hits the water,
	  * the waterfall pouring out of the drain hole when the gate is open,
	  * foam flecks floating on the surface that drift along with the current, so you can see
	    the water flowing toward the hole.

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

local arena = Workspace:WaitForChild(WaterConfig.ArenaName, 30)
local stateEvent = ReplicatedStorage:WaitForChild("WaterState", 30)
if not (arena and stateEvent) then
	return
end
while arena:GetAttribute("WaterGrid") == nil do
	arena:GetAttributeChangedSignal("WaterGrid"):Wait()
end

local C = WaterSim.CELL
local origin: Vector3 = arena:GetAttribute("WaterOrigin")
local grid: Vector3 = arena:GetAttribute("WaterGrid")
local NX, NZ = grid.X, grid.Z
local floorTop = origin.Y
local mouth = arena:FindFirstChild("InletMouth", true)
local opening = arena:FindFirstChild("GateOpening", true)
local spout = arena:FindFirstChild("Spout", true)

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FALL_GRAVITY = 110 -- how fast falling water speeds up (studs/s²)

local fx = Instance.new("Folder")
fx.Name = "WaterFX"
fx.Parent = Workspace

local function effectPart(name: string, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Glass
	p.Color = WaterConfig.StreamColor
	p.Transparency = 1
	p.Shape = shape or Enum.PartType.Block
	p.Parent = fx
	return p
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Rate = 0
	e.LightEmission = 0.2
	e.LightInfluence = 0.8
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function anchorAttachment(name: string): Attachment
	local holder = effectPart(name .. "Holder")
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = holder
	return a
end

----------------------------------------------------------------------------------------
-- latest water state from the server, blended between the last two updates
----------------------------------------------------------------------------------------
local prevState, curState
local curTime = 0
local interval = 1 / WaterConfig.NetworkRate

stateEvent.OnClientEvent:Connect(function(packet: buffer)
	local ok, state = pcall(WaterSim.Decode, packet)
	if ok and state.NX == NX and state.NZ == NZ then
		prevState = curState or state
		curState = state
		curTime = os.clock()
	end
end)

local blendAlpha = 1
local function cellValue(field: string, i: number, j: number): number
	if i < 1 or i > NX or j < 1 or j > NZ then
		return 0
	end
	local k = (j - 1) * NX + i
	local a, b = prevState[field][k], curState[field][k]
	return a + (b - a) * blendAlpha
end

-- smooth value of a field at a world position (between cell centres)
local function sample(field: string, x: number, z: number): number
	local fxc = (x - origin.X) / C + 0.5
	local fzc = (z - origin.Z) / C + 0.5
	local i0, j0 = math.floor(fxc), math.floor(fzc)
	local tx, tz = fxc - i0, fzc - j0
	local v00, v10 = cellValue(field, i0, j0), cellValue(field, i0 + 1, j0)
	local v01, v11 = cellValue(field, i0, j0 + 1), cellValue(field, i0 + 1, j0 + 1)
	return (v00 * (1 - tx) + v10 * tx) * (1 - tz) + (v01 * (1 - tx) + v11 * tx) * tz
end

----------------------------------------------------------------------------------------
-- falling water (tap stream and waterfall share this): a column whose front (head) falls
-- when it starts and whose back (tail) falls when it stops
----------------------------------------------------------------------------------------
local function newFall()
	return { On = false, Head = 0, Tail = 0, HeadSpeed = 0, TailSpeed = 0, Active = false }
end

local function updateFall(f, on: boolean, top: number, bottom: number, dt: number)
	if on and not f.Active then
		f.Active = true
		f.Head, f.Tail, f.HeadSpeed, f.TailSpeed = top, top, 0, 0
	end
	if f.Active then
		if f.Head > bottom then
			f.HeadSpeed += FALL_GRAVITY * dt
			f.Head = math.max(bottom, f.Head - f.HeadSpeed * dt)
		else
			f.Head = bottom
		end
		if on then
			f.Tail, f.TailSpeed = top, 0
		else
			f.TailSpeed += FALL_GRAVITY * dt
			f.Tail -= f.TailSpeed * dt
			if f.Tail <= bottom then
				f.Active = false
			end
		end
	end
	f.On = on
	return f.Active and math.max(0, f.Tail - f.Head) or 0
end

----------------------------------------------------------------------------------------
-- tap stream + splash
----------------------------------------------------------------------------------------
local stream = effectPart("TapStream", Enum.PartType.Cylinder)
local streamFall = newFall()
local splash = anchorAttachment("TapSplash")
local mist = emitter(splash, {
	Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
	Lifetime = NumberRange.new(0.6, 1.2),
	Speed = NumberRange.new(4, 9),
	SpreadAngle = Vector2.new(70, 70),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, -6, 0),
	Drag = 2,
})
local droplets = emitter(splash, {
	Color = ColorSequence.new(Color3.fromRGB(210, 235, 250)),
	Size = NumberSequence.new(0.25),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	Lifetime = NumberRange.new(0.4, 0.8),
	Speed = NumberRange.new(10, 18),
	SpreadAngle = Vector2.new(55, 55),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, -90, 0),
})

----------------------------------------------------------------------------------------
-- waterfall out of the drain hole
----------------------------------------------------------------------------------------
local outward, across, lip, gateWidth, groundY
if opening and spout then
	local floor = arena:FindFirstChild("Floor")
	local centre = floor and floor.CFrame.Position or arena:GetPivot().Position
	local d = opening.CFrame.Position - centre
	outward = math.abs(d.X) > math.abs(d.Z) and Vector3.new(math.sign(d.X), 0, 0) or Vector3.new(0, 0, math.sign(d.Z))
	across = Vector3.new(outward.Z, 0, -outward.X)
	-- outer edge of the spout, at floor level
	local sp = spout.CFrame.Position
	local reach = math.abs(spout.Size.X * outward.X) + math.abs(spout.Size.Z * outward.Z)
	lip = Vector3.new(sp.X, floorTop, sp.Z) + outward * (reach / 2)
	local openSize = opening.Size
	gateWidth = math.abs(openSize.X * across.X) + math.abs(openSize.Z * across.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { arena, fx }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(lip + outward * 0.8, Vector3.new(0, -300, 0), params)
	groundY = hit and hit.Position.Y or floorTop - 8
end
local waterfall = effectPart("Waterfall")
local fallState = newFall()
local fallSplash = anchorAttachment("FallSplash")
local fallMist = emitter(fallSplash, {
	Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
	Lifetime = NumberRange.new(0.8, 1.6),
	Speed = NumberRange.new(5, 12),
	SpreadAngle = Vector2.new(80, 80),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, -5, 0),
	Drag = 1.5,
})
local fallDrops = emitter(fallSplash, {
	Color = ColorSequence.new(Color3.fromRGB(210, 235, 250)),
	Size = NumberSequence.new(0.3),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	Lifetime = NumberRange.new(0.5, 0.9),
	Speed = NumberRange.new(12, 22),
	SpreadAngle = Vector2.new(60, 60),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, -90, 0),
})
local lipSpray = anchorAttachment("LipSpray")
local lipMist = emitter(lipSpray, {
	Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.5) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
	Lifetime = NumberRange.new(0.5, 1),
	Speed = NumberRange.new(2, 5),
	SpreadAngle = Vector2.new(40, 40),
	EmissionDirection = Enum.NormalId.Top,
})

----------------------------------------------------------------------------------------
-- foam flecks
----------------------------------------------------------------------------------------
local rng = Random.new()
local flecks = {}
local fleckParts = {}
local xMin, xMax = origin.X + C, origin.X + (NX - 1) * C
local zMin, zMax = origin.Z + C, origin.Z + (NZ - 1) * C
for n = 1, WaterConfig.FoamCount do
	local p = effectPart("Foam", Enum.PartType.Cylinder)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(245, 250, 255)
	local s = WaterConfig.FoamSize * rng:NextNumber(0.6, 1.3)
	p.Size = Vector3.new(0.06, s, s)
	flecks[n] = { X = 0, Z = 0, Life = 0, MaxLife = 0, Visible = false }
	fleckParts[n] = p
end

local function respawn(f, tapOn: boolean)
	for _ = 1, 6 do
		local x, z
		if tapOn and mouth and rng:NextNumber() < 0.55 then
			local m = mouth.CFrame.Position
			local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.5, 4)
			x, z = m.X + math.cos(a) * r, m.Z + math.sin(a) * r
		else
			x, z = rng:NextNumber(xMin, xMax), rng:NextNumber(zMin, zMax)
		end
		if x > xMin and x < xMax and z > zMin and z < zMax and sample("Depth", x, z) > 0.3 then
			f.X, f.Z = x, z
			f.MaxLife = rng:NextNumber(4, 9)
			f.Life = 0
			f.Visible = true
			return
		end
	end
	f.Visible = false
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local moveParts, moveFrames = {}, {}
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder part to stand up / lie flat

RunService.RenderStepped:Connect(function(dt)
	if not curState then
		return
	end
	dt = math.min(dt, 0.1)
	blendAlpha = math.clamp((os.clock() - curTime) / interval, 0, 1)
	local flags = curState.Flags
	local tapOn = bit32.band(flags, WaterSim.FLAG_TAP) ~= 0
	table.clear(moveParts)
	table.clear(moveFrames)

	-- tap stream
	if mouth then
		local m = mouth.CFrame.Position
		local depthHere = sample("Depth", m.X, m.Z)
		local surface = floorTop + (depthHere > WaterSim.MIN_VISIBLE and depthHere or 0)
		local length = updateFall(streamFall, tapOn, m.Y, surface, dt)
		if length > 0.05 then
			local wobble = Vector3.new(math.sin(os.clock() * 7) * 0.05, 0, math.cos(os.clock() * 5.3) * 0.05)
			local mid = Vector3.new(m.X, (streamFall.Head + streamFall.Tail) / 2, m.Z) + wobble
			stream.Size = Vector3.new(length, WaterConfig.StreamWidth, WaterConfig.StreamWidth)
			stream.Transparency = 0.35
			table.insert(moveParts, stream)
			table.insert(moveFrames, CFrame.new(mid) * FLAT)
		else
			stream.Transparency = 1
		end
		local landed = streamFall.Active and streamFall.Head <= surface + 0.01
		local strength = landed and math.clamp(curState.Inflow / 800, 0.2, 1) or 0
		splash.Parent.CFrame = CFrame.new(m.X, surface, m.Z)
		mist.Rate = WaterConfig.SplashRate * strength
		droplets.Rate = WaterConfig.SplashRate * 0.6 * strength
	end

	-- waterfall
	if lip then
		local flow = curState.Outflow
		local on = flow > 5
		local length = updateFall(fallState, on, lip.Y + 0.6, groundY, dt)
		local amount = math.clamp(flow / 1200, 0, 1)
		if length > 0.05 then
			local top = fallState.Tail
			local mid = lip + outward * 0.7 + Vector3.new(0, (fallState.Head + top) / 2 - lip.Y, 0)
			waterfall.Size = Vector3.new(gateWidth * (0.6 + 0.4 * amount), length, 0.35 + amount * 0.6)
			waterfall.Transparency = 0.8 - 0.45 * amount
			table.insert(moveParts, waterfall)
			table.insert(moveFrames, CFrame.fromMatrix(mid, across, Vector3.yAxis))
		else
			waterfall.Transparency = 1
		end
		local landed = fallState.Active and fallState.Head <= groundY + 0.01
		fallSplash.Parent.CFrame = CFrame.new(lip.X + outward.X * 0.7, groundY, lip.Z + outward.Z * 0.7)
		fallMist.Rate = landed and 70 * amount or 0
		fallDrops.Rate = landed and 50 * amount or 0
		lipSpray.Parent.CFrame = CFrame.new(lip + Vector3.new(0, 0.4, 0))
		lipMist.Rate = on and 25 * amount or 0
	end

	-- foam flecks drift with the current
	for n, f in flecks do
		local part = fleckParts[n]
		if not f.Visible then
			if rng:NextNumber() < dt * 3 then
				respawn(f, tapOn)
			end
		end
		if f.Visible then
			f.Life += dt
			local depth = sample("Depth", f.X, f.Z)
			if depth < 0.25 or f.Life > f.MaxLife then
				f.Visible = false
			else
				local vx, vz = sample("VelX", f.X, f.Z), sample("VelZ", f.X, f.Z)
				f.X = math.clamp(f.X + (vx + rng:NextNumber(-0.3, 0.3)) * dt, xMin, xMax)
				f.Z = math.clamp(f.Z + (vz + rng:NextNumber(-0.3, 0.3)) * dt, zMin, zMax)
				local speed = math.sqrt(vx * vx + vz * vz)
				local fade = math.min(1, f.Life / 0.6, (f.MaxLife - f.Life) / 0.8)
				part.Transparency = 1 - 0.8 * fade * math.clamp(0.25 + speed / 2, 0, 1)
				table.insert(moveParts, part)
				table.insert(moveFrames, CFrame.new(f.X, floorTop + depth + 0.04, f.Z) * FLAT)
			end
		end
		if not f.Visible then
			part.Transparency = 1
		end
	end

	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
