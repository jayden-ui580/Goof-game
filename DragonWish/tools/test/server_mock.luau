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
bodyPart("LeftHand", V3.new(1, 0.387, 1), CF.new(-1.5, 2.1935, 0), true).Color = roblox.Color3.fromRGB(240, 200, 160)
bodyPart("RightHand", V3.new(1, 0.387, 1), CF.new(1.5, 2.1935, 0), true).Color = roblox.Color3.fromRGB(240, 200, 160)
local ownHat = I.new("Accessory"); ownHat.Name = "RigOwnScouter"; ownHat.Parent = base
base.Parent = RS

-- fake imported pieces: re-centred meshes, bones at random angles, somewhere else in the world.
-- The hairs are .glb imports that bring their texture; an old untextured copy of the SSJ hair
-- is left lying in the folder first (the textured one must win).
local info = serde.decode("json", fs.readFile("tools/rig/riginfo.json"))
local parts = I.new("Folder"); parts.Name = "CharacterParts"; parts.Parent = SS
local seed = 3
local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local function makeImport(h, texture)
	local model = I.new("Model"); model.Name = h.name .. "_Rigged"; model.Parent = parts
	local mp = I.new("MeshPart"); mp.Name = h.name; mp.Parent = model
	mp.TextureID = texture or "" -- (always readable in Roblox; Lune needs it set)
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
for _, h in info do
	if h.name == "SSJHair" then makeImport(h, nil) end -- the old .fbx import, no texture
