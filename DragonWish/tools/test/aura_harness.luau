-- Runs the real HairPhysics solver with the real HairConfig on a fake R15 body through a
-- power-up (rest, aura ramp, full power, calm Super Saiyan, power down), then walking,
-- stopping and jumping, and reports how the tips of the hair moved (angles in degrees, seen
-- from each strand's root; X/Y in studs, X < 0 = towards the wearer's left).
-- usage (from the DragonWish folder): lune run tools/test/aura_harness.luau <preset> [overridesJson] [dump]
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
local ov = process.args[2] and process.args[2] ~= "" and serde.decode("json", process.args[2]) or {}
local dumpPath = process.args[3]
local layout = CFG.Layouts[preset]
local phys = table.clone(CFG.Hairs[preset].Physics)
for k, v in ov do
	if k == "LocalWind" or k == "Wind" then v = V3.new(v[1], v[2], v[3]) end
	if k ~= "_calm" then phys[k] = v end
end
local settings = HP.mergeSettings(phys)

local char = I.new("Model"); I.new("Humanoid").Parent = char
local function part(name, size) local p = I.new("Part"); p.Name = name; p.Size = size; p.Parent = char; return p end
local parts = {
	Head = { part("Head", V3.new(1.2, 1.2, 1.2)), CF.new(0, 4.5, 0) },
	UpperTorso = { part("UpperTorso", V3.new(2, 1.6, 1)), CF.new(0, 3.2, 0) },
	LowerTorso = { part("LowerTorso", V3.new(2, 0.4, 1)), CF.new(0, 2.2, 0) },
	LeftUpperLeg = { part("LeftUpperLeg", V3.new(1, 1.2, 1)), CF.new(-0.5, 1.4, 0) },
	RightUpperLeg = { part("RightUpperLeg", V3.new(1, 1.2, 1)), CF.new(0.5, 1.4, 0) },
	LeftLowerLeg = { part("LeftLowerLeg", V3.new(1, 1.2, 1)), CF.new(-0.5, 0.5, 0) },
	RightLowerLeg = { part("RightLowerLeg", V3.new(1, 1.2, 1)), CF.new(0.5, 0.5, 0) },
}
local holder = I.new("Model"); holder.Name = "DW_" .. preset; holder.Parent = char
local mesh = I.new("MeshPart"); mesh.Name = preset; mesh.Parent = holder
local seed = 99
local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local world = {}
local rootName = layout.Chains[1] and nil
local function addBone(name, parentInst, parentName)
	local b = I.new("Bone"); b.Name = name; b.Parent = parentInst
	local w = CF.new(layout.Bones[name]) * CF.fromAxisAngle(V3.new(rand() - .5, rand() - .5, rand() - .5).Unit, rand() * 6)
	b.CFrame = (parentName and world[parentName] or CF.identity):Inverse() * w
	world[name] = w
end
local root = layout.Bones.HairRoot and "HairRoot" or "BeltRoot"
addBone(root, mesh, nil)
for _, c in layout.Chains do
	local pn = root
	local all = table.clone(c.Bones); table.insert(all, c.Tip)
	for _, bn in all do addBone(bn, mesh:FindFirstChild(pn, true), pn); pn = bn end
end
local sim = assert(HP.Sim.new(mesh, layout, settings))

local PowerConfig = luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = env })()
local CALM = ov._calm or PowerConfig.SSJCalmWind

-- script: 0-2 rest | 2-4 aura 0->0.5 | 4-7 aura 1 | 7-11 calm Super Saiyan | 11-13 aura 0
--         13-14.5 walk | 14.5-16.5 stopped | 16.5-17.3 jump | 17.3-19 landed
local function auraAt(t)
	if t < 2 then return 0 elseif t < 4 then return 0.25 * (t - 2) elseif t < 7 then return 1 elseif t < 11 then return CALM end
	return 0
end
local function rootAt(t)
	local z, y = 0, 0
	if t > 13 then z = -16 * (math.min(t, 14.5) - 13) end
	if t > 16.5 and t < 17.3 then local u = t - 16.5; y = 20 * u - 50 * u * u end
	return CF.new(0, y, z)
