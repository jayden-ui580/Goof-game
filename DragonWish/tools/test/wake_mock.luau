-- The Super Saiyan hair starts hidden (asleep) and is shown when you transform. This runs the
-- real HairPhysics through exactly that: hidden for a second, shown, then a jump, and checks the
-- hair's bones actually move.
-- usage (from the DragonWish folder): lune run tools/test/wake_mock.luau [preset]
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local env = { Vector3 = V3, CFrame = CF, Instance = I, Color3 = roblox.Color3, Enum = roblox.Enum, warn = print }
local HP = luau.load(fs.readFile("src/ReplicatedStorage/HairPhysics.luau"), { environment = env })()
local CFG = luau.load(fs.readFile("src/ReplicatedStorage/HairConfig.luau"), { environment = env })()
local preset = process.args[1] or "SSJHair"
local layout, hair = CFG.Layouts[preset], CFG.Hairs[preset]

local char = I.new("Model"); I.new("Humanoid").Parent = char
local function part(name, size, cf) local p = I.new("Part"); p.Name = name; p.Size = size; p.CFrame = cf; p.Parent = char; return p end
local head = part("Head", V3.new(1.2, 1.2, 1.2), CF.new(0, 4.5, 0))
local ut = part("UpperTorso", V3.new(2, 1.6, 1), CF.new(0, 3.2, 0))
local holder = I.new("Model"); holder.Name = "DW_" .. preset; holder.Parent = char
local mesh = I.new("MeshPart"); mesh.Name = preset; mesh.Parent = holder
mesh.CFrame = head.CFrame * hair.Offset
local world = {}
local function addBone(name, parentInst, parentName)
	local b = I.new("Bone"); b.Name = name; b.Transform = CF.identity; b.Parent = parentInst
	local w = CF.new(layout.Bones[name])
	b.CFrame = (parentName and world[parentName] or CF.identity):Inverse() * w
	world[name] = w
end
local inChain = {}
for _, c in layout.Chains do for _, b in c.Bones do inChain[b] = true end inChain[c.Tip] = true end
local root
for name in layout.Bones do if not inChain[name] then root = name end end
addBone(root, mesh, nil)
for _, c in layout.Chains do
	local pn = root
	local all = table.clone(c.Bones); table.insert(all, c.Tip)
	for _, bn in all do addBone(bn, mesh:FindFirstChild(pn, true), pn); pn = bn end
end
mesh.Transparency = hair.VisibleIn == "SSJ" and 1 or 0
local sim = assert(HP.Sim.new(mesh, layout, HP.mergeSettings(hair.Physics)))
print("problems:", #sim.Problems > 0 and table.concat(sim.Problems, ", ") or "none")

local function boneTurn()
	local most = 0
	for _, ch in sim.Chains do
		for _, b in ch.Bones do
			local _, angle = b.Transform:ToAxisAngle()
			most = math.max(most, math.deg(math.abs(angle)))
		end
	end
	return most
end
local t, dt = 0, 1 / 60
local function run(seconds, label)
	local most = 0
	local stop = t + seconds
	while t < stop do
		t += dt
		local y = 0
		if label == "jump" then local u = t - 2; y = 20 * u - 50 * u * u; if y < 0 then y = 0 end end
		head.CFrame = CF.new(0, 4.5 + y, 0); ut.CFrame = CF.new(0, 3.2 + y, 0)
		mesh.CFrame = head.CFrame * hair.Offset
		sim:Update(dt, nil)
		most = math.max(most, boneTurn())
	end
	print(("%-28s awake %-5s  most a bone turned: %5.1f deg"):format(label, tostring(sim.Awake), most))
end
run(1, "hidden (base form)")
char:SetAttribute("AuraWind", 1)
mesh.Transparency = 0
run(1, "shown (bursting)")
char:SetAttribute("AuraWind", 0.12)
run(0.01, "jump")
run(1, "jump")
