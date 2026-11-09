-- Runs the real HUD, PowerUpClient and SSJCutscene scripts (and the DragonUI module they share) against a fake game, plays a scenario
-- and writes every UI object they put on screen (with its layout properties) to JSON, which
-- tools/preview/render_ui.py draws the way Roblox lays it out.
-- usage (from the DragonWish folder):
--   lune run tools/preview/ui_dump.luau <scenario> <width> <height> <out.json>
--   scenarios: idle | charging | ssj | hit | cutscene:<seconds into the transformation>
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local V2, V3, CF, I = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Instance
local Enum = roblox.Enum

local scenario = process.args[1] or "idle"
local W, H = tonumber(process.args[2]) or 1280, tonumber(process.args[3]) or 720
local outPath = process.args[4] or "ui.json"
local touch = W < 1000
local T = 0 -- the fake clock

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

-- timers (task.delay / defer / spawn) run on the fake clock
local scheduled = {}
local taskStub = {
	delay = function(s, fn, ...) table.insert(scheduled, { At = T + s, Fn = fn, Args = table.pack(...) }) end,
	defer = function(fn, ...) table.insert(scheduled, { At = T, Fn = fn, Args = table.pack(...) }) end,
	spawn = function(fn, ...) fn(...) end,
	wait = function() end,
}

-- tweens actually move the properties over time
local tweens = {}
local function ease(style, dir, a)
	local c1 = 1.70158
	local c3 = c1 + 1
	if style == Enum.EasingStyle.Back then
		if dir == Enum.EasingDirection.In then return c3 * a ^ 3 - c1 * a ^ 2 end
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end
	if dir == Enum.EasingDirection.In then return a * a end
	return 1 - (1 - a) * (1 - a)
end
local function mix(a, b, x)
	if type(a) == "number" then return a + (b - a) * x end
	local ta = typeof(a)
	if ta == "UDim2" then
		return roblox.UDim2.new(a.X.Scale + (b.X.Scale - a.X.Scale) * x, a.X.Offset + (b.X.Offset - a.X.Offset) * x,
			a.Y.Scale + (b.Y.Scale - a.Y.Scale) * x, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * x)
	elseif ta == "Color3" or ta == "Vector3" or ta == "Vector2" then
		return a:Lerp(b, x)
	end
	return x >= 1 and b or a
end
local TweenService = {
	Create = function(_, inst, info, props)
		return {
			Play = function()
				for i = #tweens, 1, -1 do -- a new tween on the same property replaces the old one
					local old = tweens[i]
					if old.Inst == inst then
						for k in props do old.To[k] = nil end
					end
				end
				local from = {}
				for k in props do from[k] = inst[k] end
				table.insert(tweens, { Inst = inst, From = from, To = table.clone(props), Start = T, Time = math.max(info.Time or 1, 1e-3), Style = info.Style, Dir = info.Dir })
			end,
		}
	end,
}
local function stepTweens()
	for i = #tweens, 1, -1 do
		local tw = tweens[i]
		local a = math.clamp((T - tw.Start) / tw.Time, 0, 1)
		local e = ease(tw.Style, tw.Dir, a)
		for k, v in tw.To do
			tw.Inst[k] = mix(tw.From[k], v, e)
		end
		if a >= 1 then table.remove(tweens, i) end
	end
end

-- the character: a real model, wrapped so the scripts can listen to its attributes
local model = I.new("Model")
model.Name = "Player1"
model.Parent = I.new("Folder") -- (stands in for Workspace: the cutscene stops if you leave it)
local hum = I.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 100
hum.HipHeight = 2
hum.Parent = model
local function part(name, size, cf)
	local p = I.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Position = cf.Position
	p.Parent = model
	return p
end
part("HumanoidRootPart", V3.new(2, 2, 1), CF.new(0, 3, 0))
part("Head", V3.new(1.2, 1.2, 1.2), CF.new(0, 4.6, 0))
part("UpperTorso", V3.new(2, 1.6, 1), CF.new(0, 3.2, 0))
for k, v in { Form = "Base", PowerState = "Idle", Charge = 0, Ki = 30, Breeze = 0, AuraWind = 0 } do
	model:SetAttribute(k, v)
end
local attrSignals = {}
local character = setmetatable({}, {
	__index = function(_, k)
		if k == "GetAttributeChangedSignal" then
			return function(_, n)
				attrSignals[n] = attrSignals[n] or signal()
				return attrSignals[n]
			end
		elseif k == "SetAttribute" then
			return function(_, n, v)
				local old = model:GetAttribute(n)
				model:SetAttribute(n, v)
				if old ~= v and attrSignals[n] then attrSignals[n]:Fire() end
			end
		elseif k == "WaitForChild" then
			return function(_, n)
				if n == "Humanoid" then
					return { Died = signal() } -- (test instances have no events)
				end
				return model:FindFirstChild(n)
			end
		end
		local v = model[k]
		if type(v) == "function" then
			return function(_, ...) return v(model, ...) end
		end
		return v
	end,
	__newindex = function(_, k, v) model[k] = v end,
})
-- someone else nearby, for the Dragon Radar
local other = I.new("Model")
local orp = I.new("Part")
orp.Name = "HumanoidRootPart"
orp.CFrame = CF.new(60, 3, -90)
orp.Position = V3.new(60, 3, -90)
orp.Parent = other
other:SetAttribute("Form", "SSJ")
local otherPlayer = { Name = "Rival", Character = other }

