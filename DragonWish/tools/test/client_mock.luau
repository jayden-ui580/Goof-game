-- Runs the real PowerUpClient (your keys, camera and screen) and the real PowerUpServer together
-- with a fake clock and a fake player who presses R and spams Space, and checks you actually
-- turn Super Saiyan, that cancelling works and that powering down works.
-- usage (from the DragonWish folder): lune run tools/test/client_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance

local T = 0 -- the fake clock (seconds)
local LATENCY = 0.1 -- how long a message from the client takes to reach the server

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

-- a fake character (Lune instances have no events, so this one is a plain table)
local attrs = { Form = "Base", PowerState = "Idle", Charge = 0, AuraWind = 0 }
local attrSignals = {}
local humanoid = { Health = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, Died = signal() }
local rootPart = { CFrame = CF.new(0, 3, 0), Position = V3.new(0, 3, 0) }
local baseHair, ssjHair = I.new("Part"), I.new("Part")
baseHair:SetAttribute("VisibleIn", "Base")
ssjHair:SetAttribute("VisibleIn", "SSJ")
ssjHair.Transparency = 1
local char = { Name = "Player1", Parent = {} }
function char:GetAttribute(n)
	return attrs[n]
end
function char:SetAttribute(n, v)
	local old = attrs[n]
	attrs[n] = v
	if old ~= v and attrSignals[n] then
		attrSignals[n]:Fire()
	end
end
function char:GetAttributeChangedSignal(n)
	attrSignals[n] = attrSignals[n] or signal()
	return attrSignals[n]
end
function char:FindFirstChildOfClass(c)
	return c == "Humanoid" and humanoid or nil
end
function char:FindFirstChild(n)
	return n == "HumanoidRootPart" and rootPart or nil
end
function char:WaitForChild()
	return humanoid
end
function char:GetDescendants()
	return { baseHair, ssjHair }
end

local player = { Name = "Player1", Character = char, CharacterAdded = signal() }
function player:WaitForChild()
	return I.new("Folder")
end

-- the RemoteEvent: client -> server messages arrive LATENCY seconds later
local inFlight = {}
local remote = { OnServerEvent = signal() }
function remote:FireServer(...)
	table.insert(inFlight, { At = T + LATENCY, Args = table.pack(...) })
end
local sent = {}

-- engine stubs
local delayed = {}
local taskStub = {
	delay = function(s, fn, ...)
		table.insert(delayed, { At = T + s, Fn = fn, Args = table.pack(...) })
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	wait = function() end,
}
local actions = {}
local cas = {
	BindAction = function(_, name, fn)
		actions[name] = fn
	end,
	BindActionAtPriority = function(_, name, fn)
		actions[name] = fn
	end,
	UnbindAction = function(_, name)
		actions[name] = nil
	end,
	SetTitle = function() end,
}
local renderSteps, renderStepped, heartbeat = {}, signal(), signal()
local lighting = I.new("Folder")
local camera = I.new("Camera")
camera.FieldOfView = 70
local function config()
	return luau.load(fs.readFile("src/ReplicatedStorage/PowerConfig.luau"), { environment = { Color3 = roblox.Color3, Enum = roblox.Enum } })()
end
local PowerConfig = config()
local DragonUI -- the shared UI module (loaded below, once the fake environment exists)
-- stands in for the SSJCutscene module: records that it played and for how long
cutsceneStub = { Plays = {}, Stopped = 0 }
function cutsceneStub.Play(character, duration, onDone)
	table.insert(cutsceneStub.Plays, { At = T, Duration = duration })
	table.insert(delayed, { At = T + duration, Fn = function() if onDone then onDone() end end, Args = table.pack() })
end
function cutsceneStub.Stop() cutsceneStub.Stopped += 1 end

local function env(isServer)
	local e = {
		Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Vector2 = roblox.Vector2, TweenInfo = { new = function() return {} end }, typeof = typeof, print = print, warn = print,
		math = math, table = table, string = string, tostring = tostring, pairs = pairs,
		task = taskStub, os = { clock = function() return T end },
		Instance = I,
		ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		require = function(m)
			if m == "SSJCutscene" then
				return cutsceneStub
			elseif m == "DragonUI" then
				return DragonUI
			end
			return PowerConfig
		end,
		script = { Parent = { WaitForChild = function(_, name) return name end } },
	}
	e.game = {
		GetService = function(_, n)
			if n == "Players" then
				return { LocalPlayer = player, PlayerRemoving = signal(), GetPlayers = function() return { player } end }
			elseif n == "ReplicatedStorage" then
				return {
					WaitForChild = function(_, what) return what == "PowerUp" and remote or what end,
					FindFirstChild = function(_, what) return what == "PowerUp" and remote or nil end,
				}
			elseif n == "RunService" then
				return {
					Heartbeat = heartbeat, RenderStepped = renderStepped,
					BindToRenderStep = function(_, _, _, fn) table.insert(renderSteps, fn) end,
				}
			elseif n == "ContextActionService" then
				return cas
			elseif n == "TweenService" then
				return { Create = function() return { Play = function() end } end }
			elseif n == "UserInputService" then
				return { TouchEnabled = false }
			elseif n == "Workspace" then
				return { CurrentCamera = camera }
			elseif n == "Lighting" then
				return lighting
			end
			error("no stub for " .. n)
		end,
	}
	return e
end

DragonUI = luau.load(fs.readFile("src/ReplicatedStorage/DragonUI.luau"), { environment = env(false) })()
luau.load(fs.readFile("src/ServerScriptService/PowerUpServer.server.luau"), { environment = env(true) })()
local clientSource = fs.readFile("src/StarterPlayerScripts/PowerUpClient.client.luau")
	:gsub("tapButton%.Activated:Connect%(tap%)", "-- (touch button skipped: test instances have no events)")
