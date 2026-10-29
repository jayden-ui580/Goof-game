--[[
	WaterSim  (ModuleScript — lives in ReplicatedStorage)

	The water's brain. The arena floor is split into a grid of 4×4-stud cells (the same size
	as Roblox's terrain water cubes) and each cell remembers how deep its water is.

	How the water moves (the "pipe method", the standard trick for game water):
	  * Imagine a little pipe between every pair of neighbouring cells.
	  * Water in a pipe speeds up toward the lower side, pushed by the difference in water
	    height (gravity), and slows down a bit from friction.
	  * Every slice of time each cell gives water to its neighbours through those pipes,
	    never more than it has, so water is never created or lost by accident.
	  This makes water pour in, spread out across the floor in a moving front, slosh, level
	  out, and run downhill toward an opening — all from that one rule.

	The drain cells (the hole in the wall) also lose water over the edge, using the real
	formulas for water spilling over a ledge (a "weir") or squirting through a submerged hole
	(an "orifice").

	This module has no Roblox-specific code in its maths, so it can be tested on its own.
]]

local WaterSim = {}
WaterSim.__index = WaterSim

WaterSim.CELL = 4 -- studs per cell (must match terrain voxels)

-- opts: NX, NZ (cells), Gravity, Friction (per second), PipeDepth (studs, how "thick" the pipes are),
--       Active (flat array of booleans: can this cell ever hold water?)
function WaterSim.new(opts)
	local self = setmetatable({}, WaterSim)
	local n = opts.NX * opts.NZ
	self.NX, self.NZ, self.N = opts.NX, opts.NZ, n
	self.L = opts.CellSize or WaterSim.CELL
	self.Gravity = opts.Gravity or 35
	self.Friction = opts.Friction or 0.5
	self.PipeArea = self.L * (opts.PipeDepth or 8)
	-- extra flow straight down any height difference, with no momentum. It irons out the
	-- cell-to-cell zigzag ("checkerboard") that the pipe method can grow, without slowing
	-- big waves. (studs³ per second per stud of height difference)
	self.Smoothing = opts.Smoothing or 40
	self.Depth = table.create(n, 0)
	self.FL = table.create(n, 0) -- flow out toward -X
	self.FR = table.create(n, 0) -- flow out toward +X
	self.FD = table.create(n, 0) -- flow out toward -Z
	self.FU = table.create(n, 0) -- flow out toward +Z
	self.SmL, self.SmR, self.SmD, self.SmU = table.create(n, 0), table.create(n, 0), table.create(n, 0), table.create(n, 0)
	self.VelX = table.create(n, 0)
	self.VelZ = table.create(n, 0)
	self.Active = opts.Active or table.create(n, true)
	self.Openness = table.create(n, 1) -- 0..1, how open a cell is (gate cells slide open)
	self.Drains = {} -- [index] = { Width = studs, Height = studs (opening height when fully open) }
	self.Sources = {} -- list of { Index = i, Rate = studs³/s }
	self.SoakRate = opts.SoakRate or 0.05 -- studs/s: a last thin film soaks away instead of lingering
	self.SoakBelow = opts.SoakBelow or 0.15 -- studs: only films thinner than this soak away
	self.SoakedRate = 0 -- studs³/s that soaked away (last step)
	self.DrainCoefficient = 0.62 -- how freely water leaves through the opening (real-world value)
	self.DrainSpeed = opts.DrainSpeed or 1
	-- the floor dips slightly into the drain opening (like a real floor drain), so the last
	-- shallow water keeps running out instead of creeping
	self.DrainDip = opts.DrainDip or 0.3
	self.OutflowRate = 0 -- studs³/s leaving through drains (last step)
	self.InflowRate = 0
	return self
end

function WaterSim:Index(i: number, j: number): number
	return (j - 1) * self.NX + i
end

function WaterSim:AddDrain(index: number, width: number, height: number)
	self.Drains[index] = { Width = width, Height = height }
end

