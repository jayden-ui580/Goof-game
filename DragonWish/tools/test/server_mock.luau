-- Runs the real CharacterSetup + PowerUpServer scripts against a fake Base rig and fake imported
-- pieces, then plays a power-up through the server.
-- usage (from the DragonWish folder): lune run tools/test/server_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
-- Roblox's Model:GetScale / ScaleTo (missing in Lune): grows the parts and moves the bones out
roblox.implementMethod("Model", "GetScale", function(m) return m:GetAttribute("_Scale") or 1 end)
roblox.implementMethod("Model", "ScaleTo", function(m, new)
	local f = new / (m:GetAttribute("_Scale") or 1)
	m:SetAttribute("_Scale", new)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= f
		elseif d:IsA("Bone") then
			local c = d.CFrame
			d.CFrame = CF.new(c.Position * f) * c.Rotation
		end
	end
end)

local game = I.new("DataModel")
local RS, SS, SP = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage"), game:GetService("StarterPlayer")
local WS = game:GetService("Workspace")

-- a fake Base rig standing at (10, 0, 5), turned 30 degrees
local base = I.new("Model"); base.Name = "Base"
local hum = I.new("Humanoid"); hum.Parent = base
local rootCF = CF.new(10, 0, 5) * CF.Angles(0, math.rad(30), 0)
local function bodyPart(name, size, offset, mesh)
	local p = I.new(mesh and "MeshPart" or "Part"); p.Name = name; p.Size = size; p.CFrame = rootCF * offset; p.Parent = base
	return p
end
bodyPart("HumanoidRootPart", V3.new(2, 2, 1), CF.new(0, 3, 0))
local head = bodyPart("Head", V3.new(1.2, 1.2, 1.2), CF.new(0, 4.5, 0), true)
bodyPart("UpperTorso", V3.new(2, 1.6, 1), CF.new(0, 3.2, 0))
local lower = bodyPart("LowerTorso", V3.new(2, 0.4, 1), CF.new(0, 2.2, 0))
bodyPart("LeftUpperLeg", V3.new(1, 1.2, 1), CF.new(-0.5, 1.4, 0))
bodyPart("RightUpperLeg", V3.new(1, 1.2, 1), CF.new(0.5, 1.4, 0))
local ownHat = I.new("Accessory"); ownHat.Name = "RigOwnScouter"; ownHat.Parent = base
base.Parent = RS

-- fake imported pieces: re-centred meshes, bones at random angles, somewhere else in the world
local info = serde.decode("json", fs.readFile("tools/rig/riginfo.json"))
local parts = I.new("Folder"); parts.Name = "CharacterParts"; parts.Parent = SS
local seed = 3
local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for _, h in info do
	local model = I.new("Model"); model.Name = h.name .. "_Rigged"; model.Parent = parts
	local mp = I.new("MeshPart"); mp.Name = h.name; mp.Parent = model
	mp.CFrame = CF.new(-40, 7, 22)
	local junk = I.new("Folder"); junk.Name = "InitialPoses"; junk.Parent = model
	local world = {}
	local function add(name, parentInst, parentName)
		local b = I.new("Bone"); b.Name = name; b.Parent = parentInst
		local p = h.bones[name]
		local w = CF.new(V3.new(p[1], p[2], p[3]) - V3.new(0.3, -0.2, 0.1)) * CF.fromAxisAngle(V3.new(rand() - .5, rand() - .5, rand() - .5).Unit, rand() * 6)
		b.CFrame = (parentName and world[parentName] or CF.identity):Inverse() * w
		world[name] = w
	end
	add(h.root, mp, nil)
	for _, c in h.chains do
		local pn = h.root
		for _, bn in c.bones do add(bn, mp:FindFirstChild(pn, true), pn); pn = bn end
	end
end

-- engine stubs the scripts need
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end
local playersStub = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local heartbeat = signal()
local remote = { Name = "PowerUp", OnServerEvent = signal() }
local tags = {}
local CS = { AddTag = function(_, inst, tag) inst:AddTag(tag) end }
local clock = 0
local function load(path, extra)
	local env = {
		Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, task = task, typeof = typeof,
		print = print, warn = function(...) print("WARN", ...) end,
		os = { clock = function() return clock end },
	}
	for k, v in extra or {} do env[k] = v end
	local src = fs.readFile(path):gsub(":WaitForChild%(", ":FindFirstChild(")
	return luau.load(src, { environment = env })()
end
local modules = {}
local mods = { Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum }
modules.HairPhysics = luau.load(fs.readFile("src/ReplicatedStorage/HairPhysics.luau"), { environment = mods })()
modules.HairConfig = luau.load(fs.readFile("src/ReplicatedStorage/HairConfig.luau"), { environment = mods })()
modules.PowerConfig = luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = mods })()
modules.PowerConfig.BurstTime = 0.3
modules.PowerConfig.SSJCalmAfter = 0.3 -- (20 s in the game)
modules.PowerConfig.SSJCalmTime = 0.3
for _, n in { "HairPhysics", "HairConfig", "PowerConfig" } do local m = I.new("ModuleScript"); m.Name = n; m.Parent = RS end
local fakeGame = { GetService = function(_, n)
	if n == "Players" then return playersStub end
	if n == "CollectionService" then return CS end
	if n == "RunService" then return { Heartbeat = heartbeat } end
	return game:GetService(n)
end }
local instanceStub = { new = function(cls) if cls == "RemoteEvent" then return remote end return I.new(cls) end }
local extra = { game = fakeGame, require = function(m) return modules[m.Name] end, Instance = instanceStub }

