-- Runs the real HairPhysics solver against a fake R15 body that stands, walks, jumps and spins.
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local env = { Vector3 = V3, CFrame = CF, Instance = I }
local HP = luau.load(fs.readFile(process.args[1]), { environment = env })()
local info = serde.decode("json", fs.readFile(process.args[2]))
local presetName = process.args[3]
local settingsJson = process.args[4] and serde.decode("json", process.args[4]) or {}
local dumpPath = process.args[5]
if dumpPath == "" then dumpPath = nil end

local layout
for _, h in info do
	if h.name == presetName then layout = h end
end
local function v(t) return V3.new(t[1], t[2], t[3]) end

-- build a fake character
local char = I.new("Model"); char.Name = "Rig"
I.new("Humanoid").Parent = char
local function part(name, size)
	local p = I.new("Part"); p.Name = name; p.Size = size; p.Parent = char; return p
end
local head = part("Head", V3.new(1.2, 1.2, 1.2))
local ut = part("UpperTorso", V3.new(2, 1.6, 1))
local lt = part("LowerTorso", V3.new(2, 0.4, 1))
local la = part("LeftUpperArm", V3.new(1, 1.2, 1))
local ra = part("RightUpperArm", V3.new(1, 1.2, 1))
-- offsets from the root (root = point under the head centre at y = 0)
local HEAD_Y = 4.5
local offs = {
	Head = CF.new(0, HEAD_Y, 0),
	UpperTorso = CF.new(0, HEAD_Y - 0.65 - 0.8, 0),
	LowerTorso = CF.new(0, HEAD_Y - 0.65 - 1.6 - 0.2, 0),
}
local acc = I.new("Accessory"); acc.Parent = char
local hair = I.new("MeshPart"); hair.Name = "Handle"; hair.Parent = acc

-- bones with random orientations (the importer gives bones arbitrary rotations; the solver must not care)
local rng = Random and Random.new(7) or nil
local seed = 12345
local function rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function randRot()
	return CF.fromAxisAngle(V3.new(rand() - 0.5, rand() - 0.5, rand() - 0.5).Unit, rand() * 6.28)
end
local worldOf = {}
local root = I.new("Bone"); root.Name = "HairRoot"; root.Parent = hair
root.CFrame = CF.new(v(layout.bones.HairRoot)) * randRot(); worldOf.HairRoot = root.CFrame
local specs = {}
for _, c in layout.chains do
	local parent, parentName = root, "HairRoot"
	for _, bn in c.bones do
		local b = I.new("Bone"); b.Name = bn; b.Parent = parent
		local w = CF.new(v(layout.bones[bn])) * randRot()
		b.CFrame = worldOf[parentName]:Inverse() * w
		worldOf[bn] = w
		parent, parentName = b, bn
	end
	local bones = {}
	for i = 1, #c.bones - 1 do bones[i] = c.bones[i] end
	table.insert(specs, { Name = c.name, Bones = bones, Tip = c.bones[#c.bones], Radii = c.radii })
end

if settingsJson.Wind then settingsJson.Wind = V3.new(settingsJson.Wind[1], settingsJson.Wind[2], settingsJson.Wind[3]) end
local settings = HP.mergeSettings(settingsJson)
local sim = assert(HP.Sim.new(hair, { Chains = specs }, settings))

-- motion script
local function pose(t)
	local x, y, z, yaw, armSwing = 0, 0, 0, 0, 0
	local walkStart, walkEnd = 2, 6
	if t > walkStart then
		local tw = math.min(t, walkEnd) - walkStart
		z = -16 * tw
		if t < walkEnd then armSwing = math.sin(tw * 8) * 0.6; y = math.abs(math.sin(tw * 8)) * 0.08 end
	end
	if t > 4.5 and t < 4.5 + 0.51 then
		local tj = t - 4.5
		y += 50 * tj - 0.5 * 196.2 * tj * tj
	end
	if t > 7 and t < 7.5 then yaw = math.pi * (t - 7) / 0.5 elseif t >= 7.5 then yaw = math.pi end
	if t > 9 and t < 9.25 then yaw = math.pi - math.pi * 0.5 * (t - 9) / 0.25 elseif t >= 9.25 then yaw = math.pi * 0.5 end
	return CF.new(x, y, z) * CF.Angles(0, yaw, 0), armSwing
end
local function place(t)
	local rootCF, swing = pose(t)
	head.CFrame = rootCF * offs.Head
	ut.CFrame = rootCF * offs.UpperTorso
	lt.CFrame = rootCF * offs.LowerTorso
	local shoulderY = HEAD_Y - 0.65
	la.CFrame = rootCF * CF.new(-1.5, shoulderY, 0) * CF.Angles(swing, 0, 0) * CF.new(0, -0.6, 0)
	ra.CFrame = rootCF * CF.new(1.5, shoulderY, 0) * CF.Angles(-swing, 0, 0) * CF.new(0, -0.6, 0)
	hair.CFrame = head.CFrame
end

-- metrics
local colliderDistance = HP.colliderDistance
local function angle(a, b) return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))) end

