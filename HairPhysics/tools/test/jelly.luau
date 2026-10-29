-- "Jelly meter": runs the real solver with the real HairConfig settings against a fake R15 body
-- and measures how wobbly the hair is after sudden stops, landings and spins.
-- usage (from the HairPhysics folder): lune run tools/test/jelly.luau <preset> [settingsOverrideJson] [dumpPath]
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local env = { Vector3 = V3, CFrame = CF, Instance = I, Color3 = roblox.Color3, Enum = roblox.Enum }
local HP = luau.load(fs.readFile("src/ReplicatedStorage/HairPhysics.luau"), { environment = env })()
local CFG = luau.load(fs.readFile("src/ReplicatedStorage/HairConfig.luau"), { environment = env })()
local preset = process.args[1]
local override = process.args[2] and process.args[2] ~= "" and serde.decode("json", process.args[2]) or {}
local dumpPath = process.args[3]
if dumpPath == "" then dumpPath = nil end
local jitter = tonumber(process.args[4]) or 0 -- random head shake per frame (studs), like network jitter
local layout = CFG.Layouts[preset]
local phys = table.clone(CFG.Hairs[preset].Physics)
for k, v in override do
	if type(v) == "table" and #v == 3 and k == "Wind" then v = V3.new(v[1], v[2], v[3]) end
	phys[k] = v
end
local settings = HP.mergeSettings(phys)

-- fake character (head 1.2 cube, R15-ish torso and arms)
local char = I.new("Model"); I.new("Humanoid").Parent = char
local function part(name, size) local p = I.new("Part"); p.Name = name; p.Size = size; p.Parent = char; return p end
local head = part("Head", V3.new(1.2, 1.2, 1.2))
local ut = part("UpperTorso", V3.new(2, 1.6, 1))
local la = part("LeftUpperArm", V3.new(1, 1.2, 1))
local ra = part("RightUpperArm", V3.new(1, 1.2, 1))
local acc = I.new("Accessory"); acc.Parent = char
local hair = I.new("MeshPart"); hair.Name = "Handle"; hair.Parent = acc
-- bones (random orientations, like an import), placed so the layout's HeadCenter sits on the head
local hc = layout.HeadCenter or V3.zero
local seed = 4242
local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local world = {}
local function addBone(name, parentInst, parentName)
	local b = I.new("Bone"); b.Name = name; b.Parent = parentInst
	local w = CF.new(layout.Bones[name]) * CF.fromAxisAngle(V3.new(rand() - .5, rand() - .5, rand() - .5).Unit, rand() * 6)
	b.CFrame = (parentName and world[parentName] or CF.identity):Inverse() * w
	world[name] = w
end
addBone("HairRoot", hair, nil)
for _, c in layout.Chains do
	local pn = "HairRoot"
	local all = table.clone(c.Bones); table.insert(all, c.Tip)
	for _, bn in all do addBone(bn, hair:FindFirstChild(pn, true), pn); pn = bn end
end
local sim = assert(HP.Sim.new(hair, layout, settings))

-- motion: stand, walk, abrupt stop, jump in place, quick 180 spin, stand
local HEAD_Y = 4.5
local function pose(t)
	local z, y, yaw, swing = 0, 0, 0, 0
	if t > 2 then
		local tw = math.min(t, 4) - 2
		z = -16 * tw
		if t < 4 then swing = math.sin(tw * 8) * 0.6; y = math.abs(math.sin(tw * 8)) * 0.08 end
	end
	if t > 6 and t < 6.51 then local tj = t - 6; y += 50 * tj - 0.5 * 196.2 * tj * tj end
	if t > 8 and t < 8.3 then yaw = math.pi * (t - 8) / 0.3 elseif t >= 8.3 then yaw = math.pi end
	return CF.new(0, y, z) * CF.Angles(0, yaw, 0), swing
end
local function place(t)
	local root, swing = pose(t)
	head.CFrame = root * CF.new(0, HEAD_Y, 0)
	ut.CFrame = root * CF.new(0, HEAD_Y - 0.65 - 0.8, 0)
	la.CFrame = root * CF.new(-1.5, HEAD_Y - 0.65, 0) * CF.Angles(swing, 0, 0) * CF.new(0, -0.6, 0)
	ra.CFrame = root * CF.new(1.5, HEAD_Y - 0.65, 0) * CF.Angles(-swing, 0, 0) * CF.new(0, -0.6, 0)
	if jitter > 0 then
		head.CFrame = head.CFrame + V3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (2 * jitter)
	end
	hair.CFrame = head.CFrame * CF.new(-hc)
end

