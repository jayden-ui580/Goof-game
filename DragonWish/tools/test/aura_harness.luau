-- Runs the real HairPhysics solver with the real HairConfig on a fake R15 body through a
-- power-up: rest, aura ramp, full power, calm Super Saiyan aura, power down, then walking.
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
for k, v in ov do phys[k] = v end
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

-- script: 0-2 rest | 2-4 aura 0->0.5 | 4-7 aura 1 | 7-10 calm 0.3 | 10-12 aura 0 | 12-15 walk
local function auraAt(t)
	if t < 2 then return 0 elseif t < 4 then return 0.25 * (t - 2) elseif t < 7 then return 1 elseif t < 10 then return 0.3 elseif t < 12 then return 0 end
	return 0
end
local function rootAt(t)
	local z = 0
	if t > 12 then z = -12 * (t - 12) end
	return CF.new(0, 0, z)
end
local attach = parts[layout.Attach][1]
local attachOff = parts[layout.Attach][2]
local dt = 1 / 60
local t = 0
local tipsRest
local lift = { rest = 0, half = 0, full = 0, calm = 0, off = 0 }
local flutter = { full = 0, calm = 0 }
local samples = { rest = 0, half = 0, full = 0, calm = 0, off = 0 }
local lastTips
local nan, pen, bendOver, frames = false, 0, 0, {}
while t < 15 do
	t += dt
	local rootCF = rootAt(t)
	for _, pr in parts do pr[1].CFrame = rootCF * pr[2] end
	mesh.CFrame = attach.CFrame
	char:SetAttribute("AuraWind", auraAt(t))
	sim:Update(dt, nil)
	-- tips relative to the attach part
	local tips = {}
	local alpha = sim.Accum / (1 / 60)
	for ci, ch in sim.Chains do
		local p = ch.LocalPrev[ch.N + 1]:Lerp(ch.LocalCur[ch.N + 1], alpha)
		tips[ci] = p
		if p.X ~= p.X then nan = true end
		for k = 1, ch.N + 1 do
			for cj, col in sim.Colliders do
				local r = ch.BodyRadius[k] and ch.BodyRadius[k][cj]
				if r then pen = math.max(pen, r - HP.colliderDistance(col, ch.Pos[k])) end
			end
		end
	end
	if t > 1.5 and t < 2 then tipsRest = tipsRest or tips end
	local phase = (t > 1.6 and t < 2 and "rest") or (t > 3.6 and t < 4 and "half") or (t > 5.5 and t < 7 and "full") or (t > 8.5 and t < 10 and "calm") or (t > 11.5 and t < 12 and "off") or nil
	if phase and tipsRest then
		local sumLift, sumMove = 0, 0
		for ci, p in tips do
			sumLift += p.Y - tipsRest[ci].Y
			if lastTips then sumMove += (p - lastTips[ci]).Magnitude / dt end
		end
		lift[phase] += sumLift / #tips
		if flutter[phase] then flutter[phase] += sumMove / #tips end
		samples[phase] += 1
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
local out = { nan = nan, bodyPen = math.floor(pen * 1000) / 1000 }
for k, v in lift do out["lift_" .. k] = math.floor(v / math.max(samples[k], 1) * 100) / 100 end
for k, v in flutter do out["flutter_" .. k] = math.floor(v / math.max(samples[k], 1) * 100) / 100 end
print(preset, serde.encode("json", out, false))
if dumpPath then fs.writeFile(dumpPath, serde.encode("json", frames, false)) end
