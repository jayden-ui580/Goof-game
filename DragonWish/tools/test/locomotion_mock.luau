-- Runs the real Locomotion script (with the real Gait) on a fake R15 character and checks what
-- a player would see: the feet don't slide while it walks and runs, the arms swing against the
-- legs, the head stays steady, it rocks forward when it stops, it shifts its weight and looks
-- around when standing, and it hands the body to Roblox's animations in the air and for emotes.
-- usage (from the DragonWish folder): lune run tools/test/locomotion_mock.luau [dump.json] [motor6d]
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local dumpPath = process.args[1] ~= "" and process.args[1] or nil
local jointClass = process.args[2] == "motor6d" and "Motor6D" or "AnimationConstraint"

-- the character: joints at the R15 body's pivots (ground at y = 0, root part centre at y = 3)
local char = I.new("Model")
char.Name = "Player1"
char.Parent = I.new("Folder")
local hum = I.new("Humanoid")
hum.HipHeight = 2
hum.Sit = false
hum.RigType = roblox.Enum.HumanoidRigType.R15
hum.Parent = char
local humState = roblox.Enum.HumanoidStateType.Running
roblox.implementMethod("Humanoid", "GetState", function()
	return humState
end)
local parts = {}
local function part(name, centre)
	local p = I.new("Part")
	p.Name = name
	p.Size = V3.new(1, 1, 1)
	p.CFrame = CF.new(centre)
	p.Position = centre -- (test parts don't work this out themselves)
	p.Parent = char
	parts[name] = p
	return p
end
local root = part("HumanoidRootPart", V3.new(0, 3, 0))
root.Size = V3.new(2, 2, 1)
root.AssemblyLinearVelocity = V3.zero
local PIVOTS = { -- joint = { parent part, child part, pivot }
	Root = { "HumanoidRootPart", "LowerTorso", V3.new(0, 2.26, 0) },
	Waist = { "LowerTorso", "UpperTorso", V3.new(0, 2.45, 0) },
	Neck = { "UpperTorso", "Head", V3.new(0, 4.0, 0) },
}
for side, sx in { Left = -1, Right = 1 } do
	PIVOTS[side .. "Shoulder"] = { "UpperTorso", side .. "UpperArm", V3.new(1.0 * sx, 3.76, 0) }
	PIVOTS[side .. "Elbow"] = { side .. "UpperArm", side .. "LowerArm", V3.new(1.5 * sx, 3.03, 0) }
	PIVOTS[side .. "Wrist"] = { side .. "LowerArm", side .. "Hand", V3.new(1.5 * sx, 2.29, 0) }
	PIVOTS[side .. "Hip"] = { "LowerTorso", side .. "UpperLeg", V3.new(0.5 * sx, 2.0, 0) }
	PIVOTS[side .. "Knee"] = { side .. "UpperLeg", side .. "LowerLeg", V3.new(0.5 * sx, 1.17, 0) }
	PIVOTS[side .. "Ankle"] = { side .. "LowerLeg", side .. "Foot", V3.new(0.5 * sx, 0.27, 0) }
end
-- each part's centre: a little below its joint (where exactly doesn't matter to the pose)
for name, j in PIVOTS do
	part(j[2], j[3] - V3.new(0, 0.3, 0))
end
local joints = {}
for name, j in PIVOTS do
	local p0, p1 = parts[j[1]], parts[j[2]]
	local c0 = CF.new(j[3] - p0.CFrame.Position)
	local c1 = CF.new(j[3] - p1.CFrame.Position)
	local m = I.new(jointClass)
	m.Name = name
	if jointClass == "Motor6D" then
		m.Part0, m.Part1, m.C0, m.C1 = p0, p1, c0, c1
	else
		local a0, a1 = I.new("Attachment"), I.new("Attachment")
		a0.Name, a1.Name = name .. "RigAttachment", name .. "RigAttachment"
		a0.CFrame, a1.CFrame = c0, c1
		a0.Parent, a1.Parent = p0, p1
		m.Attachment0, m.Attachment1 = a0, a1
	end
	m.Transform = CF.identity
	m.Parent = p1
	joints[name] = { Inst = m, P0 = j[1], P1 = j[2], C0 = c0, C1 = c1 }
end

-- forward kinematics from the joints' Transforms: every part's frame in the world
local function solve()
	local world = { HumanoidRootPart = root.CFrame }
	local function get(name)
		if world[name] then
			return world[name]
		end
		for jn, j in joints do
			if j.P1 == name then
				world[name] = get(j.P0) * j.C0 * j.Inst.Transform * j.C1:Inverse()
				return world[name]
			end
		end
	end
	for _, j in joints do
		get(j.P1)
	end
	return world
end

