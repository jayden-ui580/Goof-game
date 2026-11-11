--[[
	Gait  (ModuleScript — lives in ReplicatedStorage)

	Walks any two-legged rig (an R15 character's joints, or a skinned model's bones) so its feet
	really plant, the problem behind most "sliding" walks in games:
	  * Each foot stays exactly where it landed until it steps again. The legs bend to reach it
	    (two-bone IK: hip, knee, ankle), so a planted foot can't drift however the body moves.
	  * The steps come from the distance actually travelled, not from a clock. How long a step
	    is depends on the speed AND the length of the legs (the way real animals scale: a giant
	    takes long slow strides, a person quick short ones), so the body's speed and the feet
	    always agree, at any speed.
	  * Each step lands where the body will be when the foot comes down (it looks ahead using
	    the velocity and how fast you're turning), so turning and speeding up don't leave the
	    feet behind.
	  * Stopping is a real move: the swinging foot comes down beside the other one, and if the
	    back foot is still trailing it takes one short settle step to come in. Turning on the
	    spot shuffles the feet round one at a time.
	  * The feet roll heel to toe: toes up as a foot lands on its heel, flat, then the heel
	    peels up and the foot pushes off its toes.
	  * The hips do what hips do: rise and fall with each step (highest over the standing foot
	    when walking, lowest when running), sway over the standing foot, turn with the swinging
	    leg and drop on its side.
	The script using it (Locomotion, for people) adds the upper
	body, arms and head on top, reading Phase / Mode / Accel / events from here.

	A rig is described as joints: { Parent, C0, C1, Instance } where the child sits at
	parent * C0 * Transform * C1:Inverse() (Motor6D and AnimationConstraint work this way; a
	Bone is the same with C0 = Bone.CFrame and C1 = identity). Everything is worked out in the
	HumanoidRootPart's space. Gait writes the Transforms it wants into rig.Out; the script
	decides how to put them on (straight, or blended with other animation).
]]

local Gait = {}
Gait.__index = Gait

local UP = Vector3.yAxis
-- real gravity in studs/s² (a stud is about 28 cm). Only used to judge how fast a walk "is"
-- for legs that long, so a giant and a person each move like themselves.
local G = 35

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- an orientation whose X axis runs along dir and whose Y axis is as close to ref as it can be
local function basis(dir: Vector3, ref: Vector3): CFrame
	local x = dir.Unit
	local y = ref - x * ref:Dot(x)
	if y.Magnitude < 1e-5 then
		local alt = math.abs(x.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		y = alt - x * alt:Dot(x)
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

-- the turn that carries (dir0, ref0) onto (dir1, ref1)
local function turnBetween(dir0: Vector3, ref0: Vector3, dir1: Vector3, ref1: Vector3): CFrame
	return basis(dir1, ref1) * basis(dir0, ref0):Inverse()
end

local function about(pivot: Vector3, turn: CFrame): CFrame
	return CFrame.new(pivot) * turn * CFrame.new(-pivot)
end

-- which way a flat direction points, as a turn about the vertical (0 = facing -Z)
local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function yawVector(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function angleDiff(a: number, b: number): number
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

Gait.Smooth = smooth
Gait.Basis = basis
Gait.TurnBetween = turnBetween
Gait.About = about
Gait.AngleDiff = angleDiff
Gait.YawOf = yawOf
Gait.YawVector = yawVector

----------------------------------------------------------------------------------------
-- rigs
----------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig
Gait.Rig = Rig

-- joints: { [name] = { Parent = name?, C0 = CFrame, C1 = CFrame, Instance = Instance? } }
-- base: where the top joints' parent sits, in root space (identity when it's the root part)
function Rig.new(joints, base: CFrame?)
	local self = setmetatable({ Joints = joints, Base = base or CFrame.identity, Rest = {}, Out = {} }, Rig)
	local function rest(name)
		if self.Rest[name] then
			return self.Rest[name]
		end
		local j = joints[name]
		local parent = j.Parent and rest(j.Parent) or self.Base
		self.Rest[name] = parent * j.C0 * j.C1:Inverse()
		return self.Rest[name]
	end
	for name in joints do
		rest(name)
	end
	return self
end

-- the frame a joint's parent is in, at rest
function Rig:RestParent(name: string): CFrame
	local j = self.Joints[name]
	return j.Parent and self.Rest[j.Parent] or self.Base
end

-- the joint's pivot frame (parent * C0) given the parent's frame
function Rig:Pivot(name: string, parentFrame: CFrame): CFrame
	return parentFrame * self.Joints[name].C0
end

-- the Transform that puts a joint's child at `child` (root space) when its parent is at `parent`
function Rig:TransformFor(name: string, parent: CFrame, child: CFrame): CFrame
	local j = self.Joints[name]
	return j.C0:Inverse() * parent:Inverse() * child * j.C1
end

-- A turn (and a shift) in the rig's rest axes, applied at the joint: the same idea as
-- CFrame.Angles on an R15 joint, for any rig (x = right, y = up, -z = forward, as the
-- character stands at rest). The axes follow the parent when it moves.
function Rig:Local(name: string, turn: CFrame): CFrame
	local axes = (self:RestParent(name) * self.Joints[name].C0).Rotation
	return axes:Inverse() * turn * axes
end

-- the child's frame given its parent's frame and a Transform
function Rig:ChildFrame(name: string, parent: CFrame, transform: CFrame): CFrame
	local j = self.Joints[name]
	return parent * j.C0 * transform * j.C1:Inverse()
end

-- the frame of every piece (root space) for a set of Transforms (missing ones are at rest)
function Rig:Frames(transforms)
	local frames = {}
	local function frame(name)
		local f = frames[name]
		if f then
			return f
		end
		local j = self.Joints[name]
		local parent = j.Parent and frame(j.Parent) or self.Base
		f = parent * j.C0 * (transforms[name] or CFrame.identity) * j.C1:Inverse()
		frames[name] = f
		return f
	end
	for name in self.Joints do
		frame(name)
	end
	return frames
end

function Rig:Write(name: string, transform: CFrame)
	self.Out[name] = transform
end

-- puts rig.Out straight onto the joints
function Rig:Apply()
	for name, t in self.Out do
		local inst = self.Joints[name].Instance
		if inst and inst.Parent then
			inst.Transform = t
		end
	end
end

----------------------------------------------------------------------------------------
-- the gait
----------------------------------------------------------------------------------------
local DEFAULTS = {
	-- a step is Stride x leg x (Froude number)^0.3 long: the rule real walkers and runners of
	-- every size follow. The Froude number (speed² / (gravity x leg)) says how fast a walk is
	-- for legs that long.
	Stride = 1.15,
	MinStep = 0.3, -- shortest and longest step (leg lengths)
	MaxStep = 2.1,
	SideStep = 0.5, -- steps sideways are this much shorter (feet would cross otherwise) ...
	SideWiden = 0.45, -- ... and the stance this much wider
	BackStep = 0.7, -- steps backward are this much shorter
	SwingShare = { 0.4, 0.78 }, -- share of a stride each foot is in the air: walking, running
	AheadShare = { 0.42, 0.5 }, -- how much of its time on the ground a foot spends in front of the
	-- hips (the rest behind them): walking lands closer and pushes off further back, where
	-- rolling onto the toes gives the leg the reach
	RunFrom = 0.35, -- Froude number where walking starts turning into running ...
	RunTo = 1.3, -- ... and where it's fully running
	Lift = { 0.12, 0.36 }, -- how high a swinging foot rises (leg lengths): walking, running
	Width = 1, -- stance width (1 = the hips' own width)
	ToeOut = math.rad(7), -- feet turned out a little
	Bob = { 0.02, 0.045 }, -- hips rising and falling (leg lengths): walking, running
	HeavyDrop = 0, -- an extra dip after a foot lands (leg lengths), for heavy walkers
	ImpactTime = 0.3, -- how long that dip takes (seconds)
	Sway = 0.03, -- hips swaying over the standing foot (leg lengths)
	Yaw = math.rad(7), -- hips turning with the swinging leg
	Roll = math.rad(4), -- the swinging side's hip dropping
	Pitch = { math.rad(2), math.rad(8) }, -- hips tipping forward: walking, running
	KneeOut = 0.12, -- knees pointing out as well as forward
	Crouch = 0.002, -- knees never quite locked straight (leg lengths; a little goes a long way)
	MaxDrop = 0.25, -- the most the hips sink to let a foot reach (leg lengths)
	ToeOff = math.rad(30), -- the heel rising at the end of a step
	HeelStrike = math.rad(14), -- the toes up as a foot lands
	StartFroude = 0.02, -- start walking above this (a person: about 1.2 studs/s) ...
	StopFroude = 0.005, -- ... and stop below this
	SettleTime = 0.34, -- a stopping / turning step's length (seconds)
	SettleDistance = 0.16, -- a foot further than this (leg lengths) from its spot steps in
	TurnTolerance = math.rad(32), -- a foot turned more than this from the body shuffles round
	FootForward = 0.3, -- ankle to toe pivot, along the ground (leg lengths)
	FootBack = 0.1, -- ankle to heel (leg lengths)
}
Gait.Defaults = DEFAULTS

-- spec = { Pelvis = joint name, Legs = { Left = { Hip, Knee, Ankle }, Right = { ... } },
--          GroundY = root-space height of the ground at rest, Params = { overrides } }
function Gait.new(rig, spec)
	local self = setmetatable({}, Gait)
	self.Rig = rig
	self.Pelvis = spec.Pelvis
	local p = table.clone(DEFAULTS)
	for k, v in spec.Params or {} do
		p[k] = v
	end
	self.P = p
	self.GroundY = spec.GroundY
	self.Legs = {}
	local forward = Vector3.new(0, 0, -1)
	local right = Vector3.xAxis
	local hipHeights = 0
	for side, names in spec.Legs do
		local hip = rig:Pivot(names.Hip, rig:RestParent(names.Hip)).Position
		local knee = rig:Pivot(names.Knee, rig:RestParent(names.Knee)).Position
		local ankle = rig:Pivot(names.Ankle, rig:RestParent(names.Ankle)).Position
		local thighRest, shinRest, footRest = rig.Rest[names.Hip], rig.Rest[names.Knee], rig.Rest[names.Ankle]
		local leg = {
			Side = side,
			Sign = (hip.X < 0) and -1 or 1,
			Names = names,
			L1 = (knee - hip).Magnitude,
			L2 = (ankle - knee).Magnitude,
			Hip = hip,
			AnkleHeight = ankle.Y - spec.GroundY,
			Spot = Vector3.new(ankle.X, 0, ankle.Z), -- where the foot stands at rest (root space, flat)
			-- the leg's directions, in each piece's own frame, to turn them by later
			ThighDir = thighRest:VectorToObjectSpace(knee - hip),
			ThighHinge = thighRest:VectorToObjectSpace(right),
			ShinDir = shinRest:VectorToObjectSpace(ankle - knee),
			ShinHinge = shinRest:VectorToObjectSpace(right),
			FootFwd = footRest:VectorToObjectSpace(forward),
			FootUp = footRest:VectorToObjectSpace(UP),
			Pos = nil, -- where the foot is planted (world, the ground under the ankle)
			Yaw = 0, -- which way it points (world)
			Swing = nil, -- the step it's taking, if it's in the air
			Stance = 1, -- 0..1 through its time on the ground
			FootPitch = 0,
			FootYaw = 0,
		}
		leg.Length = leg.L1 + leg.L2
		hipHeights += hip.Y - spec.GroundY
		self.Legs[side] = leg
	end
	assert(self.Legs.Left and self.Legs.Right, "Gait needs a Left and a Right leg")
	self.HipHeight = hipHeights / 2 -- the "leg length" every size rule uses
	self.Phase = 0 -- 0..1 through a stride (two steps): the left foot lifts at 0, the right at 0.5
	self.Mode = "Idle" -- "Idle", "Walk", "Stop" (settling after walking), "Air"
	self.RunBlend = 0
	self.Speed = 0
	self.Froude = 0
	self.StepLen = 0
	self.Forwardness = 1
	self.Drop = 0
	self.Impact = 0 -- 1 right after a foot lands, counting down
	self.ImpactScale = 0
	self.WalkWeight = 0 -- eases 0..1 into and out of walking
	self.Accel = Vector3.zero -- the body's acceleration (x = right, z = forward), smoothed
	self.YawRate = 0 -- how fast it's turning (radians/s, + = left)
	self.AirTime = 0
	self.Events = {}
	return self
end

-- which way a foot should point when the body faces rootYaw
function Gait:FootYaw(leg, rootYaw: number): number
	return rootYaw - leg.Sign * self.P.ToeOut
end

-- the world spot a leg stands on when idle, under the root
function Gait:IdleSpot(leg, root: CFrame): Vector3
	local spot = leg.Spot
	return root * Vector3.new(spot.X * self.P.Width, self.GroundY, spot.Z)
end

local function plantAt(leg, pos: Vector3, yaw: number, ground)
	local y = ground and ground(pos)
	leg.Pos = y and Vector3.new(pos.X, y, pos.Z) or pos
	leg.Yaw = yaw
	leg.Swing = nil
	leg.Stance = 0
end

local function startSwing(leg, toPitch: number)
	leg.Swing = {
		From = leg.Pos,
		FromYaw = leg.Yaw,
		FromHeight = 0,
		FromPitch = leg.FootPitch or 0,
		RollFrom = 1,
		To = leg.Pos,
		ToYaw = leg.Yaw,
		ToPitch = toPitch,
		T = 0,
		Duration = nil, -- seconds for a timed (settle) step; nil while walking
		Head = 0, -- (walking steps) how much of the usual time in the air it skips
		LiftScale = 1,
		Current = leg.Pos,
		Height = 0,
		Yaw = leg.Yaw,
		Pitch = leg.FootPitch or 0,
		RollW = 1,
	}
	return leg.Swing
end

-- sends a foot that's in the air somewhere else, from wherever it is right now
local function retarget(leg, to: Vector3, toYaw: number, duration: number, toPitch: number, liftScale: number)
	local sw = leg.Swing
	sw.From = sw.Current
	sw.FromYaw = sw.Yaw
	sw.FromHeight = sw.Height
	sw.FromPitch = sw.Pitch
	sw.RollFrom = sw.RollW
	sw.To = to
	sw.ToYaw = toYaw
	sw.ToPitch = toPitch
	sw.T = 0
	sw.Duration = duration
	sw.LiftScale = liftScale
	sw.ProbeAt = nil
end

-- the ground height under a landing spot, looked up again only when the spot has moved
local function probe(sw, pos: Vector3, ground, size: number): number?
	if not ground then
		return nil
	end
	if sw.ProbeAt and flat(sw.ProbeAt - pos).Magnitude < size * 0.08 then
		return sw.ProbeY
	end
	sw.ProbeAt = pos
	sw.ProbeY = ground(pos)
	return sw.ProbeY
end

-- Starting to walk (or picking the walk back up): one foot steps first, and the stride is
-- lined up with where the other foot already stands, so it lifts off when it's as far behind
-- as it would be mid-walk (not later, trailing behind a body that's already moving).
function Gait:StartWalking(root: CFrame, heading: Vector3, swingShare: number, stepLen: number)
	local left, right = self.Legs.Left, self.Legs.Right
	self.Mode = "Walk"
	-- a foot already in the air (a settle step) carries on as the first step; otherwise the
	-- foot further behind goes first
	local first = (left.Swing and left) or (right.Swing and right)
	if not first then
		local lBack = (left.Pos - root.Position):Dot(heading)
		local rBack = (right.Pos - root.Position):Dot(heading)
		first = (lBack <= rBack) and left or right
	end
	local other = (first == left) and right or left
	if other.Swing then
		plantAt(other, other.Swing.Current, other.Swing.Yaw, nil)
	end
	-- how far through its time on the ground the standing foot is, from where it is
	local travel = math.max((1 - swingShare) * 2 * stepLen, 1e-3) -- how far the hips pass over a foot
	local ahead = travel * lerp(self.P.AheadShare[1], self.P.AheadShare[2], self.RunBlend)
	local x = (other.Pos - root.Position):Dot(heading)
	local progress = math.clamp((ahead - x) / travel, 0, 0.9)
	other.Stance = progress
	local otherStart = (other.Side == "Left") and 0 or 0.5
	self.Phase = (otherStart - (1 - progress) * (1 - swingShare)) % 1
	local firstStart = (first.Side == "Left") and 0 or 0.5
	local into = (self.Phase - firstStart) % 1
	if into > swingShare then -- (can't happen with the numbers above; just in case)
		into = 0
	end
	local sw = first.Swing
	if sw then
		local done = math.clamp(sw.T, 0, 0.95)
		sw.Duration = nil
		sw.LiftScale = math.max(sw.LiftScale, 0.8)
		sw.Head = math.max(0, into - done * swingShare)
		sw.T = done
	else
		sw = startSwing(first, 0)
		sw.Head = into
	end
	table.insert(self.Events, { Kind = "Start" })
end

-- one frame. root: the HumanoidRootPart's CFrame; vel: its velocity; grounded: standing on
-- something; ground(pos) -> the ground's height there, or nil (optional);
-- extra = { Offset = Vector3, Turn = CFrame } added to the hips (rest axes, after the gait's own)
function Gait:Step(dt: number, root: CFrame, vel: Vector3, grounded: boolean, ground, extra)
	local p = self.P
	local events = self.Events
	table.clear(events)
	dt = math.max(dt, 1e-4)
	local L = self.HipHeight
	local planar = flat(vel)
	local speed = planar.Magnitude
	local facing = flat(root.LookVector)
	facing = (facing.Magnitude > 1e-3) and facing.Unit or Vector3.new(0, 0, -1)
	local rootYaw = yawOf(facing)
	local bodyRight = facing:Cross(UP)
	local heading = (speed > 0.05) and planar / speed or facing
	self.Speed = speed

	-- how the body is speeding up and turning (the scripts lean with these)
	local accel = (planar - (self.LastVel or planar)) / dt
	self.LastVel = planar
	local k = 1 - math.exp(-dt * 10)
	self.Accel = self.Accel:Lerp(Vector3.new(accel:Dot(bodyRight), 0, accel:Dot(facing)), k)
	local yawRate = angleDiff(rootYaw, self.LastYaw or rootYaw) / dt
	self.LastYaw = rootYaw
	self.YawRate += (math.clamp(yawRate, -20, 20) - self.YawRate) * (1 - math.exp(-dt * 8))

	-- how fast this is for these legs, and the steps that go with it
	local fr = speed * speed / (G * L)
	self.Froude = fr
	self.RunBlend = smooth((fr - p.RunFrom) / math.max(p.RunTo - p.RunFrom, 1e-3))
	local swingShare = lerp(p.SwingShare[1], p.SwingShare[2], self.RunBlend)
	self.SwingShare = swingShare
	local forwardness = heading:Dot(facing)
	local sideways = math.abs(heading:Dot(bodyRight))
	local dirFactor = 1 - (1 - p.SideStep) * sideways * sideways - (1 - p.BackStep) * math.max(0, -forwardness) ^ 2
	local stepLen = math.clamp(p.Stride * L * fr ^ 0.3, p.MinStep * L, p.MaxStep * L) * dirFactor
	self.StepLen = stepLen
	self.Forwardness = forwardness
	self.Sideways = sideways
	local rate = speed / (2 * stepLen) -- strides per second
	self.Rate = rate
	local left, right = self.Legs.Left, self.Legs.Right

	-- first frame, or teleported: stand where we are
	for _, leg in self.Legs do
		if not leg.Pos or flat(leg.Pos - root.Position).Magnitude > L * 6 then
			for _, l in self.Legs do
				plantAt(l, self:IdleSpot(l, root), self:FootYaw(l, rootYaw), ground)
			end
			self.Mode = grounded and "Idle" or "Air"
			break
		end
	end

	-- in the air, landing, starting and stopping
	if not grounded then
		if self.Mode ~= "Air" then
			self.Mode = "Air"
			self.AirTime = 0
			for _, leg in self.Legs do
				leg.Swing = nil
			end
		end
		self.AirTime += dt
	elseif self.Mode == "Air" then
		for _, leg in self.Legs do
			plantAt(leg, leg.Pos, self:FootYaw(leg, rootYaw), ground)
		end
		self.Mode = "Stop"
		self.Impact = 1
		self.ImpactScale = math.clamp(0.4 + self.AirTime * 1.5, 0.4, 1.5)
		table.insert(events, { Kind = "Land", Strength = self.ImpactScale })
	end
	if grounded then
		if self.Mode ~= "Walk" and speed > math.sqrt(p.StartFroude * G * L) then
			self:StartWalking(root, heading, swingShare, stepLen)
		elseif self.Mode == "Walk" and speed < math.sqrt(p.StopFroude * G * L) then
			self.Mode = "Stop"
			table.insert(events, { Kind = "Stop", Speed = self.LastWalkSpeed or 0 })
			-- a foot still in the air comes down beside the other one
			for _, leg in self.Legs do
				if leg.Swing then
					local spot = self:IdleSpot(leg, root)
					local gy = ground and ground(spot)
					retarget(leg, gy and Vector3.new(spot.X, gy, spot.Z) or spot, self:FootYaw(leg, rootYaw), p.SettleTime * 0.75, 0, 0.6)
				end
			end
		end
	end

	if self.Mode == "Walk" then
		self.LastWalkSpeed = speed
		-- the stride: driven by the distance travelled, two steps per stride
		local before = self.Phase
		self.Phase = (self.Phase + rate * dt) % 1
		local travel = (1 - swingShare) * 2 * stepLen -- how far the hips pass over a planted foot
		local ahead = travel * lerp(p.AheadShare[1], p.AheadShare[2], self.RunBlend) -- it lands this far in front
		for _, leg in self.Legs do
			local start = (leg.Side == "Left") and 0 or 0.5
			local was = (before - start) % 1
			local into = (self.Phase - start) % 1
			local sw = leg.Swing
			if not sw and into < was then
				sw = startSwing(leg, 0) -- its turn: lift off
			end
			if not sw then
				-- a foot left behind (the body sped up, turned hard, or is stepping sideways
				-- over it) lifts off early, once the other one is down or nearly; the stride
				-- lines up with it
				local other = (leg == left) and right or left
				local rel = leg.Pos - root.Position
				local behind = -rel:Dot(heading)
				local outward = rel:Dot(bodyRight) * leg.Sign -- out to its own side
				local otherReady = not other.Swing or other.Swing.T > 0.35
				if otherReady and (behind > (travel - ahead) * 1.25 + 0.06 * L or (leg.Reach or 0) > 1.05 or outward < 0.1 * L) then
					sw = startSwing(leg, 0)
					self.Phase = start
				end
			end
			if sw then
				if sw.Duration then -- (a settle step carries on as a walking step)
					sw.Duration = nil
				end
				local span = math.max(swingShare - (sw.Head or 0), 0.12)
				sw.T += rate * dt / span
				-- where it comes down: where the hips will be by then, plus half a step (on the
				-- frame it lands, timeLeft is a hair below zero: it came down a moment ago)
				local timeLeft = (1 - sw.T) * span / math.max(rate, 1e-3)
				local futureYaw = rootYaw + self.YawRate * math.clamp(timeLeft, -0.1, 0.5)
				local futureFacing = yawVector(futureYaw)
				local futureRight = futureFacing:Cross(UP)
				local land = root.Position
					+ planar * timeLeft
					+ heading * ahead
					+ futureRight * (leg.Spot.X * p.Width * (1 + p.SideWiden * sideways))
					- futureFacing * leg.Spot.Z
				land = Vector3.new(land.X, root.Position.Y + self.GroundY, land.Z)
				local gy = probe(sw, land, ground, L)
				if gy then
					land = Vector3.new(land.X, gy, land.Z)
				end
				sw.To = land
				sw.Arrive = land - planar * timeLeft -- (the landing spot, seen from where the hips are now)
				sw.ToYaw = self:FootYaw(leg, futureYaw)
				sw.ToPitch = -p.HeelStrike * math.clamp(forwardness, 0, 1)
				if sw.T >= 1 then
					plantAt(leg, sw.To, sw.ToYaw, nil)
					table.insert(events, { Kind = "Footfall", Side = leg.Side, Position = leg.Pos, Speed = speed })
					self.Impact = 1
					self.ImpactScale = 1
				end
			else
				leg.Stance = math.min(1, leg.Stance + rate * dt / math.max(1 - swingShare, 0.05))
			end
		end
	elseif self.Mode ~= "Air" then
		-- standing (or stopping): timed steps to settle in, or to turn on the spot
		for _, leg in self.Legs do
			local sw = leg.Swing
			if sw then
				if not sw.Duration then
					local spot = self:IdleSpot(leg, root)
					retarget(leg, spot, self:FootYaw(leg, rootYaw), p.SettleTime * 0.75, 0, 0.6)
				end
				sw.T += dt / sw.Duration
				if sw.T >= 1 then
					plantAt(leg, sw.To, sw.ToYaw, ground)
					table.insert(events, { Kind = "Footfall", Side = leg.Side, Position = leg.Pos, Speed = 0, Settle = true })
					self.Impact = 1
					self.ImpactScale = 0.5
				end
			end
		end
		if not (left.Swing or right.Swing) then
			-- the foot furthest from where it should stand steps in (one at a time)
			local worst, worstScore = nil, 1
			for _, leg in self.Legs do
				local spot = self:IdleSpot(leg, root)
				local off = flat(leg.Pos - spot).Magnitude / L
				local turn = math.abs(angleDiff(leg.Yaw, self:FootYaw(leg, rootYaw)))
				local score = math.max(off / p.SettleDistance, turn / p.TurnTolerance)
				if score > worstScore then
					worst, worstScore = leg, score
				end
			end
			if worst then
				local spot = self:IdleSpot(worst, root)
				local gy = ground and ground(spot)
				startSwing(worst, 0)
				retarget(worst, gy and Vector3.new(spot.X, gy, spot.Z) or spot, self:FootYaw(worst, rootYaw), p.SettleTime, 0, 0.55)
			elseif self.Mode == "Stop" then
				self.Mode = "Idle"
				table.insert(events, { Kind = "Settled" })
			end
		end
		for _, leg in self.Legs do
			leg.Stance = 0.4 -- (flat-footed)
		end
	end

	-- in the air the feet hang under the hips, tucked up a little
	if self.Mode == "Air" then
		for _, leg in self.Legs do
			leg.Pos = root * Vector3.new(leg.Spot.X * p.Width, self.GroundY + L * 0.16, leg.Spot.Z - L * 0.04)
			leg.Yaw = self:FootYaw(leg, rootYaw)
		end
	end

	-- where each swinging foot is right now
	for _, leg in self.Legs do
		local sw = leg.Swing
		if sw then
			local s = math.clamp(sw.T, 0, 1)
			-- running: the foot flicks up behind (the heel kicks up), then comes through and down
			local kick = sw.Duration and 0 or self.RunBlend
			-- Walking, the foot peels up off its toes before it starts forward; it gets to its
			-- new spot a moment before it's down. Either way it never scuffs along the ground.
			local wait = sw.Duration and 0 or lerp(0.12, 0, kick) * sw.RollFrom
			local done = sw.Duration and 1 or lerp(0.97, 0.93, kick)
			local e = smooth((s - wait) / (done - wait))
			local lift = sw.LiftScale * lerp(p.Lift[1], p.Lift[2], self.RunBlend) * L
			local peak = lerp(0.45, 0.3, kick) -- when it's highest
			local arc
			if s < peak then
				arc = math.sin(0.5 * math.pi * s / peak)
			else
				-- walking: an even arc down to the ground; running: the foot drops early and
				-- comes through low, reaching forward to land
				local t = (s - peak) / (1 - peak)
				arc = lerp(math.cos(0.5 * math.pi * t), (1 - t) ^ 1.15, kick)
			end
			sw.Current = sw.From:Lerp(sw.To, e)
			sw.Height = lift * arc + sw.FromHeight * (1 - e)
			sw.Yaw = sw.FromYaw + angleDiff(sw.ToYaw, sw.FromYaw) * e
			-- the foot's tip: from how it left (pushing off its toes) to how it lands (on its heel)
			local bulge = (sw.Duration and 0.25 or 0.12) * p.ToeOff
			sw.Pitch = lerp(sw.FromPitch, sw.ToPitch, e) + bulge * math.sin(math.pi * s)
			sw.RollW = math.max(sw.RollFrom * (1 - smooth(s / 0.35)), smooth((s - 0.65) / 0.35))
		end
	end

	-- the hips
	local run = self.RunBlend
	self.WalkWeight += (((self.Mode == "Walk") and 1 or 0) - self.WalkWeight) * (1 - math.exp(-dt * 6))
	local w = self.WalkWeight
	local cyc = 2 * math.pi * (self.Phase + 0.05) -- (lined up with mid-stance)
	local bobAmp = lerp(p.Bob[1], p.Bob[2], run) * L * w
	-- walking: highest over the standing foot (vaulting over it); running: lowest (landing)
	local bob = lerp(-math.cos(2 * cyc), math.cos(2 * cyc), run) * bobAmp
	self.Impact = math.max(0, self.Impact - dt / math.max(p.ImpactTime, 0.05))
	local dip = -p.HeavyDrop * L * self.ImpactScale * math.sin(math.pi * (1 - self.Impact)) * ((self.Impact > 0) and 1 or 0)
	local sway = math.sin(cyc) * p.Sway * L * w * (1 - run * 0.6)
	local yaw = -math.sin(cyc) * p.Yaw * w
	local roll = math.sin(cyc) * p.Roll * w * (1 - run * 0.4)
	local pitch = lerp(p.Pitch[1], p.Pitch[2], run) * w * forwardness
	-- reach: the hips sit as high as the legs let them. A foot far out in front or behind (or
	-- down a step) pulls them down; that's what makes a walk rise over each standing foot.
	local want = -math.huge
	local targets = {}
	local crouch = p.Crouch * L
	for _, leg in self.Legs do
		local target = self:AnkleTarget(leg, root)
		local hip = leg.Hip + Vector3.new(0, bob + dip - crouch - self.Drop, 0)
		want = math.max(want, (target - hip).Magnitude - leg.Length * 0.99)
		targets[leg] = target
		-- a foot about to land: the hips get low enough for it before it's down
		local sw = leg.Swing
		if sw and sw.Arrive and not sw.Duration and sw.T > 0.4 then
			local landing = root:PointToObjectSpace(sw.Arrive + UP * leg.AnkleHeight)
			local need = (landing - hip).Magnitude - leg.Length * 0.99
			want = math.max(want, need * smooth((sw.T - 0.4) / 0.35))
		end
	end
	local goal = math.clamp(want + self.Drop, 0, p.MaxDrop * L)
	local rate2 = (goal > self.Drop) and 45 or 16
	self.Drop += (goal - self.Drop) * (1 - math.exp(-dt * rate2))
	local offset = Vector3.new(sway, bob + dip - crouch - self.Drop, 0)
	local turn = CFrame.Angles(-pitch, yaw, roll)
	if extra then
		if extra.Offset then
			offset += extra.Offset
		end
		if extra.Turn then
			turn = extra.Turn * turn
		end
	end
	local rig = self.Rig
	local pelvisT = rig:Local(self.Pelvis, CFrame.new(offset) * turn)
	rig:Write(self.Pelvis, pelvisT)
	local pelvisFrame = rig:ChildFrame(self.Pelvis, rig:RestParent(self.Pelvis), pelvisT)
	self.PelvisFrame = pelvisFrame
	self.PelvisT = pelvisT

	-- the legs
	for _, leg in self.Legs do
		self:SolveLeg(leg, root, pelvisFrame, targets[leg])
	end
	return self
end

-- how far the ankle moves when the foot tips by `pitch` about a point `along` studs ahead of
-- the ankle (the toes) or behind it (the heel)
local function rollOffset(fwd: Vector3, side: Vector3, height: number, pitch: number, along: number): Vector3
	local rel = UP * height - fwd * along
	return CFrame.fromAxisAngle(side, -pitch):VectorToWorldSpace(rel) - rel
end

-- where the ankle should be (root space): over the planted (or swinging) foot, with the heel
-- rising at the end of a step and the toes up as it lands
function Gait:AnkleTarget(leg, root: CFrame): Vector3
	local p = self.P
	local L = self.HipHeight
	local sw = leg.Swing
	local groundPt = sw and sw.Current or leg.Pos
	local yaw = sw and sw.Yaw or leg.Yaw
	local fwd = yawVector(yaw)
	local side = fwd:Cross(UP)
	local ankle = groundPt + UP * (leg.AnkleHeight + (sw and sw.Height or 0))
	local pitch = 0
	local fwdness = math.clamp(self.Forwardness or 1, 0, 1)
	if sw then
		pitch = sw.Pitch
		if sw.RollW > 1e-3 and math.abs(pitch) > 1e-4 then
			local along = (pitch > 0) and p.FootForward * L or -p.FootBack * L
			ankle += rollOffset(fwd, side, leg.AnkleHeight, pitch, along) * sw.RollW
		end
		-- a foot in the air never dips its toes or heel into the ground: lift it clear
		local tip = CFrame.fromAxisAngle(side, -pitch)
		local toe = tip:VectorToWorldSpace(fwd * (p.FootForward * L) - UP * leg.AnkleHeight)
		local heel = tip:VectorToWorldSpace(-fwd * (p.FootBack * L) - UP * leg.AnkleHeight)
		local st = math.clamp(sw.T, 0, 1)
		local clear = 0.04 * L * smooth(st / 0.2) * (1 - smooth((st - 0.7) / 0.3))
		local under = groundPt.Y + clear - (ankle.Y + math.min(toe.Y, heel.Y))
		if under > 0 then
			ankle += UP * under
		end
	elseif self.Mode == "Walk" then
		local st = leg.Stance
		local along = 0
		if st > 0.55 then -- heel off: the foot turns on its toes
			pitch = p.ToeOff * smooth((st - 0.55) / 0.45) * fwdness
			along = p.FootForward * L
		elseif st < 0.15 then -- just landed on the heel, rolling flat
			pitch = -p.HeelStrike * (1 - smooth(st / 0.15)) * fwdness
			along = -p.FootBack * L
		end
		if math.abs(pitch) > 1e-4 then
			ankle += rollOffset(fwd, side, leg.AnkleHeight, pitch, along)
		end
	end
	leg.FootPitch = pitch
	leg.FootYaw = yaw
	return root:PointToObjectSpace(ankle)
end

function Gait:SolveLeg(leg, root: CFrame, pelvisFrame: CFrame, ankleTarget: Vector3)
	local rig = self.Rig
	local names = leg.Names
	local p = self.P
	-- hip pivot (root space) with the hips posed
	local hipParent = pelvisFrame
	local hipParentName = rig.Joints[names.Hip].Parent
	if hipParentName ~= self.Pelvis then
		hipParent = rig:ChildFrame(hipParentName, pelvisFrame, CFrame.identity)
	end
	local hip = rig:Pivot(names.Hip, hipParent).Position
	-- the knee bends forward (toward the foot's facing) and a little out
	local footFwd = root:VectorToObjectSpace(yawVector(leg.FootYaw))
	local pole = (footFwd + Vector3.new(leg.Sign * p.KneeOut, 0, 0)).Unit
	local d = ankleTarget - hip
	local L1, L2 = leg.L1, leg.L2
	local dist = math.clamp(d.Magnitude, math.abs(L1 - L2) + 1e-3, L1 + L2 - 1e-4)
	local u = (d.Magnitude > 1e-5) and d.Unit or Vector3.new(0, -1, 0)
	local cosA = math.clamp((L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local v = pole - u * pole:Dot(u)
	v = (v.Magnitude > 1e-5) and v.Unit or Vector3.new(0, 0, -1)
	local knee = hip + (u * cosA + v * sinA) * L1
	local ankle = hip + u * dist
	local hinge = u:Cross(v) -- the knee's hinge (points to the right)
	hinge = (hinge.Magnitude > 1e-5) and hinge.Unit or Vector3.xAxis

	-- thigh
	local thighRest = rig:ChildFrame(names.Hip, hipParent, CFrame.identity)
	local turn = turnBetween(thighRest:VectorToWorldSpace(leg.ThighDir), thighRest:VectorToWorldSpace(leg.ThighHinge), knee - hip, hinge)
	local thigh = about(hip, turn) * thighRest
	rig:Write(names.Hip, rig:TransformFor(names.Hip, hipParent, thigh))
	-- shin
	local shinRest = rig:ChildFrame(names.Knee, thigh, CFrame.identity)
	local kneePivot = rig:Pivot(names.Knee, thigh).Position
	turn = turnBetween(shinRest:VectorToWorldSpace(leg.ShinDir), shinRest:VectorToWorldSpace(leg.ShinHinge), ankle - kneePivot, hinge)
	local shin = about(kneePivot, turn) * shinRest
	rig:Write(names.Knee, rig:TransformFor(names.Knee, thigh, shin))
	-- foot: flat on the ground, facing its planted way, tipped by the heel-toe roll
	local footRest = rig:ChildFrame(names.Ankle, shin, CFrame.identity)
	local anklePivot = rig:Pivot(names.Ankle, shin).Position
	local side = footFwd:Cross(Vector3.yAxis)
	local tip = CFrame.fromAxisAngle((side.Magnitude > 1e-5) and side.Unit or Vector3.xAxis, -leg.FootPitch)
	turn = turnBetween(
		footRest:VectorToWorldSpace(leg.FootFwd),
		footRest:VectorToWorldSpace(leg.FootUp),
		tip:VectorToWorldSpace(footFwd),
		tip:VectorToWorldSpace(Vector3.yAxis)
	)
	local foot = about(anklePivot, turn) * footRest
	rig:Write(names.Ankle, rig:TransformFor(names.Ankle, shin, foot))
	leg.FootFrame = foot
	leg.KneeAt = knee
	leg.AnkleAt = ankle
	leg.AnkleWant = ankleTarget
	leg.Reach = (ankleTarget - hip).Magnitude / (L1 + L2)
end

return Gait
