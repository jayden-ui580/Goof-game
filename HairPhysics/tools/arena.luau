-- Builds the TestArena model (used by build_rbxmx.luau). Every size here is in studs.
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame, Color3, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local ORIGIN = Vector3.new(0, 8, -120) -- centre of the floor's top surface, in the world
local INNER = Vector3.new(64, 24, 64) -- inside of the box: width, height, depth
local WALL = 2 -- wall thickness
local FLOOR_T = 4 -- floor thickness (thick enough to hide the underside of the terrain water)
local GATE_W, GATE_H = 8, 4 -- the drain hole at the bottom of the +X wall

local WALL_COLOR = Color3.fromRGB(226, 229, 234)
local FLOOR_COLOR = Color3.fromRGB(178, 190, 200)
local TRIM_COLOR = Color3.fromRGB(40, 70, 120)

local function part(parent, name, size, pos, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(ORIGIN + pos)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = WALL_COLOR
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end

return function()
	local arena = Instance.new("Model")
	arena.Name = "TestArena"
	arena:SetAttribute("InteriorSize", INNER)
	arena:SetAttribute("GateOpen", false)

	local hw, hd, h = INNER.X / 2, INNER.Z / 2, INNER.Y
	local outerW, outerD = INNER.X + WALL * 2, INNER.Z + WALL * 2

	-- floor (its top surface is the arena's floor level; scripts read it from this part)
	part(arena, "Floor", Vector3.new(outerW, FLOOR_T, outerD), Vector3.new(0, -FLOOR_T / 2, 0), {
		Material = Enum.Material.Concrete,
		Color = FLOOR_COLOR,
	})

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = arena
	part(walls, "WallMinusX", Vector3.new(WALL, h, outerD), Vector3.new(-hw - WALL / 2, h / 2, 0))
	part(walls, "WallMinusZ", Vector3.new(INNER.X, h, WALL), Vector3.new(0, h / 2, -hd - WALL / 2))
	part(walls, "WallPlusZ", Vector3.new(INNER.X, h, WALL), Vector3.new(0, h / 2, hd + WALL / 2))
	-- +X wall, built around the drain hole
	local side = (outerD - GATE_W) / 2
	local wx = hw + WALL / 2
	part(walls, "WallPlusX_A", Vector3.new(WALL, h, side), Vector3.new(wx, h / 2, -(GATE_W / 2 + side / 2)))
	part(walls, "WallPlusX_B", Vector3.new(WALL, h, side), Vector3.new(wx, h / 2, GATE_W / 2 + side / 2))
	part(walls, "WallPlusX_Top", Vector3.new(WALL, h - GATE_H, GATE_W), Vector3.new(wx, GATE_H + (h - GATE_H) / 2, 0))

	-- dark trim along the bottom of the inside walls (shows where the floor meets the wall)
	local trim = Instance.new("Folder")
	trim.Name = "Trim"
	trim.Parent = arena
	local t = 0.6
	part(trim, "TrimMinusX", Vector3.new(0.1, t, INNER.Z), Vector3.new(-hw + 0.05, t / 2, 0), { Color = TRIM_COLOR, CanCollide = false })
	part(trim, "TrimMinusZ", Vector3.new(INNER.X, t, 0.1), Vector3.new(0, t / 2, -hd + 0.05), { Color = TRIM_COLOR, CanCollide = false })
	part(trim, "TrimPlusZ", Vector3.new(INNER.X, t, 0.1), Vector3.new(0, t / 2, hd - 0.05), { Color = TRIM_COLOR, CanCollide = false })

	-- glass ceiling: the box is sealed but daylight still gets in
	part(arena, "Ceiling", Vector3.new(outerW, 1, outerD), Vector3.new(0, h + 0.5, 0), {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(200, 225, 240),
		Transparency = 0.6,
	})

	-- the drain: a gate that slides up into the wall, a grate players can't squeeze through,
	-- and a lip outside for the water to pour over
	local drain = Instance.new("Folder")
	drain.Name = "Drain"
	drain.Parent = arena
	part(drain, "Gate", Vector3.new(1.2, GATE_H, GATE_W), Vector3.new(wx, GATE_H / 2, 0), {
		Material = Enum.Material.DiamondPlate,
		Color = Color3.fromRGB(90, 96, 105),
	})
	part(drain, "GateOpening", Vector3.new(WALL, GATE_H, GATE_W), Vector3.new(wx, GATE_H / 2, 0), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local bars = 7
	for i = 1, bars do
		local z = -GATE_W / 2 + GATE_W * (i - 0.5) / bars
		part(drain, "Bar", Vector3.new(0.3, GATE_H, 0.3), Vector3.new(hw + WALL + 0.2, GATE_H / 2, z), {
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 63, 70),
		})
	end
	part(drain, "Spout", Vector3.new(3, FLOOR_T, GATE_W + 1), Vector3.new(hw + WALL + 1.5, -FLOOR_T / 2, 0), {
		Material = Enum.Material.Concrete,
		Color = FLOOR_COLOR,
	})

	-- the tap: a pipe sticking out of the -Z wall that the water pours from
	local inlet = Instance.new("Folder")
	inlet.Name = "Inlet"
	inlet.Parent = arena
	local pipeY = 18
	local pipe = part(inlet, "Pipe", Vector3.new(3, 2.4, 2.4), Vector3.new(0, pipeY, -hd + 1.5), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(120, 126, 134),
		Shape = Enum.PartType.Cylinder,
	})
	pipe.CFrame = CFrame.new(ORIGIN + Vector3.new(0, pipeY, -hd + 1.5)) * CFrame.Angles(0, math.rad(90), 0)
	local flange = part(inlet, "Flange", Vector3.new(0.4, 3.4, 3.4), Vector3.new(0, pipeY, -hd + 0.2), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(90, 96, 105),
		Shape = Enum.PartType.Cylinder,
	})
	flange.CFrame = CFrame.new(ORIGIN + Vector3.new(0, pipeY, -hd + 0.2)) * CFrame.Angles(0, math.rad(90), 0)
	-- where the water leaves the pipe (the water scripts read this)
	part(inlet, "InletMouth", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0, pipeY - 0.6, -hd + 3.4), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	-- depth gauge on the -X wall: a stripe every 2 studs, a number every 4
	local gauge = Instance.new("Folder")
	gauge.Name = "DepthGauge"
	gauge.Parent = arena
	for y = 2, h - 2, 2 do
		local big = y % 4 == 0
		part(gauge, "Mark" .. y, Vector3.new(0.06, big and 0.2 or 0.12, big and 3 or 1.6), Vector3.new(-hw + 0.03, y, 0), {
			Color = TRIM_COLOR,
			CanCollide = false,
			CanQuery = false,
		})
		if big then
			local label = part(gauge, "Label" .. y, Vector3.new(0.06, 1.4, 2), Vector3.new(-hw + 0.03, y + 0.9, 2.8), {
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			})
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId.Right
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 50
			surface.Parent = label
			local text = Instance.new("TextLabel")
			text.BackgroundTransparency = 1
			text.Size = roblox.UDim2.fromScale(1, 1)
			text.Text = tostring(y)
			text.TextScaled = true
			text.Font = Enum.Font.GothamBold
			text.TextColor3 = TRIM_COLOR
			text.Parent = surface
		end
	end

	-- where players and the dummies start
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(ORIGIN + Vector3.new(-24, 0.2, 0))
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(110, 170, 230)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = arena
	for name, pos in { MrPigtails = Vector3.new(-14, 0, -8), MrLady = Vector3.new(-14, 0, 8) } do
		local spot = part(arena, "RigSpot_" .. name, Vector3.new(2, 0.2, 2), pos + Vector3.new(0, 0.1, 0), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		-- face the middle of the arena (+X)
		local at = ORIGIN + pos + Vector3.new(0, 0.1, 0)
		spot.CFrame = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
	end

	-- legs holding the arena up off the ground (the drain pours out of the side)
	local legs = Instance.new("Folder")
	legs.Name = "Legs"
	legs.Parent = arena
	local legH = ORIGIN.Y - FLOOR_T
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(legs, "Leg", Vector3.new(3, legH, 3), Vector3.new(sx * (hw - 1), -FLOOR_T - legH / 2, sz * (hd - 1)), {
				Material = Enum.Material.Concrete,
				Color = Color3.fromRGB(150, 155, 160),
			})
		end
	end

	return arena
end