local dt = tonumber(process.args[6]) or (1 / 60)
local T = 11
local stats = { nan = false, bodyPen = 0, bodyPenAt = "", selfPen = 0, selfPenAt = "", bendOver = 0, settleSpeed1 = 0, settleSpeed2 = 0, sag = 0, trail = 0, jumpLift = 0, maxStretch = 0, cpu = 0 }
local frames = {}
local t = 0
local prevPos = {}
local frame = 0
while t < T do
	t += dt; frame += 1
	place(t)
	local c0 = os.clock()
	sim:Update(dt, nil)
	stats.cpu += os.clock() - c0
	local hcf = hair.CFrame
	local frameBend = false
	local alphaR = (sim.Accum or 0) / (1 / 60)
	for _, chain in sim.Chains do
		chain.R = {}
		for k = 1, chain.N + 1 do chain.R[k] = hair.CFrame * chain.LocalPrev[k]:Lerp(chain.LocalCur[k], alphaR) end
	end
	for ci, chain in sim.Chains do
		for k = 1, chain.N + 1 do
			local p = chain.R[k]
			if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then stats.nan = true end
		end
		-- body penetration (only colliders the bead is allowed to use)
		for k = 2, chain.N + 1 do
			for cj, col in sim.Colliders do
				local r = chain.BodyRadius[k][cj]
				if r then
					local pen = r - colliderDistance(col, chain.R[k])
					if pen > stats.bodyPen then stats.bodyPen = pen; stats.bodyPenAt = ("%s[%d] vs %s t=%.2f"):format(chain.Name, k, col.Part.Name, t) end
				end
			end
		end
		-- bend: angle between segment and its target (parent-swung rest dir)
		for k = 1, chain.N do
			local restW = hcf:VectorToWorldSpace(chain.RestDir[k])
			local dir = (chain.R[k + 1] - chain.R[k]).Unit
			local target = restW
			if k > 1 then
				target = HP.rotateByArc(restW, hcf:VectorToWorldSpace(chain.RestDir[k - 1]), (chain.R[k] - chain.R[k - 1]).Unit)
			end
			local over = angle(dir, target) - math.deg(math.acos(chain.CosMax[k]))
			stats.bendOver = math.max(stats.bendOver, over)
			if over > 5 then frameBend = true end
			local stretch = math.abs((chain.R[k + 1] - chain.R[k]).Magnitude / chain.RestLen[k] - 1)
			stats.maxStretch = math.max(stats.maxStretch, stretch)
		end
		-- settle speed + sag
		for k = 2, chain.N + 1 do
			local key = ci * 100 + k
			local p = chain.R[k]
			if prevPos[key] then
				local sp = (p - prevPos[key]).Magnitude / dt
				if t > 1.6 and t < 2 then stats.settleSpeed1 = math.max(stats.settleSpeed1, sp) end
				if t > 10.5 then stats.settleSpeed2 = math.max(stats.settleSpeed2, sp) end
			end
			prevPos[key] = p
			if t > 1.6 and t < 2 then stats.sag = math.max(stats.sag, (p - hcf * chain.J[k]).Magnitude) end
		end
		-- trailing while walking: tip deviation angle from rest (root->tip) in head space
		if t > 3 and t < 4.4 then
			local restVec = chain.J[chain.N + 1] - chain.J[1]
			local cur = hcf:VectorToObjectSpace(chain.R[chain.N + 1] - chain.R[1])
			stats.trail = math.max(stats.trail, angle(restVec, cur))
		end
		if t > 4.5 and t < 5.3 then
			local restVec = chain.J[chain.N + 1] - chain.J[1]
			local cur = hcf:VectorToObjectSpace(chain.R[chain.N + 1] - chain.R[1])
			stats.jumpLift = math.max(stats.jumpLift, angle(restVec, cur))
		end
	end
	if frameBend then stats.bendFrames = (stats.bendFrames or 0) + 1 end
	-- strand overlap regardless of solver pair list: deepest capsule overlap between different chains
	for ia = 1, #sim.Chains do
		for ib = ia + 1, #sim.Chains do
			local A, B = sim.Chains[ia], sim.Chains[ib]
			for a = 1, A.N do for b = 1, B.N do
				local s1, t1 = HP.closestSegSeg(A.R[a], A.R[a + 1], B.R[b], B.R[b + 1])
				local d = (A.R[a]:Lerp(A.R[a + 1], s1) - B.R[b]:Lerp(B.R[b + 1], t1)).Magnitude
				local restS, restT = HP.closestSegSeg(A.J[a], A.J[a + 1], B.J[b], B.J[b + 1])
				local restD = (A.J[a]:Lerp(A.J[a + 1], restS) - B.J[b]:Lerp(B.J[b + 1], restT)).Magnitude
				local allowed = math.min(A.SegRadius[a] + B.SegRadius[b], restD * 0.9)
				if restD < 1.2 and allowed > 0.03 then
					local ov = allowed - d
					if ov > (stats.strandOverlap or 0) then stats.strandOverlap = ov; stats.overlapAt = A.Name .. a .. "/" .. B.Name .. b .. (" t=%.2f"):format(t) end
					if d < 0.05 then stats.touchFrames = (stats.touchFrames or 0) + 1 end
				end
			end end
		end
	end
	for _, pr in sim.Pairs do
		local s, tt = HP.closestSegSeg(pr.A.R[pr.a], pr.A.R[pr.a + 1], pr.B.R[pr.b], pr.B.R[pr.b + 1])
		local ca = pr.A.R[pr.a]:Lerp(pr.A.R[pr.a + 1], s)
		local cb = pr.B.R[pr.b]:Lerp(pr.B.R[pr.b + 1], tt)
		local pen = pr.MinDist - (ca - cb).Magnitude
		if pen > stats.selfPen then stats.selfPen = pen; stats.selfPenAt = ("%s%d/%s%d t=%.2f min=%.2f"):format(pr.A.Name, pr.a, pr.B.Name, pr.b, t, pr.MinDist) end
	end
	if dumpPath and frame % 3 == 0 then
		local row = { t = t, head = { hcf:GetComponents() }, chains = {} }
		for _, chain in sim.Chains do
			local pts = {}
			for k = 1, chain.N + 1 do local p = hcf:PointToObjectSpace(chain.Pos[k]); table.insert(pts, { p.X, p.Y, p.Z }) end
			table.insert(row.chains, pts)
		end
		-- bone check: world position of each bone's child joint from Transforms must match the beads
		table.insert(frames, row)
	end