local dt = 1 / 60
local events = { { name = "stop", t0 = 4.0, t1 = 6.0 }, { name = "land", t0 = 6.51, t1 = 8.0 }, { name = "spin", t0 = 8.3, t1 = 10.5 } }
local series = {} -- [chainName] = { {t, localTip} }
local frames = {}
local strain, bend, bodyPen = 0, 0, 0
local shiver, shiverN, lastTips = 0, 0, {}
local t = 0
while t < 10.5 do
	t += dt
	place(t)
	sim:Update(dt, nil)
	local hcf = hair.CFrame
	local alpha = sim.Accum / (1 / 60)
	local R = {}
	for _, ch in sim.Chains do
		local r = {}
		for k = 1, ch.N + 1 do r[k] = ch.LocalPrev[k]:Lerp(ch.LocalCur[k], alpha) end -- part space
		R[ch.Name] = r
		if t > 0.5 and t < 2 and lastTips[ch.Name] then
			shiver += (r[ch.N + 1] - lastTips[ch.Name]).Magnitude / dt
			shiverN += 1
		end
		lastTips[ch.Name] = r[ch.N + 1]
		series[ch.Name] = series[ch.Name] or {}
		table.insert(series[ch.Name], { t, r[ch.N + 1] })
		-- joint bend relative to modeled bend (big bends = squashed-looking mesh)
		for k = 2, ch.N do
			local a, b = (r[k] - r[k - 1]).Unit, (r[k + 1] - r[k]).Unit
			local a0, b0 = ch.RestDir[k - 1], ch.RestDir[k]
			local cur = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
			local rest = math.deg(math.acos(math.clamp(a0:Dot(b0), -1, 1)))
			bend = math.max(bend, math.abs(cur - rest))
		end
	end
	-- sheet strain between neighbouring back strands (a squishing / stretching mesh between them)
	local order = { "BackL2", "BackL1", "BackC", "BackR1", "BackR2" }
	for i = 1, #order - 1 do
		local A, B = sim.Chains, nil
		local ca, cb
		for _, ch in sim.Chains do if ch.Name == order[i] then ca = ch elseif ch.Name == order[i + 1] then cb = ch end end
		if ca and cb then
			for k = 2, math.min(ca.N, cb.N) + 1 do
				local d0 = (ca.J[k] - cb.J[k]).Magnitude
				local d = (R[ca.Name][k] - R[cb.Name][k]).Magnitude
				strain = math.max(strain, math.abs(d / d0 - 1))
			end
		end
	end
	if dumpPath and math.floor(t * 60 + 0.5) % 2 == 0 then
		local row = { t = t, chains = {} }
		for _, ch in sim.Chains do
			local pts = {}
			for k = 1, ch.N + 1 do local p = R[ch.Name][k] + hc; table.insert(pts, { p.X, p.Y, p.Z }) end
			table.insert(row.chains, pts)
		end
		table.insert(frames, row)
	end
end

-- wobble analysis per event: how long until still, how many back-and-forth swings, how far it swung
local report = {}
for _, ev in events do
	local worstSettle, worstSwings, worstPeak = 0, 0, 0
	for name, s in series do
		local final = s[#s][2]
		local pts = {}
		for _, e in s do if e[1] >= ev.t0 and e[1] <= ev.t1 then table.insert(pts, e) end end
		local finalEv = pts[#pts][2]
		local settle, peak, swings = 0, 0, 0
		local dir, lastSign = nil, 0
		for i, e in pts do
			local d = e[2] - finalEv
			peak = math.max(peak, d.Magnitude)
			if d.Magnitude > 0.03 then settle = e[1] - ev.t0 end
			if i > 1 then
				local v = e[2] - pts[i - 1][2]
				if v.Magnitude > 0.002 then
					dir = dir or v.Unit
					local sgn = v:Dot(dir) > 0 and 1 or -1
					if lastSign ~= 0 and sgn ~= lastSign then swings += 1 end
					lastSign = sgn
				end
			end
		end
		worstSettle = math.max(worstSettle, settle)
		worstSwings = math.max(worstSwings, swings)
		worstPeak = math.max(worstPeak, peak)
	end
	report[ev.name] = ("settle %.2fs, swings %d, peak %.2f studs"):format(worstSettle, worstSwings, worstPeak)
end
print(preset, serde.encode("json", { stop = report.stop, land = report.land, spin = report.spin, sheetStrain = math.floor(strain * 1000) / 1000, standingShiver = math.floor(shiver / math.max(shiverN, 1) * 1000) / 1000, maxJointBend = math.floor(bend * 10) / 10 }, false))
if dumpPath then fs.writeFile(dumpPath, serde.encode("json", frames, false)) end
