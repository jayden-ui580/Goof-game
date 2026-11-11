--[[
	PowerFX  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Draws powering up for EVERY character on this player's screen, from the attributes
	PowerUpServer sets (so everyone sees everyone's aura):
	  * the power-up animation, coded joint by joint (no animation asset needed):
	      start     standing tall, fists clenched at the waist, elbows out
	      charging  the fuller the bar, the more you hunch over with your head down and your
	                elbows thrown wide, trembling with effort
	      transform you stay hunched as the power builds, then at the explosion you lean back,
	                head up, arms lowered and spread ... then your arms come in (your left
	                fingers on the inside of your right elbow), you coil, and swipe the left arm
	                out into a point at the camera: "YOU'RE FINISHED!" (PowerConfig.PointAt)
	      Kaioken   each level snaps you into a flex: chest out, head back, fists driven down
	      exhausted bent over, head hanging, breathing hard
	  * the aura: a glowing ring on the ground at your feet with a sheet of fire rising from it
	    all the way round you. The flames are rooted on the ring, lean outward as they rise and
	    fade at their tips; thin streaks shoot up through them and licks of flame break off and
	    rise. Energy swirls round you, ripples pulse out along the ground and sparks float up.
	    It grows bigger and faster as the bar fills; blue in base form, gold as a Super Saiyan,
	    red in Kaioken. After transforming the gold aura stays up, then fades when you calm down
	    (the Breeze attribute).
	  * the Kaioken: a red aura sized by the level, a red glow over your whole body throbbing
	    like a heartbeat (faster the higher you go), a red shockwave each time you push it, and
	    a strained tremble at x10 and x20,
	  * dust blasting off the ground and rocks lifting at high power,
	  * the transformation explosion: a pillar of light, a flash, a shockwave ring and a spray.
	The hair and belt being blown upward is HairPhysics reacting to the AuraWind attribute.
	Settings: ReplicatedStorage > PowerConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))
local PoseLayers = require(ReplicatedStorage:WaitForChild("PoseLayers"))

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local ROCKS = 8
local S = PowerConfig.AuraSize
local EXPLODE_AT = PowerConfig.ExplodeAt or 0
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
local RELEASE = { -- the explosion: leaning back, head up, arms lowered and spread
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

-- Kaioken: the flex you snap into each time you light it or push it higher: chest out, head
-- back (a shout), arms driven down and back, fists clenched, knees bent
local KAIOKEN_FLEX = {
	Root = CFrame.new(0, -0.14, 0) * CFrame.Angles(0.06, 0, 0),
	Waist = CFrame.Angles(0.22, 0, 0),
	Neck = CFrame.Angles(0.38, 0, 0),
	LeftShoulder = CFrame.Angles(-0.38, 0, -0.42),
	RightShoulder = CFrame.Angles(-0.38, 0, 0.42),
	LeftElbow = CFrame.Angles(0.5, 0, 0),
	RightElbow = CFrame.Angles(0.5, 0, 0),
	LeftWrist = CFrame.Angles(-0.2, 0, 0),
	RightWrist = CFrame.Angles(-0.2, 0, 0),
	LeftHip = CFrame.Angles(0.28, 0, -0.24),
	RightHip = CFrame.Angles(0.28, 0, 0.24),
	LeftKnee = CFrame.Angles(-0.5, 0, 0),
	RightKnee = CFrame.Angles(-0.5, 0, 0),
	LeftAnkle = CFrame.Angles(0.22, 0, 0.14),
	RightAnkle = CFrame.Angles(0.22, 0, -0.14),
}
-- exhausted (the Kaioken pushed until your body gave out): bent over, head hanging, arms limp
local SLUMP = {
	Root = CFrame.new(0, -0.1, 0) * CFrame.Angles(-0.1, 0, 0),
	Waist = CFrame.Angles(-0.3, 0, 0),
	Neck = CFrame.Angles(-0.35, 0, 0),
	LeftShoulder = CFrame.Angles(0.15, 0, 0.08),
	RightShoulder = CFrame.Angles(0.15, 0, -0.08),
	LeftElbow = CFrame.Angles(0.2, 0, 0),
	RightElbow = CFrame.Angles(0.2, 0, 0),
	LeftWrist = CFrame.identity,
	RightWrist = CFrame.identity,
	LeftHip = CFrame.Angles(0.3, 0, -0.06),
	RightHip = CFrame.Angles(0.3, 0, 0.06),
	LeftKnee = CFrame.Angles(-0.5, 0, 0),
	RightKnee = CFrame.Angles(-0.5, 0, 0),
	LeftAnkle = CFrame.Angles(0.2, 0, 0),
	RightAnkle = CFrame.Angles(0.2, 0, 0),
}

-- The "YOU'RE FINISHED!" point at the end of the transformation. From the release pose your
-- arms come in (TOUCH: right forearm up, left fingertips on the inside of your right elbow),
-- you coil for a beat, then swipe the left arm out into a point at the camera (HIT). Every
-- joint starts a moment after the one driving it and overshoots a little before settling, the
-- body sinks into the stance and the head gives a nod. Angles in degrees: { x, y, z } (Root
-- also moves: { x, y, z, studs right, up, back }).
local POINT_TOUCH = {
	Root = { 0, -10, 0, 0, -0.05, 0 },
	Waist = { -4, -18, 0 },
	Neck = { -6, 26, 0 },
	RightShoulder = { 72, 0, -32 },
	RightElbow = { 108, 0, 0 },
	RightWrist = { 0, 0, 0 },
	LeftShoulder = { 56.3, -18.5, 78.1 },
	LeftElbow = { 54.8, 0, 0 },
	LeftWrist = { -10.6, 0, 26.7 },
	LeftHip = { 6, 0, -10 },
	RightHip = { 6, 0, 8 },
	LeftKnee = { -12, 0, 0 },
	RightKnee = { -8, 0, 0 },
	LeftAnkle = { 4, 0, 6 },
	RightAnkle = { 2, 0, -6 },
}
local POINT_HIT = {
	Root = { 0, -12, 0, 0, -0.12, 0 },
	Waist = { -7, -16, 0 },
	Neck = { -9, 24, 6 },
	RightShoulder = { -28, 0, 24 }, -- the right fist pulled back to the hip
	RightElbow = { 100, 0, 0 },
	RightWrist = { 0, 0, 0 },
	LeftShoulder = { 86.4, 1.6, -29.6 }, -- the left arm straight out at the camera
	LeftElbow = { 4, 0, 0 },
	LeftWrist = { 1.5, 0, -16.4 },
	LeftHip = { 16, 0, -18 },
	RightHip = { -6, 0, 16 },
	LeftKnee = { -24, 0, 0 },
	RightKnee = { -10, 0, 0 },
	LeftAnkle = { 8, 0, 10 },
	RightAnkle = { -4, 0, -8 },
}
local POINT_COIL = { Root = { 0, -3, 0 }, Waist = { 0, -5, 0 }, LeftShoulder = { 0, 0, 5 }, RightElbow = { 6, 0, 0 } }
-- per joint: { delay into TOUCH, delay into the swipe, swipe length, overshoot }
local POINT_TIMING = {
	default = { 0, 0, 0.28, 0.6 },
	Root = { 0, 0, 0.3, 0.8 },
	Waist = { 0.03, 0.01, 0.26, 1.2 },
	Neck = { 0.02, 0.04, 0.24, 1.0 },
	LeftShoulder = { 0.06, 0.02, 0.2, 2.0 },
	LeftElbow = { 0.09, 0.05, 0.17, 1.6 },
	LeftWrist = { 0.11, 0.08, 0.15, 1.8 },
	RightShoulder = { 0.05, 0, 0.22, 1.2 },
	RightElbow = { 0.08, 0.02, 0.2, 1.2 },
	RightWrist = { 0.1, 0.04, 0.18, 1.0 },
}
local POINT_IN, POINT_SWIPE = 0.4, 0.62 -- seconds after PointAt: arms in by; the swipe starts
local POINT_LAND = POINT_SWIPE + 0.19 -- the point lands (the third manga panel slams in)

local function smoother(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

-- 0..1 with an overshoot past 1 before settling (bigger c1 = more overshoot)
local function backOut(x: number, c1: number): number
	x = math.clamp(x, 0, 1)
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local POINT_E = {}
do
	local function angles(t)
		return Vector3.new(math.rad(t[1]), math.rad(t[2]), math.rad(t[3])), Vector3.new(t[4] or 0, t[5] or 0, t[6] or 0)
	end
	for name, cf in RELEASE do
		local rx, ry, rz = cf:ToEulerAnglesXYZ()
		local ta, tp = angles(POINT_TOUCH[name])
		local ha, hp = angles(POINT_HIT[name])
		local coil = POINT_COIL[name] and (angles(POINT_COIL[name])) or Vector3.zero
		POINT_E[name] = { RA = Vector3.new(rx, ry, rz), RP = cf.Position, TA = ta, TP = tp, HA = ha, HP = hp, Coil = coil }
	end
end

-- the point pose of one joint, t seconds after PowerConfig.PointAt
local function pointPose(name: string, t: number): CFrame
	local e = POINT_E[name]
	local d = POINT_TIMING[name] or POINT_TIMING.default
	local a = smoother((t - d[1]) / POINT_IN)
	local b = backOut((t - POINT_SWIPE - d[2]) / d[3], d[4])
	local coil = smoother((t - POINT_IN) / (POINT_SWIPE - POINT_IN)) * (1 - smoother((t - POINT_SWIPE) / 0.1))
	local ang = e.RA + (e.TA - e.RA) * a + (e.HA - e.TA) * b + e.Coil * coil
	local pos = e.RP + (e.TP - e.RP) * a + (e.HP - e.TP) * b
	local land = t - POINT_LAND
	if land > 0 then
		if name == "Root" then -- the body sinks into the stance and bobs back up
			pos += Vector3.new(0, -0.07 * math.exp(-8 * land) * math.cos(13 * land), 0)
		elseif name == "Neck" then -- a nod
			ang += Vector3.new(math.rad(-7) * math.exp(-9 * land) * math.sin(15 * land), 0, 0)
		end
		if name == "Waist" or name == "LeftShoulder" then -- breathing while holding it
			ang += Vector3.new(math.rad(1.2) * math.sin(land * 5.5) * smoother(land / 0.6), 0, 0)
		end
	end
	return CFrame.new(pos) * CFrame.Angles(ang.X, ang.Y, ang.Z)
end

-- how strongly the Kaioken flex holds, t seconds after you pushed it a level
local function flexWeight(t: number): number
	if t < 0 or t > 0.9 then
		return 0
	elseif t < 0.1 then
		return smoother(t / 0.1)
	elseif t < 0.42 then
		return 1
	end
	return 1 - smoother((t - 0.42) / 0.45)
end

----------------------------------------------------------------------------------------
-- the aura
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

-- sizes in studs, each {at no power, at full power}
local RING_RADIUS = { 1.7, 2.4 } -- the glowing ring on the ground the flames rise from
local FLAME_HEIGHT = { 2.6, 8.5 } -- the tallest flames
local FLAME_LEAN = { 0.4, 2.2 } -- how far the tops of the tallest flames lean out
local RING_SEGMENTS = 36 -- glowing pieces the ground ring is made of
local RIPPLE_SEGMENTS = 24 -- ... and each ripple pulsing out from it
local SWOOSHES = 4 -- energy streaks swirling up around you

-- The flames are Beams: tapered ribbons that always face the camera, so each one reads as a
-- flame tongue. Per group: how many; how tall (share of FLAME_HEIGHT) and wide at the base;
-- how fast they flicker {no power, full power}; how see-through from root (0) to tip (1); and
-- colours. The sheet's flames overlap all the way round, so together they look like one fire,
-- brightest at its edges where you look through the most flames.
local GROUPS = {
	{ -- the sheet of fire, rooted on the ground ring
		Kind = "Sheet", Count = 30, Height = { 0.55, 1 }, Width = { 0.9, 1.5 }, Speed = { 2, 5 },
		Transparency = seq({ { 0, 0.78 }, { 0.15, 0.5 }, { 0.45, 0.45 }, { 0.8, 0.78 }, { 1, 1 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, main }, { 0.5, main }, { 1, edge } })
		end,
	},
	{ -- thin bright streaks shooting up through it
		Kind = "Streak", Count = 8, Height = { 0.6, 1 }, Width = { 0.18, 0.3 }, Speed = { 4, 8 },
		Transparency = seq({ { 0, 0.75 }, { 0.25, 0.3 }, { 0.7, 0.55 }, { 1, 1 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, Color3.new(1, 1, 1) }, { 0.5, core }, { 1, main } })
		end,
	},
	{ -- licks of flame breaking off and rising (Speed = licks per second)
		Kind = "Lick", Count = 10, Height = { 0.25, 0.45 }, Width = { 0.6, 1.1 }, Speed = { 1.2, 2.4 },
		Transparency = seq({ { 0, 1 }, { 0.2, 0.45 }, { 0.6, 0.55 }, { 1, 1 } }),
		Paint = function(core, main, edge)
			return colours({ { 0, main }, { 0.5, main }, { 1, edge } })
		end,
	},
}
local AURA_FPS = math.max(PowerConfig.AuraFrameRate or 24, 1)

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

local function ringPiece(name: string): Part
	local p = fxPart(name, Vector3.new(0.4, 0.06, 0.2))
	p.Material = Enum.Material.Neon
	return p
end

-- a new random start for a flame (and, for a lick, a new place to break off from)
local function reroll(t)
	t.WidthMul = rng:NextNumber(0.75, 1.25)
	t.HeightMul = rng:NextNumber(0, 1)
	t.LeanMul = rng:NextNumber(0.7, 1.3)
	t.SpeedMul = rng:NextNumber(0.75, 1.3)
	if t.Kind == "Lick" then
		t.Angle = rng:NextNumber(0, math.pi * 2)
	end
end

local function resetSwoosh(w, feet: number, first: boolean)
	w.Angle = rng:NextNumber(0, math.pi * 2)
	w.R = rng:NextNumber(2.2, 3.2) * S
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
		Red = 0, -- Kaioken red (the aura's colour)
		PaintedRed = -1,
		GlowW = 0, -- the red glow over the body
		PointMix = 0, -- 1 while the "YOU'RE FINISHED!" point plays
		PointT = 0,
		FlexW = 0, -- the Kaioken flex
		Slump = 0, -- exhausted
		KaiokenSeen = 0,
		Spin = 0, -- the whole fire slowly turns round you
		RipplePhase = 0,
		-- how far below the HumanoidRootPart's centre the feet are
		FootDrop = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2,
	}
	fx.Aura = fxPart("Aura", Vector3.new(4.8, 6, 4.8) * S)

	fx.Tongues = {}
	local amount = math.max(PowerConfig.AuraFlames or 1, 0)
	for gi, group in GROUPS do
		local count = math.max(1, math.floor(group.Count * amount + 0.5))
		local offset = rng:NextNumber(0, math.pi * 2)
		for k = 1, count do
			local beam, a0, a1 = newBeam(fx.Aura, group.Transparency)
			local t = {
				Group = group, GroupIndex = gi, Kind = group.Kind, Index = k, Of = count,
				Beam = beam, A0 = a0, A1 = a1, Boil = 1, BoilAngle = 0,
				-- spread evenly round the ring, a little uneven
				Angle = (k - 1) / count * math.pi * 2 + offset + rng:NextNumber(-0.4, 0.4) * (math.pi * 2 / count),
				Phase = rng:NextNumber(0, math.pi * 2),
				Life = rng:NextNumber(),
			}
			reroll(t)
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

	-- the glowing ring on the ground, and the ripples pulsing out of it
	fx.Ring, fx.RingLocal = {}, {}
	for k = 1, RING_SEGMENTS do
		fx.Ring[k] = ringPiece("AuraRing")
		fx.RingLocal[k] = CFrame.identity
	end
	fx.RipplePieces, fx.RippleLocal = {}, {}
	for k = 1, RIPPLE_SEGMENTS do
		fx.RipplePieces[k] = ringPiece("AuraRipple")
		fx.RippleLocal[k] = CFrame.identity
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
	fx.Sparks = emitter(fx.Aura, { -- sparks floating up through the fire
		Texture = SPARK,
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 2, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.28 * S),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	fx.Haze = emitter(fx.Aura, { -- a soft glow around the flames
		Texture = SMOKE,
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.7, 1.1),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(20, 20),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 1) }),
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
			Radius = rng:NextNumber(3.5, 6) * S,
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
	for _, p in fx.Ring do
		p:Destroy()
	end
	for _, p in fx.RipplePieces do
		p:Destroy()
	end
	if fx.Pillar then
		fx.Pillar:Destroy()
	end
	if fx.Glow then
		fx.Glow:Destroy()
	end
	for name, motor in fx.Motors do
		if motor.Parent and fx.LastWritten[name] and sameFrame(motor.Transform, fx.LastWritten[name]) then
			motor.Transform = CFrame.identity
		end
	end
end

-- recolours everything when the aura's colour changes (base blue <-> Super Saiyan gold, or
-- Kaioken red)
local function paint(fx)
	local g, r = fx.Gold, fx.Red
	local main = PowerConfig.BaseAuraColor:Lerp(PowerConfig.SSJAuraColor, g):Lerp(PowerConfig.KaiokenAuraColor, r)
	local edge = PowerConfig.BaseAuraEdge:Lerp(PowerConfig.SSJAuraEdge, g):Lerp(PowerConfig.KaiokenAuraEdge, r)
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
	local ringColor = main:Lerp(Color3.new(1, 1, 1), 0.25)
	for _, p in fx.Ring do
		p.Color = ringColor
	end
	for _, p in fx.RipplePieces do
		p.Color = main
	end
	fx.Streaks.Color = ColorSequence.new(core, main)
	fx.Sparks.Color = ColorSequence.new(core)
	fx.Haze.Color = ColorSequence.new(main)
	fx.Light.Color = main
	fx.Core, fx.Main, fx.Edge = core, main, edge
	fx.PaintedGold, fx.PaintedRed = g, r
end

----------------------------------------------------------------------------------------
-- the transformation explosion
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

-- each time the Kaioken is lit or pushed higher: a red shockwave along the ground and a flash
local function playFlare(fx, root: BasePart, groundY: number)
	fx.Sparks:Emit(40)
	fx.Streaks:Emit(25)
	fx.Light.Brightness = 10
	fx.Flare = math.max(fx.Flare, 1.35)
	fx.Shudder = math.max(fx.Shudder, 0.6)
	local color = PowerConfig.KaiokenAuraColor
	local ring = fxPart("KaiokenWave", Vector3.new(0.25, 2, 2))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(root.Position.X, groundY + 0.15, root.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.25, 22 * S, 22 * S),
		Transparency = 1,
	}):Play()
	local ball = fxPart("KaiokenFlash", Vector3.new(2, 2, 2))
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color:Lerp(Color3.new(1, 1, 1), 0.4)
	ball.Transparency = 0.25
	ball.CFrame = root.CFrame
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(10, 10, 10) * S,
		Transparency = 1,
	}):Play()
	task.delay(0.6, function()
		ring:Destroy()
		ball:Destroy()
	end)
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local active = {} -- [character] = fx
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function targetIntensity(character: Model, fx): number
	local state = character:GetAttribute("PowerState")
	if state == "Charging" then
		local c = character:GetAttribute("Charge") or 0
		return c >= PowerConfig.AuraStart and math.max(c, 0.12) or 0
	elseif state == "Bursting" then
		return (fx and fx.Exploded) and 1.25 or 1 -- the power builds, then explodes out
	end
	local kaioken = character:GetAttribute("Kaioken") or 0
	if kaioken > 0 then
		return PowerConfig.KaiokenAura[kaioken] or 0.7
	elseif PowerConfig.IsSuper(character:GetAttribute("Form")) then
		-- the golden aura stays up after transforming and fades when you calm down
		return PowerConfig.SSJIdleAura * (character:GetAttribute("Breeze") or 1)
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

