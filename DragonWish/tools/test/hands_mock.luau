-- Runs the real HandFX script on a fake character whose finger bones were imported at random
-- angles (as an importer can turn them), and checks where the fingertips really end up, in the
-- hand's own space: relaxed, idle fidgets, fists when powering up, the point, Kaioken, limp.
-- usage (from the DragonWish folder): lune run tools/test/hands_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance

local info = {}
for _, h in serde.decode("json", fs.readFile("tools/rig/riginfo.json")) do
	info[h.name] = h
end
local seed = 5
local function rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function randomTurn()
	return CF.fromAxisAngle(V3.new(rand() - 0.5, rand() - 0.5, rand() - 0.5).Unit, rand() * 6)
end

-- the character: hands at the R15 spots, turned 40 degrees, fingers welded on
local char = I.new("Model")
char.Name = "Player1"
char.Parent = I.new("Folder")
local hum = I.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 100
hum.Parent = char
local rootCF = CF.new(4, 0, -2) * CF.Angles(0, math.rad(40), 0)
local function part(name, size, offset, class)
	local p = I.new(class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = rootCF * offset
	p.Position = p.CFrame.Position -- (test parts don't work this out themselves)
	p.Parent = char
	return p
end
local root = part("HumanoidRootPart", V3.new(2, 2, 1), CF.new(0, 3, 0))
root.AssemblyLinearVelocity = V3.zero
local hands = {}
for _, side in { "Left", "Right" } do
	local sx = side == "Left" and -1 or 1
	local hand = part(side .. "Hand", V3.new(1, 0.387, 1), CF.new(1.5 * sx, 2.1935, 0), "MeshPart")
	hands[side] = hand
	local h = info[side .. "Fingers"]
	local holder = I.new("Model")
	holder.Name = "DW_" .. side .. "Fingers"
	holder.Parent = char
	local mesh = I.new("MeshPart")
	mesh.Name = side .. "Fingers"
	mesh.CFrame = hand.CFrame * CF.new(0.1, -0.2, 0.05) * randomTurn() -- the importer's own frame
	mesh.Parent = holder
	local world = {}
	local function add(name, parentInst, parentName)
		local b = I.new("Bone")
		b.Name = name
		b.Parent = parentInst
		local p = h.bones[name]
		local w = hand.CFrame * CF.new(p[1], p[2], p[3]) * randomTurn()
		b.CFrame = (parentName and world[parentName] or mesh.CFrame):Inverse() * w
		b.Transform = CF.identity
		world[name] = w
	end
	add(h.root, mesh, nil)
	for _, c in h.chains do
		local pn = h.root
		for _, bn in c.bones do
			add(bn, mesh:FindFirstChild(pn, true), pn)
			pn = bn
		end
	end
end
for k, v in { Form = "Base", PowerState = "Idle", Charge = 0, Kaioken = 0, Breeze = 0, Exhausted = false } do
	char:SetAttribute(k, v)
end

-- where a bone really is (rest pose plus Transforms), in its hand's space
local function tipInHand(side: string, finger: string)
	local mesh = char["DW_" .. side .. "Fingers"][side .. "Fingers"]
	local bone = mesh:FindFirstChild(side:sub(1, 1) .. finger .. "Tip", true)
	local chain = {}
	local node = bone
	while node ~= mesh do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	local cf = mesh.CFrame
	for _, b in chain do
		cf = cf * b.CFrame * b.Transform
	end
	return hands[side].CFrame:PointToObjectSpace(cf.Position)
end
local function restTip(side: string, finger: string)
	local p = info[side .. "Fingers"].bones[side:sub(1, 1) .. finger .. "Tip"]
	return V3.new(p[1], p[2], p[3])
end
-- how far a fingertip has curled toward the palm (studs; thumbs curl the other way)
local function curl(side: string, finger: string): number
	local inward = (side == "Right") and -1 or 1
	if finger == "Thumb" then
		inward = -inward
	end
	return (tipInHand(side, finger).X - restTip(side, finger).X) * inward
end

-- the fake game
local T = 0
local function signal()
	local s = { fns = {} }
	function s:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, f in self.fns do
			f(...)
		end
	end
	return s
end
local preRender = signal()
local env = {
	Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, typeof = typeof, print = print, warn = print,
	os = { clock = function() return T end },
	Random = { new = function()
		local r = { s = 3 }
		function r:NextNumber(a, b)
			a = a or 0
			b = b or 1
			self.s = (self.s * 1103515245 + 12345) % 2147483648
			return a + (b - a) * self.s / 2147483648
		end
		return r
	end },
	require = function()
		return luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = { Color3 = roblox.Color3, Enum = roblox.Enum } })()
	end,
}
env.game = { GetService = function(_, n)
	if n == "Players" then
		return { GetPlayers = function() return { { Character = char } } end }
	elseif n == "RunService" then
		return { PreRender = preRender, RenderStepped = signal() }
	elseif n == "Workspace" then
		return { CurrentCamera = { CFrame = rootCF * CF.new(0, 4, -10) } }
	elseif n == "ReplicatedStorage" then
		return { WaitForChild = function(_, x) return x end }
	end
end }
luau.load(fs.readFile("src/StarterPlayerScripts/HandFX.client.luau"), { environment = env })()
local PowerConfig = env.require()
local function run(seconds)
	local stop = T + seconds
	while T < stop do
		T += 1 / 60
		preRender:Fire(1 / 60)
	end
