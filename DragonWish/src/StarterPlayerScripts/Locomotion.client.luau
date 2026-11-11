--[[
	Locomotion  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	A realistic idle, walk and run for every R15 character on this player's screen, in place of
	Roblox's default (cartoony) idle / walk / run animations. Coded joint by joint, no animation
	assets:
	  * The legs come from Gait (ReplicatedStorage): feet that plant and never slide, steps that
	    match the speed you actually move at (walk -> jog -> run), a settle step when you stop,
	    the feet shuffling round when you turn on the spot.
	  * Standing: slow breathing, your weight shifting from one leg to the other now and then
	    (that hip drops, the knee of the other leg softens, the shoulders tilt against it), the
	    head looking around, arms hanging loose with soft elbows, a tiny balance sway.
	  * Moving: the arms swing against the legs (further, and bent more, the faster you go), the
	    chest turns against the hips, the head stays level and looking ahead, you lean into
	    turns, and when you stop the body carries on forward a little and rocks back upright.
	Roblox's own jump, fall, climb, swim and sit animations still play: this fades out while
	you're off your feet and back in when you land. Emotes, and anything an attack plays at
	Action priority, take over from it while they play. Tools keep their arm pose.
	Walk / run style: the HUMAN table below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Gait = require(ReplicatedStorage:WaitForChild("Gait"))
local PoseLayers = require(ReplicatedStorage:WaitForChild("PoseLayers"))

-- how the legs move (see Gait for what each one does)
local HUMAN = {
	Stride = 1.0,
	Yaw = math.rad(9),
	Width = 1.05,
	ToeOut = math.rad(8),
	KneeOut = 0.04,
	Sway = 0.03,
	Bob = { 0.022, 0.05 },
	SettleTime = 0.32,
}

local JOINTS = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
}
local LEGS = { "Root", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local RIGHT_ARM = { RightShoulder = true, RightElbow = true, RightWrist = true }
local FAR = 110 -- studs from the camera: further away the pose is worked out every third frame

-- Roblox's own animations this replaces (the Animate script's idle / walk / run) ...
local REPLACED = { idle = true, walk = true, run = true }
-- ... and the ones it leaves alone: being off your feet
local STATES = { jump = true, fall = true, climb = true, sit = true, swim = true, swimidle = true }
-- emotes take over the whole body while they play; tools take the right arm
local EMOTES = { wave = true, point = true, dance = true, dance2 = true, dance3 = true, laugh = true, cheer = true }
local TOOLS = { toolnone = true, toolslash = true, toollunge = true }

local State = Enum.HumanoidStateType
local ON_FEET = {
	[State.Running] = true,
	[State.RunningNoPhysics] = true,
	[State.Landed] = true,
	[State.GettingUp] = true,
	[State.None] = true,
}
local IN_AIR = { [State.Jumping] = true, [State.Freefall] = true }

local rng = Random.new()

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

-- a damped spring, for things with weight (the arms, the body's lean)
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

local function newSpring()
	return { X = 0, V = 0 }
end

----------------------------------------------------------------------------------------
-- the character's joints
----------------------------------------------------------------------------------------
-- Characters now spawn with AnimationConstraints (Roblox's joint upgrade); older ones have
-- Motor6Ds. Both put the child at parent * C0 * Transform * C1:Inverse().
local function findJoints(character: Model)
	local found = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) and table.find(JOINTS, d.Name) then
			if not found[d.Name] or d:IsA("AnimationConstraint") then
				found[d.Name] = d
			end
		end
	end
	return found
end

local function partsOf(joint): (BasePart?, BasePart?, CFrame, CFrame)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.Part1, joint.C0, joint.C1
	end
	local a0, a1 = joint.Attachment0, joint.Attachment1
	if a0 and a1 and a0.Parent and a1.Parent then
		return a0.Parent :: BasePart, a1.Parent :: BasePart, a0.CFrame, a1.CFrame
	end
	return nil, nil, CFrame.identity, CFrame.identity
end

-- the rig as Gait needs it, or nil if this isn't an R15 body
local function buildRig(root: BasePart, humanoid: Humanoid, found)
	for _, name in LEGS do
		if not found[name] then
			return nil
		end
	end
	local spec, byChild = {}, {}
	for name, joint in found do
		local p0, p1, c0, c1 = partsOf(joint)
		if p0 and p1 then
			spec[name] = { C0 = c0, C1 = c1, Instance = joint, Part0 = p0 }
			byChild[p1] = name
		end
	end
	for name, j in spec do
		j.Parent = byChild[j.Part0]
	end
	if not spec.Root or spec.Root.Part0 ~= root then
		return nil
	end
	for name, j in spec do
		if name ~= "Root" and not j.Parent then
			spec[name] = nil -- (hangs off something we don't know: leave it alone)
		end
	end
	for _, name in LEGS do
		if not spec[name] then
			return nil
		end
	end
	local rig = Gait.Rig.new(spec)
	local gait = Gait.new(rig, {
		Pelvis = "Root",
		Legs = {
			Left = { Hip = "LeftHip", Knee = "LeftKnee", Ankle = "LeftAnkle" },
			Right = { Hip = "RightHip", Knee = "RightKnee", Ankle = "RightAnkle" },
		},
		GroundY = -(humanoid.HipHeight + root.Size.Y / 2),
		Params = HUMAN,
	})
	return rig, gait
end

----------------------------------------------------------------------------------------
-- each character
----------------------------------------------------------------------------------------
local states = {} -- [character] = state
local retryAt = {} -- [character] = when to look at a body that wasn't R15 again

local function stopWatching(st)
	for _, c in st.Connections do
		c:Disconnect()
	end
	table.clear(st.Connections)
end

-- Roblox's idle / walk / run are stopped as they start; emotes and tool poses are noted
local function watchAnimator(st)
	local animator = st.Humanoid:FindFirstChildOfClass("Animator")
	if not animator or st.Animator == animator then
		return
	end
	st.Animator = animator
	local function onTrack(track: AnimationTrack)
		local anim = track.Animation
		local holder = anim and anim.Parent
		local kind = (holder and holder.Parent and holder.Parent.Name == "Animate") and holder.Name or nil
		if kind and REPLACED[kind] then
			if not st.Broken then
				track:Stop(0)
			end
			return
		end
		if kind and STATES[kind] then
			return
		end
		local priority = track.Priority
		local takesOver = (kind and EMOTES[kind])
			or (priority ~= Enum.AnimationPriority.Core and priority.Value >= Enum.AnimationPriority.Action.Value)
		local set = (takesOver and st.Override) or ((kind and TOOLS[kind]) and st.ArmOverride) or nil
		if set then
			set[track] = true
			table.insert(st.Connections, track.Stopped:Connect(function()
				set[track] = nil
			end))
		end
	end
	table.insert(st.Connections, animator.AnimationPlayed:Connect(onTrack))
	for _, track in animator:GetPlayingAnimationTracks() do
		onTrack(track)
	end
end

local function newState(character: Model, root: BasePart, humanoid: Humanoid)
	local found = findJoints(character)
	local rig, gait = buildRig(root, humanoid, found)
	if not rig then
		return nil
	end
	local now = os.clock()
	local st = {
		Character = character,
		Root = root,
		Humanoid = humanoid,
		Rig = rig,
		Gait = gait,
		HipHeight = humanoid.HipHeight,
		Weight = 0,
		Override = {},
		ArmOverride = {},
		Connections = {},
		Lean = newSpring(), -- forward lean (radians, + = forward)
		SideLean = newSpring(), -- leaning into turns (+ = to the left)
		ArmL = newSpring(), -- arm swing (radians, + = forward)
		ArmR = newSpring(),
		LookYaw = newSpring(),
		LookPitch = newSpring(),
		LookAt = Vector2.zero,
		NextLook = now + rng:NextNumber(1, 3),
		Shift = 0, -- -1 = weight on the left leg, +1 = on the right
		ShiftTo = 0,
		NextShift = now + rng:NextNumber(2, 5),
		Seed = rng:NextNumber(0, 100),
		Skip = 0,
		SkipDt = 0,
		Errors = 0,
		NextCheck = now + 1,
	}
	watchAnimator(st)
	return st
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function()
	rayParams.RespectCanCollide = true
end)

local function groundAt(pos: Vector3): number?
	local hit = Workspace:Raycast(pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -6, 0), rayParams)
	return hit and hit.Position.Y or nil
end

-- the walk and idle for one character, into st.Rig.Out
local function pose(st, dt: number, now: number, grounded: boolean)
	local gait, rig = st.Gait, st.Rig
	local P = gait.P
	local L = gait.HipHeight
	local walk = gait.WalkWeight
	local idle = 1 - walk
	local run = gait.RunBlend
	local fwd = math.clamp(gait.Forwardness or 1, 0, 1)

	-- standing: weight shifts from leg to leg, the head looks around
	if now > st.NextShift then
		local options = { -0.9, -0.55, 0, 0.55, 0.9 }
		st.ShiftTo = options[rng:NextInteger(1, #options)]
		st.NextShift = now + rng:NextNumber(4, 9)
	end
	st.Shift = ease(st.Shift, st.ShiftTo * idle, 1.8, dt)
	local shift = st.Shift
	if now > st.NextLook then
		local far = rng:NextNumber() < 0.3
		st.LookAt = Vector2.new(rng:NextNumber(-1, 1) * (far and 0.7 or 0.28), rng:NextNumber(-0.12, 0.08))
		st.NextLook = now + rng:NextNumber(1.8, 5.5)
	end
	local breath = math.sin(now * 2 * math.pi / 4.2 + st.Seed)
	local balance = math.sin(now * 0.9 + st.Seed) * 0.006 + math.sin(now * 0.37 + st.Seed * 2) * 0.005

	-- leaning: into turns, and the body carrying on forward when you stop
	for _, e in gait.Events do
		if e.Kind == "Stop" then
			st.Lean.V += 1.9 * math.clamp(e.Speed / 16, 0.25, 1.3)
		elseif e.Kind == "Start" then
			st.Lean.V += 0.9
		elseif e.Kind == "Land" then
			st.Lean.V += 0.6 * (e.Strength or 1)
		end
	end
	local lean = spring(st.Lean, 0, 7, 0.45, dt)
	local turnLean = math.clamp(gait.YawRate * gait.Speed / 196.2 * 0.7, -0.22, 0.22) * walk
	local sideLean = spring(st.SideLean, turnLean, 9, 0.8, dt)

	-- the hips (Gait adds its own walking motion to this)
	local extra = {
		Offset = Vector3.new(shift * 0.07 * L, -math.abs(shift) * 0.03 * L, -lean * 0.22 * L),
		Turn = CFrame.Angles(-lean * 0.3 + balance, shift * 0.05, shift * 0.075 + sideLean),
	}
	gait:Step(dt, st.Root.CFrame, st.Root.AssemblyLinearVelocity, grounded, groundAt, extra)

	-- the walk's rhythm, the same numbers Gait moves the hips with
	local cyc = 2 * math.pi * (gait.Phase + 0.05)
	local hipYaw = -math.sin(cyc) * P.Yaw * walk
	local hipRoll = math.sin(cyc) * P.Roll * walk * (1 - run * 0.4)
	local hipPitch = lerp(P.Pitch[1], P.Pitch[2], run) * walk * fwd

	-- spine: leaning forward the faster you go, the chest turning against the hips and
	-- keeping the shoulders level, breathing when still
	local chestPitch = -(0.025 + 0.07 * run) * walk * fwd - lean * 0.7 + breath * 0.014 * idle
	local chestYaw = math.sin(cyc) * math.rad(13) * walk * (1 - 0.35 * run) - hipYaw * 0.3
	local chestRoll = -shift * 0.1 - hipRoll * 0.85 - sideLean * 0.3
	rig:Write("Waist", rig:Local("Waist", CFrame.Angles(chestPitch, chestYaw, chestRoll)))

	-- head: level, looking where you're going (and into turns); looking around when still
	local lookYaw = spring(st.LookYaw, st.LookAt.X * idle + math.clamp(gait.YawRate * 0.09, -0.4, 0.4) * walk, 7, 0.85, dt)
	local lookPitch = spring(st.LookPitch, st.LookAt.Y * idle, 7, 0.85, dt)
	local neckPitch = -(chestPitch - lean * 0.3 - hipPitch) * 0.75 + lookPitch - 0.03 - breath * 0.006 * idle
	local neckYaw = -(chestYaw + hipYaw) * 0.9 + lookYaw - shift * 0.04
	local neckRoll = -(chestRoll + shift * 0.075 + hipRoll + sideLean) * 0.6
	rig:Write("Neck", rig:Local("Neck", CFrame.Angles(neckPitch, neckYaw, neckRoll)))

	-- arms: against the legs while moving (the right arm forward as the left foot does),
	-- hanging loose when still. They swing on springs so they carry on when you stop.
	local omega = lerp(20, 30, run)
	-- (the springs lag behind a quick swing: aim that much ahead, and a little bigger)
	local r = 2 * math.pi * (gait.Rate or 0) * walk / omega
	local lag = math.atan2(1.4 * r, 1 - r * r)
	local gain = math.clamp(math.sqrt((1 - r * r) ^ 2 + (1.4 * r) ^ 2), 1, 2.5)
	-- (the right arm is furthest forward as the left foot lands)
	local swing = math.sin(2 * math.pi * (gait.Phase - (gait.SwingShare or 0.4) + 0.25) + lag)
	local amp = lerp(0.3, 0.52, run) * walk * lerp(0.35, 1, fwd) * gain
	local carry = -(0.03 + 0.1 * run) * walk -- (arms swing a little further back than forward)
	local hang = 0.04 + breath * 0.012 * idle
	local armR = spring(st.ArmR, swing * amp + carry + hang * idle, omega, 0.7, dt)
	local armL = spring(st.ArmL, -swing * amp + carry + hang * idle, omega, 0.7, dt)
	local out = lerp(0.06, 0.03, walk) + 0.03 * run
	for _, side in { "Left", "Right" } do
		local s = (side == "Left") and -1 or 1
		local a = (side == "Left") and armL or armR
		local forward = math.max(a, 0)
		-- elbows: soft when still, bending more as the arm comes forward, ~90 degrees running
		local elbow = lerp(0.17, lerp(0.2 + forward * 0.45, 1.2 + forward * 0.4, run), walk)
		rig:Write(side .. "Shoulder", rig:Local(side .. "Shoulder", CFrame.Angles(a, s * 0.14 * run * walk, s * out - s * chestRoll * 0.5)))
		rig:Write(side .. "Elbow", rig:Local(side .. "Elbow", CFrame.Angles(elbow, 0, 0)))
		rig:Write(side .. "Wrist", rig:Local(side .. "Wrist", CFrame.Angles(lerp(0.08, -0.05, walk), 0, 0)))
	end
end

-- puts rig.Out on the joints, blended with whatever Roblox's animations left there
local function apply(st, weight: number)
	local rig = st.Rig
	local armBusy = next(st.ArmOverride) ~= nil
	for name, t in rig.Out do
		if not (armBusy and RIGHT_ARM[name]) then
			local inst = rig.Joints[name].Instance
			if inst and inst.Parent then
				if weight >= 0.999 then
					inst.Transform = t
				else
					inst.Transform = inst.Transform:Lerp(t, weight)
				end
			end
		end
	end
end

local function stepCharacter(st, dt: number, now: number, near: boolean)
	local humanoid, gait = st.Humanoid, st.Gait
	local hs = humanoid:GetState()
	local grounded = ON_FEET[hs] == true
	local airborne = IN_AIR[hs] == true
	local busy = next(st.Override) ~= nil
	local want = (grounded and not busy and not humanoid.Sit) and 1 or 0
	st.Weight = ease(st.Weight, want, (want > st.Weight) and 7 or 14, dt)
	if not grounded and not airborne then
		-- sitting, climbing, swimming, ragdolled...: Roblox's animations have the body; the
		-- feet start fresh when you're back on them
		for _, leg in gait.Legs do
			leg.Pos = nil
		end
		return
	end
	-- (far away: worked out every third frame, put back on every frame)
	st.SkipDt += dt
	st.Skip -= 1
	if near or st.Skip <= 0 or not next(st.Rig.Out) then
		pose(st, math.min(st.SkipDt, 0.1), now, grounded)
		st.SkipDt = 0
		st.Skip = near and 0 or 3
	end
	local w = smooth(st.Weight)
	if w > 0.002 then
		apply(st, w)
	end
end

-- every frame, in the order PoseLayers keeps (before PowerFX's poses go on top)
PoseLayers.Add(10, "Locomotion", function(dt: number)
	dt = math.clamp(dt, 0, 0.1)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local seen = {}
	local exclude = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			table.insert(exclude, character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude

	for _, character in exclude do
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
			seen[character] = true
			local st = states[character]
			-- joints swapped out (the joint upgrade, a respawned limb) or the body resized:
			-- build it again
			if st and now > st.NextCheck then
				st.NextCheck = now + 1
				local stale = st.Root ~= root or st.HipHeight ~= humanoid.HipHeight
				for _, j in st.Rig.Joints do
					if not (j.Instance and j.Instance.Parent) then
						stale = true
					end
				end
				if stale then
					stopWatching(st)
					states[character] = nil
					st = nil
				else
					watchAnimator(st)
				end
			end
			if not st and now >= (retryAt[character] or 0) then
				st = newState(character, root, humanoid)
				states[character] = st
				retryAt[character] = (not st) and now + 2 or nil
			end
			if st and not st.Broken then
				local near = not camPos or (root.Position - camPos).Magnitude < FAR
				local ok, err = pcall(stepCharacter, st, dt, now, near)
				if not ok then
					st.Errors += 1
					if st.Errors >= 3 then
						-- give the body back to Roblox's own animations rather than freeze it
						st.Broken = true
						warn("[Locomotion] stopped animating " .. character.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end
	for character, st in states do
		if not seen[character] then
			stopWatching(st)
			states[character] = nil
		end
	end
	for character in retryAt do
		if not character.Parent then
			retryAt[character] = nil
		end
	end
end)
