--[[
	PowerFX  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Draws powering up for EVERY character on this player's screen, from the attributes
	PowerUpServer sets (so everyone sees everyone's aura):
	  * the power-up animation, coded joint by joint (no animation asset needed):
	      start     standing tall, fists clenched at the waist, elbows out
	      charging  the fuller the bar, the more you hunch over with your head down and your
	                elbows thrown wide, trembling with effort
	      release   at the transformation you lean back, head up, arms lowered and spread, and
	                hold it until you get control back
	  * the aura, Dragon Ball style: a flame-shaped shell that surrounds you (widest near the
	    ground with flares sticking out sideways, narrowing to a spiky top), filled with
	    see-through flames and a white-hot core, flickering in steps like hand-drawn anime
	    frames. Energy streaks swirl up and light streaks shoot past. It grows bigger and
	    faster as the bar fills; white-blue in base form, gold as a Super Saiyan.
	  * dust blasting off the ground and rocks lifting at high power,
	  * the transformation burst: a pillar of light, a flash, a shockwave ring and a spray.
	The hair and belt being blown upward is HairPhysics reacting to the AuraWind attribute.
	Settings: ReplicatedStorage > PowerConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local ROCKS = 8
local S = PowerConfig.AuraSize
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "PowerFX"
folder.Parent = Workspace

local function smooth(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- moves current toward target; rate = how quickly (per second)
local function ease(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-dt * rate))
end

----------------------------------------------------------------------------------------
-- the power-up animation: three key poses for each R15 joint, blended in code.
-- Characters face -Z: a negative X turn bends the spine or head forward, a positive one
-- leans it back; on the shoulders a Z turn swings the arm out to the side.
----------------------------------------------------------------------------------------
local READY = { -- standing tall, fists clenched at the waist, elbows out
	Root = CFrame.new(0, -0.01, 0),
	Waist = CFrame.Angles(0.06, 0, 0),
	Neck = CFrame.Angles(-0.06, 0, 0),
	LeftShoulder = CFrame.Angles(-0.4, -0.25, -0.32),
	RightShoulder = CFrame.Angles(-0.4, 0.25, 0.32),
	LeftElbow = CFrame.Angles(1.25, 0, 0),
	RightElbow = CFrame.Angles(1.25, 0, 0),
	LeftWrist = CFrame.Angles(0.2, 0, 0),
	RightWrist = CFrame.Angles(0.2, 0, 0),
	LeftHip = CFrame.Angles(0.04, 0, -0.1),
	RightHip = CFrame.Angles(0.04, 0, 0.1),
	LeftKnee = CFrame.Angles(-0.08, 0, 0),
	RightKnee = CFrame.Angles(-0.08, 0, 0),
	LeftAnkle = CFrame.Angles(0.04, 0, 0.1),
	RightAnkle = CFrame.Angles(0.04, 0, -0.1),
}
local STRAIN = { -- hunched over, head down, elbows thrown wide, knees bent
	Root = CFrame.new(0, -0.16, 0) * CFrame.Angles(-0.08, 0, 0),
	Waist = CFrame.Angles(-0.28, 0, 0),
	Neck = CFrame.Angles(-0.3, 0, 0),
	LeftShoulder = CFrame.Angles(0.1, -0.35, -0.7),
	RightShoulder = CFrame.Angles(0.1, 0.35, 0.7),
	LeftElbow = CFrame.Angles(1.15, 0, 0),
	RightElbow = CFrame.Angles(1.15, 0, 0),
	LeftWrist = CFrame.Angles(0.3, 0, 0),
	RightWrist = CFrame.Angles(0.3, 0, 0),
	LeftHip = CFrame.Angles(0.5, 0, -0.3),
	RightHip = CFrame.Angles(0.5, 0, 0.3),
	LeftKnee = CFrame.Angles(-0.95, 0, 0),
	RightKnee = CFrame.Angles(-0.95, 0, 0),
	LeftAnkle = CFrame.Angles(0.45, 0, 0.15),
	RightAnkle = CFrame.Angles(0.45, 0, -0.15),
}
local RELEASE = { -- the transformation: leaning back, head up, arms lowered and spread
	Root = CFrame.new(0, -0.08, 0) * CFrame.Angles(0.1, 0, 0),
	Waist = CFrame.Angles(0.3, 0, 0),
	Neck = CFrame.Angles(0.45, 0, 0),
	LeftShoulder = CFrame.Angles(-0.2, 0, -0.7),
	RightShoulder = CFrame.Angles(-0.2, 0, 0.7),
	LeftElbow = CFrame.Angles(0.2, 0, 0),
	RightElbow = CFrame.Angles(0.2, 0, 0),
	LeftWrist = CFrame.Angles(-0.1, 0, 0),
	RightWrist = CFrame.Angles(-0.1, 0, 0),
	LeftHip = CFrame.Angles(0.2, 0, -0.32),
	RightHip = CFrame.Angles(0.2, 0, 0.32),
	LeftKnee = CFrame.Angles(-0.35, 0, 0),
	RightKnee = CFrame.Angles(-0.35, 0, 0),
	LeftAnkle = CFrame.Angles(0.05, 0, 0.2),
	RightAnkle = CFrame.Angles(0.05, 0, -0.2),
}
-- how much each joint trembles with effort
local SHAKE = { Root = 0.5, Waist = 1, Neck = 1.2, LeftShoulder = 0.7, RightShoulder = 0.7, LeftElbow = 0.5, RightElbow = 0.5 }

----------------------------------------------------------------------------------------
-- the aura: tongues of flame made from Beams (tapered ribbons that always face the
-- camera, so each one reads as a sharp anime flame shape)
----------------------------------------------------------------------------------------
local function seq(points): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function colours(points): ColorSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(keys)
end

-- The aura is a flame-shaped shell around the body, drawn from the reference: widest near the
-- ground, bulging, then narrowing to a spiky top. PROFILE is its outline: at each height (0 =
-- feet, 1 = top of the shell) how far out it reaches, as a share of its widest point.
local PROFILE = { { 0, 0.5 }, { 0.1, 1 }, { 0.3, 0.9 }, { 0.55, 0.68 }, { 0.8, 0.42 }, { 1, 0.12 } }
local SHELL_HEIGHT = { 5.5, 8 } -- studs from the feet to the top of the shell {no power, full power}
local SHELL_WIDTH = { 2.8, 3.8 } -- studs from the middle out to its widest point

local function outline(u: number): number
	u = math.clamp(u, 0, 1)
	for k = 2, #PROFILE do
		local a, b = PROFILE[k - 1], PROFILE[k]
		if u <= b[1] then
			return lerp(a[2], b[2], (u - a[1]) / (b[1] - a[1]))
		end
	end
	return PROFILE[#PROFILE][2]
end

-- The flames, as Beams. Per group: how many, how many times a second each one licks up
-- {no power, full power}, how wide at the base, how see-through from base (0) to tip (1),
-- and its colours.
local GROUPS = {
	{ -- jagged spikes sticking out of the shell: sideways at the bottom, straight up on top
		Kind = "Spike", Count = 36, Speed = { 1.6, 3.6 }, Width = { 0.7, 1.4 },
		Transparency = seq({ { 0, 0.65 }, { 0.35, 0.2 }, { 0.85, 0.35 }, { 1, 0.8 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, core }, { 0.45, main }, { 1, edge } })
		end,
	},
	{ -- broad see-through flames filling the shell, from the feet to the top
		Kind = "Body", Count = 8, Speed = { 0.8, 1.8 }, Width = { 2.2, 3.6 },
		Transparency = seq({ { 0, 0.9 }, { 0.3, 0.72 }, { 0.8, 0.76 }, { 1, 1 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, Color3.new(1, 1, 1) }, { 0.6, core }, { 1, main } })
		end,
	},
	{ -- white-hot flames hugging the body
		Kind = "Core", Count = 6, Speed = { 1.2, 2.6 }, Width = { 0.8, 1.4 },
		Transparency = seq({ { 0, 0.8 }, { 0.25, 0.35 }, { 0.8, 0.5 }, { 1, 0.95 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, Color3.new(1, 1, 1) }, { 0.5, core }, { 1, main } })
		end,
	},
}
local AURA_FPS = math.max(PowerConfig.AuraFrameRate or 15, 1)
local SWOOSHES = 3 -- energy streaks swirling up around the body

-- an attachment frame whose axis (X) points straight up
local UP_FRAME = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.xAxis)

-- an attachment frame at pos whose axis (X) points along dir (a unit vector); a Beam's curve
-- leaves and arrives along its attachments' axes
local function pointing(pos: Vector3, dir: Vector3): CFrame
	local side = dir:Cross(Vector3.zAxis)
	if side.Magnitude < 1e-3 then
		side = dir:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(pos, dir, side.Unit)
end

----------------------------------------------------------------------------------------
-- building one character's effects
----------------------------------------------------------------------------------------
local function fxPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = folder
	return p
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function newBeam(parent: Instance, transparency: NumberSequence)
	local a0 = Instance.new("Attachment")
	a0.Parent = parent
	local a1 = Instance.new("Attachment")
	a1.Parent = parent
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Segments = 10
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0
	beam.Width1 = 0
	beam.Transparency = transparency
	pcall(function()
		beam.Brightness = 2 -- newer property: a little extra glow where it exists
	end)
	beam.Parent = parent
	return beam, a0, a1
end

-- gives a flame a new place, size and speed for its next lick
local function respawn(t)
	local slot = (t.Index - 1) / t.Of * math.pi * 2 + t.Offset
	t.Angle = slot + rng:NextNumber(-0.5, 0.5) * (math.pi * 2 / t.Of)
	t.LenMul = rng:NextNumber(0.75, 1.2)
	t.WidthMul = rng:NextNumber(0.75, 1.2)
	t.SpeedMul = rng:NextNumber(0.8, 1.25)
	if t.Kind == "Spike" then
		-- where on the shell: plenty low down (the side flares), most in the middle, some on top
		local r = rng:NextNumber()
		t.U = r < 0.3 and rng:NextNumber(0.04, 0.2) or r < 0.75 and rng:NextNumber(0.2, 0.7) or rng:NextNumber(0.7, 0.97)
	elseif t.Kind == "Body" then
		t.R0 = rng:NextNumber(0.3, 1)
		t.TipU = rng:NextNumber(0.85, 1.05)
		t.TipOff = rng:NextNumber(-0.5, 0.5)
	else
		t.R0 = rng:NextNumber(0.5, 0.9)
		t.Lift = rng:NextNumber(0.2, 1.5)
		t.TipU = rng:NextNumber(0.45, 0.7)
	end
end

local function resetSwoosh(w, feet: number, first: boolean)
	w.Angle = rng:NextNumber(0, math.pi * 2)
	w.R = rng:NextNumber(2, 3) * S
	w.Y = feet + (first and rng:NextNumber(0, 6) or rng:NextNumber(0, 1)) * S
	w.Top = feet + rng:NextNumber(6, 9) * S
	w.Rise = rng:NextNumber(4, 7) * S
	w.Spin = rng:NextNumber(3.5, 5.5) * (rng:NextNumber() < 0.5 and -1 or 1)
end

-- The character's joints the animation turns. Characters now spawn with AnimationConstraints
-- (Roblox's "Avatar Joint Upgrade") instead of Motor6Ds; both are posed the same way, through
-- their Transform.
local function findJoints(character: Model)
	local joints = {}
	for _, d in character:GetDescendants() do
		if READY[d.Name] and (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) then
			if not joints[d.Name] or d:IsA("AnimationConstraint") then
				joints[d.Name] = d
			end
		end
	end
	return joints
end

local function newFX(character: Model, root: BasePart)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local fx = {
		Character = character,
		Intensity = 0,
		Pose = 0,
		Strain = 0,
		Release = 0,
		Shudder = 0,
		Flare = 1,
		Gold = 0,
		PaintedGold = -1,
		-- how far below the HumanoidRootPart's centre the feet are
		FootDrop = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2,
	}
	fx.Aura = fxPart("Aura", Vector3.new(3.2, 5.6, 3.2) * S)

	fx.Tongues = {}
	local amount = math.max(PowerConfig.AuraFlames or 1, 0)
	for gi, group in GROUPS do
		local count = math.max(1, math.floor(group.Count * amount + 0.5))
		local offset = rng:NextNumber(0, math.pi * 2)
		for k = 1, count do
			local beam, a0, a1 = newBeam(fx.Aura, group.Transparency)
			local t = {
				Group = group, GroupIndex = gi, Kind = group.Kind, Index = k, Of = count, Offset = offset,
				Beam = beam, A0 = a0, A1 = a1, Boil = 1,
			}
			respawn(t)
			t.Phase = rng:NextNumber()
			table.insert(fx.Tongues, t)
		end
	end
	fx.FrameClock = math.huge -- draw the first frame straight away
	fx.Swooshes = {}
	for _ = 1, SWOOSHES do
		local beam, a0, a1 = newBeam(fx.Aura, seq({ { 0, 1 }, { 0.5, 0.35 }, { 1, 0.05 } }))
		local w = { Beam = beam, A0 = a0, A1 = a1 }
		resetSwoosh(w, -fx.FootDrop, true)
		table.insert(fx.Swooshes, w)
	end

	fx.Streaks = emitter(fx.Aura, { -- light streaks shooting up past the body
		Texture = SPARK,
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(26, 42),
		Squash = NumberSequence.new(2.5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * S), NumberSequenceKeypoint.new(1, 0.1 * S) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	})
	fx.Sparks = emitter(fx.Aura, {
		Texture = SPARK,
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(30, 30),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * S), NumberSequenceKeypoint.new(1, 0) }),
	})
	fx.Haze = emitter(fx.Aura, { -- a soft glow around the flames
		Texture = SMOKE,
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.7, 1.1),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(20, 20),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) }),
	})
	fx.Light = Instance.new("PointLight")
	fx.Light.Shadows = false
	fx.Light.Brightness = 0
	fx.Light.Parent = fx.Aura

	fx.Ground = fxPart("GroundFX", Vector3.new(1, 0.2, 1))
	fx.Dust = emitter(fx.Ground, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(190, 180, 165)),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(88, 88),
		Speed = NumberRange.new(18, 28),
		Drag = 3,
		Acceleration = Vector3.new(0, 3, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * S), NumberSequenceKeypoint.new(1, 5 * S) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		LightInfluence = 1,
	})

	fx.Rocks = {}
	for i = 1, ROCKS do
		local rock = fxPart("Rock", Vector3.new(1, 1, 1) * rng:NextNumber(0.35, 0.8) * S)
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(110, 104, 98)
		table.insert(fx.Rocks, {
			Part = rock,
			Angle = (i / ROCKS) * math.pi * 2 + rng:NextNumber(-0.3, 0.3),
			Radius = rng:NextNumber(3, 5.5) * S,
			Top = rng:NextNumber(1.2, 3.8),
			Height = 0,
			Spin = rng:NextNumber(-1.5, 1.5),
			Bob = rng:NextNumber(0, 6),
		})
	end

	-- the animation needs the character's joints
	fx.Motors = findJoints(character)
	fx.NextJointScan = 0
	fx.LastWritten = {}
	return fx
