local luau = require("@lune/luau"); local roblox = require("@lune/roblox"); local fs = require("@lune/fs"); local task = require("@lune/task"); local serde = require("@lune/serde")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local SRC = "src/"
local game = I.new("DataModel")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
print("services ok", Workspace, ReplicatedStorage, ServerStorage)
-- module scripts as instances (so script.Parent / WaitForChild paths work in spirit)
local warnings = {}
local env
local function loadModule(path)
	return luau.load(fs.readFile(path), { environment = env })()
end
local modules = {}
env = {
	game = game, Vector3 = V3, CFrame = CF, Instance = I, Color3 = roblox.Color3, Enum = roblox.Enum,
	task = task, warn = function(...) table.insert(warnings, table.concat({...}, " ")); print("WARN", ...) end,
	require = function(inst) return modules[inst.Name] end,
	typeof = typeof,
}
local hp = I.new("ModuleScript"); hp.Name = "HairPhysics"; hp.Parent = ReplicatedStorage
local hc = I.new("ModuleScript"); hc.Name = "HairConfig"; hc.Parent = ReplicatedStorage
modules.HairPhysics = loadModule(SRC .. "ReplicatedStorage/HairPhysics.luau")
modules.HairConfig = loadModule(SRC .. "ReplicatedStorage/HairConfig.luau")
-- CollectionService stand-in (Lune has no engine services): tags straight onto the instance
local CS = { AddTag = function(_, inst, tag) inst:AddTag(tag) end }
local realGetService = game.GetService
env.game = setmetatable({}, { __index = function(_, k)
	if k == "GetService" then return function(_, name) if name == "CollectionService" then return CS end return game:GetService(name) end end
	return game[k]
end })

-- rigs
local function makeRig(name, x)
	local rig = I.new("Model"); rig.Name = name
	local hum = I.new("Humanoid"); hum.Parent = rig
	local head = I.new("Part"); head.Name = "Head"; head.Size = V3.new(1.2, 1.2, 1.2)
	head.CFrame = CF.new(x, 4.5, 0) * CF.Angles(0, math.rad(37), 0); head.Parent = rig
	rig.Parent = Workspace
	return rig, head
end
local rigP, headP = makeRig("MrPigtails", 0)
local rigL, headL = makeRig("MrLady", 10)

-- fake imported hair models: MeshPart somewhere random, bones re-centred + randomly rotated
local info = serde.decode("json", fs.readFile("tools/rig/riginfo.json"))
local folder = I.new("Folder"); folder.Name = "HairModels"; folder.Parent = ServerStorage
local seed = 99
local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for _, h in info do
	local model = I.new("Model"); model.Name = h.name .. "_Rigged"; model.Parent = folder
	local mp = I.new("MeshPart"); mp.Name = h.name; mp.Parent = model
	mp.CFrame = CF.new(50, 3, -20)
	local centre = V3.new(h.center[1], h.center[2], h.center[3]) -- importer centres the mesh
	local junk = I.new("Folder"); junk.Name = "InitialPoses"; junk.Parent = model
	local junk2 = I.new("Attachment"); junk2.Name = "NotABone"; junk2.Parent = mp
	local world = {}
	local function add(name, parentInst, parentName)
		local b = I.new("Bone"); b.Name = name; b.Parent = parentInst
		local p = h.bones[name]
		local w = CF.new(V3.new(p[1], p[2], p[3]) - centre) * CF.fromAxisAngle(V3.new(rand()-0.5, rand()-0.5, rand()-0.5).Unit, rand() * 6)
		b.CFrame = (parentName and world[parentName] or CF.identity):Inverse() * w
		world[name] = w
		return b
	end
	local root = add("HairRoot", mp, nil)
	for _, c in h.chains do
		local parent, pn = root, "HairRoot"
		for _, bn in c.bones do parent = add(bn, parent, pn); pn = bn end
	end
end

-- run the applier (it spawns a task per rig)
local flat = { print = print }
for k, v in env do flat[k] = v end
local applierSrc = fs.readFile(SRC .. "ServerScriptService/HairApplier.server.luau"):gsub(":WaitForChild%(", ":FindFirstChild(")
luau.load(applierSrc, { environment = flat })()
task.wait(0.2)

-- verify: every bone ends up where it was modeled relative to the head
for _, pair in { { rigP, headP, "Pigtails" }, { rigL, headL, "LadyHair" } } do
	local rig, head, preset = pair[1], pair[2], pair[3]
	local acc = rig:FindFirstChild(preset .. "Hair")
	assert(acc, "no accessory on " .. rig.Name)
	local handle = acc:FindFirstChild("Handle")
	local weld = handle:FindFirstChild("AccessoryWeld")
	assert(weld, "no weld")
	local handleCF = weld.Part0.CFrame * weld.C0 -- where the weld puts the hair
	local worst, n = 0, 0
	for name, p in modules.HairConfig.Layouts[preset].Bones do
		local bone = handle:FindFirstChild(name, true)
		local ps = modules.HairPhysics.PartSpaceCFrame(bone, handle)
		local got = handleCF * ps.Position
		local want = head.CFrame * p
		worst = math.max(worst, (got - want).Magnitude); n += 1
	end
	local leftovers = {}
	for _, d in handle:GetDescendants() do if not d:IsA("Bone") then table.insert(leftovers, d.ClassName .. ":" .. d.Name) end end
	print(rig.Name, "bones", n, "worst placement error", worst, "tagged", handle:HasTag("HairPhysics"), "preset", handle:GetAttribute("HairPreset"), "non-bone leftovers", table.concat(leftovers, ","), "massless", handle.Massless, "cancollide", handle.CanCollide)
end
print("warnings:", #warnings)