local playerGui = I.new("Folder")
playerGui.Name = "PlayerGui"
local playerAttrs = {}
local player = { Name = "Player1", DisplayName = "Kakarot", UserId = 1, Character = character, CharacterAdded = signal() }
function player:WaitForChild() return playerGui end
function player:GetAttribute(n) return playerAttrs[n] end
function player:SetAttribute(n, v) playerAttrs[n] = v end

local camera = { CFrame = CF.new(0, 5, -10), ViewportSize = V2.new(W, H), FieldOfView = 70, CameraType = Enum.CameraType.Custom }
local renderStepped = signal()
local renderSteps = {}
local actions = {}
local remoteLog = {}
local services = {
	Players = { LocalPlayer = player, GetPlayers = function() return { player, otherPlayer } end, PlayerAdded = signal(), PlayerRemoving = signal() },
	RunService = {
		RenderStepped = renderStepped, Heartbeat = signal(), Stepped = signal(),
		BindToRenderStep = function(_, name, _, fn) renderSteps[name] = fn end,
		UnbindFromRenderStep = function(_, name) renderSteps[name] = nil end,
	},
	TweenService = TweenService,
	Workspace = { CurrentCamera = camera },
	ReplicatedStorage = {
		WaitForChild = function(_, n)
			if n == "PowerUp" then
				return { FireServer = function(_, ...) table.insert(remoteLog, { ... }) end, OnClientEvent = signal() }
			end
			return n
		end,
	},
	StarterGui = { SetCoreGuiEnabled = function() end },
	CollectionService = { HasTag = function() return false end, RemoveTag = function() end },
	ContextActionService = {
		BindAction = function(_, name, fn) actions[name] = fn end,
		BindActionAtPriority = function(_, name, fn) actions[name] = fn end,
		UnbindAction = function(_, name) actions[name] = nil end,
		SetTitle = function() end,
	},
	UserInputService = { TouchEnabled = touch, IsKeyDown = function() return false end },
	Lighting = I.new("Folder"),
}
local configEnv = { Color3 = roblox.Color3, Enum = Enum }
local PowerConfig = luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = configEnv })()
local modules = { PowerConfig = PowerConfig }
local randomStub = {
	new = function()
		local r = { s = 11 }
		function r:NextNumber(a, b)
			a = a or 0
			b = b or 1
			self.s = (self.s * 1103515245 + 12345) % 2147483648
			return a + (b - a) * self.s / 2147483648
		end
		function r:NextInteger(a, b) return math.floor(self:NextNumber(a, b + 0.999)) end
		return r
	end,
}
local function env()
	return {
		game = { GetService = function(_, n) return assert(services[n], "no stub for " .. n) end },
		script = { Parent = { WaitForChild = function(_, n) return n end } },
		require = function(m) return assert(modules[m], "no module " .. tostring(m)) end,
		task = taskStub, os = { clock = function() return T end },
		Instance = I, Enum = Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = V2, Vector3 = V3, CFrame = CF,
		Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange,
		TweenInfo = { new = function(t, style, dir) return { Time = t, Style = style, Dir = dir } end },
		Random = randomStub, typeof = typeof, print = print, warn = print,
	}
end
local function run(path)
	-- test instances have no events: skip hooking up the touch button
	local src = fs.readFile(path):gsub("tapButton%.Activated:Connect%(tap%)", "-- (touch button skipped)")
	return luau.load(src, { environment = env() })()
end
modules.DragonUI = run("src/ReplicatedStorage/DragonUI.luau")
modules.SSJCutscene = run("src/StarterPlayerScripts/SSJCutscene.luau")
run("src/StarterPlayerScripts/PowerUpClient.client.luau")
run("src/StarterPlayerScripts/HUD.client.luau")