end

-- true if two joint angles are the same (reading one back can lose a hair of precision)
local function sameFrame(a: CFrame, b: CFrame): boolean
	local ca = { a:GetComponents() }
	local cb = { b:GetComponents() }
	for k = 1, 12 do
		if math.abs(ca[k] - cb[k]) > 1e-4 then
			return false
		end
	end
	return true
end

local function destroyFX(fx)
	fx.Aura:Destroy()
	fx.Ground:Destroy()
	for _, r in fx.Rocks do
		r.Part:Destroy()
	end
	if fx.Pillar then
		fx.Pillar:Destroy()
	end
	for name, motor in fx.Motors do
		if motor.Parent and fx.LastWritten[name] and sameFrame(motor.Transform, fx.LastWritten[name]) then
			motor.Transform = CFrame.identity
		end
	end
end

-- recolours everything when the aura's colour changes (base white-blue <-> Super Saiyan gold)
local function paint(fx)
	local g = fx.Gold
	local main = PowerConfig.BaseAuraColor:Lerp(PowerConfig.SSJAuraColor, g)
	local edge = PowerConfig.BaseAuraEdge:Lerp(PowerConfig.SSJAuraEdge, g)
	local core = Color3.new(1, 1, 1):Lerp(main, 0.35)
	local painted = {}
	for _, t in fx.Tongues do
		painted[t.GroupIndex] = painted[t.GroupIndex] or t.Group.Paint(core, main, edge)
		t.Beam.Color = painted[t.GroupIndex]
	end
	local swoosh = colours({ { 0, edge }, { 1, core } })
	for _, w in fx.Swooshes do
		w.Beam.Color = swoosh
	end
	fx.Streaks.Color = ColorSequence.new(core, main)
	fx.Sparks.Color = ColorSequence.new(core)
	fx.Haze.Color = ColorSequence.new(main)
	fx.Light.Color = main
	fx.Core, fx.Main, fx.Edge = core, main, edge
	fx.PaintedGold = g