-- Volume in studs³ (optionally only where filter(index) is true).
function WaterSim:Volume(filter): number
	local v, area = 0, self.L * self.L
	for i = 1, self.N do
		if not filter or filter(i) then
			v += self.Depth[i] * area
		end
	end
	return v
end

function WaterSim:Step(dt: number)
	local NX, NZ, L = self.NX, self.NZ, self.L
	local area = L * L
	local depth, active, open = self.Depth, self.Active, self.Openness
	local FL, FR, FD, FU = self.FL, self.FR, self.FD, self.FU
	local gain = dt * self.PipeArea * self.Gravity / L
	local keep = math.exp(-self.Friction * dt)
	local smooth = self.Smoothing

	-- 1) pipes speed up / slow down
	for j = 1, NZ do
		for i = 1, NX do
			local k = (j - 1) * NX + i
			if active[k] and open[k] > 0 and depth[k] > 0 then
				local h = depth[k]
				local fl, fr, fd, fu = 0, 0, 0, 0
				local sl, sr, sd, su = 0, 0, 0, 0
				if i > 1 and active[k - 1] and open[k - 1] > 0 then
					local dh = (h - depth[k - 1]) * math.min(open[k], open[k - 1])
					fl = math.max(0, FL[k] * keep + gain * dh)
					sl = math.max(0, smooth * dh)
				end
				if i < NX and active[k + 1] and open[k + 1] > 0 then
					local dh = (h - depth[k + 1]) * math.min(open[k], open[k + 1])
					fr = math.max(0, FR[k] * keep + gain * dh)
					sr = math.max(0, smooth * dh)
				end
				if j > 1 and active[k - NX] and open[k - NX] > 0 then
					local dh = (h - depth[k - NX]) * math.min(open[k], open[k - NX])
					fd = math.max(0, FD[k] * keep + gain * dh)
					sd = math.max(0, smooth * dh)
				end
				if j < NZ and active[k + NX] and open[k + NX] > 0 then
					local dh = (h - depth[k + NX]) * math.min(open[k], open[k + NX])
					fu = math.max(0, FU[k] * keep + gain * dh)
					su = math.max(0, smooth * dh)
				end
				-- the smoothing flow is added on top but not remembered as momentum
				self.SmL[k], self.SmR[k], self.SmD[k], self.SmU[k] = sl, sr, sd, su
				fl, fr, fd, fu = fl + sl, fr + sr, fd + sd, fu + su
				-- never send out more water than the cell holds
				local total = (fl + fr + fd + fu) * dt
				if total > h * area then
					local s = h * area / total
					fl, fr, fd, fu = fl * s, fr * s, fd * s, fu * s
				end
				FL[k], FR[k], FD[k], FU[k] = fl, fr, fd, fu
			else
				FL[k], FR[k], FD[k], FU[k] = 0, 0, 0, 0
				self.SmL[k], self.SmR[k], self.SmD[k], self.SmU[k] = 0, 0, 0, 0
			end
		end
	end

	-- 2) move the water and work out how fast it's flowing (for foam and splashes)
	local velX, velZ = self.VelX, self.VelZ
	for j = 1, NZ do
		for i = 1, NX do
			local k = (j - 1) * NX + i
			if active[k] then
				local inX = (i > 1 and FR[k - 1] or 0) + (i < NX and FL[k + 1] or 0)
				local inZ = (j > 1 and FU[k - NX] or 0) + (j < NZ and FD[k + NX] or 0)
				local before = depth[k]
				local after = before + dt * (inX + inZ - FL[k] - FR[k] - FD[k] - FU[k]) / area
				depth[k] = after > 1e-5 and after or 0
				local avg = math.max((before + depth[k]) * 0.5, 0.05)
				local throughX = ((i > 1 and FR[k - 1] or 0) - FL[k] + FR[k] - (i < NX and FL[k + 1] or 0)) * 0.5
				local throughZ = ((j > 1 and FU[k - NX] or 0) - FD[k] + FU[k] - (j < NZ and FD[k + NX] or 0)) * 0.5
				velX[k] = throughX / (L * avg)
				velZ[k] = throughZ / (L * avg)
			end
		end
	end

	-- forget the smoothing part so it doesn't build up momentum next step
	local SmL, SmR, SmD, SmU = self.SmL, self.SmR, self.SmD, self.SmU
	for k = 1, self.N do
		FL[k] = math.max(0, FL[k] - SmL[k])
		FR[k] = math.max(0, FR[k] - SmR[k])
		FD[k] = math.max(0, FD[k] - SmD[k])
		FU[k] = math.max(0, FU[k] - SmU[k])
	end

	-- 3) taps pour in
	local inflow = 0
	for _, src in self.Sources do
		if src.Rate > 0 and active[src.Index] then
			depth[src.Index] += src.Rate * dt / area
			inflow += src.Rate
		end
	end
	self.InflowRate = inflow

	-- 4) drains: water spills over the ledge (weir) or squirts through the hole (orifice)
	local out = 0
	local g2 = math.sqrt(2 * self.Gravity)
	for k, drain in self.Drains do
		local h = depth[k]
		local opening = drain.Height * open[k]
		if active[k] and h > 0 and opening > 0.01 then
			local q
			local head = h + self.DrainDip
			if head <= opening then
				q = self.DrainCoefficient * (2 / 3) * drain.Width * g2 * head ^ 1.5
			else
				q = self.DrainCoefficient * drain.Width * opening * g2 * math.sqrt(head - opening / 2)
			end
			q = math.min(q * self.DrainSpeed, h * area / dt)
			depth[k] = h - q * dt / area
			out += q
		end
	end
	self.OutflowRate = out

	-- 5) the last thin film soaks away (otherwise a 1-millimetre puddle lingers forever)
	local soak = self.SoakRate * dt
	local soaked = 0
	if soak > 0 and inflow == 0 then
		local below = self.SoakBelow
		for k = 1, self.N do
			local h = depth[k]
			if h > 0 and h < below then
				local nh = h > soak and h - soak or 0
				soaked += (h - nh) * area
				depth[k] = nh
			end
		end
	end
	self.SoakedRate = soaked / dt