end
local attach = parts[layout.Attach][1]
local dt = 1 / 60
local t = 0
local modeled = {}
for ci, ch in sim.Chains do modeled[ci] = ch.J[ch.N + 1] - ch.J[1] end
local function angle(a, b) return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))) end
local rest
local acc = {}
local function add(key, v) acc[key] = acc[key] or { sum = 0, n = 0, max = -math.huge }; local a = acc[key]; a.sum += v; a.n += 1; a.max = math.max(a.max, v) end
local lastTips
local nan, pen, frames = false, 0, {}
while t < 19 do
	t += dt
	local rootCF = rootAt(t)
	for _, pr in parts do pr[1].CFrame = rootCF * pr[2] end
	mesh.CFrame = attach.CFrame
	char:SetAttribute("AuraWind", auraAt(t))
	sim:Update(dt, nil)
	local alpha = sim.Accum / (1 / 60)
	local tips = {}
	for ci, ch in sim.Chains do
		local p = ch.LocalPrev[ch.N + 1]:Lerp(ch.LocalCur[ch.N + 1], alpha) - ch.J[1]
		tips[ci] = p
		if p.X ~= p.X then nan = true end
		for k = 1, ch.N + 1 do
			for cj, col in sim.Colliders do
				local r = ch.BodyRadius[k] and ch.BodyRadius[k][cj]
				if r then pen = math.max(pen, r - HP.colliderDistance(col, ch.Pos[k])) end
			end
		end
	end
	if t > 1.9 and not rest then rest = tips end
	local function mean(f) local sum = 0 for ci, p in tips do sum += f(ci, p) end return sum / #tips end
	if t > 1.6 and t < 2 then
		add("droop_deg", mean(function(ci, p) return angle(p, modeled[ci]) end))
		add("droop_y", mean(function(ci, p) return p.Y - modeled[ci].Y end))
		add("rest_x", mean(function(ci, p) return p.X - modeled[ci].X end))
	end
	if rest then
		local devDeg = mean(function(ci, p) return angle(p, rest[ci]) end)
		local speed = lastTips and mean(function(ci, p) return (p - lastTips[ci]).Magnitude / dt end) or 0
		if t > 5.5 and t < 7 then add("full_lift_y", mean(function(ci, p) return p.Y - rest[ci].Y end)); add("full_flutter", speed) end
		if t > 8.5 and t < 11 then
			add("calm_deg", devDeg)
			add("calm_x", mean(function(ci, p) return p.X - modeled[ci].X end))
			add("calm_vs_model_deg", mean(function(ci, p) return angle(p, modeled[ci]) end))
			add("calm_flutter", speed)
		end
		if t > 12.5 and t < 13 then add("off_deg", devDeg) end
		if t > 13 and t < 14.5 then add("walk_deg", devDeg) end
		if t > 14.5 and t < 15.5 then add("stop_deg", devDeg); add("stop_wobble", speed) end
		if t > 16 and t < 16.5 then add("still_deg", devDeg) end
		if t > 16.5 and t < 18 then add("jump_deg", devDeg) end
	end
	lastTips = tips
	if dumpPath and math.floor(t * 60 + 0.5) % 6 == 0 then
		local row = { t = t, chains = {} }
		for ci, ch in sim.Chains do
			local pts = {}
			for k = 1, ch.N + 1 do local p = ch.LocalPrev[k]:Lerp(ch.LocalCur[k], alpha); table.insert(pts, { p.X, p.Y, p.Z }) end
			row.chains[ci] = pts
		end
		table.insert(frames, row)
	end
end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local line = { ("%-8s"):format(preset), ("nan %s  body pen %.3f"):format(tostring(nan), pen) }
for _, key in { "droop_deg", "droop_y", "rest_x", "walk_deg", "stop_deg", "stop_wobble", "still_deg", "jump_deg", "full_lift_y", "full_flutter", "calm_deg", "calm_vs_model_deg", "calm_x", "calm_flutter", "off_deg" } do
	local a = acc[key]
	if a then
		local useMax = key == "walk_deg" or key == "stop_deg" or key == "jump_deg"
		table.insert(line, ("%s %s"):format(key, tostring(r2(useMax and a.max or a.sum / a.n))))
	end
end
print(table.concat(line, "  "))
if dumpPath then fs.writeFile(dumpPath, serde.encode("json", frames, false)) end