end

----------------------------------------------------------------------------------------
-- the transformation burst
----------------------------------------------------------------------------------------
local function playBurst(fx, root: BasePart, groundY: number)
	fx.Streaks:Emit(70)
	fx.Sparks:Emit(90)
	fx.Dust:Emit(60)
	fx.Light.Brightness = 16
	fx.Flare = 1.7 -- the flames shoot up extra high for a moment
	fx.Shudder = 1
	local color = PowerConfig.SSJAuraColor

	-- a pillar of light shooting into the sky
	local pillar = fxPart("Pillar", Vector3.new(1, 1, 1))
	pillar.CFrame = CFrame.new(root.Position.X, groundY, root.Position.Z)
	local bottom = Instance.new("Attachment")
	bottom.CFrame = UP_FRAME
	bottom.Parent = pillar
	local top = Instance.new("Attachment")
	top.CFrame = CFrame.new(0, 70 * S, 0) * UP_FRAME
	top.Parent = pillar
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0
	beam.Width1 = 0
	beam.Color = ColorSequence.new(Color3.new(1, 1, 0.9), color)
	beam.Transparency = seq({ { 0, 0.15 }, { 0.6, 0.45 }, { 1, 1 } })
	beam.Parent = pillar
	fx.Pillar = pillar
	TweenService:Create(beam, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Width0 = 11 * S,
		Width1 = 4 * S,
	}):Play()
	task.delay(0.18, function()
		TweenService:Create(beam, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Width0 = 0, Width1 = 0 }):Play()
	end)

	local ring = fxPart("Shockwave", Vector3.new(0.3, 2, 2))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.CFrame = CFrame.new(root.Position.X, groundY + 0.15, root.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 40 * S, 40 * S),
		Transparency = 1,
	}):Play()
	local ball = fxPart("Flash", Vector3.new(2, 2, 2))
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.new(1, 1, 0.9)
	ball.Transparency = 0.1
	ball.CFrame = root.CFrame
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(18, 18, 18) * S,
		Transparency = 1,
	}):Play()
	task.delay(1.4, function()
		ring:Destroy()
		ball:Destroy()
		pillar:Destroy()
		if fx.Pillar == pillar then
			fx.Pillar = nil
		end
	end)
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local active = {} -- [character] = fx
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function targetIntensity(character: Model): number
	local state = character:GetAttribute("PowerState")
	if state == "Charging" then
		local c = character:GetAttribute("Charge") or 0
		return c >= PowerConfig.AuraStart and math.max(c, 0.12) or 0
	elseif state == "Bursting" then
		return 1.3
	elseif character:GetAttribute("Form") == "SSJ" then
		return PowerConfig.SSJIdleAura
	end
	return 0