end

-- Removes water from cells that can't hold any right now (e.g. a gate that just shut).
function WaterSim:ClearInactive()
	for k = 1, self.N do
		if not self.Active[k] or self.Openness[k] <= 0 then
			self.Depth[k] = 0
			self.FL[k], self.FR[k], self.FD[k], self.FU[k] = 0, 0, 0, 0
		end
	end
end

----------------------------------------------------------------------------------------
-- Network packet: what the server sends players so they can draw splashes and foam.
-- Depth in millimetres (u16), flow speed in centistuds/s (i16).
----------------------------------------------------------------------------------------
local HEADER = 16

function WaterSim:Encode(flags: number): buffer
	local n = self.N
	local b = buffer.create(HEADER + n * 6)
	buffer.writeu8(b, 0, 1)
	buffer.writeu8(b, 1, self.NX)
	buffer.writeu8(b, 2, self.NZ)
	buffer.writeu8(b, 3, flags)
	buffer.writef32(b, 4, self.InflowRate)
	buffer.writef32(b, 8, self.OutflowRate)
	buffer.writef32(b, 12, 0)
	for k = 1, n do
		local o = HEADER + (k - 1) * 6
		buffer.writeu16(b, o, math.clamp(math.round(self.Depth[k] * 1000), 0, 65535))
		buffer.writei16(b, o + 2, math.clamp(math.round(self.VelX[k] * 100), -32768, 32767))
		buffer.writei16(b, o + 4, math.clamp(math.round(self.VelZ[k] * 100), -32768, 32767))
	end
	return b
end

