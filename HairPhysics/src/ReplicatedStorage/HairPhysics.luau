--[[
	HairPhysics  (ModuleScript — lives in ReplicatedStorage)

	The hair simulator. It runs on each player's computer (the LocalScript
	"HairPhysicsClient" starts it), because bone movement is purely visual and
	Roblox intentionally does not send Bone.Transform changes over the network.

	How it works, in plain English:
	  * Every hair strand is a "chain" of bones (PigL_1 -> PigL_2 -> ... -> PigL_End).
	    Each joint between bones is treated like a little bead on a string.
	  * Each frame the beads keep their momentum, get pulled down by gravity, and
	    get dragged along when the head moves (that's the swing / lag).
	  * Then rules are applied to the beads, in order:
	      1. Length   – the string never stretches.
	      2. Shape    – each bone springs back toward the shape the hair was modeled in.
	      3. Bend cap – no joint can bend more than MaxBend degrees, so a strand can never
	                    fold back on itself.
	      4. Body     – beads are pushed out of the head / torso / upper arms.
	      5. Hair     – every bone is a capsule (a pill shape); capsules from different
	                    strands (and far-apart parts of the same strand) push each other
	                    apart, so strands can't pass through each other or bunch into one spot.
	  * Finally the bones are rotated to point at their beads, which bends the mesh.

	Every tunable lives in HairConfig — you shouldn't need to edit this file.
]]

local HairPhysics = {}

HairPhysics.TAG = "HairPhysics" -- CollectionService tag the server puts on hair parts

local STEP = 1 / 60 -- the simulation always runs in fixed 60 Hz slices, so it behaves the
-- same at any frame rate; frames in between are smoothed (see WriteBones)
local MAX_SUBSTEPS = 4 -- most slices per frame (protects low frame rates)
local TELEPORT_DISTANCE = 8 -- head moved further than this in one frame? reset the hair
local EPS = 1e-6

-- Used for anything a hair's Physics table in HairConfig leaves out.
local DEFAULTS = {
	Gravity = 30,
	GravityCompensation = 0.85,
	Damping = 0.1,
	Inertia = 0.35,
	Stiffness = { 0.3, 0.2, 0.14, 0.1, 0.08 },
	MaxBend = { 35, 35, 40, 45, 50 },
	Wind = Vector3.zero,
	WindGust = 0,
	SelfCollision = true,
	SelfCollisionRadiusScale = 1,
	SelfCollisionRange = 1.2,
	CollisionIterations = 2,
	BodyColliders = { "Head", "UpperTorso", "Torso", "LeftUpperArm", "RightUpperArm" },
	TorsoExtendDown = 0.4,
	HeadColliderScale = 1.05,
	BodyColliderScale = 0.95,
	BodyRadiusScale = 0.8,
	SimulationDistance = 150,
	ChainOverrides = {},
}
HairPhysics.DEFAULTS = DEFAULTS