end

local function characters()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- moves the flames, streaks and swirls of one character's aura
local function updateAura(fx, i: number, dt: number, camDir: Vector3?)
	-- glow, light and particles change smoothly every frame
	local visible = i > 0.02
	fx.Streaks.Rate = i > 0.3 and 70 * (i - 0.3) or 0
	fx.Sparks.Rate = i > 0.5 and 60 * (i - 0.5) or 0
	fx.Haze.Rate = visible and (6 + 18 * i) or 0
	fx.Haze.Size = NumberSequence.new(5 * S * (0.7 + 0.5 * i))
	fx.Light.Range = visible and (8 + 18 * i) or 0
	fx.Light.Brightness = ease(fx.Light.Brightness, visible and (1 + 5 * i) or 0, 6, dt)

	-- the flames change shape in steps, like hand-drawn anime frames
	fx.FrameClock += dt
	if fx.FrameClock < 1 / AURA_FPS then
		return
	end
	local step = math.min(fx.FrameClock, 0.25)
	fx.FrameClock = 0

	local feet = -fx.FootDrop
	local k = math.min(i, 1.4)
	local height = lerp(SHELL_HEIGHT[1], SHELL_HEIGHT[2], k) * S * fx.Flare
	local half = lerp(SHELL_WIDTH[1], SHELL_WIDTH[2], math.min(k, 1.2)) * S
	local share = i > 0.02 and math.clamp(0.3 + 0.8 * i, 0, 1) or 0 -- fewer flames at low power
	for _, t in fx.Tongues do
		local group = t.Group
		t.Phase += step * lerp(group.Speed[1], group.Speed[2], math.min(k, 1.2)) * t.SpeedMul
		if t.Phase >= 1 then
			t.Phase -= math.floor(t.Phase)
			respawn(t)
		end
		if t.Index > math.ceil(t.Of * share) then
			if t.Beam.Width0 ~= 0 then
				t.Beam.Width0 = 0
			end
			continue
		end
		-- every drawn frame each flame wobbles a little, as if redrawn by hand
		t.Boil = rng:NextNumber(0.85, 1.15)
		local a = t.Angle + rng:NextNumber(-0.06, 0.06)
		-- each lick shoots out fast, then thins away and starts again somewhere else
		local p = t.Phase
		local grow = smooth(0, 0.3, p)
		local fade = 1 - smooth(0.65, 1, p)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local width = lerp(group.Width[1], group.Width[2], k) * S * t.WidthMul * (0.4 + 0.6 * grow) * (0.25 + 0.75 * fade)
		if camDir then
			-- flames between the camera and the character thin out so they don't hide them
			width *= 1 - 0.65 * smooth(0.3, 0.85, out:Dot(camDir))
		end
		if t.Kind == "Spike" then
			-- sits on the shell and points outward: sideways low down, diagonally in the middle,
			-- straight up on top, curling upward at the tip
			local u = t.U
			local dir = (out * (1.15 - 0.95 * u) + Vector3.yAxis * (-0.1 + 1.45 * u)).Unit
			local len = (0.18 + 0.22 * u) * height * t.LenMul * t.Boil * (0.5 + 0.5 * grow)
			local base = out * (outline(u) * half * 0.8) + Vector3.new(0, feet + u * height, 0)
			t.A0.CFrame = pointing(base, dir)
			t.A1.CFrame = pointing(base + dir * len, (dir + Vector3.yAxis * 0.5).Unit)
			t.Beam.CurveSize0 = len * 0.3
			t.Beam.CurveSize1 = len * 0.25
		elseif t.Kind == "Body" then
			-- rises from the feet, bows outward along the shell and meets the top
			local top = t.TipU * height * t.Boil * (0.6 + 0.4 * grow)
			local base = out * (t.R0 * S) + Vector3.new(0, feet + 0.1 * S, 0)
			t.A0.CFrame = pointing(base, (out * 0.9 + Vector3.yAxis * 0.7).Unit)
			t.A1.CFrame = CFrame.new(-out * (t.TipOff * S) + Vector3.new(0, feet + top, 0)) * UP_FRAME
			t.Beam.CurveSize0 = top * 0.45
			t.Beam.CurveSize1 = top * 0.2
		else
			local h = t.TipU * height * t.Boil * (0.5 + 0.5 * grow)
			local base = out * (t.R0 * S) + Vector3.new(0, feet + t.Lift * S, 0)
			t.A0.CFrame = CFrame.new(base) * UP_FRAME
			t.A1.CFrame = CFrame.new(base + out * (0.3 * S) + Vector3.new(0, h, 0)) * UP_FRAME
			t.Beam.CurveSize0 = h * 0.35
			t.Beam.CurveSize1 = h * 0.2
		end
		t.Beam.Width0 = width
	end

	-- energy streaks swirling up around the body
	local swirl = smooth(0.35, 0.8, i)
	for _, w in fx.Swooshes do
		w.Angle += step * w.Spin * (0.6 + i)
		w.Y += step * w.Rise * (0.6 + i)
		if w.Y > w.Top then
			resetSwoosh(w, feet, false)
		end
		local arc = 1.3 * (w.Spin > 0 and 1 or -1)
		local a, b = w.Angle, w.Angle + arc
		local p0 = Vector3.new(math.cos(a) * w.R, w.Y, math.sin(a) * w.R)
		local p1 = Vector3.new(math.cos(b) * w.R, w.Y + 1.2 * S, math.sin(b) * w.R)
		local dirSign = w.Spin > 0 and 1 or -1
		w.A0.CFrame = pointing(p0, Vector3.new(-math.sin(a) * dirSign, 0.25, math.cos(a) * dirSign).Unit)
		w.A1.CFrame = pointing(p1, Vector3.new(-math.sin(b) * dirSign, 0.25, math.cos(b) * dirSign).Unit)
		local curve = w.R * math.abs(arc) / 3
		w.Beam.CurveSize0 = curve
		w.Beam.CurveSize1 = curve
		local life = smooth(feet, feet + 1.5 * S, w.Y) * (1 - smooth(w.Top - 2 * S, w.Top, w.Y))
		w.Beam.Width0 = 0.04 * S * swirl * life
		w.Beam.Width1 = 0.4 * S * swirl * life
	end
