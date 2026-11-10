-- Walks an R15-sized pair of legs with the real Gait module and measures what players would
-- notice: feet sliding on the ground while they're planted, steps that don't match the
-- distance, the stop and turn steps, strafing without the feet crossing, and landing.
-- usage (from the DragonWish folder): lune run tools/test/gait_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local V3, CF = roblox.Vector3, roblox.CFrame

local Gait = luau.load(fs.readFile("src/ReplicatedStorage/Gait.luau"), {
	environment = { Vector3 = V3, CFrame = CF, setmetatable = setmetatable, table = table, math = math, assert = assert },
})()

-- the legs of the R15 body (HumanoidRootPart centre 3 studs above the ground)
local function r15()
	local joints = {
		Root = { C0 = CF.new(0, -1, 0), C1 = CF.new(0, -0.2, 0) },
		LeftHip = { Parent = "Root", C0 = CF.new(-0.5, -0.2, 0), C1 = CF.new(0, 0.415, 0) },
		LeftKnee = { Parent = "LeftHip", C0 = CF.new(0, -0.415, 0), C1 = CF.new(0, 0.45, 0) },
		LeftAnkle = { Parent = "LeftKnee", C0 = CF.new(0, -0.45, 0), C1 = CF.new(0, 0.135, 0.1) },
		RightHip = { Parent = "Root", C0 = CF.new(0.5, -0.2, 0), C1 = CF.new(0, 0.415, 0) },
		RightKnee = { Parent = "RightHip", C0 = CF.new(0, -0.415, 0), C1 = CF.new(0, 0.45, 0) },
		RightAnkle = { Parent = "RightKnee", C0 = CF.new(0, -0.45, 0), C1 = CF.new(0, 0.135, 0.1) },
	}
	local rig = Gait.Rig.new(joints)
	local gait = Gait.new(rig, {
		Pelvis = "Root",
		Legs = { Left = { Hip = "LeftHip", Knee = "LeftKnee", Ankle = "LeftAnkle" }, Right = { Hip = "RightHip", Knee = "RightKnee", Ankle = "RightAnkle" } },
		GroundY = -3,
	})
	return rig, gait
end

local failed = false
local function check(what, ok)
	print((ok and "PASS  " or "FAIL  ") .. what)
	if not ok then
		failed = true
	end
end

-- the toe and heel of each foot, in the foot's own frame (from the rest pose)
local function contactPoints(rig, gait)
	local pts = {}
	for side, leg in gait.Legs do
		local restFoot = rig.Rest[leg.Names.Ankle]
		local ankle = rig:Pivot(leg.Names.Ankle, rig:RestParent(leg.Names.Ankle)).Position
		local L = gait.HipHeight
		local sole = ankle - V3.new(0, leg.AnkleHeight, 0)
		pts[side] = {
			Toe = restFoot:PointToObjectSpace(sole + V3.new(0, 0, -gait.P.FootForward * L)),
			Heel = restFoot:PointToObjectSpace(sole + V3.new(0, 0, gait.P.FootBack * L)),
		}
	end
	return pts
end