----------------------------------------------------------------------------------------
-- small vector helpers (no CFrames in the hot loop: they're slower than plain vectors)
----------------------------------------------------------------------------------------

-- Rotates v by the rotation that turns unit vector a into unit vector b.
local function rotateByArc(v: Vector3, a: Vector3, b: Vector3): Vector3
	local axis = a:Cross(b)
	local s2 = axis:Dot(axis)
	local c = a:Dot(b)
	if s2 < EPS then
		if c > 0 then
			return v
		end
		-- a and b point opposite ways: spin 180 degrees around any axis at right angles to a
		local perp = (math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis):Cross(a).Unit
		return perp * (2 * perp:Dot(v)) - v
	end
	return v * c + axis:Cross(v) + axis * (axis:Dot(v) * (1 - c) / s2)
end

-- Rotation-only CFrame that turns unit vector a into unit vector b.
local function arcCFrame(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local w = 1 + a:Dot(b)
	if w < EPS then
		local perp = (math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis):Cross(a).Unit
		return CFrame.new(0, 0, 0, perp.X, perp.Y, perp.Z, 0)
	end
	local m = math.sqrt(axis:Dot(axis) + w * w)
	return CFrame.new(0, 0, 0, axis.X / m, axis.Y / m, axis.Z / m, w / m)
end

-- If dir points more than maxAngle away from target, swing it back onto the edge of that cone.
local function clampToCone(dir: Vector3, target: Vector3, cosMax: number, sinMax: number): Vector3
	if dir:Dot(target) >= cosMax then
		return dir
	end
	local axis = target:Cross(dir)
	local s = axis.Magnitude
	if s < EPS then
		axis = (math.abs(target.X) < 0.9 and Vector3.xAxis or Vector3.yAxis):Cross(target)
		s = axis.Magnitude
	end
	return target * cosMax + (axis / s):Cross(target) * sinMax
end

-- Closest points between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9).
-- Returns s, t: how far along each segment (0..1) the closest points are.
local function closestSegSeg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (number, number)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	if a <= EPS and e <= EPS then
		return 0, 0
	end
	if a <= EPS then
		return 0, math.clamp(f / e, 0, 1)
	end
	local c = d1:Dot(r)
	if e <= EPS then
		return math.clamp(-c / a, 0, 1), 0
	end
	local b = d1:Dot(d2)
	local denom = a * e - b * b
	local s = denom > EPS and math.clamp((b * f - c * e) / denom, 0, 1) or 0
	local t = (b * s + f) / e
	if t < 0 then
		return math.clamp(-c / a, 0, 1), 0
	elseif t > 1 then
		return math.clamp((b - c) / a, 0, 1), 1
	end
	return s, t
end

HairPhysics.rotateByArc = rotateByArc
HairPhysics.closestSegSeg = closestSegSeg

-- Value for bone index k from a per-bone list; lists shorter than the chain reuse their last value.
local function pick(list, k: number): number
	if type(list) ~= "table" then
		return list
	end
	return list[math.min(k, #list)]
end

-- A bone's CFrame relative to the MeshPart it lives in (walks up through parent bones).
local function partSpaceCFrame(inst: Instance, part: BasePart): CFrame?
	if inst == part then
		return CFrame.identity
	end
	local cf = CFrame.identity
	local node: Instance? = inst
	while node ~= part do
		if node == nil or not node:IsA("Bone") then
			return nil
		end
		cf = (node :: Bone).CFrame * cf
		node = node.Parent
	end
	return cf
end

HairPhysics.PartSpaceCFrame = partSpaceCFrame

----------------------------------------------------------------------------------------
-- Rig fitting (used by the server when it puts hair on a head)
----------------------------------------------------------------------------------------

-- The 24 ways a model can be turned so its sides still line up with the axes (what an
-- importer's "which way is up/forward" setting can do to a mesh).
local AXIS_ROTATIONS = {}
do
	local axes = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
	for _, x in axes do
		for _, y in axes do
			if math.abs(x:Dot(y)) < 0.5 then
				table.insert(AXIS_ROTATIONS, CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y)))
			end
		end
	end
end

-- Works out how the imported hair relates to the rig as designed: compares where each bone
-- was modeled (design, head space) with where it actually ended up inside the MeshPart
-- (actual, part space). Returns the scale, turn and shift that map one onto the other, plus
-- Error = average mismatch in studs (should be ~0).
function HairPhysics.FitRig(design: { Vector3 }, actual: { Vector3 })
	local n = #design
	local cd, ca = Vector3.zero, Vector3.zero
	for i = 1, n do
		cd += design[i]
		ca += actual[i]
	end
	cd /= n
	ca /= n
	local spread = 0
	for i = 1, n do
		local d = design[i] - cd
		spread += d:Dot(d)
	end
	local best
	for _, rot in AXIS_ROTATIONS do
		local num = 0
		for i = 1, n do
			num += rot:VectorToWorldSpace(design[i] - cd):Dot(actual[i] - ca)
		end
		local scale = num / spread
		if scale > 0 then
			local err = 0
			for i = 1, n do
				local e = rot:VectorToWorldSpace(design[i] - cd) * scale - (actual[i] - ca)
				err += e:Dot(e)
			end
			if not best or err < best.err then
				best = { err = err, rot = rot, scale = scale }
			end
		end
	end
	return {
		Scale = best.scale,
		Rotation = best.rot,
		Translation = ca - best.rot:VectorToWorldSpace(cd) * best.scale,
		Error = math.sqrt(best.err / n),
	}
end

-- CFrame of the hair part relative to the head, from a FitRig result: puts the modeled head
-- centre of the hair on the head's centre, facing the same way.
function HairPhysics.HeadToPart(fit): CFrame
	return (CFrame.new(fit.Translation) * fit.Rotation):Inverse()
end

local function mergeSettings(overrides)
	local s = table.clone(DEFAULTS)
	for key, value in overrides or {} do
		s[key] = value
	end
	return s
end
HairPhysics.mergeSettings = mergeSettings

----------------------------------------------------------------------------------------
-- Sim: one simulated hair (one MeshPart with bone chains)
----------------------------------------------------------------------------------------

local Sim = {}
Sim.__index = Sim
HairPhysics.Sim = Sim

local function buildChain(part: BasePart, spec, settings)
	local bones = {}
	for _, name in spec.Bones do
		local bone = part:FindFirstChild(name, true)
		if not (bone and bone:IsA("Bone")) then
			return nil, ("bone '%s' missing"):format(name)
		end
		table.insert(bones, bone)
	end
	local n = #bones
	local parentRest = partSpaceCFrame(bones[1].Parent :: Instance, part)
	if not parentRest then
		return nil, ("bone '%s' is not inside the hair part"):format(spec.Bones[1])
	end

	-- joint positions in the part's own space; joint n+1 is the strand tip
	local J, restCF = {}, {}
	for k, bone in bones do
		restCF[k] = partSpaceCFrame(bone, part) :: CFrame
		J[k] = restCF[k].Position
	end
	local tip = spec.Tip and part:FindFirstChild(spec.Tip, true)
	if tip and tip:IsA("Bone") and partSpaceCFrame(tip, part) then
		J[n + 1] = (partSpaceCFrame(tip, part) :: CFrame).Position
	elseif n >= 2 then
		-- tip bone didn't survive import: extend the last bone by the length of the one before
		J[n + 1] = J[n] + (J[n] - J[n - 1])
	else
		J[n + 1] = J[n] + Vector3.new(0, -0.4, 0)
	end

	-- per-chain overrides (e.g. "Lock" = both front locks) on top of the hair's settings
	local stiff, bend = settings.Stiffness, settings.MaxBend
	for prefix, ov in settings.ChainOverrides do
		if spec.Name:sub(1, #prefix) == prefix then
			stiff = ov.Stiffness or stiff
			bend = ov.MaxBend or bend
		end
	end

	local chain = {
		Name = spec.Name,
		Bones = bones,
		N = n,
		BoneCF = {},
		ParentRest = parentRest,
		J = J,
		RestLen = {},
		RestDir = {},
		ChildOffset = {},
		Radius = {},
		SegRadius = {},
		Stiffness = {},
		CosMax = {},
		SinMax = {},
		Pos = {},
		Prev = {},
		LocalPrev = {}, -- bead positions relative to the hair part, previous slice
		LocalCur = {}, -- ... and latest slice (drawn frames blend between the two)
		BodyRadius = {},
	}
	for k = 1, n do
		chain.BoneCF[k] = bones[k].CFrame
		local d = J[k + 1] - J[k]
		chain.RestLen[k] = math.max(d.Magnitude, 0.01)
		chain.RestDir[k] = d.Magnitude > EPS and d.Unit or Vector3.new(0, -1, 0)
		chain.ChildOffset[k] = restCF[k]:PointToObjectSpace(J[k + 1])
		chain.Stiffness[k] = math.clamp(pick(stiff, k), 0, 1)
		local maxBend = math.rad(math.clamp(pick(bend, k), 1, 179))
		chain.CosMax[k] = math.cos(maxBend)
		chain.SinMax[k] = math.sin(maxBend)
	end
	for k = 1, n + 1 do
		chain.Radius[k] = pick(spec.Radii or 0.15, k)
	end
	for k = 1, n do
		chain.SegRadius[k] = (chain.Radius[k] + chain.Radius[k + 1]) * 0.5 * settings.SelfCollisionRadiusScale
	end
	return chain
end

-- Hair-vs-hair capsule pairs. The allowed gap is shrunk wherever two capsules already
-- overlap in the modeled pose, so the collision never fights the hair's own shape.
local function buildPairs(chains, range: number)
	local pairsList = {}
	for ia, A in chains do
		for ib = ia, #chains do
			local B = chains[ib]
			for a = 1, A.N do
				for b = (ia == ib) and a + 2 or 1, B.N do
					local s, t = closestSegSeg(A.J[a], A.J[a + 1], B.J[b], B.J[b + 1])
					local pa = A.J[a]:Lerp(A.J[a + 1], s)
					local pb = B.J[b]:Lerp(B.J[b + 1], t)
					local restGap = (pa - pb).Magnitude
					local minDist = math.min(A.SegRadius[a] + B.SegRadius[b], restGap * 0.9)
					if minDist > 0.03 and restGap < range then
						table.insert(pairsList, {
							A = A,
							a = a,
							B = B,
							b = b,
							MinDist = minDist,
							Reach = (A.RestLen[a] + B.RestLen[b]) * 0.5 + minDist,
						})
					end
				end
			end
		end
	end
	return pairsList
end

function Sim.new(part: BasePart, layout, settings)
	local self = setmetatable({}, Sim)
	self.Part = part
	self.Settings = settings
	self.Chains = {}
	self.Colliders = {}
	self.Awake = false
	self.Time = 0
	local problems = {}
	for _, spec in layout.Chains do
		local chain, err = buildChain(part, spec, settings)
		if chain then
			table.insert(self.Chains, chain)
		else
			table.insert(problems, err)
		end
	end
	if #self.Chains == 0 then
		return nil, "no usable bone chains (" .. table.concat(problems, ", ") .. ")"
	end
	self.Problems = problems
	self.Pairs = settings.SelfCollision and buildPairs(self.Chains, settings.SelfCollisionRange) or {}
	return self
end

-- Finds the character this hair is worn by (first ancestor Model that has a Humanoid).
local function findCharacter(part: Instance): Model?
	local node = part.Parent
	while node do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Body collider shapes: Head = sphere, everything else = box. The UpperTorso box is stretched
-- down over the LowerTorso (TorsoExtendDown) — two stacked boxes would keep shoving a strand
-- that sits at the seam back and forth between them.
function Sim:BuildColliders(character: Model?)
	local s = self.Settings
	self.Colliders = {}
	if not character then
		return
	end
	for _, name in s.BodyColliders do
		local bp = character:FindFirstChild(name)
		if bp and bp:IsA("BasePart") then
			if name == "Head" then
				local size = bp.Size
				table.insert(self.Colliders, {
					Part = bp,
					Sphere = true,
					Radius = math.min(size.X, size.Y, size.Z) * 0.5 * s.HeadColliderScale,
					Offset = CFrame.identity,
				})
			else
				local half = bp.Size * 0.5 * s.BodyColliderScale
				local offset = CFrame.identity
				if name == "UpperTorso" and s.TorsoExtendDown > 0 then
					half += Vector3.new(0, s.TorsoExtendDown * 0.5, 0)
					offset = CFrame.new(0, -s.TorsoExtendDown * 0.5, 0)
				end
				table.insert(self.Colliders, { Part = bp, Sphere = false, Half = half, Offset = offset })
			end
		end
	end
end

-- Signed distance from point p to a collider's surface (negative = inside).
local function colliderDistance(col, p: Vector3): number
	local cf = col.Part.CFrame * col.Offset
	if col.Sphere then
		return (p - cf.Position).Magnitude - col.Radius
	end
	local lp = cf:PointToObjectSpace(p)
	local q = Vector3.new(math.abs(lp.X), math.abs(lp.Y), math.abs(lp.Z)) - col.Half
	local outside = Vector3.new(math.max(q.X, 0), math.max(q.Y, 0), math.max(q.Z, 0)).Magnitude
	return outside + math.min(math.max(q.X, q.Y, q.Z), 0)
end

HairPhysics.colliderDistance = colliderDistance

-- Puts every bead back at its modeled position (used on start and after teleports).
function Sim:ResetToRest(partCF: CFrame)
	for _, chain in self.Chains do
		for k = 1, chain.N + 1 do
			local p = partCF * chain.J[k]
			chain.Pos[k] = p
			chain.Prev[k] = p
			chain.LocalPrev[k] = chain.J[k]
			chain.LocalCur[k] = chain.J[k]
		end
	end
	self.AnchorCF = partCF
	self.LastCF = partCF
	self.LastH = STEP
	self.Accum = 0
	for _, col in self.Colliders do
		col.To = nil -- don't sweep body parts across a teleport
	end
end

function Sim:Wake(partCF: CFrame)
	self:BuildColliders(findCharacter(self.Part))
	for _, col in self.Colliders do
		col.From = col.Part.CFrame
		col.To = col.From
	end
	self:ResetToRest(partCF)
	-- How far each bead may get from each body part. A bead that already sits closer than its
	-- radius in the modeled pose gets a smaller radius, and one that starts inside ignores that
	-- part, so the body never shoves the hair out of its own resting shape.
	local s = self.Settings
	for _, chain in self.Chains do
		for k = 2, chain.N + 1 do
			local radii = {}
			for ci, col in self.Colliders do
				local gap = colliderDistance(col, chain.Pos[k])
				radii[ci] = gap > 0.01 and math.min(chain.Radius[k] * s.BodyRadiusScale, gap * 0.9) or false
			end
			chain.BodyRadius[k] = radii
		end
	end
	self.Awake = true
end

function Sim:Sleep()
	self.Awake = false
	for _, chain in self.Chains do
		for _, bone in chain.Bones do
			if bone.Parent then
				bone.Transform = CFrame.identity
			end
		end
	end
end

-- Rules 1-3: length, spring back to the modeled shape, bend cap. Works root -> tip.
-- Each bone's "target" direction is its modeled direction, swung along with however much
-- the bone above it has swung, so a strand keeps its curl while it moves.
--
-- gravityStep (optional) is this slice's pull of gravity. The modeled shape is how the hair
-- already hangs under gravity, so without help gravity would sag it below that shape at rest.
-- Gravity compensation aims the spring a little above the modeled shape by exactly the amount
-- gravity drags it down, so a still character's hair sits in its modeled pose, while swings,
-- jumps and falls still move it.
function Sim:SolveShape(chain, rot: CFrame, stiffnessFactor: number, gravityStep: Vector3?)
	local pos = chain.Pos
	local prevRest, prevDir
	for k = 1, chain.N do
		local restW = rot:VectorToWorldSpace(chain.RestDir[k])
		local target = (k == 1) and restW or rotateByArc(restW, prevRest, prevDir)
		local d = pos[k + 1] - pos[k]
		local len = d.Magnitude
		local dir = len > EPS and d / len or target
		if stiffnessFactor > 0 then
			local st = 1 - (1 - chain.Stiffness[k]) ^ stiffnessFactor
			local aim = target
			if gravityStep and st > 0.01 then
				local sideways = gravityStep - target * gravityStep:Dot(target)
				aim = (target - sideways * ((1 - st) / (st * chain.RestLen[k]))).Unit
			end
			dir = dir + (aim - dir) * st
			local m = dir.Magnitude
			dir = m > EPS and dir / m or target
		end
		dir = clampToCone(dir, target, chain.CosMax[k], chain.SinMax[k])
		pos[k + 1] = pos[k] + dir * chain.RestLen[k]
		prevRest, prevDir = restW, dir
	end
end

-- Rule 4: push beads out of the body parts. Body parts are placed where they were at the same
-- moment as the slice being simulated (between last frame and this one), not where they are now.
function Sim:CollideBody()
	local colliders = self.Colliders
	if #colliders == 0 then
		return
	end
	local frames = {}
	local alpha = self.SliceAlpha or 1
	for ci, col in colliders do
		frames[ci] = col.From:Lerp(col.To, alpha) * col.Offset
	end
	for _, chain in self.Chains do
		local pos, prev = chain.Pos, chain.Prev
		for k = 2, chain.N + 1 do
			local radii = chain.BodyRadius[k]
			local p = pos[k]
			for ci, col in colliders do
				local r = radii[ci]
				if r then
					local cf = frames[ci]
					if col.Sphere then
						local c = cf.Position
						local d = p - c
						local m = d.Magnitude
						local reach = col.Radius + r
						if m < reach and m > EPS then
							p = c + d * (reach / m)
						end
					else
						-- box with rounded edges (the bead is a ball of radius r)
						local lp = cf:PointToObjectSpace(p)
						local half = col.Half
						local ax, ay, az = math.abs(lp.X), math.abs(lp.Y), math.abs(lp.Z)
						if ax < half.X + r and ay < half.Y + r and az < half.Z + r then
							local cx = math.clamp(lp.X, -half.X, half.X)
							local cy = math.clamp(lp.Y, -half.Y, half.Y)
							local cz = math.clamp(lp.Z, -half.Z, half.Z)
							local out = lp - Vector3.new(cx, cy, cz)
							local m = out.Magnitude
							if m > EPS then
								-- outside the box but too close to it: push straight away
								if m < r then
									p = cf:PointToWorldSpace(Vector3.new(cx, cy, cz) + out * (r / m))
								end
							else
								-- inside: leave through the nearest face, unless the bead was outside
								-- the opposite face last slice (it moved so fast it went past the
								-- middle) - then send it back out the side it came from
								local px, py, pz = half.X - ax, half.Y - ay, half.Z - az
								local lq = cf:PointToObjectSpace(prev[k])
								local axis, side, lqc, h
								if px <= py and px <= pz then
									axis, side, lqc, h = 1, lp.X, lq.X, half.X
								elseif py <= pz then
									axis, side, lqc, h = 2, lp.Y, lq.Y, half.Y
								else
									axis, side, lqc, h = 3, lp.Z, lq.Z, half.Z
								end
								if math.abs(lqc) > h and (lqc >= 0) ~= (side >= 0) then
									side = lqc
								end
								local face = (side >= 0 and 1 or -1) * (h + r)
								if axis == 1 then
									lp = Vector3.new(face, lp.Y, lp.Z)
								elseif axis == 2 then
									lp = Vector3.new(lp.X, face, lp.Z)
								else
									lp = Vector3.new(lp.X, lp.Y, face)
								end
								p = cf:PointToWorldSpace(lp)
							end
						end
					end
				end
			end
			pos[k] = p
		end
	end
end

-- Rule 5: bone capsules push each other apart (joint 1 of every chain is pinned to the head).
function Sim:CollideSelf()
	for _, pr in self.Pairs do
		local A, a, B, b = pr.A, pr.a, pr.B, pr.b
		local PA, PB = A.Pos, B.Pos
		local a0, a1, b0, b1 = PA[a], PA[a + 1], PB[b], PB[b + 1]
		if ((a0 + a1) - (b0 + b1)).Magnitude * 0.5 < pr.Reach then
			local s, t = closestSegSeg(a0, a1, b0, b1)
			local ca = a0 + (a1 - a0) * s
			local cb = b0 + (b1 - b0) * t
			local d = ca - cb
			local m = d.Magnitude
			local minDist = pr.MinDist
			if m < minDist then
				local normal = m > EPS and d / m or (a1 - b1).Unit
				-- how much each end can move (pinned root joints can't)
				local wa0 = a > 1 and (1 - s) or 0
				local wa1 = s
				local wb0 = b > 1 and (1 - t) or 0
				local wb1 = t
				local denom = wa0 * wa0 + wa1 * wa1 + wb0 * wb0 + wb1 * wb1
				if denom > 0.05 then
					local lambda = (minDist - m) / denom
					if wa0 > 0 then
						PA[a] += normal * (lambda * wa0)
					end
					PA[a + 1] += normal * (lambda * wa1)
					if wb0 > 0 then
						PB[b] -= normal * (lambda * wb0)
					end
					PB[b + 1] -= normal * (lambda * wb1)
				end
			end
		end
	end
end

function Sim:Substep(h: number, anchorCF: CFrame, sliceAlpha: number?)
	local s = self.Settings
	self.SliceAlpha = sliceAlpha or 1
	-- Part of the head's movement is copied straight onto the hair; the rest (Inertia)
	-- is left behind, which is what makes the hair trail and swing.
	local carry = 1 - s.Inertia
	local delta = anchorCF * self.AnchorCF:Inverse()
	self.AnchorCF = anchorCF
	local rot = anchorCF.Rotation

	local ratio = math.clamp(h / self.LastH, 0.5, 2)
	self.LastH = h
	local keep = (1 - s.Damping) ^ (h * 60)
	self.Time += h
	local wind = s.Wind
	if s.WindGust > 0 then
		wind *= 1 + s.WindGust * math.sin(self.Time * 1.7) * math.sin(self.Time * 0.63 + 1)
	end
	local gravity = Vector3.new(0, -s.Gravity, 0) * (h * h)
	local accel = gravity + wind * (h * h)
	local compensation = s.GravityCompensation > 0 and gravity * s.GravityCompensation or nil

	for _, chain in self.Chains do
		local pos, prev = chain.Pos, chain.Prev
		pos[1] = anchorCF * chain.J[1]
		prev[1] = pos[1]
		for k = 2, chain.N + 1 do
			local p, q = pos[k], prev[k]
			if carry > 0 then
				p = p:Lerp(delta * p, carry)
				q = q:Lerp(delta * q, carry)
			end
			local vel = (p - q) * (keep * ratio)
			prev[k] = p
			pos[k] = p + vel + accel
		end
		self:SolveShape(chain, rot, h * 60, compensation)
	end

	-- collisions go last so nothing is left inside the body or another strand; the small
	-- length error this can leave is fixed by the next slice and never shows (bones only aim)
	for i = 1, s.CollisionIterations do
		if i > 1 then
			for _, chain in self.Chains do
				self:SolveShape(chain, rot, 0)
			end
		end
		self:CollideBody()
		if #self.Pairs > 0 then
			self:CollideSelf()
		end
	end
	-- the body gets the very last word: hair poking into a body part is the most visible error
	self:CollideBody()
end

-- Turns each bone so it points at the next bead. Only Bone.Transform is touched, so the
-- modeled pose (Bone.CFrame) is never changed.
-- alpha (0..1) blends between the last two simulation slices for frames that land between them.
function Sim:WriteBones(partCF: CFrame, alpha: number)
	for _, chain in self.Chains do
		local lprev, lcur = chain.LocalPrev, chain.LocalCur
		local parentWorld = partCF * chain.ParentRest
		for k = 1, chain.N do
			local restWorld = parentWorld * chain.BoneCF[k]
			local restDir = restWorld:VectorToWorldSpace(chain.ChildOffset[k])
			local bead = partCF * lprev[k + 1]:Lerp(lcur[k + 1], alpha)
			local simDir = bead - restWorld.Position
			local newWorld = restWorld
			if simDir.Magnitude > EPS and restDir.Magnitude > EPS then
				local arc = arcCFrame(restDir.Unit, simDir.Unit)
				newWorld = CFrame.new(restWorld.Position) * arc * restWorld.Rotation
			end
			chain.Bones[k].Transform = restWorld:ToObjectSpace(newWorld)
			parentWorld = newWorld
		end
	end
end

-- Call once per rendered frame.
function Sim:Update(dt: number, cameraPosition: Vector3?)
	local partCF = self.Part.CFrame
	if cameraPosition and (partCF.Position - cameraPosition).Magnitude > self.Settings.SimulationDistance then
		if self.Awake then
			self:Sleep()
		end
		return
	end
	if not self.Awake then
		self:Wake(partCF)
	elseif (partCF.Position - self.LastCF.Position).Magnitude > TELEPORT_DISTANCE then
		self:ResetToRest(partCF)
	end

	dt = math.clamp(dt, 1e-4, 0.25)
	for _, col in self.Colliders do
		col.From = col.To or col.Part.CFrame
		col.To = col.Part.CFrame
	end
	local carried = self.Accum
	self.Accum += dt
	local from = self.LastCF
	local steps = 0
	while self.Accum >= STEP and steps < MAX_SUBSTEPS do
		steps += 1
		self.Accum -= STEP
		-- where the head was at the moment this slice ends (somewhere inside this frame)
		local alpha = math.clamp((steps * STEP - carried) / dt, 0, 1)
		local anchor = from:Lerp(partCF, alpha)
		self:Substep(STEP, anchor, alpha)
		for _, chain in self.Chains do
			local lprev, lcur, pos = chain.LocalPrev, chain.LocalCur, chain.Pos
			for k = 1, chain.N + 1 do
				lprev[k] = lcur[k]
				lcur[k] = anchor:PointToObjectSpace(pos[k])
			end
		end
	end
	if self.Accum >= STEP then
		self.Accum = 0 -- the game is running too slowly to keep up; skip ahead rather than spiral
	end
	self.LastCF = partCF
	self:WriteBones(partCF, self.Accum / STEP)
end

----------------------------------------------------------------------------------------
-- Client runner: simulates every part tagged "HairPhysics"
----------------------------------------------------------------------------------------

local started = false

function HairPhysics.StartClient()
	if started then
		return
	end
	started = true

	local RunService = game:GetService("RunService")
	local CollectionService = game:GetService("CollectionService")
	local Workspace = game:GetService("Workspace")
	local HairConfig = require(script.Parent:WaitForChild("HairConfig"))

	local sims = {} -- [part] = Sim
	local waiting = {} -- [part] = time we started waiting for its bones to arrive

	-- returns true when done with the part (started, or hopeless), false to try again later
	local function tryStart(part: Instance): (boolean, string?)
		if not part:IsA("BasePart") then
			return true
		end
		if not part:IsDescendantOf(Workspace) then
			return false, "not in Workspace"
		end
		local presetName = part:GetAttribute("HairPreset")
		local layout = HairConfig.Layouts[presetName]
		local hair = HairConfig.Hairs[presetName]
		if not layout then
			warn(("[HairPhysics] %s has unknown HairPreset '%s'"):format(part:GetFullName(), tostring(presetName)))
			return true -- give up on it
		end
		local sim, err = Sim.new(part, layout, mergeSettings(hair and hair.Physics))
		if not sim then
			return false, err
		end
		if #sim.Problems > 0 then
			warn("[HairPhysics] " .. part:GetFullName() .. ": skipped " .. table.concat(sim.Problems, ", "))
		end
		sims[part] = sim
		return true
	end

	local function add(part: Instance)
		if sims[part] then
			return
		end
		local ok = tryStart(part)
		if not ok then
			waiting[part] = os.clock() -- bones may still be streaming in; retry for a bit
		end
	end

	local function remove(part: Instance)
		waiting[part] = nil
		local sim = sims[part]
		if sim then
			sims[part] = nil
			sim:Sleep()
		end
	end

	CollectionService:GetInstanceAddedSignal(HairPhysics.TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(HairPhysics.TAG):Connect(remove)
	for _, part in CollectionService:GetTagged(HairPhysics.TAG) do
		add(part)
	end

	-- PreRender runs after Roblox has played animations for the frame and right before it
	-- draws, so our bone rotations are what ends up on screen.
	local ok, renderSignal = pcall(function()
		return RunService.PreRender
	end)
	if not ok or not renderSignal then
		renderSignal = RunService.RenderStepped
	end

	local retryClock = 0
	renderSignal:Connect(function(dt: number)
		retryClock += dt
		if retryClock > 0.5 then
			retryClock = 0
			for part, since in waiting do
				if part.Parent == nil then
					waiting[part] = nil
				else
					local done, err = tryStart(part)
					if done then
						waiting[part] = nil
					elseif not part:IsDescendantOf(Workspace) then
						waiting[part] = os.clock() -- stored away (e.g. ReplicatedStorage): keep watching quietly
					elseif os.clock() - since > 15 then
						waiting[part] = nil
						warn(("[HairPhysics] gave up on %s: %s"):format(part:GetFullName(), tostring(err)))
					end
				end
			end
		end

		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position
		for part, sim in sims do
			if part.Parent == nil then
				sims[part] = nil
			else
				local success, err = pcall(sim.Update, sim, dt, camPos)
				if not success then
					sims[part] = nil
					warn("[HairPhysics] stopped simulating " .. part:GetFullName() .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return HairPhysics
