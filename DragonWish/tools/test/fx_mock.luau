-- Runs the real PowerFX script against a fake R15 character whose attributes go through a
-- power-up, and checks the aura, stance, rocks and burst respond.
-- usage (from the DragonWish folder): lune run tools/test/fx_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance
local emitted = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, n) emitted += n end)

local char = I.new("Model"); char.Name = "Player1"
char.Parent = I.new("Folder") -- stands in for Workspace
I.new("Humanoid").Parent = char
local function part(name, size, y)
	local p = I.new("Part"); p.Name = name; p.Size = size; p.CFrame = CF.new(0, y, 0); p.Position = V3.new(0, y, 0); p.Parent = char; return p
end
local root = part("HumanoidRootPart", V3.new(2, 2, 1), 3)
local lt = part("LowerTorso", V3.new(2, 0.4, 1), 2.2)
local ut = part("UpperTorso", V3.new(2, 1.6, 1), 3.2)
local head = part("Head", V3.new(1.2, 1.2, 1.2), 4.5)
local motors = {}
for _, name in { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip", "LeftKnee", "RightKnee" } do
	local m = I.new("Motor6D"); m.Name = name; m.Transform = CF.identity; m.Parent = ut
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
	Raycast = function(_, from) return { Position = V3.new(from.X, 0, from.Z) } end,
	BulkMoveTo = function(_, parts, cfs) for i, p in parts do p.CFrame = cfs[i] end end,
}
local tweens = 0
local env = {
	Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange,
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
	os = os,
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

local function frame(dt) render:Fire(dt); stepped:Fire(dt) end
local function find(name) for _, c in folder:GetChildren() do if c.Name == name then return c end end end
local function report(tag)
	local aura = find("Aura")
	local flame = aura and aura:FindFirstChildOfClass("ParticleEmitter")
	local rocks = 0
	for _, c in folder:GetChildren() do if c.Name == "Rock" and c.Transparency < 1 then rocks += 1 end end
	local light = aura and aura:FindFirstChildOfClass("PointLight")
	local rx = select(1, motors.LeftKnee.Transform:ToEulerAnglesXYZ())
	print(("%-22s aura %s  flame rate %5.0f  aura height %4.1f  light %4.1f  rocks up %d  knee bend %+.2f  colour %s"):format(
		tag, tostring(aura ~= nil), flame and flame.Rate or 0, aura and aura.Size.Y or 0, light and light.Brightness or 0, rocks, rx,
		flame and tostring(flame.Color.Keypoints[#flame.Color.Keypoints].Value) or "-"))
end
for _ = 1, 30 do frame(1 / 60) end
report("idle")
char:SetAttribute("PowerState", "Charging")
for c = 0, 1, 0.01 do char:SetAttribute("Charge", c); frame(1 / 30) end
report("charged to full")
char:SetAttribute("PowerState", "Bursting"); char:SetAttribute("Form", "SSJ")
for _ = 1, 10 do frame(1 / 60) end
report("bursting")
print("burst tweens started (shockwave + flash):", tweens, " particles burst out:", emitted)
char:SetAttribute("PowerState", "Idle"); char:SetAttribute("Charge", 0)
for _ = 1, 240 do frame(1 / 60) end
report("calm super saiyan")
char:SetAttribute("Form", "Base")
for _ = 1, 400 do frame(1 / 60) end
report("powered down")