load("src/ServerScriptService/CharacterSetup.server.luau", extra)
task.wait(0.05)

local sc = SP:FindFirstChild("StarterCharacter")
assert(sc, "no StarterCharacter")
print("StarterCharacter children:", (function() local t = {} for _, c in sc:GetChildren() do table.insert(t, c.Name) end table.sort(t) return table.concat(t, ", ") end)())
local schead, sclower = sc:FindFirstChild("Head"), sc:FindFirstChild("LowerTorso")
for _, h in info do
	local holder = sc:FindFirstChild("DW_" .. h.name)
	local mesh = holder:FindFirstChild(h.name)
	local weld = mesh:FindFirstChild("DWWeld")
	local attach = weld.Part0
	local meshCF = attach.CFrame * weld.C0
	local worst = 0
	for name, p in h.bones do
		local bone = mesh:FindFirstChild(name, true)
		local got = meshCF * modules.HairPhysics.PartSpaceCFrame(bone, mesh).Position
		local cfg = modules.HairConfig.Hairs[h.name]
		local want = attach.CFrame * cfg.Offset * (V3.new(p[1], p[2], p[3]) * mesh:GetAttribute("FitScale"))
		worst = math.max(worst, (got - want).Magnitude)
	end
	print(("%-8s on %-10s bones %3d  size x%.3f  worst placement error %.5f  visible %s  tagged %s  preset %s"):format(
		h.name, attach.Name, #(function() local t = {} for k in h.bones do table.insert(t, k) end return t end)(), mesh:GetAttribute("FitScale"), worst,
		tostring(mesh.Transparency < 1), tostring(mesh:HasTag("HairPhysics")), tostring(mesh:GetAttribute("HairPreset"))))
end
local seen, dupes = {}, {}
for _, d in sc:GetDescendants() do
	if d:IsA("Bone") then
		if seen[d.Name] then table.insert(dupes, d.Name) end
		seen[d.Name] = true
	end
end
print("every bone name in the character is unique:", #dupes == 0, #dupes > 0 and table.concat(dupes, ", ") or "")
print("rig's own accessory kept and marked:", sc:FindFirstChild("RigOwnScouter") and sc.RigOwnScouter:GetAttribute("DWOwned"))

-- power-up through the referee
load("src/ServerScriptService/PowerUpServer.server.luau", extra)
local char = sc:Clone()
char.Name = "PlayerOne"; char.Parent = WS
local h2 = char:FindFirstChildOfClass("Humanoid")
h2.WalkSpeed = 16; h2.JumpPower = 50; h2.Health = 100
local fakePlayer = { Character = char }
playersStub.GetPlayers = function() return { fakePlayer } end
local function send(...) remote.OnServerEvent:Fire(fakePlayer, ...) end
local function show(tag)
	local base_ = char.DW_BaseHair.BaseHair.Transparency
	local ssj = char.DW_SSJHair.SSJHair.Transparency
	print(("%-28s state %-9s form %-4s charge %.2f wind %.2f breeze %.2f ki %3d walk %2d | base hair %s, SSJ hair %s"):format(
		tag, char:GetAttribute("PowerState"), char:GetAttribute("Form"), char:GetAttribute("Charge"), char:GetAttribute("AuraWind"),
		char:GetAttribute("Breeze") or -1, char:GetAttribute("Ki") or -1,
		h2.WalkSpeed, base_ < 1 and "shown" or "hidden", ssj < 1 and "shown" or "hidden"))
end
show("spawned")
send("Start"); show("pressed R")
clock += 0.1; send("Charge", 0.9); show("cheat: jumped to 0.9")
for i = 1, 30 do clock += 0.1; send("Charge", math.min(1, i * 0.04)) end
show("tapped for 3 s")
send("Transform"); show("full -> transform")
task.wait(0.4); heartbeat:Fire(0.016); show("after the burst")
local glowing = char:GetAttribute("Breeze") == 1 and char:GetAttribute("AuraWind") > 0
task.wait(0.8); heartbeat:Fire(0.016); show("calmed down (20 s in game)")
print("SSJ glow on after transforming, then the hair and aura calm down:",
	glowing and char:GetAttribute("Breeze") == 0 and char:GetAttribute("AuraWind") == 0)
send("Start"); show("R as Super Saiyan (ignored)")
send("PowerDown"); show("power down")
send("Start"); clock += 0.1; send("Charge", 0.1); send("Cancel"); show("start then cancel")
send("Start"); clock += 10; heartbeat:Fire(0.016); show("went quiet for 10 s")
char:SetAttribute("Ki", 10)
for _ = 1, 8 do heartbeat:Fire(0.25) end
print("ki refills while idle (10 -> 13 after 2 s):", char:GetAttribute("Ki"))