end

local moveParts, moveFrames = {}, {}

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	table.clear(moveParts)
	table.clear(moveFrames)
	local seen = {}
	local finished = {}
	local filter = characters()
	table.insert(filter, folder)
	groundParams.FilterDescendantsInstances = filter
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position

	for _, character in characters() do
		seen[character] = true
		local root = character:FindFirstChild("HumanoidRootPart")
		local want = targetIntensity(character)
		local state = character:GetAttribute("PowerState")
		local fx = active[character]
		if not fx and (want > 0 or state == "Charging") and root then
			fx = newFX(character, root)
			active[character] = fx
		end
		if fx and root then
			-- smooth ramps: fast up, slower down
			fx.Intensity = ease(fx.Intensity, want, want > fx.Intensity and 5 or 2, dt)
			local i = fx.Intensity
			fx.Flare = ease(fx.Flare, 1, 2.5, dt)
			local gold = (character:GetAttribute("Form") == "SSJ" or state == "Bursting") and 1 or 0
			fx.Gold = ease(fx.Gold, gold, 6, dt)
			if math.abs(fx.Gold - fx.PaintedGold) > 0.01 then
				paint(fx)
			end

			if state == "Bursting" and not fx.Burst then
				fx.Burst = true
				local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
				playBurst(fx, root, hit and hit.Position.Y or root.Position.Y - fx.FootDrop)
			elseif state ~= "Bursting" then
				fx.Burst = false
			end

			-- the aura follows the character, kept upright
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local auraCF = flat.Magnitude > 1e-3 and CFrame.lookAt(root.Position, root.Position + flat) or CFrame.new(root.Position)
			table.insert(moveParts, fx.Aura)
			table.insert(moveFrames, auraCF)
			local camDir = nil
			if camPos then
				local rel = auraCF:PointToObjectSpace(camPos)
				local h = Vector3.new(rel.X, 0, rel.Z)
				if h.Magnitude > 0.5 and rel.Magnitude < 80 then
					camDir = h.Unit
				end
			end
			updateAura(fx, i, dt, camDir)

			-- ground: dust and lifting rocks (only if there's ground close below)
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(fx.FootDrop + 5), 0), groundParams)
			local groundY = hit and hit.Position.Y
			if groundY then
				table.insert(moveParts, fx.Ground)
				table.insert(moveFrames, CFrame.new(root.Position.X, groundY + 0.2, root.Position.Z))
			end
			fx.Dust.Rate = (groundY and i > 0.55) and 40 * (i - 0.55) / 0.45 or 0
			for _, rock in fx.Rocks do
				local lift = (groundY and i > 0.7) and rock.Top * math.clamp((i - 0.7) / 0.3, 0, 1) or 0
				if lift > rock.Height then
					rock.Height += (lift - rock.Height) * (1 - math.exp(-dt * 1.5))
				else
					rock.Height = math.max(lift, rock.Height - dt * 6) -- falls back down
				end
				if rock.Height > 0.02 and groundY then
					rock.Part.Transparency = 0
					rock.Angle += dt * 0.25
					local pos = root.Position + Vector3.new(math.cos(rock.Angle), 0, math.sin(rock.Angle)) * rock.Radius
					local bob = math.sin(now * 2 + rock.Bob) * 0.15 * math.min(1, rock.Height)
					table.insert(moveParts, rock.Part)
					table.insert(moveFrames, CFrame.new(pos.X, groundY + rock.Part.Size.Y / 2 + rock.Height + bob, pos.Z)
						* CFrame.Angles(now * rock.Spin, now * rock.Spin * 0.7, 0))
				else
					rock.Part.Transparency = 1
				end
			end

			-- the animation: how far into each key pose we are
			local posing = state == "Charging" or state == "Bursting"
			fx.Pose = ease(fx.Pose, posing and 1 or 0, posing and 6 or 3.5, dt)
			if state == "Charging" then
				local charge = character:GetAttribute("Charge") or 0
				fx.Strain = ease(fx.Strain, smooth(0.2, 0.85, charge), 3, dt)
				fx.Release = ease(fx.Release, 0, 10, dt)
			elseif state == "Bursting" then
				fx.Release = ease(fx.Release, 1, 14, dt) -- snaps into the release pose and holds it
			end
			fx.Shudder = math.max(fx.Shudder - dt * 0.8, 0)
			fx.Tremble = 0.035 * fx.Strain * (1 - fx.Release) + 0.03 * fx.Shudder

			-- tidy up once fully calm
			if want <= 0 and fx.Intensity < 0.01 and fx.Pose < 0.01 and state ~= "Charging" then
				table.insert(finished, fx)
				active[character] = nil
			end
		end
	end
	for character, fx in active do
		if not seen[character] or not character.Parent then
			table.insert(finished, fx)
			active[character] = nil
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- removed only after this frame's moves, so nothing moves a part that's already gone
	for _, fx in finished do
		destroyFX(fx)
	end