local function frames(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += 1 / 60
		for i = #scheduled, 1, -1 do
			local s = scheduled[i]
			if s.At <= T then
				table.remove(scheduled, i)
				s.Fn(table.unpack(s.Args, 1, s.Args.n))
			end
		end
		stepTweens()
		for _, fn in renderSteps do fn(1 / 60) end
		renderStepped:Fire(1 / 60)
	end
end
local function press(name)
	local fn = actions[name]
	if fn then fn(name, Enum.UserInputState.Begin) end
end

frames(1.5)
if scenario == "charging" then
	press("DWPower")
	character:SetAttribute("PowerState", "Charging")
	for k = 1, 14 do
		press("DWTap")
		character:SetAttribute("Charge", math.min(1, k * 0.05))
		character:SetAttribute("Ki", math.max(30, k * 5))
		frames(0.12)
	end
	frames(0.3)
elseif scenario == "ssj" then
	character:SetAttribute("Form", "SSJ")
	character:SetAttribute("Breeze", 1)
	character:SetAttribute("Ki", 100)
	frames(2.5)
elseif scenario == "hit" then
	hum.Health = 22
	frames(0.12)
elseif scenario:sub(1, 8) == "cutscene" then
	local at = tonumber(scenario:sub(10)) or 3
	press("DWPower")
	character:SetAttribute("PowerState", "Charging")
	frames(0.2)
	character:SetAttribute("Charge", 1)
	character:SetAttribute("Form", "SSJ")
	character:SetAttribute("PowerState", "Bursting")
	frames(at)
end

-- write out every ScreenGui and the UI objects inside it
local function get(inst, prop, default)
	local ok, v = pcall(function() return inst[prop] end)
	if ok and v ~= nil then return v end
	return default
end
local function udim2(u) return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } end
local function color(c) return { c.R, c.G, c.B } end
local function dump(inst)
	local node = { class = inst.ClassName, name = inst.Name, children = {} }
	if inst:IsA("GuiObject") then
		node.pos = udim2(get(inst, "Position", roblox.UDim2.new()))
		node.size = udim2(get(inst, "Size", roblox.UDim2.new()))
		local ap = get(inst, "AnchorPoint", V2.zero)
		node.anchor = { ap.X, ap.Y }
		node.rot = get(inst, "Rotation", 0)
		node.bg = color(get(inst, "BackgroundColor3", roblox.Color3.new(1, 1, 1)))
		node.bgT = get(inst, "BackgroundTransparency", 0)
		node.visible = get(inst, "Visible", true)
		node.z = get(inst, "ZIndex", 1)
		node.clip = get(inst, "ClipsDescendants", false)
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			node.text = get(inst, "Text", "")
			node.tc = color(get(inst, "TextColor3", roblox.Color3.new(0, 0, 0)))
			node.tT = get(inst, "TextTransparency", 0)
			node.scaled = get(inst, "TextScaled", false)
			node.tsize = get(inst, "TextSize", 14)
			node.font = get(inst, "Font", Enum.Font.SourceSans).Name
			node.xa = get(inst, "TextXAlignment", Enum.TextXAlignment.Center).Name
			node.ya = get(inst, "TextYAlignment", Enum.TextYAlignment.Center).Name
			node.strokeT = get(inst, "TextStrokeTransparency", 1)
			node.strokeC = color(get(inst, "TextStrokeColor3", roblox.Color3.new(0, 0, 0)))
		end
		if inst:IsA("CanvasGroup") then
			node.groupT = get(inst, "GroupTransparency", 0)
		end
	elseif inst:IsA("UICorner") then
		local r = get(inst, "CornerRadius", roblox.UDim.new(0, 8))
		node.radius = { r.Scale, r.Offset }
	elseif inst:IsA("UIStroke") then
		node.color = color(get(inst, "Color", roblox.Color3.new()))
		node.thick = get(inst, "Thickness", 1)
		node.t = get(inst, "Transparency", 0)
		node.mode = get(inst, "ApplyStrokeMode", Enum.ApplyStrokeMode.Contextual).Name
	elseif inst:IsA("UIGradient") then
		local cs = get(inst, "Color", roblox.ColorSequence.new(roblox.Color3.new(1, 1, 1)))
		local ts = get(inst, "Transparency", roblox.NumberSequence.new(0))
		node.colors, node.trans = {}, {}
		for _, k in cs.Keypoints do table.insert(node.colors, { k.Time, k.Value.R, k.Value.G, k.Value.B }) end
		for _, k in ts.Keypoints do table.insert(node.trans, { k.Time, k.Value }) end
		node.rot = get(inst, "Rotation", 0)
		local off = get(inst, "Offset", V2.zero)
		node.offset = { off.X, off.Y }
	elseif inst:IsA("UIScale") then
		node.scale = get(inst, "Scale", 1)
	elseif inst:IsA("UIAspectRatioConstraint") then
		node.ratio = get(inst, "AspectRatio", 1)
	elseif inst:IsA("ScreenGui") then
		node.enabled = get(inst, "Enabled", true)
		node.ignoreInset = get(inst, "IgnoreGuiInset", false)
		node.order = get(inst, "DisplayOrder", 0)
	end
	for _, c in inst:GetChildren() do
		table.insert(node.children, dump(c))
	end
	return node
end
-- screen effects on the 3D view (the manga filter's colour)
local effects = {}
for _, e in services.Lighting:GetChildren() do
	if e:IsA("ColorCorrectionEffect") and e.Enabled then
		table.insert(effects, { saturation = e.Saturation, contrast = e.Contrast, brightness = e.Brightness, tint = { e.TintColor.R, e.TintColor.G, e.TintColor.B } })
	end
end
local guis = {}
for _, g in playerGui:GetChildren() do
	table.insert(guis, dump(g))
end
table.sort(guis, function(a, b) return (a.order or 0) < (b.order or 0) end)
fs.writeFile(outPath, serde.encode("json", { width = W, height = H, touch = touch, scenario = scenario, guis = guis, effects = effects }, false))
print(("wrote %s (%s, %dx%d, %d screens)"):format(outPath, scenario, W, H, #guis))