end
for _, h in info do
	makeImport(h, h.name:match("Hair$") and ("rbxassetid://" .. #h.name) or nil)
end

-- engine stubs the scripts need
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end
local playersStub = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end, RespawnTime = 5 }
local clock = 0
local heartbeat = signal()
local remote = { Name = "PowerUp", OnServerEvent = signal() }
local tags = {}
local CS = { AddTag = function(_, inst, tag) inst:AddTag(tag) end, HasTag = function(_, inst, tag) return inst:HasTag(tag) end }
-- (more engine pieces Lune doesn't have)
roblox.implementMethod("Workspace", "GetServerTimeNow", function() return clock end)
roblox.implementMethod("Workspace", "Raycast", function() return nil end)
local function pivotPart(m) return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") end
roblox.implementMethod("Model", "GetPivot", function(m) return pivotPart(m).CFrame end)
roblox.implementMethod("Model", "PivotTo", function(m, cf)
	local delta = cf * pivotPart(m).CFrame:Inverse()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end
end)
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
modules.PowerConfig.NextBurstTime = 0.3
modules.PowerConfig.SSJCalmAfter = 0.3 -- (20 s in the game)
modules.PowerConfig.SSJCalmTime = 0.3
modules.PowerConfig.KaiokenExhaustTime = 0.3 -- (4 s in the game)
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
	print(("%-12s on %-10s bones %3d  size x%.3f  worst placement error %.5f  visible %s  tagged %s  preset %s%s"):format(
		h.name, attach.Name, #(function() local t = {} for k in h.bones do table.insert(t, k) end return t end)(), mesh:GetAttribute("FitScale"), worst,
		tostring(mesh.Transparency < 1), tostring(mesh:HasTag("HairPhysics")), tostring(mesh:GetAttribute("HairPreset")),
		mesh:GetAttribute("FingerHand") and ("  fingers on " .. mesh:GetAttribute("FingerHand") .. ", hand colour " .. tostring(mesh.Color == attach.Color)) or ""))
end
local seen, dupes = {}, {}
for _, d in sc:GetDescendants() do
	if d:IsA("Bone") then
		if seen[d.Name] then table.insert(dupes, d.Name) end
		seen[d.Name] = true
	end
end
print("every bone name in the character is unique:", #dupes == 0, #dupes > 0 and table.concat(dupes, ", ") or "")
local function hidden(model, name) local m = model:FindFirstChild("DW_" .. name); return m and m[name].Transparency >= 1 end
local function pass(what, ok) print((ok and "PASS  " or "FAIL  ") .. what) end
pass("the SSJ2 and SSJ3 hair are put on hidden (base hair shown)", hidden(sc, "SSJ2Hair") and hidden(sc, "SSJ3Hair") and not hidden(sc, "BaseHair"))
pass("the textured SSJ hair (.glb) is picked over an old untextured copy", sc.DW_SSJHair.SSJHair.TextureID == "rbxassetid://7")
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
	local ssj23 = char.DW_SSJ2Hair.SSJ2Hair.Transparency + char.DW_SSJ3Hair.SSJ3Hair.Transparency
	print(("%-28s state %-9s form %-4s charge %.2f wind %.2f breeze %.2f ki %3d walk %2d | base hair %s, SSJ hair %s, SSJ2/3 %s"):format(
		tag, char:GetAttribute("PowerState"), char:GetAttribute("Form"), char:GetAttribute("Charge"), char:GetAttribute("AuraWind"),
		char:GetAttribute("Breeze") or -1, char:GetAttribute("Ki") or -1,
		h2.WalkSpeed, base_ < 1 and "shown" or "hidden", ssj < 1 and "shown" or "hidden", ssj23 >= 2 and "hidden" or "SHOWN"))
end
show("spawned")
send("Start"); show("pressed R")
clock += 0.1; send("Charge", 0.9); show("cheat: jumped to 0.9")
for i = 1, 30 do clock += 0.1; send("Charge", math.min(1, i * 0.04)) end
show("tapped for 3 s")
send("Transform"); show("full -> transform")
task.wait(0.4); heartbeat:Fire(0.016); show("after the burst")
pass("as a Super Saiyan only the SSJ hair shows (SSJ2 / SSJ3 stay hidden)", hidden(char, "BaseHair") and not hidden(char, "SSJHair")
	and hidden(char, "SSJ2Hair") and hidden(char, "SSJ3Hair"))
local glowing = char:GetAttribute("Breeze") == 1 and char:GetAttribute("AuraWind") > 0
task.wait(0.8); heartbeat:Fire(0.016); show("calmed down (20 s in game)")
print("SSJ glow on after transforming, then the hair and aura calm down:",
	glowing and char:GetAttribute("Breeze") == 0 and char:GetAttribute("AuraWind") == 0)
local function goHigher(tag)
	send("Start"); clock += 0.1
	for i = 1, 30 do clock += 0.1; send("Charge", math.min(1, i * 0.04)) end
	send("Transform"); show(tag)
	task.wait(0.4); heartbeat:Fire(0.016)
end
goHigher("R again: Super Saiyan 2")
pass("powering up as a Super Saiyan goes to SSJ2: only the SSJ2 hair shows", char:GetAttribute("Form") == "SSJ2"
	and hidden(char, "SSJHair") and not hidden(char, "SSJ2Hair") and hidden(char, "SSJ3Hair") and hidden(char, "BaseHair"))
goHigher("R again: Super Saiyan 3")
pass("and again goes to SSJ3: only the SSJ3 hair shows", char:GetAttribute("Form") == "SSJ3"
	and hidden(char, "SSJ2Hair") and not hidden(char, "SSJ3Hair"))
send("Start"); show("R as SSJ3 (the top: ignored)")
pass("no higher than SSJ3", char:GetAttribute("PowerState") == "Idle" and char:GetAttribute("Form") == "SSJ3")
send("PowerDown"); show("power down")
pass("powering down goes all the way back to base", char:GetAttribute("Form") == "Base" and not hidden(char, "BaseHair") and hidden(char, "SSJ3Hair"))
send("Start"); clock += 0.1; send("Charge", 0.1); send("Cancel"); show("start then cancel")
send("Start"); clock += 10; heartbeat:Fire(0.016); show("went quiet for 10 s")
char:SetAttribute("Ki", 10)
for _ = 1, 8 do heartbeat:Fire(0.25) end
print("ki refills while idle (10 -> 13 after 2 s):", char:GetAttribute("Ki"))

-- the Kaioken through the referee
print()
local function kshow(tag)
	print(("%-34s kaioken %d x%-2d ki %3d hp %5.1f walk %5.2f wind %.2f exhausted %s"):format(tag, char:GetAttribute("Kaioken") or -1,
		char:GetAttribute("KaiokenMult") or -1, char:GetAttribute("Ki") or -1, h2.Health, h2.WalkSpeed, char:GetAttribute("AuraWind") or -1,
		tostring(char:GetAttribute("Exhausted"))))
end
local function check(what, ok) print((ok and "PASS  " or "FAIL  ") .. what) end
char:SetAttribute("Ki", 100); h2.Health = 100; clock += 5
kshow("before")
send("Kaioken"); kshow("K")
check("K lights it: x2, one ki pip spent, faster legs, hair lifted",
	char:GetAttribute("Kaioken") == 1 and char:GetAttribute("KaiokenMult") == 2 and char:GetAttribute("Ki") == 80
	and math.abs(h2.WalkSpeed - 16 * 1.15) < 1e-3 and char:GetAttribute("AuraWind") > 0)
send("Kaioken"); kshow("K again at once")
check("a second K straight away is too soon", char:GetAttribute("Kaioken") == 1)
clock += 0.7; send("Kaioken"); kshow("K after 0.7 s")
check("then it climbs to x3", char:GetAttribute("Kaioken") == 2 and char:GetAttribute("KaiokenMult") == 3)
local hp0, ki0 = h2.Health, char:GetAttribute("Ki")
for _ = 1, 60 do heartbeat:Fire(1 / 60) end
kshow("1 s at x3")
check("the strain eats 2.5 health a second at x3, and ki doesn't refill",
	math.abs((hp0 - h2.Health) - 2.5) < 0.05 and char:GetAttribute("Ki") == ki0)
send("Start"); kshow("R to power up")
check("can't start powering up in Kaioken", char:GetAttribute("PowerState") == "Idle")
send("PowerDown"); kshow("R: let it go")
check("R lets it go: speed and hair back to normal", char:GetAttribute("Kaioken") == 0 and h2.WalkSpeed == 16 and char:GetAttribute("AuraWind") == 0)
char:SetAttribute("Ki", 100); h2.Health = 100
for _ = 1, 5 do clock += 0.7; send("Kaioken") end
kshow("pushed to x20")
check("five presses reach x20 and spend all five pips", char:GetAttribute("KaiokenMult") == 20 and char:GetAttribute("Ki") == 0)
for _ = 1, 60 * 8 do heartbeat:Fire(1 / 60) end
kshow("8 s at x20")
check("the body gives out at 10 health: Kaioken off, exhausted, slow",
	char:GetAttribute("Kaioken") == 0 and char:GetAttribute("Exhausted") == true and math.abs(h2.Health - 10) < 0.01
	and math.abs(h2.WalkSpeed - 16 * 0.55) < 1e-3)
char:SetAttribute("Ki", 100); clock += 1
send("Kaioken"); send("Start"); kshow("K and R while exhausted")
check("no Kaioken and no powering up while exhausted", char:GetAttribute("Kaioken") == 0 and char:GetAttribute("PowerState") == "Idle")
task.wait(0.4); heartbeat:Fire(0.016); kshow("rested")
check("after resting: not exhausted, normal speed", char:GetAttribute("Exhausted") == false and h2.WalkSpeed == 16)
char:SetAttribute("Ki", 10); clock += 1; send("Kaioken"); kshow("K with 10 ki")
check("not enough ki: refused", char:GetAttribute("Kaioken") == 0)
char:SetAttribute("Ki", 100); char:SetAttribute("Form", "SSJ"); clock += 1; send("Kaioken"); kshow("K as a Super Saiyan")
check("base form only", char:GetAttribute("Kaioken") == 0)
char:SetAttribute("Form", "Base")