function WaterSim.Decode(b: buffer)
	local nx, nz = buffer.readu8(b, 1), buffer.readu8(b, 2)
	local n = nx * nz
	local state = {
		NX = nx,
		NZ = nz,
		Flags = buffer.readu8(b, 3),
		Inflow = buffer.readf32(b, 4),
		Outflow = buffer.readf32(b, 8),
		Depth = table.create(n, 0),
		VelX = table.create(n, 0),
		VelZ = table.create(n, 0),
	}
	for k = 1, n do
		local o = HEADER + (k - 1) * 6
		state.Depth[k] = buffer.readu16(b, o) / 1000
		state.VelX[k] = buffer.readi16(b, o + 2) / 100
		state.VelZ[k] = buffer.readi16(b, o + 4) / 100
	end
	return state
end

WaterSim.FLAG_TAP = 1
WaterSim.FLAG_GATE = 2

----------------------------------------------------------------------------------------
-- Turning a water depth into terrain-cube fill amounts.
----------------------------------------------------------------------------------------

-- Roblox draws a water surface halfway (in fill amount) between neighbouring cube centres, so a
-- cube that's 30% full doesn't show its surface 30% of the way up. This converts "the surface
-- should be s studs above the bottom of this cube" into the fill amount that puts it there.
-- (s from 0 to 4, with a full cube underneath.)
function WaterSim.OccupancyForSurface(s: number): number
	local c = WaterSim.CELL
	s = math.clamp(s / c * 4, 0, 4) -- work in units of a 4-tall cube
	if s <= 2 then
		return s / (s + 2)
	end
	return 2 / (6 - s)
end

----------------------------------------------------------------------------------------
-- Arena layout: where the grid sits in the world, which cells are inside the box, which
-- cells are the drain hole, and where the tap pours.
----------------------------------------------------------------------------------------

-- The grid is the inside of the box plus one ring of cells outside the walls (the drain hole
-- is in that ring). Returns nil and a reason if the arena is missing something.
function WaterSim.Layout(arena: Instance)
	local C = WaterSim.CELL
	local floor = arena:FindFirstChild("Floor")
	local size = arena:GetAttribute("InteriorSize")
	if not (floor and floor:IsA("BasePart") and typeof(size) == "Vector3") then
		return nil, "the arena needs a Floor part and an InteriorSize attribute"
	end
	local fcf = floor.CFrame
	local floorTop = fcf.Position.Y + floor.Size.Y / 2
	local nxIn, nzIn = math.round(size.X / C), math.round(size.Z / C)
	local layers = math.max(1, math.round(size.Y / C))
	local x0 = fcf.Position.X - nxIn * C / 2
	local z0 = fcf.Position.Z - nzIn * C / 2
	-- terrain water lives on a fixed 4-stud grid, so the box has to line up with it
	local sx, sy, sz = math.round(x0 / C) * C, math.round(floorTop / C) * C, math.round(z0 / C) * C
	local look = fcf.LookVector
	local turned = math.abs(look.Y) > 0.01 or (math.abs(look.X) > 0.01 and math.abs(look.Z) > 0.01)
	local misaligned = turned or math.abs(sx - x0) > 0.05 or math.abs(sy - floorTop) > 0.05 or math.abs(sz - z0) > 0.05

	local NX, NZ = nxIn + 2, nzIn + 2
	local origin = Vector3.new(sx - C, sy, sz - C) -- grid corner (outer ring included), at floor level
	local layout = {
		Cell = C,
		NX = NX,
		NZ = NZ,
		Layers = layers,
		Origin = origin,
		FloorTop = sy,
		Misaligned = misaligned,
		Interior = table.create(NX * NZ, false),
		InteriorCount = nxIn * nzIn,
		Gates = {},
		GateHeight = 0,
		Inlet = {}, -- list of { Index, Weight }
	}
	for j = 2, NZ - 1 do
		for i = 2, NX - 1 do
			layout.Interior[(j - 1) * NX + i] = true
		end
	end

	local opening = arena:FindFirstChild("GateOpening", true)
	if opening and opening:IsA("BasePart") then
		local half = opening.Size / 2
		layout.GateHeight = opening.Size.Y
		local thinIsX = half.X < half.Z
		for j = 1, NZ do
			for i = 1, NX do
				local k = (j - 1) * NX + i
				if not layout.Interior[k] then
					local centre = origin + Vector3.new((i - 0.5) * C, C / 2, (j - 0.5) * C)
					local p = opening.CFrame:PointToObjectSpace(centre)
					local thin, wide = math.abs(p.X), math.abs(p.Z)
					local halfThin, halfWide = half.X, half.Z
					if not thinIsX then
						thin, wide, halfThin, halfWide = wide, thin, halfWide, halfThin
					end
					if thin <= halfThin + C / 2 + 0.01 and wide < halfWide and math.abs(p.Y) < half.Y + C then
						table.insert(layout.Gates, k)
					end
				end
			end
		end
	end

	local mouth = arena:FindFirstChild("InletMouth", true)
	if mouth and mouth:IsA("BasePart") then
		-- share the pouring water between the 4 cells around the spot it lands on
		local m = mouth.CFrame.Position
		local fx = (m.X - origin.X) / C + 0.5
		local fz = (m.Z - origin.Z) / C + 0.5
		local i0, j0 = math.floor(fx), math.floor(fz)
		local tx, tz = fx - i0, fz - j0
		local total = 0
		for _, c in { { i0, j0, (1 - tx) * (1 - tz) }, { i0 + 1, j0, tx * (1 - tz) }, { i0, j0 + 1, (1 - tx) * tz }, { i0 + 1, j0 + 1, tx * tz } } do
			local i, j, w = c[1], c[2], c[3]
			local k = (j - 1) * NX + i
			if i >= 1 and i <= NX and j >= 1 and j <= NZ and layout.Interior[k] and w > 0 then
				table.insert(layout.Inlet, { Index = k, Weight = w })
				total += w
			end
		end
		for _, e in layout.Inlet do
			e.Weight /= total
		end
		layout.InletPosition = m
	end
	return layout