-- runs the gait along a path. path(t) -> root CFrame, velocity, grounded
local function run(rig, gait, seconds, path, t0, stats)
	local dt = 1 / 60
	local pts = contactPoints(rig, gait)
	stats = stats or { Slide = 0, Planted = 0, Footfalls = 0, Settles = 0, IKMiss = 0, Crossed = 0, Frames = 0, Events = {} }
	local last = stats.Last or {}
	local t = t0 or 0
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += dt
		local root, vel, grounded = path(t)
		gait:Step(dt, root, vel, grounded ~= false, function() return 0 end)
		local frames = rig:Frames(rig.Out)
		for _, e in gait.Events do
			table.insert(stats.Events, { Kind = e.Kind, T = t, Settle = e.Settle, Side = e.Side })
			if e.Kind == "Footfall" then
				if e.Settle then
					stats.Settles += 1
				else
					stats.Footfalls += 1
				end
			end
		end
		for side, leg in gait.Legs do
			local foot = root * frames[leg.Names.Ankle]
			local toe, heel = foot * pts[side].Toe, foot * pts[side].Heel
			local contact
			if leg.FootPitch > 1e-3 then
				contact = toe
			elseif leg.FootPitch < -1e-3 then
				contact = heel
			else
				contact = (toe + heel) / 2
			end
			local key = leg.Swing and "air" or tostring(leg.Pos)
			local prev = last[side]
			if prev and prev.Key == key and key ~= "air" and gait.Mode ~= "Air" then
				-- a planted foot: its contact point must not move along the ground
				local d = V3.new(contact.X - prev.Contact.X, 0, contact.Z - prev.Contact.Z).Magnitude
				-- (switching from the heel to the toe moves the contact point by design)
				if (prev.Pitch > 1e-3) == (leg.FootPitch > 1e-3) and (prev.Pitch < -1e-3) == (leg.FootPitch < -1e-3) then
					stats.Slide += d
					stats.MaxSlide = math.max(stats.MaxSlide or 0, d)
				end
				stats.Planted += 1
			end
			last[side] = { Key = key, Contact = contact, Pitch = leg.FootPitch }
			if not leg.Swing and leg.AnkleWant then
				local miss = (leg.AnkleAt - leg.AnkleWant).Magnitude
				stats.WorstMiss = math.max(stats.WorstMiss or 0, miss)
				if miss > 0.03 then
					stats.IKMiss += 1
				end
			end
		end
		-- the feet mustn't cross over (left foot staying on the body's left)
		local lp = root:PointToObjectSpace(root * frames.LeftAnkle.Position)
		local rp = root:PointToObjectSpace(root * frames.RightAnkle.Position)
		if lp.X > rp.X - 0.15 then
			stats.Crossed += 1
		end
		stats.Frames += 1
	end
	stats.Last = last
	return stats, t
end

local function straight(speed, yaw)
	local dir = V3.new(-math.sin(yaw or 0), 0, -math.cos(yaw or 0))
	return function(t)
		local pos = V3.new(0, 3, 0) + dir * speed * t
		return CF.new(pos) * CF.Angles(0, yaw or 0, 0), dir * speed, true
	end
end

-- 1. walking and running straight at Roblox speeds: no sliding, steps match the distance
for _, speed in { 4, 8, 12, 16, 22 } do
	local rig, gait = r15()
	run(rig, gait, 0.3, straight(0, 0)) -- standing first
	local st = run(rig, gait, 4, straight(speed, 0), 0)
	local distance = speed * 4
	local perStep = distance / math.max(st.Footfalls, 1)
	local cadence = st.Footfalls / 4
	print(("  speed %2d: %d steps (%.2f studs each, %.1f steps/s, run blend %.2f), slide %.3f studs total (worst frame %.4f), planted feet out of reach %d frames (worst %.3f)"):format(
		speed, st.Footfalls, perStep, cadence, gait.RunBlend, st.Slide, st.MaxSlide or 0, st.IKMiss, st.WorstMiss or 0))
	check(("speed %d: planted feet don't slide (%.2f%% of the distance)"):format(speed, 100 * st.Slide / distance), st.Slide / distance < 0.01)
	check(("speed %d: one step per %.2f studs, as planned (%.2f)"):format(speed, perStep, gait.StepLen), math.abs(perStep - gait.StepLen) / gait.StepLen < 0.12)
	check(("speed %d: the legs reach every planted foot"):format(speed), st.IKMiss <= 2)
	check(("speed %d: the feet never cross"):format(speed), st.Crossed == 0)
end

-- 2. stopping: the swinging foot comes down, then at most one settle step, then still
do
	local rig, gait = r15()
	run(rig, gait, 0.2, straight(0, 0))
	local st, t = run(rig, gait, 2.13, straight(16, 0), 0)
	local stopAt = straight(16, 0)(t)
	local here = function()
		return stopAt, V3.zero, true
	end
	local before = #st.Events
	st, t = run(rig, gait, 1.5, here, t, st)
	local settles, settledAt = 0, nil
	for i = before + 1, #st.Events do
		local e = st.Events[i]
		if e.Kind == "Footfall" then
			settles += 1
		elseif e.Kind == "Settled" then
			settledAt = settledAt or e.T
		end
	end
	local lOff = (gait.Legs.Left.Pos - gait:IdleSpot(gait.Legs.Left, stopAt)).Magnitude
	local rOff = (gait.Legs.Right.Pos - gait:IdleSpot(gait.Legs.Right, stopAt)).Magnitude
	print(("  stop: %d steps to settle, settled %.2f s after stopping, feet %.2f / %.2f studs from their spots"):format(
		settles, (settledAt or 99) - (t - 1.5), lOff, rOff))
	check("stop: one or two steps to come to rest", settles >= 1 and settles <= 2)
	check("stop: settled within 0.8 s", settledAt and settledAt - (t - 1.5) < 0.8)
	check("stop: both feet back under the body", lOff < 0.35 and rOff < 0.35 and gait.Mode == "Idle")
	check("stop: no sliding on the way", st.Slide / (16 * 2.13) < 0.01)
