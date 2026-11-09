-- Runs the real PowerFX script against a fake R15 character whose attributes go through a
-- power-up, and checks the aura flames, the coded animation, rocks and burst respond.
-- usage (from the DragonWish folder): lune run tools/test/fx_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local dumpPath = process.args[1] ~= "" and process.args[1] or nil -- optional: write the flame shapes here for a picture
local dumps = {}
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local emitted = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, n) emitted += n end)

local char = I.new("Model"); char.Name = "Player1"
char.Parent = I.new("Folder") -- stands in for Workspace
local hum = I.new("Humanoid"); hum.HipHeight = 2; hum.Parent = char
local function part(name, size, y)
	local p = I.new("Part"); p.Name = name; p.Size = size; p.CFrame = CF.new(0, y, 0); p.Position = V3.new(0, y, 0); p.Parent = char; return p
end
local root = part("HumanoidRootPart", V3.new(2, 2, 1), 3)
local lt = part("LowerTorso", V3.new(2, 0.4, 1), 2.2)
local ut = part("UpperTorso", V3.new(2, 1.6, 1), 3.2)
local head = part("Head", V3.new(1.2, 1.2, 1.2), 4.5)
local motors = {}
for _, name in { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" } do
	-- characters now spawn with AnimationConstraints (Roblox's joint upgrade); "motor6d" as the
	-- second argument tests the old joints instead
	local m = I.new(process.args[2] == "motor6d" and "Motor6D" or "AnimationConstraint"); m.Name = name; m.Transform = CF.identity; m.Parent = ut
	motors[name] = m
end
char:SetAttribute("Form", "Base"); char:SetAttribute("PowerState", "Idle"); char:SetAttribute("Charge", 0)

local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end
local render, stepped = signal(), signal()
local fxRoot = I.new("Folder")
local workspaceStub = {
	CurrentCamera = { CFrame = CF.new(0, 4, -12) }, -- in front of the character (it faces -Z)
	Raycast = function(_, from) return { Position = V3.new(from.X, 0, from.Z) } end,
	BulkMoveTo = function(_, parts, cfs) for i, p in parts do p.CFrame = cfs[i] end end,
}
local tweens = 0
fakeClock = 0 -- the scripts' clock: moves with the simulated frames
local env = {
	Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Vector2 = roblox.Vector2, TweenInfo = { new = function() return {} end }, typeof = typeof, print = print,
	RaycastParams = { new = function() return {} end },
	task = { delay = function() end },
	Random = {
		new = function()
			local r = { s = 7 }
			function r:NextNumber(a, b)
				a = a or 0
				b = b or 1
				self.s = (self.s * 1103515245 + 12345) % 2147483648
				return a + (b - a) * self.s / 2147483648
			end
			function r:NextInteger(a, b)
				return math.floor(self:NextNumber(a, b + 0.999))
			end
			return r
		end,
	},
	os = { clock = function() return fakeClock end },
	require = function() return luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = { Color3 = roblox.Color3, Enum = roblox.Enum } })() end,
}
env.game = { GetService = function(_, n)
	if n == "Players" then return { GetPlayers = function() return { { Character = char } } end } end
	if n == "RunService" then return { RenderStepped = render, Stepped = stepped } end
	if n == "TweenService" then return { Create = function() tweens += 1; return { Play = function() end } end } end
	if n == "Workspace" then return workspaceStub end
	if n == "ReplicatedStorage" then return { WaitForChild = function() return {} end } end
end }
local created = {}
env.Instance = { new = function(cls)
	local inst = I.new(cls)
	table.insert(created, inst)
	return inst
end }
local src = fs.readFile("src/StarterPlayerScripts/PowerFX.client.luau"):gsub("folder%.Parent = Workspace", "-- (parent skipped)")
luau.load(src, { environment = env })()
local folder = created[1]

