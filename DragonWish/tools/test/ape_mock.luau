-- Runs the real OozaruFX script (with the real Gait) on a fake Great Ape built from the rig
-- (tools/rig/oozaru.json, at PowerConfig's size) and checks what players would see: the roar
-- (jaw open, leaning back, head up, rings of sound, dust), dropping into the hunch, the heavy
-- walk with the feet planted, the stop, turning at a giant's pace, and your screen: black, the
-- cut in, the red tint, the UI hidden ... and everything back when you turn back.
-- usage (from the DragonWish folder): lune run tools/test/ape_mock.luau [dump.json]
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local dumpPath = process.args[1] ~= "" and process.args[1] or nil

local emitted, sounds = 0, 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, n)
	emitted += n
end)
roblox.implementMethod("Sound", "Play", function()
	sounds += 1
end)
local humState = roblox.Enum.HumanoidStateType.Running
roblox.implementMethod("Humanoid", "GetState", function()
	return humState
end)

local PowerConfig = luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = { Color3 = roblox.Color3, Enum = roblox.Enum } })()
local s = PowerConfig.OozaruScale
local rigInfo = serde.decode("json", fs.readFile("tools/rig/oozaru.json"))

-- the giant, standing on the origin facing -Z (as the server builds it)
local world = I.new("Folder")
world.Name = "Workspace"
local ape = I.new("Model")
ape.Name = "Player1"
ape:SetAttribute("Oozaru", true)
ape:SetAttribute("OozaruScale", s)
ape:SetAttribute("OozaruAt", 0)
ape:SetAttribute("OozaruUntil", 60)
ape:SetAttribute("PowerState", "Idle")
ape.Parent = world
local root = I.new("Part")
root.Name = "HumanoidRootPart"
root.Size = V3.new(4.0, 4.4, 2.6) * s
root.CFrame = CF.new(0, 4.0 * s + root.Size.Y / 2, 0)
root.Position = root.CFrame.Position
root.AssemblyLinearVelocity = V3.zero
root.Parent = ape
local hum = I.new("Humanoid")
hum.HipHeight = 4.0 * s
hum.MaxHealth = 500
hum.Health = 500
hum.WalkSpeed = 0
hum.AutoRotate = true
hum.MoveDirection = V3.zero
hum.CameraOffset = V3.zero
hum.Parent = ape
local holder = I.new("MeshPart")
holder.Name = "Fur"
holder.CFrame = CF.identity
holder.Parent = ape
local rest, bones, parentOf = {}, {}, {}
for _, b in rigInfo.bones do
	local r = b.rot
	rest[b.name] = CF.new(b.head[1] * s, b.head[2] * s, b.head[3] * s, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3])
	parentOf[b.name] = b.parent
end
for _, b in rigInfo.bones do
	local bone = I.new("Bone")
	bone.Name = b.name
	bone.CFrame = (b.parent and rest[b.parent] or CF.identity):Inverse() * rest[b.name]
	bone.Transform = CF.identity
	bones[b.name] = bone
end
for name, bone in bones do
	bone.Parent = parentOf[name] and bones[parentOf[name]] or holder