end
-- verify WriteBones: recompute bone world CFrames from Bone.CFrame/Transform and compare with beads
local maxBoneErr = 0
for _, chain in sim.Chains do
	local world = hair.CFrame * chain.ParentRest
	for k = 1, chain.N do
		local b = chain.Bones[k]
		world = world * b.CFrame * b.Transform
		local childWorld = world * chain.ChildOffset[k]; local beadNow = hair.CFrame * chain.LocalPrev[k + 1]:Lerp(chain.LocalCur[k + 1], sim.Accum / (1/60))
		maxBoneErr = math.max(maxBoneErr, (childWorld - beadNow).Magnitude)
	end
end
stats.boneErr = maxBoneErr
stats.pairs = #sim.Pairs; stats.frames = frame
stats.cpuPerFrameMs = stats.cpu / frame * 1000
stats.cpu = nil
print(serde.encode("json", stats, false))
if dumpPath then fs.writeFile(dumpPath, serde.encode("json", frames, false)) end
-- crossing check: order of the five back strands' tips (left to right) at the end
local order = {}
for _, chain in sim.Chains do
	local p = hair.CFrame:PointToObjectSpace(chain.Pos[chain.N + 1])
	table.insert(order, { chain.Name, p.X })
end
table.sort(order, function(a, b) return a[2] < b[2] end)
local names = {}
for _, o in order do table.insert(names, o[1]) end
print("tip order L->R:", table.concat(names, " "))