luau.load(clientSource, { environment = env(false) })()

local function press(name)
	local fn = actions[name]
	if fn then
		fn(name, roblox.Enum.UserInputState.Begin)
		fn(name, roblox.Enum.UserInputState.End)
	end
	return fn ~= nil
end

local log = {}
local lastState, lastForm = attrs.PowerState, attrs.Form
local function step(dt)
	T += dt
	while inFlight[1] and inFlight[1].At <= T do
		local m = table.remove(inFlight, 1)
		table.insert(sent, m.Args[1])
		remote.OnServerEvent:Fire(player, table.unpack(m.Args, 1, m.Args.n))
	end
	for i = #delayed, 1, -1 do
		local d = delayed[i]
		if d.At <= T then
			table.remove(delayed, i)
			d.Fn(table.unpack(d.Args, 1, d.Args.n))
		end
	end
	for _, fn in renderSteps do
		fn(dt)
	end
	renderStepped:Fire(dt)
	heartbeat:Fire(dt)
	if attrs.PowerState ~= lastState or attrs.Form ~= lastForm then
		table.insert(log, ("  t=%5.2fs  %s / %s  (bar %.2f, wind %.2f, camera %s)"):format(
			T, attrs.Form, attrs.PowerState, attrs.Charge or 0, attrs.AuraWind or 0, tostring(camera.CameraType)))
		lastState, lastForm = attrs.PowerState, attrs.Form
	end
end

local function run(seconds, tapsPerSecond)
	local nextTap = T
	local stop = T + seconds
	while T < stop do
		if tapsPerSecond and T >= nextTap then
			press("DWTap")
			nextTap += 1 / tapsPerSecond
		end
		step(1 / 60)
	end
end

local function check(what, ok)
	print((ok and "PASS  " or "FAIL  ") .. what)
	if not ok then
		_G.failed = true
	end
end

-- 1. press R, spam Space at 8 taps a second
run(0.5)
press("DWPower")
run(0.3)
check("R starts charging and you're frozen in place", attrs.PowerState == "Charging" and humanoid.WalkSpeed == 0)
check("the camera swings round (Scriptable)", camera.CameraType == roblox.Enum.CameraType.Scriptable)
local reached
for _ = 1, 600 do
	run(1 / 60 * 4, 8)
	if attrs.PowerState == "Bursting" then
		reached = T
		break
	end
end
check(("spamming Space turns you Super Saiyan (took %.1fs at 8 taps/s)"):format((reached or T) - 0.5), reached ~= nil and attrs.Form == "SSJ")
check("the SSJ hair is shown and the base hair hidden", ssjHair.Transparency == 0 and baseHair.Transparency == 1)
check(("the transformation cutscene plays (%d time, %.1f s)"):format(#cutsceneStub.Plays, cutsceneStub.Plays[1] and cutsceneStub.Plays[1].Duration or 0),
	#cutsceneStub.Plays == 1 and math.abs(cutsceneStub.Plays[1].Duration - (PowerConfig.BurstTime - 0.05)) < 1e-6)
run(PowerConfig.BurstTime + 0.5)
check("after the burst you're a calm Super Saiyan and can move again",
	attrs.PowerState == "Idle" and attrs.Form == "SSJ" and humanoid.WalkSpeed == 16 and math.abs(attrs.AuraWind - PowerConfig.SSJCalmWind) < 1e-6)
check("the camera is given back", camera.CameraType ~= roblox.Enum.CameraType.Scriptable)

-- 2. power down
press("DWPower")
run(0.5)
check("R as a Super Saiyan powers down", attrs.Form == "Base" and ssjHair.Transparency == 1 and baseHair.Transparency == 0)

-- 3. start, tap a little, cancel
press("DWPower")
run(1, 8)
local midCharge = attrs.Charge
press("DWPower")
run(0.5)
check(("R while charging cancels (bar was %.2f)"):format(midCharge), attrs.PowerState == "Idle" and attrs.Form == "Base" and humanoid.WalkSpeed == 16)

-- 4. tapping too slowly never gets there
press("DWPower")
run(8, 2)
check(("tapping slowly (2/s) doesn't transform (bar stuck at %.2f)"):format(attrs.Charge), attrs.Form == "Base")
press("DWPower")
run(0.5)

-- 5. a cheater sending "Transform" straight away gets refused
remote.OnServerEvent:Fire(player, "Start")
remote.OnServerEvent:Fire(player, "Charge", 1)
remote.OnServerEvent:Fire(player, "Transform")
check("the server refuses an instant full bar + transform", attrs.Form == "Base")
remote.OnServerEvent:Fire(player, "Cancel")

-- 6. Kaioken: K lights it, K again pushes it higher, R lets it go
attrs.Ki = 100
run(0.5)
press("DWKaioken")
run(0.3)
check(("K lights the Kaioken (x%d) and you move faster (walk %.1f)"):format(attrs.KaiokenMult or 0, humanoid.WalkSpeed),
	attrs.Kaioken == 1 and humanoid.WalkSpeed > 16)
run(0.7)
press("DWKaioken")
run(0.3)
check(("K again pushes it higher (x%d)"):format(attrs.KaiokenMult or 0), attrs.Kaioken == 2)
press("DWPower")
run(0.3)
check("R lets it go (and doesn't start powering up)", attrs.Kaioken == 0 and attrs.PowerState == "Idle" and humanoid.WalkSpeed == 16)

print("\nwhat happened:")
for _, l in log do
	print(l)
end
if _G.failed then
	error("some checks failed")
end