end)

-- The pose goes on after Roblox has played the character's animations for this frame (in
-- PreSimulation, as Roblox recommends), blended with them by how far into the power-up we are.
local okPre, preSimulation = pcall(function()
	return RunService.PreSimulation
end)
local poseSignal = (okPre and preSimulation) or RunService.Stepped
poseSignal:Connect(function()
	local t = os.clock()
	for _, fx in active do
		-- joints can be swapped out after spawning (e.g. by the joint upgrade): look again if so
		if t >= fx.NextJointScan then
			fx.NextJointScan = t + 1
			local ok = next(fx.Motors) ~= nil
			for _, joint in fx.Motors do
				if not joint.Parent then
					ok = false
				end
			end
			if not ok then
				fx.Motors = findJoints(fx.Character)
				table.clear(fx.LastWritten)
			end
		end
		if fx.Pose > 0.001 then
			local w = math.min(fx.Pose, 1)
			local tremble = fx.Tremble or 0
			for name, motor in fx.Motors do
				if motor.Parent then
					local current = motor.Transform
					-- if the animator didn't touch this joint since our last write, blend from rest
					if fx.LastWritten[name] and sameFrame(current, fx.LastWritten[name]) then
						current = CFrame.identity
					end
					local pose = READY[name]:Lerp(STRAIN[name], fx.Strain):Lerp(RELEASE[name], fx.Release)
					local shake = SHAKE[name]
					if shake and tremble > 0 then
						local a = tremble * shake
						pose *= CFrame.Angles(math.sin(t * 41 + #name) * a, math.sin(t * 37) * a, math.sin(t * 29 + #name) * a)
					end
					local final = current:Lerp(pose, w)
					motor.Transform = final
					fx.LastWritten[name] = final
				end
			end
		else
			table.clear(fx.LastWritten)
		end
	end
end)
