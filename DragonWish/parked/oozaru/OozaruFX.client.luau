--[[
	OozaruFX  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Brings the Great Ape to life on this player's screen (every giant, not just yours), coded
	bone by bone, no animation assets:
	  * The entrance: it comes in already roaring: leaning back, head thrown up, jaw wide open,
	    arms flung out with the fingers curled in rage (clawed, not fists), toes gripping the
	    ground, trembling, rings of sound pounding out of its mouth and dust blasting off the
	    ground ... then it drops forward into its hunch: back rounded, head up, knees bent, feet
	    wide apart, arms hanging heavy.
	  * Standing: deep, slow breaths (a puff of breath on each one), its weight rolling from
	    foot to foot, looking around (at anyone close by, if there is someone), now and then a
	    snarl and a shake of the head. The tail sways on its own.
	  * Walking: heavy steps from Gait: each one lands with a dip of the whole body, a thud, a
	    ring of dust and the ground shaking for anyone near. The hips sway, the shoulders roll,
	    the arms swing, the tail swings behind. The steps are worked out from how fast it
	    really moves, so the feet never slide.
	  * Stopping: the swinging foot comes down, the body carries on forward and rocks back, it
	    lets out a big breath, and settles.
	  * Turning: it can't spin on the spot. It turns at a giant's pace (PowerConfig.
	    OozaruTurnSpeed), slowing while it turns hard, and shuffles its feet round.
	For you, while you're the giant: the screen goes black and cuts in on the roar; everything
	is tinted red with a dark red edge that throbs with its breathing; your UI is hidden; the
	camera pulls back to take it all in. A few seconds before it wears off your vision starts
	to swim.
	Settings: ReplicatedStorage > PowerConfig (Oozaru...).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Gait = require(ReplicatedStorage:WaitForChild("Gait"))
local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local player = Players.LocalPlayer
local TAG = "DW_Oozaru"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local INTRO = PowerConfig.OozaruIntro or 4.4
local CUT_IN = 0.25 -- seconds after the giant appears that your screen cuts in on it
local rng = Random.new()

-- how the giant walks (see Gait for what each one does)
local APE = {
	Stride = 1.0, -- shorter, heavier steps than a person's
	Width = 1.3, -- feet wide apart
	ToeOut = math.rad(16),
	SwingShare = { 0.36, 0.6 }, -- (a long time on each foot)
	Lift = { 0.09, 0.2 },
	Bob = { 0.022, 0.03 },
	HeavyDrop = 0.04, -- the whole body dips as each foot lands ...
	ImpactTime = 0.5, -- ... and takes this long to come back up
	Sway = 0.065, -- a rolling waddle from foot to foot
	Yaw = math.rad(8),
	Roll = math.rad(5),
	Pitch = { math.rad(3), math.rad(6) },
	KneeOut = 0.3, -- bow-legged
	ToeOff = math.rad(16), -- flat-footed: not much heel-toe roll
	HeelStrike = math.rad(5),
	SettleTime = 0.7, -- slow, heavy steps to settle or turn
	SettleDistance = 0.12,
	TurnTolerance = math.rad(24),
	FootForward = 0.075, -- (to the ball of the foot, where its toes bend)
	FootBack = 0.05,
	MaxDrop = 0.15,
}

-- fingers: how far each joint curls (degrees) from the knuckle out, and how far they fan
local HANDS = {
	Loose = { 8, 10, 6 },
	Relaxed = { 16, 22, 14 },
	Rage = { 36, 64, 46 }, -- clawed, not a fist
}
local FINGERS = { FORE = -8, MIDDLE = 0, MEDICINAL = 7, LITTLE = 14 } -- (fan, degrees)
local TOES = { "MIDDLE", "FORE", "MEDICINAL", "LITTLE", "THUMB" }

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function ease(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-dt * rate))
end

local function spring(s, target: number, omega: number, zeta: number, dt: number): number
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		local a = omega * omega * (target - s.X) - 2 * zeta * omega * s.V
		s.V += a * h
		s.X += s.V * h
	end
	return s.X
end

local function newSpring(x: number?)
	return { X = x or 0, V = 0 }
end

local function flatYaw(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

----------------------------------------------------------------------------------------
-- effects in the world (seen by everyone)
----------------------------------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = "OozaruFX"
folder.Parent = Workspace

local effects = {} -- { Update = function(dt) -> keep } running each frame

local function fxPart(name: string, shape: Enum.PartType, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Color = colour
	p.Material = material
	p.Transparency = 1
	p.Parent = folder
	return p
end

-- a ring of sound: a shimmering bubble bursting out of the mouth, rushing forward and fading
local function soundRing(at: CFrame, size: number)
	local p = fxPart("RoarRing", Enum.PartType.Ball, Color3.fromRGB(255, 196, 170), Enum.Material.ForceField)
	local t = 0
	table.insert(effects, function(dt)
		t += dt
		local k = math.clamp(t / 0.7, 0, 1)
		local grow = 1 - (1 - k) ^ 3
		local r = size * (0.35 + 2.4 * grow)
		p.Size = Vector3.new(r, r, r * 0.55)
		p.CFrame = at * CFrame.new(0, 0, -size * 2.6 * grow)
		p.Transparency = 0.05 + 0.95 * k
		if k >= 1 then
			p:Destroy()
			return false
		end
		return true
	end)
end

-- a ring of dust blowing out along the ground
local function dustRing(position: Vector3, radius: number, time: number, strength: number)
	local p = fxPart("DustRing", Enum.PartType.Cylinder, Color3.fromRGB(176, 158, 128), Enum.Material.SmoothPlastic)
	local t = 0
	table.insert(effects, function(dt)
		t += dt
		local k = math.clamp(t / time, 0, 1)
		local grow = 1 - (1 - k) ^ 2.4
		local r = radius * (0.25 + 0.75 * grow)
		p.Size = Vector3.new(radius * 0.08 * (1 - k) + 0.05, r * 2, r * 2)
		p.CFrame = CFrame.new(position + Vector3.new(0, radius * 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		p.Transparency = 1 - strength * 0.55 * (1 - k) ^ 1.5
		if k >= 1 then
			p:Destroy()
			return false
		end
		return true
	end)
end

-- puffs of smoke / dust / breath: one emitter, moved to wherever it's needed
local puffHolder = fxPart("Puffs", Enum.PartType.Block, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
puffHolder.Size = Vector3.new(0.2, 0.2, 0.2)
local puffAt = Instance.new("Attachment")
puffAt.Parent = puffHolder
local puffs = Instance.new("ParticleEmitter")
puffs.Texture = SMOKE
puffs.Rate = 0
puffs.LightEmission = 0
puffs.Parent = puffAt
local function puff(position: Vector3, count: number, size: number, colour: Color3, speed: number, direction: Vector3?, life: number?)
	puffHolder.CFrame = CFrame.lookAt(position, position + (direction or Vector3.yAxis))
	puffs.Color = ColorSequence.new(colour)
	puffs.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	puffs.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	puffs.Lifetime = NumberRange.new((life or 1.2) * 0.7, life or 1.2)
	puffs.Speed = NumberRange.new(speed * 0.6, speed)
	puffs.SpreadAngle = Vector2.new(direction and 18 or 180, direction and 18 or 180)
	puffs.EmissionDirection = Enum.NormalId.Front
	puffs.Drag = 2
	puffs.Rotation = NumberRange.new(0, 360)
	puffs.RotSpeed = NumberRange.new(-40, 40)
	puffs:Emit(count)
end

local function sound(id: string, parent: Instance, volume: number, speed: number, range: number)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMaxDistance = range
	s.RollOffMinDistance = range * 0.15
	s.Parent = parent
	s:Play()
	task.delay(10, function()
		s:Destroy()
	end)
end

-- the camera shaking (stomps and roars near you)
local shake = 0
local function addShake(amount: number)
	shake = math.min(shake + amount, 2.5)
end
local function shakeFrom(position: Vector3, strength: number, reach: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local d = (camera.CFrame.Position - position).Magnitude
	local k = 1 - math.clamp(d / reach, 0, 1)
	if k > 0 then
		addShake(strength * k * k)
	end
end
pcall(function()
	RunService:BindToRenderStep("DW_OozaruShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shake > 0.002 then
			local camera = Workspace.CurrentCamera
			local t = os.clock()
			local a = shake
			camera.CFrame = camera.CFrame
				* CFrame.new(math.noise(t * 23, 1.3) * a * 0.5, math.noise(t * 23, 2.7) * a * 0.5, 0)
				* CFrame.Angles(math.noise(t * 19, 3.1) * a * 0.012, math.noise(t * 19, 4.9) * a * 0.012, math.noise(t * 17, 5.3) * a * 0.025)
			shake = math.max(0, shake - dt * (1.2 + shake * 1.8))
		end
	end)
end)

----------------------------------------------------------------------------------------
-- each giant
----------------------------------------------------------------------------------------
local function partOfBone(bone: Instance): BasePart?
	local node = bone.Parent
	while node and not node:IsA("BasePart") do
		node = node.Parent
	end
	return node :: BasePart?
end

local apes = {} -- [model] = state

-- a bone's name as this script knows it (an importer can add a prefix like "Armature:", or
-- change the case)
local function canonical(name: string): string
	return string.upper(string.match(name, "[^:|/]+$") or name)
end

local REQUIRED = { "WAIST", "THIGH_L", "CLANK_L", "TOE1_L", "THIGH_R", "CLANK_R", "TOE1_R", "SPINE1", "HEAD" }

-- the giant's skeleton: returns its state, or nil and why not
local function newApe(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return nil, "it has no HumanoidRootPart or Humanoid (yet)"
	end
	-- every bone, by name. An importer can give each mesh its own copy of the skeleton; every
	-- copy gets the same pose, so whichever one a mesh follows, it moves.
	local copies = {}
	local perPart = {}
	local total = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			local key = canonical(d.Name)
			copies[key] = copies[key] or {}
			table.insert(copies[key], d)
			local part = partOfBone(d)
			if part then
				perPart[part] = (perPart[part] or 0) + 1
			end
			total += 1
		end
	end
	-- the fullest copy gives the rest pose
	local holder, most = nil, 0
	for part, n in perPart do
		if n > most then
			holder, most = part, n
		end
	end
	if not holder then
		return nil, "there are no bones in it (re-import Oozaru_Rigged.fbx with the rig)"
	end
	local joints = {}
	for _, d in holder:GetDescendants() do
		if d:IsA("Bone") then
			local key = canonical(d.Name)
			if not joints[key] then
				local parent = d.Parent
				local parentKey = (parent and parent:IsA("Bone")) and canonical(parent.Name) or nil
				joints[key] = {
					Parent = (parentKey ~= key) and parentKey or nil,
					C0 = d.CFrame,
					C1 = CFrame.identity,
					Instance = d,
					Copies = copies[key],
				}
			end
		end
	end
	for _, j in joints do
		if j.Parent and not joints[j.Parent] then
			j.Parent = nil
		end
	end
	local missing = {}
	for _, name in REQUIRED do
		if not joints[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		local names = {}
		for key in joints do
			table.insert(names, key)
			if #names >= 12 then
				break
			end
		end
		return nil, ("its skeleton is missing %s (it has %d bones, e.g. %s). Re-import Oozaru_Rigged.fbx with Rig Type Custom and \"Keep Zero Influence Bones\" ticked"):format(
			table.concat(missing, ", "), total, table.concat(names, ", "))
	end
	local rig = Gait.Rig.new(joints, root.CFrame:ToObjectSpace(holder.CFrame))
	local gait = Gait.new(rig, {
		Pelvis = "WAIST",
		Legs = {
			Left = { Hip = "THIGH_L", Knee = "CLANK_L", Ankle = "TOE1_L" },
			Right = { Hip = "THIGH_R", Knee = "CLANK_R", Ankle = "TOE1_R" },
		},
		GroundY = -(humanoid.HipHeight + root.Size.Y / 2),
		Params = APE,
	})
	local s = model:GetAttribute("OozaruScale") or 3.2
	-- where the mouth is, on the jaw (for the roar rings and breath)
	local mouth = Vector3.zero
	if joints.CHIN then
		local chinRest = rig.Rest.CHIN
		mouth = chinRest:PointToObjectSpace(chinRest.Position + Vector3.new(0, -0.08 * s, -0.55 * s))
	end
	local tail = {}
	for i = 1, 30 do
		local name = "TAIL" .. i
		if joints[name] then
			table.insert(tail, { Name = name, Yaw = newSpring(), Pitch = newSpring() })
		end
	end
	local now = os.clock()
	return {
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Rig = rig,
		Gait = gait,
		Bones = total,
		Copies = most > 0 and math.floor(total / most + 0.5) or 1,
		Scale = s,
		Mouth = mouth,
		Tail = tail,
		Lean = newSpring(), -- forward lean (+ = forward): the body carrying on when it stops
		ArmL = newSpring(),
		ArmR = newSpring(),
		LookYaw = newSpring(),
		LookPitch = newSpring(),
		LookAt = Vector2.zero,
		NextLook = now + rng:NextNumber(1.5, 3),
		Breath = rng:NextNumber(0, 6),
		LastBreath = 0,
		SnarlAt = -10,
		NextSnarl = now + rng:NextNumber(7, 12),
		HaltAt = -10, -- when it last stopped walking
		Rage = 0,
		LastRing = 0,
		RoarSounded = false,
		Dust = false,
		Seed = rng:NextNumber(0, 100),
		TurnRate = 0,
		Throttle = 0,
		Dead = 0,
	}
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function()
	rayParams.RespectCanCollide = true
end)

local function groundFinder(size: number)
	return function(pos: Vector3): number?
		local hit = Workspace:Raycast(pos + Vector3.new(0, size * 0.6, 0), Vector3.new(0, -size * 1.6, 0), rayParams)
		return hit and hit.Position.Y or nil
	end
end

-- which way a bone's "forward" (the model's -Z at rest) points now, in the world
local function forwardOf(ape, frames, name: string): Vector3
	local rest = ape.Rig.Rest[name]
	local posed = frames[name]
	if not (rest and posed) then
		return ape.Root.CFrame.LookVector
	end
	return (ape.Root.CFrame * posed):VectorToWorldSpace(rest:VectorToObjectSpace(Vector3.new(0, 0, -1)))
end

local function turn(rig, name: string, x: number, y: number, z: number)
	if rig.Joints[name] then
		rig:Write(name, rig:Local(name, CFrame.Angles(x, y, z)))
	end
end

-- the closest person (not a giant) in front of it, to look at
local function someoneNear(ape): Vector3?
	local best, bestD = nil, 26 * ape.Scale
	local root = ape.Root
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and c ~= ape.Model and not c:GetAttribute("Oozaru") then
			local rel = root.CFrame:PointToObjectSpace(r.Position)
			local d = rel.Magnitude
			if d < bestD and rel.Z < 0 then
				best, bestD = r.Position, d
			end
		end
	end
	return best
end

local function poseApe(ape, dt: number, now: number)
	local rig, gait, model, root = ape.Rig, ape.Gait, ape.Model, ape.Root
	local s = ape.Scale
	local L = gait.HipHeight
	local age = Workspace:GetServerTimeNow() - (model:GetAttribute("OozaruAt") or -100)
	local state = model:GetAttribute("PowerState")
	local dead = ape.Humanoid.Health <= 0
	ape.Dead = ease(ape.Dead, dead and 1 or 0, 3, dt)

	-- the entrance: roar = 1 while it's roaring at full; slam = the drop into the hunch
	local roar = 0
	if age < 0.5 then
		roar = 0.35 + 0.65 * smooth(age / 0.5)
	elseif age < 3.0 then
		roar = 1
	elseif age < 3.9 then
		roar = 1 - smooth((age - 3.0) / 0.9)
	end
	local slam = (age > 3.25 and age < 4.35) and math.sin(math.pi * (age - 3.25) / 1.1) or 0
	local tremble = roar * ((age > 0.4 and age < 3.1) and 1 or 0)
	local shrinking = (state == "Shrinking") and 1 or 0
	ape.Shrink = ease(ape.Shrink or 0, shrinking, 5, dt)

	-- roar effects: the sound, rings out of the mouth, dust off the ground, the ground shaking
	local frames = nil
	if roar > 0.75 and age < 3.0 then
		frames = rig:Frames(rig.Out)
		local mouthAt = root.CFrame * (frames.CHIN or frames.HEAD) * ape.Mouth
		local headFwd = forwardOf(ape, frames, "HEAD")
		if not ape.RoarSounded and age > 0.2 then
			ape.RoarSounded = true
			local headBone = rig.Joints.HEAD and rig.Joints.HEAD.Instance
			sound(PowerConfig.OozaruRoarSound, headBone or root, 3, 0.85, 120 * s)
		end
		if now - ape.LastRing > 0.2 then
			ape.LastRing = now
			soundRing(CFrame.lookAt(mouthAt, mouthAt + headFwd), 1.6 * s)
		end
		if not ape.Dust and age > 0.45 then
			ape.Dust = true
			local feet = root.Position + Vector3.new(0, gait.GroundY, 0)
			dustRing(feet, 9 * s, 1.3, 1)
			puff(feet, 30, 2.2 * s, Color3.fromRGB(170, 150, 120), 9 * s, nil, 1.6)
		end
		shakeFrom(mouthAt, 0.06 * roar, 60 * s)
	end

	-- standing: breathing, looking about, a snarl now and then
	local walk = gait.WalkWeight
	local idle = (1 - walk) * (1 - roar)
	ape.Breath += dt * 2 * math.pi / lerp(3.6, 2.4, walk)
	local breath = math.sin(ape.Breath)
	local exhale = math.max(0, -math.cos(ape.Breath)) -- (mouth opens a little as it breathes out)
	if math.floor(ape.Breath / (2 * math.pi)) ~= ape.LastBreath then
		ape.LastBreath = math.floor(ape.Breath / (2 * math.pi))
		if roar < 0.1 and not dead then
			frames = frames or rig:Frames(rig.Out)
			local mouthAt = root.CFrame * (frames.CHIN or frames.HEAD) * ape.Mouth
			local headFwd = forwardOf(ape, frames, "HEAD")
			puff(mouthAt, 3, 0.9 * s, Color3.fromRGB(240, 236, 228), 1.6 * s, (headFwd - Vector3.yAxis * 0.4).Unit, 1.4)
		end
	end
	if now > ape.NextLook then
		local far = rng:NextNumber() < 0.35
		ape.LookAt = Vector2.new(rng:NextNumber(-1, 1) * (far and 0.55 or 0.22), rng:NextNumber(-0.1, 0.12))
		ape.NextLook = now + rng:NextNumber(2.5, 6)
	end
	local look = ape.LookAt
	local someone = someoneNear(ape)
	if someone then
		local rel = root.CFrame:PointToObjectSpace(someone)
		local headY = L * 0.95
		look = Vector2.new(
			math.clamp(math.atan2(-rel.X, -rel.Z), -0.8, 0.8),
			math.clamp(math.atan2(rel.Y - headY, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.5, 0.3)
		)
	end
	if now > ape.NextSnarl and idle > 0.8 then
		ape.SnarlAt = now
		ape.NextSnarl = now + rng:NextNumber(8, 15)
	end
	local sn = now - ape.SnarlAt
	local snarl = (sn < 1.1) and math.sin(math.pi * sn / 1.1) or 0
	local headShake = (sn < 1.1) and math.sin(sn * 26) * 0.09 * snarl or 0

	-- stopping: the body carries on forward, rocks back, and it blows out a big breath
	for _, e in gait.Events do
		if e.Kind == "Stop" then
			ape.Lean.V += 0.9 * math.clamp(e.Speed / math.max(PowerConfig.OozaruWalkSpeed, 1), 0.3, 1.2)
			ape.HaltAt = now
		elseif e.Kind == "Start" then
			ape.Lean.V += 0.35
		elseif e.Kind == "Footfall" then
			local strength = e.Settle and 0.45 or 1
			local at = e.Position
			dustRing(at, 2.6 * s, 0.9, strength)
			puff(at + Vector3.new(0, 0.2 * s, 0), math.floor(5 * strength + 0.5), 0.9 * s, Color3.fromRGB(170, 150, 120), 3.2 * s, nil, 1.1)
			shakeFrom(at, 0.35 * strength, 42 * s)
			local leg = gait.Legs[e.Side]
			local footBone = leg and rig.Joints[leg.Names.Ankle] and rig.Joints[leg.Names.Ankle].Instance
			sound(PowerConfig.OozaruStepSound, footBone or root, 1.6 * strength, 0.32 + rng:NextNumber(-0.03, 0.03), 70 * s)
		elseif e.Kind == "Land" then
			dustRing(root.Position + Vector3.new(0, gait.GroundY, 0), 6 * s, 1.1, 1)
			shakeFrom(root.Position, 0.8, 60 * s)
		end
	end
	local lean = spring(ape.Lean, 0, 4.2, 0.38, dt)
	local h = now - ape.HaltAt
	local halt = (h < 1.6) and math.sin(math.pi * math.clamp((h - 0.25) / 1.1, 0, 1)) or 0 -- the big breath out

	-- how much rage is in the hands (the roar, a snarl)
	ape.Rage = ease(ape.Rage, math.max(roar, snarl * 0.6), 9, dt)
	local rage = ape.Rage

	-- the hips: crouched, leaning into the hunch; up and back to roar; down on the slam
	local cyc = 2 * math.pi * (gait.Phase + 0.05)
	local sway = math.sin(now * 0.8 + ape.Seed) * idle
	local crouch = lerp(-0.075, 0.03, roar) - 0.06 * slam - 0.03 * halt - 0.05 * ape.Dead - 0.08 * ape.Shrink
	local extra = {
		Offset = Vector3.new(sway * 0.045 * L, (crouch + breath * 0.004 * (1 - roar)) * L, -lean * 0.14 * L),
		Turn = CFrame.Angles(lerp(-0.12, 0.2, roar) - 0.1 * slam - lean * 0.25, 0, sway * 0.025),
	}
	local hs = ape.Humanoid:GetState()
	local grounded = hs ~= Enum.HumanoidStateType.Freefall and hs ~= Enum.HumanoidStateType.Jumping
	gait:Step(dt, root.CFrame, root.AssemblyLinearVelocity, grounded, ape.Ground, extra)

	-- the spine: rounded forward into the hunch (back on the roar), turning and rolling
	-- against the hips as it walks, breathing
	local hipYaw = -math.sin(cyc) * gait.P.Yaw * walk
	local tremor = function(k)
		return math.sin(now * 37 + k * 1.9) * 0.022 * tremble
	end
	local hunch = { -0.22, -0.24, -0.13 }
	local rear = { 0.19, 0.22, 0.25 }
	local spineYaw = { 0.03, 0.08, 0.1 }
	local pitchSum = lerp(-0.12, 0.2, roar) - 0.1 * slam - lean * 0.25
	local yawSum = hipYaw
	for i, name in { "SPINE1", "SPINE2", "SPINE3" } do
		local p = lerp(hunch[i], rear[i], roar) - 0.07 * slam - lean * 0.2 - 0.08 * halt - 0.12 * ape.Dead
			+ ((i == 3) and breath * 0.035 * (1 - roar) or 0) + tremor(i)
		local y = math.sin(cyc) * spineYaw[i] * walk
		local r = -math.sin(cyc) * 0.035 * walk * i
		turn(rig, name, p, y, r)
		pitchSum += p
		yawSum += y
	end
	-- head: up and looking ahead out of the hunch; thrown back to roar; looking about
	local lookYaw = spring(ape.LookYaw, look.X * (1 - roar), 3.2, 0.9, dt)
	local lookPitch = spring(ape.LookPitch, look.Y * (1 - roar), 3.2, 0.9, dt)
	local level = -pitchSum * 0.8 * (1 - roar) -- (keeps the eyes on the horizon; not while roaring)
	local up = 0.4 * roar -- (roaring at the sky)
	turn(rig, "NECK", level * 0.45 + up * 0.4 + lookPitch * 0.4 + tremor(4), -yawSum * 0.5 + lookYaw * 0.4 + headShake * 0.4, 0)
	turn(rig, "HEAD", level * 0.55 + up * 0.6 + lookPitch * 0.6 - 0.1 * halt - 0.25 * ape.Dead, -yawSum * 0.4 + lookYaw * 0.6 + headShake, math.sin(now * 0.7) * 0.03 * idle)
	-- the jaw: wide open roaring (with a chatter of rage), parting as it breathes out
	local jaw = 0.72 * roar + math.sin(now * 31) * 0.035 * tremble + 0.05 * exhale * (1 - roar) + 0.24 * snarl + 0.2 * halt + 0.3 * ape.Dead
	turn(rig, "CHIN", -jaw, 0, 0)

	-- arms: hanging heavy in front out of the hunch, swinging against the legs; flung out wide
	-- to roar
	local swingTarget = math.sin(2 * math.pi * (gait.Phase - (gait.SwingShare or 0.36) + 0.25)) * 0.32 * walk
	local armR = spring(ape.ArmR, swingTarget + lean * 0.5, 5.5, 0.55, dt)
	local armL = spring(ape.ArmL, -swingTarget + lean * 0.5, 5.5, 0.55, dt)
	local forwardHang = -pitchSum * 0.9 + 0.12 -- (straight down in the world, a touch in front)
	for _, side in { "L", "R" } do
		local sg = (side == "L") and 1 or -1
		local a = (side == "L") and armL or armR
		local raise = lerp(0.05 * breath * idle, -0.22, roar)
		turn(rig, "CLAVICLE_" .. side, 0, -sg * lerp(0.16, 0.05, roar), sg * -raise * 0.6)
		local hang = lerp(1.22, 0.78, roar) + 0.06 * breath * idle - 0.15 * ape.Shrink
		local swingX = lerp(forwardHang, -0.55, roar) + a + tremor(5 + sg)
		turn(rig, "SHOULDER_" .. side, swingX, 0, sg * hang)
		local bend = lerp(0.42 + math.max(a, 0) * 0.5, 0.95, roar) + 0.35 * ape.Shrink
		turn(rig, "ELBOW_" .. side, 0, -sg * bend, -sg * 0.45 * roar)
		turn(rig, "WRIST_" .. side, 0, 0, sg * lerp(0.08, -0.25, rage))
		-- fingers: softly curled, clawed in rage, loose while walking
		local base = HANDS.Relaxed
		local claw = HANDS.Rage
		local loose = HANDS.Loose
		for finger, fan in FINGERS do
			for j = 1, 3 do
				local curl = lerp(lerp(base[j], loose[j], walk * 0.6), claw[j], rage)
				local spread = (j == 1) and fan * (1 + rage) or 0
				turn(rig, ("F_%s%d_%s"):format(finger, j, side), 0, -sg * math.rad(spread), sg * math.rad(curl))
			end
		end
		for j = 1, 3 do
			local curl = lerp(lerp(10, 6, walk), 30, rage)
			turn(rig, ("F_THUMB%d_%s"):format(j, side), sg * math.rad(curl * 0.4), 0, sg * math.rad(curl * 0.5))
		end
		-- toes: flat on the ground as the heel lifts; gripping while it roars
		local leg = gait.Legs[(side == "L") and "Left" or "Right"]
		turn(rig, "TOE2_" .. side, math.max(leg.FootPitch or 0, 0), 0, 0)
		for _, toe in TOES do
			turn(rig, toe .. "1_" .. side, -0.22 * roar, 0, 0)
			turn(rig, toe .. "2_" .. side, -0.15 * roar, 0, 0)
		end
	end

	-- the tail: hangs back in a lazy curve, swaying on its own, swinging with the steps,
	-- trailing behind turns, lashing while it roars
	local n = #ape.Tail
	for i, seg in ape.Tail do
		local k = i / n
		local shape = (i <= 3) and (0.3 - 0.08 * (i - 1)) or ((k > 0.55) and -0.06 or 0.01)
		local wave = math.sin(now * 1.3 + ape.Seed - i * 0.32) * 0.05 * (0.4 + k)
		local stepSwing = math.sin(cyc - i * 0.22) * 0.035 * walk
		local lash = math.sin(now * 6.5 - i * 0.45) * 0.07 * roar
		local trail = -math.clamp(gait.YawRate, -1.5, 1.5) * 0.035 * k
		local yaw = spring(seg.Yaw, wave + stepSwing + lash + trail, lerp(12, 5, k), 0.5, dt)
		local pitch = spring(seg.Pitch, shape * (1 - 0.7 * roar) - 0.06 * roar * (1 - k * 0.5) + 0.02 * ape.Dead, lerp(12, 5, k), 0.6, dt)
		turn(rig, seg.Name, pitch, yaw, 0)
	end

	-- on every copy of each bone
	for name, t in rig.Out do
		for _, bone in rig.Joints[name].Copies do
			bone.Transform = t
		end
	end
end

-- where the giant's screen effects and camera stand (only for your own giant)
local mine = {
	Ape = nil,
	SavedZoom = nil,
}

-- your giant: turning at a giant's pace and slow to get going (before physics)
local function steerMine(dt: number)
	local character = player.Character
	local ape = character and apes[character]
	if not ape then
		return
	end
	local humanoid, root = ape.Humanoid, ape.Root
	if humanoid.Health <= 0 then
		return
	end
	humanoid.AutoRotate = false
	local age = Workspace:GetServerTimeNow() - (character:GetAttribute("OozaruAt") or -100)
	local move = humanoid.MoveDirection
	local moving = move.Magnitude > 0.1
	local yaw = flatYaw(root.CFrame.LookVector)
	local diff = moving and Gait.AngleDiff(flatYaw(move), yaw) or 0
	local maxRate = math.rad(PowerConfig.OozaruTurnSpeed or 140)
	ape.TurnRate = ease(ape.TurnRate, math.clamp(diff * 3, -maxRate, maxRate), 5, dt)
	local step = math.clamp(ape.TurnRate * dt, -math.abs(diff), math.abs(diff))
	if math.abs(step) > 1e-5 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw + step, 0)
	end
	local free = age >= INTRO and character:GetAttribute("PowerState") == "Idle"
	ape.Throttle = ease(ape.Throttle, (free and moving) and 1 or 0, moving and 1.8 or 10, dt)
	local facingOk = math.max(0.2, math.cos(math.min(math.abs(diff), math.pi / 2)))
	humanoid.WalkSpeed = free and (PowerConfig.OozaruWalkSpeed * ape.Throttle * facingOk) or 0
end

local okPre, preSimulation = pcall(function()
	return RunService.PreSimulation
end)
local stepSignal = (okPre and preSimulation) or RunService.Stepped
stepSignal:Connect(function(a, b)
	local dt = (typeof(b) == "number") and b or a
	steerMine(math.clamp(dt, 0, 0.1))
end)

----------------------------------------------------------------------------------------
-- your screen while you're the giant
----------------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.Name = "OozaruScreen"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 100
screen.Parent = playerGui

local function frame(name: string, colour: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = screen
	return f
end
local black = frame("Black", Color3.new(0, 0, 0), 10)
local flash = frame("Flash", Color3.fromRGB(255, 40, 30), 9)
-- a dark red edge: four strips fading inward
local edges = {}
for i, spec in {
	{ UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), 180 },
	{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), 270 },
} do
	local f = frame("Edge" .. i, Color3.fromRGB(60, 0, 0), 2)
	f.Size, f.Position = spec[1], spec[2]
	f.BackgroundTransparency = 0
	local g = Instance.new("UIGradient")
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.55, 0.75), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Visible = false
	table.insert(edges, { Frame = f, Gradient = g })
end

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "OozaruTint"
tint.Enabled = false
tint.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "OozaruBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local blackness = 0
local wasApe = false
local cameraOn = nil -- the body the camera was last pointed at
local turningSince = nil
local hidden = {} -- ScreenGuis this hid, to show again
local coreHidden = {}
local CORE = { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu }

local function hideUI(hide: boolean)
	player:SetAttribute("Oozaru", hide or nil) -- (the HUD and the power-up screen hide themselves)
	if hide then
		for _, g in playerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= screen and g.Enabled and not hidden[g] then
				hidden[g] = true
				g.Enabled = false
			end
		end
		for _, kind in CORE do
			if coreHidden[kind] == nil then
				local ok, on = pcall(function()
					return StarterGui:GetCoreGuiEnabled(kind)
				end)
				coreHidden[kind] = ok and on or false
				pcall(function()
					StarterGui:SetCoreGuiEnabled(kind, false)
				end)
			end
		end
	else
		for g in hidden do
			if g.Parent then
				g.Enabled = true
			end
		end
		table.clear(hidden)
		for kind, was in coreHidden do
			if was then
				pcall(function()
					StarterGui:SetCoreGuiEnabled(kind, true)
				end)
			end
		end
		table.clear(coreHidden)
	end
end

local function camera(apeSize: number?)
	if apeSize then
		if not mine.SavedZoom then
			mine.SavedZoom = { player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
		end
		player.CameraMaxZoomDistance = math.max(mine.SavedZoom[2], 45 * apeSize)
		player.CameraMinZoomDistance = 16 * apeSize -- (pulls the camera back out of the fur)
	elseif mine.SavedZoom then
		player.CameraMaxZoomDistance = math.min(mine.SavedZoom[2], 18) -- (zooms back in) ...
		player.CameraMinZoomDistance = mine.SavedZoom[1]
		local saved = mine.SavedZoom
		mine.SavedZoom = nil
		task.delay(0.1, function()
			if not mine.SavedZoom then
				player.CameraMaxZoomDistance = saved[2] -- ... then lets you zoom out again
			end
		end)
	end
end

-- When your body is swapped (into the giant and back), Roblox doesn't move the camera onto the
-- new one the way it does when you spawn: point it at the new body's Humanoid.
local function followBody(character: Model?)
	if not character or cameraOn == character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	if humanoid and camera then
		if camera.CameraSubject == humanoid then
			cameraOn = character
		elseif camera.CameraType ~= Enum.CameraType.Scriptable then -- (not mid-cutscene: try again after)
			camera.CameraSubject = humanoid
			cameraOn = character
		end
	end
end

local function updateScreen(dt: number, now: number)
	local character = player.Character
	followBody(character)
	local isApe = character ~= nil and character:GetAttribute("Oozaru") == true
	local ape = isApe and apes[character] or nil
	local state = character and character:GetAttribute("PowerState")
	local age = isApe and (Workspace:GetServerTimeNow() - (character:GetAttribute("OozaruAt") or -100)) or 99
	if state == "GreatApe" and not isApe then
		turningSince = turningSince or now
	else
		turningSince = nil
	end
	local stuck = turningSince ~= nil and now - turningSince > 2.5 -- (the server said no)
	local wantBlack = ((turningSince and not stuck) or state == "Shrinking" or (isApe and age < CUT_IN)) and 1 or 0
	if wantBlack > blackness then
		blackness = math.min(1, blackness + dt / 0.3) -- fade to black ...
	elseif isApe and wantBlack == 0 and blackness > 0 and age < 1 then
		blackness = 0 -- ... and cut straight in on the roar
		flash.BackgroundTransparency = 0.35
	else
		blackness = math.max(0, blackness - dt / 0.45)
	end
	black.BackgroundTransparency = 1 - blackness
	flash.BackgroundTransparency = math.min(1, flash.BackgroundTransparency + dt * 1.6)

	if isApe ~= wasApe then
		wasApe = isApe
		hideUI(isApe)
		camera(isApe and (character:GetAttribute("OozaruScale") or 3.2) or nil)
		tint.Enabled = isApe
		for _, e in edges do
			e.Frame.Visible = isApe
		end
		if isApe then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.CameraOffset = Vector3.new(0, 1.2 * (character:GetAttribute("OozaruScale") or 3.2), 0)
			end
		end
	end
	if isApe then
		hideUI(true) -- (anything new that shows up)
		-- red, throbbing with the breath; swimming as it wears off
		local breath = ape and math.sin(ape.Breath) or 0
		local left = (character:GetAttribute("OozaruUntil") or 0) - Workspace:GetServerTimeNow()
		local fading = ((character:GetAttribute("OozaruUntil") or 0) > 0) and (1 - math.clamp(left / 6, 0, 1)) or 0
		local throb = 0.5 + 0.5 * breath
		local roarK = math.clamp(1 - math.abs(age - 1.7) / 1.5, 0, 1)
		tint.TintColor = Color3.fromRGB(255, 196 - 20 * throb, 186 - 24 * throb)
		tint.Saturation = 0.12 + 0.1 * roarK
		tint.Contrast = 0.14 + 0.08 * roarK
		tint.Brightness = -0.02
		for _, e in edges do
			e.Frame.BackgroundTransparency = math.clamp(0.45 - 0.09 * throb - 0.15 * roarK - 0.2 * math.sin(now * 9) * fading, 0, 1)
		end
		local swim = fading * (0.5 + 0.5 * math.sin(now * 4.2))
		blur.Enabled = swim > 0.01 or roarK > 0.05
		blur.Size = 10 * swim + 3 * roarK
	else
		blur.Enabled = false
	end
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local okRender, preRender = pcall(function()
	return RunService.PreRender
end)
local renderSignal = (okRender and preRender) or RunService.RenderStepped
local lastPositions = {}
local failing = {} -- [model] = { Since, Warned }

renderSignal:Connect(function(dt)
	dt = math.clamp(dt, 0, 0.1)
	local now = os.clock()
	-- the ground under the feet: everything but characters
	local exclude = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	table.insert(exclude, folder)
	rayParams.FilterDescendantsInstances = exclude

	local seen = {}
	-- every giant: tagged by the server (and, to be safe, any player who is one)
	local found = CollectionService:GetTagged(TAG)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and c:GetAttribute("Oozaru") and not table.find(found, c) then
			table.insert(found, c)
		end
	end
	for _, model in found do
		if model:IsA("Model") and model.Parent then
			seen[model] = true
			local ape = apes[model]
			if not ape then
				local ok, made, why = pcall(newApe, model)
				if not ok then
					made, why = nil, made -- (an error building it: report it like any other reason)
				end
				ape = made
				if not ape then
					-- (a moment's grace: its bones may still be arriving)
					local f = failing[model] or { Since = now }
					failing[model] = f
					if not f.Warned and now - f.Since > 3 then
						f.Warned = true
						warn(("[OozaruFX] can't animate the Great Ape: %s"):format(tostring(why)))
					end
				else
					failing[model] = nil
					print(("[OozaruFX] animating the Great Ape: %d bones%s"):format(ape.Bones,
						(ape.Copies > 1) and (" (%d copies of the skeleton, all posed together)"):format(ape.Copies) or ""))
					apes[model] = ape
					ape.Ground = groundFinder(ape.Gait.HipHeight)
					-- it appears in a burst of smoke
					local age = Workspace:GetServerTimeNow() - (model:GetAttribute("OozaruAt") or -100)
					if age < 1.5 then
						local feet = ape.Root.Position + Vector3.new(0, ape.Gait.GroundY, 0)
						puff(feet + Vector3.new(0, 4 * ape.Scale, 0), 45, 4 * ape.Scale, Color3.fromRGB(205, 200, 195), 7 * ape.Scale, nil, 2)
					end
				end
			end
			if ape then
				local ok, err = pcall(poseApe, ape, dt, now)
				if not ok and not ape.Warned then
					ape.Warned = true
					warn("[OozaruFX] " .. tostring(err))
				end
				lastPositions[model] = { ape.Root.Position, ape.Gait.GroundY, ape.Scale }
			end
		end
	end
	for model in failing do
		if not seen[model] then
			failing[model] = nil
		end
	end
	for model in apes do
		if not seen[model] then
			apes[model] = nil
			-- gone (turned back, or left): a puff of smoke where it stood
			local last = lastPositions[model]
			if last then
				puff(last[1] + Vector3.new(0, last[2] * 0.5, 0), 40, 4 * last[3], Color3.fromRGB(205, 200, 195), 6 * last[3], nil, 1.8)
			end
			lastPositions[model] = nil
		end
	end
	for i = #effects, 1, -1 do
		if not effects[i](dt) then
			table.remove(effects, i)
		end
	end
	updateScreen(dt, now)
end)