local function frame(dt) fakeClock += dt; render:Fire(dt); stepped:Fire(dt) end
local function find(name) for _, c in folder:GetChildren() do if c.Name == name then return c end end end
local function report(tag)
	local aura = find("Aura")
	local shown, tallest, colour = 0, 0, "-"
	if aura then
		for _, b in aura:GetChildren() do
			if b:IsA("Beam") and b.Width0 > 0.05 and b.Width1 == 0 then
				shown += 1
				tallest = math.max(tallest, b.Attachment1.CFrame.Position.Y - b.Attachment0.CFrame.Position.Y)
				if colour == "-" then
					local k = b.Color.Keypoints
					local c = k[math.ceil(#k / 2)].Value
					colour = ("%.2f %.2f %.2f"):format(c.R, c.G, c.B)
				end
			end
		end
	end
	local ringLit = 0
	for _, c in folder:GetChildren() do if c.Name == "AuraRing" and c.Transparency < 0.95 then ringLit += 1 end end
	local rocks = 0
	for _, c in folder:GetChildren() do if c.Name == "Rock" and c.Transparency < 1 then rocks += 1 end end
	local function rx(n) return (select(1, motors[n].Transform:ToEulerAnglesXYZ())) end
	local function rz(n) return (select(3, motors[n].Transform:ToEulerAnglesXYZ())) end
	print(("%-20s flames %2d  tallest %4.1f  ring %2d  rocks %d  colour %-14s | waist %+.2f neck %+.2f L-arm out %+.2f elbow %+.2f knee %+.2f"):format(
		tag, shown, tallest, ringLit, rocks, colour, rx("Waist"), rx("Neck"), rz("LeftShoulder"), rx("LeftElbow"), rx("LeftKnee")))
	if dumpPath and aura then
		local beams = {}
		for _, b in aura:GetChildren() do
			if b:IsA("Beam") and (b.Width0 > 0.02 or b.Width1 > 0.02) then
				local c0, c1 = b.Attachment0.CFrame, b.Attachment1.CFrame
				local function v(x) return { x.X, x.Y, x.Z } end
				local cols, trs = {}, {}
				for _, k in b.Color.Keypoints do table.insert(cols, { k.Time, k.Value.R, k.Value.G, k.Value.B }) end
				for _, k in b.Transparency.Keypoints do table.insert(trs, { k.Time, k.Value }) end
				table.insert(beams, { p0 = v(c0.Position), x0 = v(c0.XVector), p1 = v(c1.Position), x1 = v(c1.XVector),
					cs0 = b.CurveSize0, cs1 = b.CurveSize1, w0 = b.Width0, w1 = b.Width1, colors = cols, trans = trs })
			end
		end
		local pieces = {}
		for _, c in folder:GetChildren() do
			if (c.Name == "AuraRing" or c.Name == "AuraRipple") and c.Transparency < 0.98 then
				local cf = c.CFrame
				table.insert(pieces, { cf = { cf:GetComponents() }, size = { c.Size.X, c.Size.Y, c.Size.Z },
					t = c.Transparency, c = { c.Color.R, c.Color.G, c.Color.B } })
			end
		end
		dumps[tag] = { beams = beams, pieces = pieces, aura = { aura.CFrame:GetComponents() } }
		fs.writeFile(dumpPath, serde.encode("json", dumps, false))
	end
	return { waist = rx("Waist"), neck = rx("Neck"), arm = rz("LeftShoulder"), elbow = rx("LeftElbow"), flames = shown, tallest = tallest, ring = ringLit }
end
local failed = false
local function check(what, ok) print((ok and "  PASS " or "  FAIL ") .. what); if not ok then failed = true end end
for _ = 1, 30 do frame(1 / 60) end
local r = report("idle")
check("no aura or pose when idle", r.flames == 0 and math.abs(r.waist) < 0.01)
char:SetAttribute("PowerState", "Charging")
char:SetAttribute("Charge", 0.1)
for _ = 1, 40 do frame(1 / 60) end
r = report("just started")
check("starts standing tall: chest out, fists at the waist (elbows bent)", r.waist > 0 and r.elbow > 1 and r.flames > 0)
local early = r
for c = 0.1, 1, 0.01 do char:SetAttribute("Charge", c); frame(1 / 30) end
for _ = 1, 30 do frame(1 / 60) end
r = report("charged to full")
check("hunched over with head down and arms out", r.waist < -0.2 and r.neck < -0.2 and r.arm < -0.55)
check("aura bigger and fuller than at the start", r.flames > early.flames and r.tallest > early.tallest)
check("glowing ring on the ground at your feet", r.ring > 20)
char:SetAttribute("PowerState", "Bursting"); char:SetAttribute("Form", "SSJ"); char:SetAttribute("Breeze", 1)
local before = tweens
for _ = 1, 60 do frame(1 / 60) end
r = report("power building")
check("power builds first: still hunched, no explosion yet", r.waist < -0.2 and tweens == before)
for _ = 1, 100 do frame(1 / 60) end
r = report("exploded")
check("explosion at ExplodeAt: leaning back, head up, arms lowered and out", r.waist > 0.2 and r.neck > 0.3 and r.arm < -0.5 and r.elbow < 0.4)
print("explosion tweens started (pillar + shockwave + flash):", tweens - before, " particles burst out:", emitted)
for _ = 1, 120 do frame(1 / 60) end
r = report("still holding")
check("holds the release pose while transforming", r.waist > 0.2 and r.neck > 0.3)
char:SetAttribute("PowerState", "Idle"); char:SetAttribute("Charge", 0)
for _ = 1, 240 do frame(1 / 60) end
r = report("super saiyan")
check("control back: pose released, strong gold aura stays up", math.abs(r.waist) < 0.02 and r.flames >= 30 and r.ring > 20)
char:SetAttribute("Breeze", 0) -- the server calms you down after a while
for _ = 1, 400 do frame(1 / 60) end
r = report("calmed down")
check("aura fades away when you calm down", r.flames == 0 and r.ring == 0)
char:SetAttribute("Form", "Base")
for _ = 1, 400 do frame(1 / 60) end
r = report("powered down")
check("everything cleaned up", r.flames == 0 and find("Aura") == nil and r.ring == 0)
if failed then error("some checks failed") end