end
-- (an importer can give a mesh its own copy of part of the skeleton: here the skin has the
-- spine and head, and its bones' names carry a prefix)
local skin = I.new("MeshPart")
skin.Name = "Skin"
skin.CFrame = CF.identity
skin.Parent = ape
local copyOf = {}
for _, name in { "NULL", "WAIST", "SPINE1", "SPINE2", "SPINE3", "NECK", "HEAD", "FACE", "CHIN" } do
	local bone = I.new("Bone")
	bone.Name = "Armature:" .. name
	bone.CFrame = bones[name].CFrame
	bone.Transform = CF.identity
	bone.Parent = parentOf[name] and copyOf[parentOf[name]] or skin
	copyOf[name] = bone
end
-- where every bone really is now (rest pose plus Transforms), in the world
local function boneWorld(name)
	local chain = {}
	local node = bones[name]
	while node do
		table.insert(chain, 1, node)
		node = parentOf[node.Name] and bones[parentOf[node.Name]] or nil
	end
	local cf = holder.CFrame
	for _, b in chain do
		cf = cf * b.CFrame * b.Transform
	end
	return cf
end

-- the fake game
local T = 0
local serverTime = 0
local function signal()
	local sig = { fns = {} }
	function sig:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, f in self.fns do
			f(...)
		end
	end
	return sig
end
local preRender, preSimulation = signal(), signal()
local renderSteps = {}
local playerGui = I.new("Folder")
playerGui.Name = "PlayerGui"
local otherGui = I.new("ScreenGui")
otherGui.Name = "SomeoneElsesUI"
otherGui.Enabled = true
otherGui.Parent = playerGui
local lighting = I.new("Folder")
local attrs = {}
local player = {
	Name = "Player1",
	Character = ape,
	CameraMinZoomDistance = 0.5,
	CameraMaxZoomDistance = 128,
	WaitForChild = function(_, n)
		return n == "PlayerGui" and playerGui or nil
	end,
	SetAttribute = function(_, k, v)
		attrs[k] = v
	end,
	GetAttribute = function(_, k)
		return attrs[k]
	end,
}
local core = {}
local camera = { CFrame = CF.new(0, 30, 60), CameraType = roblox.Enum.CameraType.Custom, CameraSubject = nil }
local fxFolder = I.new("Folder")
fxFolder.Name = "FX"
local env = {
	Vector3 = V3, CFrame = CF, Vector2 = roblox.Vector2, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2,
	ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange, typeof = typeof, print = print, warn = print,
	os = { clock = function() return T end },
	task = { delay = function() end },
	Instance = { new = function(c) return I.new(c) end },
	Random = { new = function()
		local r = { s = 5 }
		function r:NextNumber(a, b)
			a = a or 0
			b = b or 1
			self.s = (self.s * 1103515245 + 12345) % 2147483648
			return a + (b - a) * self.s / 2147483648
		end
		return r
	end },
	RaycastParams = { new = function() return {} end },
}
local modules = {
	Gait = function()
		return luau.load(fs.readFile("src/ReplicatedStorage/Gait.luau"), { environment = { Vector3 = V3, CFrame = CF } })()
	end,
	PowerConfig = function()
		return PowerConfig
	end,
}
env.require = function(name)
	return modules[name]()
end
local workspaceStub = {
	CurrentCamera = camera,
	Raycast = function(_, from) return { Position = V3.new(from.X, 0, from.Z) } end,
	GetServerTimeNow = function() return serverTime end,
}
env.game = { GetService = function(_, n)
	if n == "Players" then
		return { LocalPlayer = player, GetPlayers = function() return { player } end }
	elseif n == "RunService" then
		return {
			PreRender = preRender,
			PreSimulation = preSimulation,
			BindToRenderStep = function(_, name, _, fn) renderSteps[name] = fn end,
		}
	elseif n == "Workspace" then
		return workspaceStub
	elseif n == "ReplicatedStorage" then
		return { WaitForChild = function(_, x) return x end }
	elseif n == "CollectionService" then
		return { GetTagged = function() return (ape.Parent and { ape }) or {} end }
	elseif n == "Lighting" then
		return lighting
	elseif n == "StarterGui" then
		return {
			GetCoreGuiEnabled = function(_, kind) return core[kind] ~= false end,
			SetCoreGuiEnabled = function(_, kind, on) core[kind] = on end,
		}
	end
end }
local src = fs.readFile("src/StarterPlayerScripts/OozaruFX.client.luau"):gsub("folder%.Parent = Workspace", "folder.Parent = fxScratch")
env.fxScratch = fxFolder
luau.load(src, { environment = env })()
local screen = playerGui:FindFirstChild("OozaruScreen")
local black = screen and screen:FindFirstChild("Black")
local tint = lighting:FindFirstChild("OozaruTint")

local frames = {}
local function frame(dt)
	T += dt
	serverTime += dt
	preSimulation:Fire(dt)
	-- (physics: the giant walks at its speed, the way it faces)
	local v = hum.MoveDirection.Magnitude > 0.1 and hum.MoveDirection.Unit * hum.WalkSpeed or V3.zero
	root.AssemblyLinearVelocity = v
	root.CFrame = root.CFrame + v * dt
	root.Position = root.CFrame.Position
	holder.CFrame = root.CFrame * CF.new(0, -(4.0 * s + root.Size.Y / 2), 0)
	preRender:Fire(dt)
	for _, fn in renderSteps do
		fn(dt)
	end
	local rec = { t = T, root = { root.CFrame:GetComponents() }, b = {} }
	for name, bone in bones do
		local t = bone.Transform
		local rx, ry, rz = t:ToEulerAnglesXYZ()
		rec.b[name] = { rx, ry, rz, t.Position.X / s, t.Position.Y / s, t.Position.Z / s }
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
local function count(name)
	local n = 0
	for _, c in fxFolder:GetDescendants() do
		if c.Name == name then
			n += 1
		end
	end
	return n
end
-- how far a bone is turned from rest (degrees), in the model's axes (x: + = tipped back / up)
local function anglesOf(name)
	local b = bones[name]
	local restRot = (rest[name]).Rotation
	local q = restRot * b.Transform.Rotation * restRot:Inverse() -- (back in model axes)
	local rx, ry, rz = q:ToEulerAnglesXYZ()
	return math.deg(rx), math.deg(ry), math.deg(rz)
end
local function pitchOf(name)
	return (anglesOf(name))
end

-- 1. the entrance: G pressed (the server marks you "GreatApe" and your screen goes black),
-- then the giant arrives
local person = I.new("Model")
person.Name = "Player1"
person:SetAttribute("PowerState", "GreatApe")
player.Character = person
ape.Parent = nil
for i = 1, 27 do
	frame(1 / 60)
end
local blackAt = black and black.BackgroundTransparency
player.Character = ape
ape.Parent = world
serverTime = 0
local clearAt, maxRings, jawOpen, spineBack, headUp = nil, 0, 0, -99, -99
local stillBlack = nil
for i = 1, 60 * 5 do
	frame(1 / 60)
	if serverTime > 0.1 and serverTime < 0.12 then
		stillBlack = black.BackgroundTransparency
	end
	if serverTime > 0.3 and serverTime < 0.32 then
		clearAt = black and black.BackgroundTransparency
	end
	maxRings = math.max(maxRings, count("RoarRing"))
	if T > 0.6 and T < 2.9 then
		jawOpen = math.max(jawOpen, -pitchOf("CHIN"))
		spineBack = math.max(spineBack, pitchOf("SPINE1") + pitchOf("SPINE2") + pitchOf("SPINE3"))
		headUp = math.max(headUp, (boneWorld("HEAD") * rest.HEAD.Rotation:Inverse()).LookVector.Y)
	end
end
local hunched = pitchOf("SPINE1") + pitchOf("SPINE2") + pitchOf("SPINE3")
local jawAfter = -pitchOf("CHIN")
print(("  roar: jaw open %.0f deg, spine back %.0f deg, head facing %.0f deg up, %d rings of sound at once, %d sounds"):format(
	jawOpen, spineBack, math.deg(math.asin(math.clamp(headUp, -1, 1))), maxRings, sounds))
print(("  after: spine %.0f deg (- = hunched forward), jaw %.0f deg"):format(hunched, jawAfter))
check("roaring: jaw wide open", jawOpen > 25)
check("roaring: leaning back with the head thrown up", spineBack > 10 and headUp > 0.35)
check("roaring: rings of sound and a roar", maxRings >= 3 and sounds >= 1)
check("roaring: dust blasts off the ground", emitted >= 30)
check("then the hunch: back rounded forward, mouth shut", hunched < -20 and jawAfter < 10)
check("your screen: black first, then cut straight in", (blackAt or 1) < 0.1 and (stillBlack or 1) < 0.05 and (clearAt or 0) > 0.95)
check("your screen: red tint on, UI hidden", tint and tint.Enabled and attrs.Oozaru == true and otherGui.Enabled == false)
check("the camera pulls back", player.CameraMinZoomDistance >= 10 * s)
check("the camera follows the giant (Roblox doesn't when a body is swapped)", camera.CameraSubject == hum)
local headA, headB = bones.HEAD.Transform, copyOf.HEAD.Transform
check("every copy of the skeleton gets the same pose", (headA.Position - headB.Position).Magnitude < 1e-5
	and headA.LookVector:Dot(headB.LookVector) > 0.99999 and headA ~= CF.identity)
local fingers = select(3, anglesOf("F_MIDDLE2_L"))
check(("hands relaxed, softly curled (middle finger %.0f deg)"):format(fingers), fingers > 8)

-- 2. the heavy walk: 6 seconds forward
local x0 = root.Position
hum.MoveDirection = V3.new(0, 0, -1)
local last = {}
local slide, planted = 0, 0
local stepsBefore = count("DustRing")
local dust = 0
local swing = 0
for i = 1, 60 * 6 do
	frame(1 / 60)
	for _, side in { "L", "R" } do
		-- the sole under the ball of the foot (where it rolls up onto its toes)
		local ballRest = rest["TOE2_" .. side].Position
		local ball = boneWorld("TOE1_" .. side) * rest["TOE1_" .. side]:PointToObjectSpace(V3.new(ballRest.X, 0, ballRest.Z))
		local prev = last[side]
		if prev and ball.Y < 0.12 and prev.Y < 0.12 then
			slide += V3.new(ball.X - prev.X, 0, ball.Z - prev.Z).Magnitude
			planted += 1
		end
		last[side] = ball
	end
	dust = math.max(dust, count("DustRing"))
	swing = math.max(swing, math.abs(pitchOf("SHOULDER_L") - pitchOf("SHOULDER_R")))
end
local travelled = (root.Position - x0).Magnitude
print(("  walk: %.1f studs in 6 s (%.1f studs/s), feet slid %.2f studs while down, arms swing %.0f deg apart, %d sounds, %d dust rings"):format(
	travelled, travelled / 6, slide, swing, sounds, dust))
check("walking: it moves at its walk speed after a heavy start", travelled > PowerConfig.OozaruWalkSpeed * 4.5)
check("walking: the feet stay planted (no sliding)", slide / travelled < 0.01)
check("walking: dust and thuds on every step", dust >= 1 and sounds >= 4)
check("walking: the arms swing", swing > 8)

-- 3. stopping: the body carries on forward and rocks back
hum.MoveDirection = V3.zero
local deepest, settled = 0, 0
for i = 1, 60 * 2.5 do
	frame(1 / 60)
	local p = pitchOf("SPINE1") + pitchOf("SPINE2") + pitchOf("SPINE3")
	deepest = math.min(deepest, p)
	settled = p
end
print(("  stop: the spine goes to %.0f deg, settles at %.0f"):format(deepest, settled))
check("stopping: lurches forward then settles back", deepest < hunched - 4 and math.abs(settled - hunched) < 4)

-- 4. turning: it can't spin on the spot
local yaw0 = select(2, root.CFrame:ToEulerAnglesYXZ())
hum.MoveDirection = V3.new(1, 0, 0) -- (asks to go right: a quarter turn)
frame(1 / 60)
for i = 1, 14 do
	frame(1 / 60)
end
local yaw1 = select(2, root.CFrame:ToEulerAnglesYXZ())
local turned = math.deg(math.abs(yaw1 - yaw0))
print(("  turning: %.0f degrees in a quarter of a second"):format(turned))
check("turning: at a giant's pace (not snapping round)", turned > 3 and turned < (PowerConfig.OozaruTurnSpeed or 140) * 0.25 + 1)
hum.MoveDirection = V3.zero
for i = 1, 60 do
	frame(1 / 60)
end

-- 5. turning back: black, then you're yourself again with everything back
ape:SetAttribute("PowerState", "Shrinking")
for i = 1, 30 do
	frame(1 / 60)
end
check("turning back: the screen goes black", black.BackgroundTransparency < 0.05)
local human = I.new("Model")
human.Name = "Player1"
human:SetAttribute("PowerState", "Idle")
local humanHum = I.new("Humanoid")
humanHum.Parent = human
player.Character = human
ape.Parent = nil
for i = 1, 60 do
	frame(1 / 60)
end
check("back as yourself: screen clear, tint off, UI back, camera back", black.BackgroundTransparency > 0.95 and not tint.Enabled and attrs.Oozaru == nil
	and otherGui.Enabled == true and player.CameraMinZoomDistance < 1)
check("... and a puff of smoke where the giant stood", emitted >= 40)
check("... and the camera back on you", camera.CameraSubject == humanHum)

if dumpPath then
	fs.writeFile(dumpPath, serde.encode("json", frames))
	print("wrote " .. #frames .. " frames to " .. dumpPath)
end
if failed then
	error("some checks failed")
end