end

-- Centre of a cell in the world, at floor level.
function WaterSim.CellCentre(layout, i: number, j: number): Vector3
	return layout.Origin + Vector3.new((i - 0.5) * layout.Cell, 0, (j - 0.5) * layout.Cell)
end

-- Fills a terrain "LiquidOccupancy" array [x][y][z] from the water depths. y = 1 is a hidden
-- layer inside the (4-stud-thick) floor: keeping it full under wet cells makes Roblox draw a
-- thin film of water lying ON the floor rather than a floating blob.
-- cap[k] (optional) limits how deep a cell can look (the drain hole is only so tall).
WaterSim.MIN_VISIBLE = 0.1
function WaterSim:FillLiquid(layout, liquid, cap)
	local C, layers = layout.Cell, layout.Layers
	local NX, NZ = self.NX, self.NZ
	local depth = self.Depth
	local minVisible = WaterSim.MIN_VISIBLE
	for i = 1, NX do
		local column = liquid[i]
		for j = 1, NZ do
			local k = (j - 1) * NX + i
			local d = depth[k]
			if cap and cap[k] then
				d = math.min(d, cap[k])
			end
			local wet = d >= minVisible
			column[1][j] = wet and 1 or 0
			for y = 2, layers + 1 do
				local occ = 0
				if wet then
					local s = d - (y - 2) * C
					if s >= C then
						occ = 1
					elseif s > 0 then
						occ = WaterSim.OccupancyForSurface(s)
						if occ < 0.02 then
							occ = 0
						end
					end
				end
				column[y][j] = occ
			end
		end
	end
end

-- An empty [x][y][z] array the right size for FillLiquid.
function WaterSim.NewLiquidArray(layout, fill)
	local a = table.create(layout.NX)
	for i = 1, layout.NX do
		local col = table.create(layout.Layers + 1)
		for y = 1, layout.Layers + 1 do
			col[y] = table.create(layout.NZ, fill or 0)
		end
		a[i] = col
	end
	return a
end

return WaterSim