end

local failed = false
local function check(what, ok)
	print((ok and "PASS  " or "FAIL  ") .. what)
	if not ok then
		failed = true
	end
end
-- a fingertip folded into a fist ends up up inside the palm
local function fist(side: string): boolean
	for _, f in { "Index", "Middle", "Ring", "Pinky" } do
		if tipInHand(side, f).Y < -0.2 then
			return false
		end
	end
	return curl(side, "Thumb") > 0.4
end
local function show(tag)
	local parts = {}
	for _, side in { "Left", "Right" } do
		for _, f in { "Thumb", "Index", "Middle", "Ring", "Pinky" } do
			table.insert(parts, ("%s%s %+.2f"):format(side:sub(1, 1), f:sub(1, 2), curl(side, f)))
		end
	end
	print(("%-18s curl toward the palm (studs): %s"):format(tag, table.concat(parts, "  ")))
end

-- standing still: relaxed
run(0.6)
show("standing")
local relaxedCurl = {}
for _, f in { "Thumb", "Index", "Middle", "Ring", "Pinky" } do
	relaxedCurl[f] = curl("Right", f)
end
local folded = false
for _, f in { "Index", "Middle", "Ring", "Pinky" } do
	folded = folded or tipInHand("Right", f).Y > -0.55 or tipInHand("Left", f).Y > -0.55
end
check("relaxed: every finger a little curled, the pinky most, none folded under",
	relaxedCurl.Pinky > relaxedCurl.Index and relaxedCurl.Index > 0.04 and not folded and math.abs(curl("Left", "Pinky") - relaxedCurl.Pinky) < 1e-3)
local still = tipInHand("Right", "Index")
check("the fingers sit where the rig put them (tips under the hand)", still.Y < -0.6)

-- bored: within a few seconds a hand fidgets
local maxCurl, minCurl = -1, 1
for _ = 1, 600 do
	run(1 / 60)
	local c = curl("Left", "Middle") + curl("Right", "Middle")
	maxCurl, minCurl = math.max(maxCurl, c), math.min(minCurl, c)
end
check(("idle fidgets: the fingers open and close now and then (range %.2f studs)"):format(maxCurl - minCurl), maxCurl - minCurl > 0.3)

-- powering up: fists
char:SetAttribute("PowerState", "Charging")
char:SetAttribute("Charge", 0.6)
run(0.6)
show("charging")
check("powering up: fists (every finger folded into the palm, the thumb across)", fist("Left") and fist("Right"))

-- transforming, then the point: left index straight out, the rest folded
char:SetAttribute("Form", "SSJ")
char:SetAttribute("PowerState", "Bursting")
run(PowerConfig.PointAt + 1.2)
show("the point")
check("the point: left index straight", math.abs(curl("Left", "Index")) < 0.08 and tipInHand("Left", "Index").Y < -0.8)
check("... with the other fingers folded and the right hand still a fist",
	tipInHand("Left", "Middle").Y > -0.2 and tipInHand("Left", "Pinky").Y > -0.2 and fist("Right"))

-- Kaioken: fists; exhausted: limp
char:SetAttribute("PowerState", "Idle")
char:SetAttribute("Form", "Base")
char:SetAttribute("Kaioken", 4)
run(0.6)
show("kaioken")
check("Kaioken: fists", fist("Left") and fist("Right"))
char:SetAttribute("Kaioken", 0)
char:SetAttribute("Exhausted", true)
run(0.6)
show("exhausted")
check("exhausted: limp, more open than relaxed",
	curl("Right", "Middle") < relaxedCurl.Middle - 0.05 and curl("Right", "Index") < relaxedCurl.Index and tipInHand("Right", "Middle").Y < -0.8)

-- walking: the fingers trail behind the hand when the arm swings
char:SetAttribute("Exhausted", false)
root.AssemblyLinearVelocity = V3.new(0, 0, -16)
local hand = hands.Right
local base = hand.CFrame
local fingers = char.DW_RightFingers.RightFingers
local welded = base:ToObjectSpace(fingers.CFrame) -- (the weld that holds them on in the game)
local lo, hi = 1, -1
for k = 1, 240 do
	-- the arm swings the hand forward and back
	hand.CFrame = base * CF.new(0.6 * math.sin(k / 60 * 2 * math.pi * 1.4), 0, 0)
	fingers.CFrame = hand.CFrame * welded
	run(1 / 60)
	local c = curl("Right", "Middle")
	lo, hi = math.min(lo, c), math.max(hi, c)
end
hand.CFrame = base
check(("walking: the fingers trail behind the swinging hand (fingertips swing %.2f studs)"):format(hi - lo), hi - lo > 0.05 and hi - lo < 0.6)

if failed then
	error("some checks failed")
end