-- the fake game
local T = 0
local layer
local env = {
	Vector3 = V3, CFrame = CF, Vector2 = roblox.Vector2, Enum = roblox.Enum, typeof = typeof, print = print, warn = print,
	os = { clock = function() return T end },
	Random = { new = function()
		local r = { s = 11 }
		function r:NextNumber(a, b)
			a = a or 0
			b = b or 1
			self.s = (self.s * 1103515245 + 12345) % 2147483648
			return a + (b - a) * self.s / 2147483648
		end
		function r:NextInteger(a, b)
			return math.floor(self:NextNumber(a, b + 0.999))
		end
		return r
	end },
	RaycastParams = { new = function() return {} end },
}
local modules = {
	Gait = function()
		return luau.load(fs.readFile("src/ReplicatedStorage/Gait.luau"), { environment = { Vector3 = V3, CFrame = CF } })()
	end,
	PoseLayers = function()
		return { Add = function(order, name, fn) layer = fn end }
	end,
}
env.require = function(name)
	return modules[name]()
end
env.game = { GetService = function(_, n)
	if n == "Players" then
		return { GetPlayers = function() return { { Character = char } } end }
	elseif n == "Workspace" then
		return {
			CurrentCamera = { CFrame = CF.new(0, 6, 12) },
			Raycast = function(_, from) return { Position = V3.new(from.X, 0, from.Z) } end,
		}
	elseif n == "ReplicatedStorage" then
		return { WaitForChild = function(_, x) return x end }
	end
end }
luau.load(fs.readFile("src/StarterPlayerScripts/Locomotion.client.luau"), { environment = env })()
assert(layer, "Locomotion didn't add its pose layer")

local frames = {}
local events = {}
local function frame(dt, rootCF, vel)
	T += dt
	root.CFrame = rootCF
	root.Position = rootCF.Position
	root.AssemblyLinearVelocity = vel
	layer(dt)
	local rec = { t = T, root = { rootCF.Position.X, rootCF.Position.Y, rootCF.Position.Z }, yaw = select(2, rootCF:ToEulerAnglesYXZ()), j = {} }
	for name, j in joints do
		local t = j.Inst.Transform
		local rx, ry, rz = t:ToEulerAnglesXYZ()
		rec.j[name] = { a = { rx, ry, rz }, p = { t.Position.X, t.Position.Y, t.Position.Z } }
	end
	table.insert(frames, rec)
end

local failed = false
local function check(what, ok)
	print((ok and "PASS  " or "FAIL  ") .. what)
	if not ok then
		failed = true
	end
end