-- moves the flames, ring, streaks and swirls of one character's aura
local function updateAura(fx, i: number, dt: number, camDir: Vector3?)
	-- glow, light and particles change smoothly every frame
	local visible = i > 0.02
	local k = math.min(i, 1.4)
	fx.Streaks.Rate = i > 0.3 and 70 * (i - 0.3) or 0
	fx.Sparks.Rate = visible and (6 + 34 * i) or 0
	fx.Haze.Rate = visible and (6 + 18 * i) or 0
	fx.Haze.Size = NumberSequence.new(5 * S * (0.7 + 0.5 * i))
	fx.Light.Range = visible and (8 + 18 * i) or 0
	fx.Light.Brightness = ease(fx.Light.Brightness, visible and (1 + 5 * i) or 0, 6, dt)
	fx.Spin += dt * (0.25 + 0.35 * k)

	-- the shapes change in steps (AuraFrameRate a second); a low rate flickers like anime
	fx.FrameClock += dt
	if fx.FrameClock < 1 / AURA_FPS then
		return
	end
	local step = math.min(fx.FrameClock, 0.25)
	fx.FrameClock = 0

	local feet = -fx.FootDrop
	local ringRadius = lerp(RING_RADIUS[1], RING_RADIUS[2], math.min(k, 1.2)) * S
	local tallest = lerp(FLAME_HEIGHT[1], FLAME_HEIGHT[2], k) * S * fx.Flare
	local leanMax = lerp(FLAME_LEAN[1], FLAME_LEAN[2], k) * S
	local share = visible and math.clamp(0.35 + 0.75 * i, 0, 1) or 0 -- fewer flames at low power

	for _, t in fx.Tongues do
		local group = t.Group
		local speed = lerp(group.Speed[1], group.Speed[2], math.min(k, 1.2)) * t.SpeedMul
		if t.Index > math.ceil(t.Of * share) then
			if t.Beam.Width0 ~= 0 then
				t.Beam.Width0 = 0
			end
			continue
		end
		-- each drawn frame every flame wobbles a little, as if redrawn by hand
		t.Boil = rng:NextNumber(0.9, 1.1)
		t.BoilAngle = rng:NextNumber(-0.04, 0.04)
		local a = t.Angle + fx.Spin + t.BoilAngle
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local front = camDir and smooth(0.05, 0.6, out:Dot(camDir)) or 0 -- between the camera and you
		local width = lerp(group.Width[1], group.Width[2], math.min(k, 1)) * S * t.WidthMul
		local height, lean, baseY, radius
		if t.Kind == "Lick" then
			-- breaks off near the ground and rises along the fire, shrinking as it goes
			t.Life += step * speed
			if t.Life >= 1 then
				t.Life -= math.floor(t.Life)
				reroll(t)
			end
			local life = t.Life
			height = lerp(group.Height[1], group.Height[2], t.HeightMul) * tallest * (1 - 0.5 * life) * t.Boil
			baseY = feet + 0.15 * S + life * 0.6 * tallest
			lean = leanMax * t.LeanMul * (baseY - feet) / math.max(tallest, 0.1)
			radius = ringRadius + lean
			width *= (1 - life) * smooth(0, 0.15, life)
		else
			-- rooted on the ring; licks up and down
			t.Phase += step * speed
			local lick = 0.8 + 0.2 * math.sin(t.Phase) + 0.08 * math.sin(t.Phase * 2.7 + t.Index)
			height = lerp(group.Height[1], group.Height[2], t.HeightMul) * tallest * lick * t.Boil
			baseY = feet + 0.03 * S
			radius = ringRadius * (t.Kind == "Streak" and 0.9 or 0.97)
			lean = 0
		end
		local tipLean = leanMax * t.LeanMul * height / math.max(tallest, 0.1)
		width *= 1 - 0.85 * front
		local base = out * radius + Vector3.new(0, baseY, 0)
		local tip = out * (radius + tipLean) + Vector3.new(0, baseY + height, 0)
		t.A0.CFrame = CFrame.new(base) * UP_FRAME
		t.A1.CFrame = pointing(tip, (Vector3.yAxis * height + out * (tipLean * 1.3)).Unit)
		t.Beam.Width0 = width
		t.Beam.CurveSize0 = height * 0.4
		t.Beam.CurveSize1 = height * 0.2
	end

	-- the glowing ground ring: flickers, and swells with power
	local ringOn = visible and smooth(0.02, 0.25, i) or 0
	local length = 2 * ringRadius * math.sin(math.pi / #fx.Ring) * 1.15
	for n, p in fx.Ring do
		local a = (n - 1) / #fx.Ring * math.pi * 2 + fx.Spin * 0.3
		local r = ringRadius * (1 + rng:NextNumber(-0.025, 0.025))
		fx.RingLocal[n] = CFrame.new(math.cos(a) * r, feet + 0.04, math.sin(a) * r) * CFrame.Angles(0, -(a + math.pi / 2), 0)
		p.Size = Vector3.new(length, 0.06 * S, (0.14 + 0.12 * k) * S * rng:NextNumber(0.8, 1.25))
		p.Transparency = 1 - ringOn * rng:NextNumber(0.55, 0.9)
	end
	-- ripples pulse out of it along the ground while the power is high
	fx.RipplePhase += step * (0.9 + 0.8 * k)
	if fx.RipplePhase >= 1 then
		fx.RipplePhase -= math.floor(fx.RipplePhase)
	end
	local ripple = fx.RipplePhase
	local rippleOn = visible and smooth(0.3, 0.7, i) or 0
	local rippleRadius = ringRadius * (1 + 0.9 * ripple)
	local rippleLength = 2 * rippleRadius * math.sin(math.pi / #fx.RipplePieces) * 1.15
	for n, p in fx.RipplePieces do
		local a = (n - 1) / #fx.RipplePieces * math.pi * 2
		fx.RippleLocal[n] = CFrame.new(math.cos(a) * rippleRadius, feet + 0.03, math.sin(a) * rippleRadius)
			* CFrame.Angles(0, -(a + math.pi / 2), 0)
		p.Size = Vector3.new(rippleLength, 0.05 * S, 0.1 * S)
		p.Transparency = 1 - rippleOn * 0.6 * (1 - ripple)
	end

	-- energy streaks swirling up around you
	local swirl = smooth(0.3, 0.75, i)
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
		local state = character:GetAttribute("PowerState")
		local fx = active[character]
		local want = targetIntensity(character, fx)
		if not fx and (want > 0 or state == "Charging" or character:GetAttribute("Exhausted")) and root then
			fx = newFX(character, root)
			active[character] = fx
		end
		if fx and root then
			-- the transformation: the power builds for ExplodeAt seconds, then explodes out
			if state == "Bursting" then
				fx.BurstAt = fx.BurstAt or now
				if not fx.Exploded and now - fx.BurstAt >= EXPLODE_AT then
					fx.Exploded = true
					local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
					playBurst(fx, root, hit and hit.Position.Y or root.Position.Y - fx.FootDrop)
				end
			else
				fx.BurstAt, fx.Exploded = nil, false
			end
			want = targetIntensity(character, fx)

			-- smooth ramps: fast up, slower down
			fx.Intensity = ease(fx.Intensity, want, want > fx.Intensity and 5 or 1.5, dt)
			local i = fx.Intensity
			fx.Flare = ease(fx.Flare, 1, 2.5, dt)
			local gold = (PowerConfig.IsSuper(character:GetAttribute("Form")) or state == "Bursting") and 1 or 0
			fx.Gold = ease(fx.Gold, gold, 6, dt)
			local kaioken = character:GetAttribute("Kaioken") or 0
			-- red while the Kaioken burns, and while its aura dies away after; another aura
			-- (charging, Super Saiyan) takes the colour back
			if kaioken > 0 then
				fx.Red = ease(fx.Red, 1, 8, dt)
			elseif state == "Charging" or state == "Bursting" or gold > 0 then
				fx.Red = ease(fx.Red, 0, 6, dt)
			end
			fx.GlowW = ease(fx.GlowW, kaioken > 0 and 1 or 0, kaioken > 0 and 8 or 3, dt)
			if math.abs(fx.Gold - fx.PaintedGold) > 0.01 or math.abs(fx.Red - fx.PaintedRed) > 0.01 then
				paint(fx)
			end
			-- the Kaioken's red glow over the whole body, throbbing like a heartbeat
			if fx.GlowW > 0.01 then
				if not fx.Glow then
					local glow = Instance.new("Highlight")
					glow.Name = "KaiokenGlow"
					glow.DepthMode = Enum.HighlightDepthMode.Occluded
					glow.FillColor = PowerConfig.KaiokenGlow
					glow.OutlineColor = PowerConfig.KaiokenGlow:Lerp(Color3.new(1, 1, 1), 0.35)
					glow.Adornee = character
					glow.Parent = folder
					fx.Glow = glow
				end
				local beat = 0.5 + 0.5 * math.sin(now * (6 + kaioken))
				fx.Glow.FillTransparency = 1 - fx.GlowW * (0.28 + 0.1 * beat + 0.03 * kaioken)
				fx.Glow.OutlineTransparency = 1 - fx.GlowW * (0.55 + 0.3 * beat)
				fx.Glow.Enabled = true
			elseif fx.Glow then
				fx.Glow.Enabled = false
			end

			-- the aura follows the character, kept upright
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local auraCF = flat.Magnitude > 1e-3 and CFrame.lookAt(root.Position, root.Position + flat) or CFrame.new(root.Position)
			local camDir = nil
			if camPos then
				local rel = auraCF:PointToObjectSpace(camPos)
				local h = Vector3.new(rel.X, 0, rel.Z)
				if h.Magnitude > 0.5 and rel.Magnitude < 80 then
					camDir = h.Unit
				end
			end
			updateAura(fx, i, dt, camDir)
			table.insert(moveParts, fx.Aura)
			table.insert(moveFrames, auraCF)
			for n, p in fx.Ring do
				table.insert(moveParts, p)
				table.insert(moveFrames, auraCF * fx.RingLocal[n])
			end
			for n, p in fx.RipplePieces do
				table.insert(moveParts, p)
				table.insert(moveFrames, auraCF * fx.RippleLocal[n])
			end

			-- ground: dust and lifting rocks (only if there's ground close below)
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(fx.FootDrop + 5), 0), groundParams)
			local groundY = hit and hit.Position.Y
			if groundY then
				table.insert(moveParts, fx.Ground)
				table.insert(moveFrames, CFrame.new(root.Position.X, groundY + 0.2, root.Position.Z))
			end
			fx.Dust.Rate = (groundY and i > 0.55) and 40 * (i - 0.55) / 0.45 or 0

			-- Kaioken: a shockwave and a flex each time it's lit or pushed higher
			local kaiokenLevel = character:GetAttribute("Kaioken") or 0
			if kaiokenLevel > fx.KaiokenSeen then
				fx.FlexAt = now
				playFlare(fx, root, groundY or (root.Position.Y - fx.FootDrop))
			end
			fx.KaiokenSeen = kaiokenLevel
			fx.FlexW = fx.FlexAt and flexWeight(now - fx.FlexAt) or 0
			fx.Slump = ease(fx.Slump, character:GetAttribute("Exhausted") and 1 or 0, 4, dt)
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
				if fx.Exploded then
					fx.Release = ease(fx.Release, 1, 14, dt) -- snaps into the release pose and holds it
				else
					fx.Strain = ease(fx.Strain, 1, 4, dt) -- hunched, straining, as the power builds
				end
				-- then the "YOU'RE FINISHED!" point
				local pointAt = PowerConfig.PointAt
				-- (only the first transformation, Super Saiyan, has the point)
				if pointAt and character:GetAttribute("Form") == "SSJ" and now - fx.BurstAt >= pointAt then
					fx.PointMix = 1
					fx.PointT = now - fx.BurstAt - pointAt
				end
			end
			if state ~= "Bursting" and fx.Pose < 0.01 then
				fx.PointMix = 0 -- (held while the pose fades out after the transformation)
			end
			fx.Shudder = math.max(fx.Shudder - dt * 0.8, 0)
			local building = (state == "Bursting" and not fx.Exploded) and 0.5 or 0
			local pointing = fx.PointMix * (1 - smoother((fx.PointT - POINT_LAND) / 0.3))
			fx.Tremble = (0.035 * fx.Strain * (1 - fx.Release) + 0.03 * fx.Shudder + 0.02 * building) * (1 - pointing)
				+ 0.012 * math.max(0, kaiokenLevel - 3)
				+ 0.025 * fx.FlexW

			-- tidy up once fully calm
			if
				want <= 0
				and fx.Intensity < 0.01
				and fx.Pose < 0.01
				and fx.FlexW < 0.01
				and fx.Slump < 0.01
				and fx.GlowW < 0.01
				and state ~= "Charging"
				and not character:GetAttribute("Exhausted")
			then
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

-- The pose goes on after Roblox has played the character's animations for this frame and after
-- Locomotion's walk / idle (PoseLayers runs them in that order, in PreSimulation as Roblox
-- recommends), blended with them by how far into the power-up we are.
PoseLayers.Add(20, "PowerFX", function()
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
		local w = math.min(fx.Pose, 1)
		local flexW, slumpW = fx.FlexW or 0, fx.Slump or 0
		if w > 0.001 or flexW > 0.001 or slumpW > 0.001 then
			local tremble = fx.Tremble or 0
			for name, motor in fx.Motors do
				if motor.Parent then
					local current = motor.Transform
					-- if the animator didn't touch this joint since our last write, blend from rest
					if fx.LastWritten[name] and sameFrame(current, fx.LastWritten[name]) then
						current = CFrame.identity
					end
					-- layers on top of the walk/idle animation: the power-up (or the point), the
					-- Kaioken flex, the exhausted slump
					local final = current
					if w > 0.001 then
						local pose = READY[name]:Lerp(STRAIN[name], fx.Strain):Lerp(RELEASE[name], fx.Release)
						if fx.PointMix > 0 then
							pose = pose:Lerp(pointPose(name, fx.PointT), fx.PointMix)
						end
						final = final:Lerp(pose, w)
					end
					if flexW > 0.001 then
						final = final:Lerp(KAIOKEN_FLEX[name], flexW)
					end
					if slumpW > 0.001 then
						local slump = SLUMP[name]
						if name == "Waist" or name == "Neck" then -- breathing hard
							slump *= CFrame.Angles(0.06 * math.sin(t * 6.5), 0, 0)
						end
						final = final:Lerp(slump, slumpW)
					end
					local shake = SHAKE[name]
					if shake and tremble > 0 then
						local a = tremble * shake
						final *= CFrame.Angles(math.sin(t * 41 + #name) * a, math.sin(t * 37) * a, math.sin(t * 29 + #name) * a)
					end
					motor.Transform = final
					fx.LastWritten[name] = final
				end
			end
		else
			table.clear(fx.LastWritten)
		end
	end
end)