end

-- 3. turning on the spot: the feet shuffle round
do
	local rig, gait = r15()
	run(rig, gait, 0.3, straight(0, 0))
	local turning = function(t)
		local yaw = math.rad(120) * math.clamp((t - 0.3) / 0.5, 0, 1)
		return CF.new(0, 3, 0) * CF.Angles(0, yaw, 0), V3.zero, true
	end
	local st = run(rig, gait, 1.8, turning, 0.3)
	local yawL = gait.Legs.Left.Yaw
	print(("  turn 120 degrees: %d shuffle steps, left foot now at %.0f degrees"):format(st.Settles, math.deg(yawL)))
	check("turning on the spot shuffles the feet round", st.Settles >= 2 and math.abs(Gait.AngleDiff(yawL, math.rad(120))) < math.rad(32))
	check("... without sliding a planted foot", st.Slide < 0.05)
end

-- 4. walking a curve, sideways, backward
for _, case in { { "curving", 0 }, { "sideways", 1 }, { "backward", 2 } } do
	local rig, gait = r15()
	run(rig, gait, 0.3, straight(0, 0))
	local path
	if case[2] == 0 then
		path = function(t) -- a circle of radius 12 at 12 studs/s
			local a = t
			local pos = V3.new(12 * math.cos(a) - 12, 3, -12 * math.sin(a))
			local dir = V3.new(-math.sin(a), 0, -math.cos(a))
			return CF.new(pos) * CF.Angles(0, a, 0), dir * 12, true
		end
	elseif case[2] == 1 then
		path = function(t)
			return CF.new(V3.new(8 * t, 3, 0)), V3.new(8, 0, 0), true
		end
	else
		path = function(t)
			return CF.new(V3.new(0, 3, 7 * t)), V3.new(0, 0, 7), true
		end
	end
	local st = run(rig, gait, 3, path, 0)
	local distance = case[2] == 0 and 36 or case[2] == 1 and 24 or 21
	print(("  %s: %d steps, slide %.3f studs, crossed %d frames, IK misses %d"):format(case[1], st.Footfalls, st.Slide, st.Crossed, st.IKMiss))
	check(("%s: no sliding (%.2f%%)"):format(case[1], 100 * st.Slide / distance), st.Slide / distance < 0.015)
	check(("%s: the feet don't cross"):format(case[1]), st.Crossed == 0)
end

-- 5. speeding up from standing to a run
do
	local rig, gait = r15()
	run(rig, gait, 0.3, straight(0, 0))
	local x = 0
	local lastT = 0
	local accel = function(t)
		local v = 16 * math.clamp(t / 0.4, 0, 1)
		x += v * (t - lastT)
		lastT = t
		return CF.new(V3.new(0, 3, -x)), V3.new(0, 0, -v), true
	end
	local st = run(rig, gait, 2, accel, 0)
	check(("speeding up: no sliding (%.3f studs)"):format(st.Slide), st.Slide / x < 0.01)
end

-- 6. a jump: legs tuck up, land, settle
do
	local rig, gait = r15()
	run(rig, gait, 0.3, straight(0, 0))
	local jump = function(t)
		local up = t < 0.6 and math.max(0, 6 * t - 10 * t * t) or 0
		return CF.new(V3.new(0, 3 + up, 0)), V3.zero, t >= 0.6
	end
	local st = run(rig, gait, 1.4, jump, 0)
	local landed = false
	for _, e in st.Events do
		landed = landed or e.Kind == "Land"
	end
	check("jumping: lands, then stands still", landed and gait.Mode == "Idle")
	local finite = true
	for _, t in rig.Out do
		local p = t.Position
		finite = finite and p.X == p.X and p.Y == p.Y and p.Z == p.Z
	end
	check("... and every joint is a real number", finite)
end

if failed then
	error("some checks failed")
end