local function footPoints(world, side)
	local foot = world[side .. "Foot"]
	local ankleLocal = foot:PointToObjectSpace(PIVOTS[side .. "Ankle"][3]) -- (rest: the foot hasn't moved yet)
	return foot, ankleLocal
end
local restWorld = solve()
local soleLocal = {}
for _, side in { "Left", "Right" } do
	local foot = restWorld[side .. "Foot"]
	soleLocal[side] = {
		Toe = foot:PointToObjectSpace(V3.new(PIVOTS[side .. "Ankle"][3].X, 0, -0.6)),
		Heel = foot:PointToObjectSpace(V3.new(PIVOTS[side .. "Ankle"][3].X, 0, 0.2)),
	}
end

-- 1. standing still for 8 seconds
local yaw0 = 0
local shifts, looks = {}, {}
local footStart = {}
for i = 1, 480 do
	frame(1 / 60, CF.new(0, 3, 0), V3.zero)
	local w = solve()
	if i == 30 then
		for _, side in { "Left", "Right" } do
			footStart[side] = w[side .. "Foot"].Position
		end
	end
	local rootT = joints.Root.Inst.Transform
	table.insert(shifts, rootT.Position.X)
	local _, neckYaw = joints.Neck.Inst.Transform:ToEulerAnglesYXZ()
	table.insert(looks, neckYaw)
end
local function range(list)
	local lo, hi = math.huge, -math.huge
	for _, v in list do
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	return hi - lo
end
local w = solve()
local footMoved = (w.LeftFoot.Position - footStart.Left).Magnitude + (w.RightFoot.Position - footStart.Right).Magnitude
print(("  standing: hips shift %.2f studs side to side, head turns over %.0f degrees, feet moved %.3f"):format(range(shifts), math.deg(range(looks)), footMoved))
check("standing: the weight shifts from leg to leg", range(shifts) > 0.08)
check("standing: the head looks around", math.deg(range(looks)) > 10)
check("standing: the feet stay put (or take a small adjusting step)", footMoved < 0.6)
local leftKnee = select(1, joints.LeftKnee.Inst.Transform:ToEulerAnglesXYZ())
check("standing: knees not locked straight", math.abs(leftKnee) > 0.005 or math.abs(select(1, joints.RightKnee.Inst.Transform:ToEulerAnglesXYZ())) > 0.005)

-- 2. running at Roblox's normal speed (16), then walking slower (8, like when exhausted)
for _, speed in { 16, 8, 4.5 } do
	local x = 0
	local slide, planted, worst = 0, 0, 0
	local last = {}
	local armLegs, armN = 0, 0
	local headYaw = 0
	local start = #frames
	for i = 1, 240 do
		x += speed / 60
		frame(1 / 60, CF.new(0, 3, -x), V3.new(0, 0, -speed))
		local wo = solve()
		for _, side in { "Left", "Right" } do
			local foot = wo[side .. "Foot"]
			local toe, heel = foot * soleLocal[side].Toe, foot * soleLocal[side].Heel
			local low = (toe.Y < heel.Y) and toe or heel
			local prev = last[side]
			-- a foot touching the ground (its lowest point on it, in this frame and the last)
			-- mustn't slide
			if prev and low.Y < 0.015 and prev.Y < 0.015 then
				local d = V3.new(low.X - prev.X, 0, low.Z - prev.Z).Magnitude
				if (toe.Y < heel.Y) == prev.ToeDown then
					slide += d
					worst = math.max(worst, d)
					planted += 1
				end
			end
			last[side] = { X = low.X, Y = low.Y, Z = low.Z, ToeDown = toe.Y < heel.Y }
		end
		-- the right arm forward while the left foot is forward
		local lf = wo.LeftFoot.Position.Z - wo.RightFoot.Position.Z -- (+: the right foot is ahead)
		local ra = select(1, joints.RightShoulder.Inst.Transform:ToEulerAnglesXYZ())
		local la = select(1, joints.LeftShoulder.Inst.Transform:ToEulerAnglesXYZ())
		armLegs += (ra - la) * lf
		armN += 1
		if i > 60 then
			local _, hy = wo.Head:ToEulerAnglesYXZ()
			headYaw = math.max(headYaw, math.abs(hy))
		end
	end
	print(("  %s at %d: planted-foot slide %.3f studs over %d studs (worst frame %.4f), head turns at most %.1f degrees"):format(
		speed >= 12 and "running" or "walking", speed, slide, speed * 4, worst, math.deg(headYaw)))
	check(("speed %d: planted feet don't slide"):format(speed), slide / (speed * 4) < 0.01)
	-- (left foot ahead = right arm forward: the product is negative)
	print(("  arms against legs: %.3f"):format(armLegs / armN))
	check(("speed %d: the arms swing against the legs"):format(speed), armLegs / armN < -0.01)
	check(("speed %d: the head stays facing forward"):format(speed), math.deg(headYaw) < 12)
	if speed == 16 then
		-- 3. stopping: the body carries on forward, rocks back, settles
		local stopAt = CF.new(0, 3, -x)
		local minPitch, settledPitch = 0, 0
		for i = 1, 90 do
			frame(1 / 60, stopAt, V3.zero)
			local p = select(1, joints.Waist.Inst.Transform:ToEulerAnglesXYZ())
			minPitch = math.min(minPitch, p)
			settledPitch = p
		end
		print(("  stopping: the chest pitches %.0f degrees forward, then back to %.1f"):format(-math.deg(minPitch), -math.deg(settledPitch)))
		check("stopping: the body carries on forward and rocks back upright", -math.deg(minPitch) > 4 and math.abs(math.deg(settledPitch)) < 3)
		for i = 1, 60 do
			frame(1 / 60, stopAt, V3.zero)
		end
	end
	-- (back to the start for the next run)
	for i = 1, 60 do
		frame(1 / 60, CF.new(0, 3, 0), V3.zero)
	end
end

-- 4. a jump: the body is handed to Roblox's jump / fall animations
humState = roblox.Enum.HumanoidStateType.Freefall
local marker = CF.Angles(0.3, 0, 0)
for i = 1, 30 do
	for _, j in joints do
		j.Inst.Transform = marker -- (what Roblox's fall animation would put there)
	end
	frame(1 / 60, CF.new(0, 5, 0), V3.new(0, -10, 0))
end
local untouched = true
for name, j in joints do
	local same = (j.Inst.Transform.Position - marker.Position).Magnitude < 1e-6 and j.Inst.Transform.LookVector:Dot(marker.LookVector) > 0.99999
	if not same then
		print("  (touched in the air: " .. name .. ")")
	end
	untouched = untouched and same
end
check("in the air: Roblox's jump / fall animations play untouched", untouched)
humState = roblox.Enum.HumanoidStateType.Running
for i = 1, 30 do
	frame(1 / 60, CF.new(0, 3, 0), V3.zero)
end
check("landing: back on its feet", joints.Root.Inst.Transform ~= marker and joints.LeftHip.Inst.Transform ~= marker)

if dumpPath then
	fs.writeFile(dumpPath, serde.encode("json", frames))
	print("wrote " .. #frames .. " frames to " .. dumpPath)
end
if failed then
	error("some checks failed")
end
