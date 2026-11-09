--[[
	PowerUpServer  (Script — lives in ServerScriptService)

	The referee for powering up. Players' computers tell it "I started charging", "my bar is at
	X", "I'm full — transform", "cancel" and "power down"; it checks those make sense and sets
	attributes on the character that every player's screen reads to draw the aura, pose, hair
	and HUD:
	  Form        "Base" or "SSJ"
	  PowerState  "Idle", "Charging" or "Bursting" (the transformation, cutscene included)
	  Charge      0..1, how full the power bar is
	  AuraWind    0..1, how hard the aura blows the hair and belt upward
	  Breeze      0..1, the Super Saiyan glow: the SSJ hair's breeze and the golden aura. 1 when
	              you transform, fading to 0 when you calm down (PowerConfig.SSJCalmAfter)
	  Ki          0..KiMax, shown on the HUD: refills slowly, and charging fills it up
	It also swaps the visible hair (base <-> Super Saiyan) and stops you walking while charging
	and transforming.
	Settings: ReplicatedStorage > PowerConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local remote = ReplicatedStorage:FindFirstChild("PowerUp")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "PowerUp"
	remote.Parent = ReplicatedStorage
end

local MAX_TAPS_PER_SECOND = 16 -- nobody taps faster than this, so the bar can't rise faster either
local STALE_SECONDS = 4 -- a charging player who goes quiet this long is cancelled
local KI_STEP = 0.25 -- seconds between ki refills

local info = {} -- [character] = { Started, LastUpdate, WalkSpeed, JumpPower, JumpHeight, Token }

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function state(character: Model)
	info[character] = info[character] or {}
	return info[character]
end

-- shows the pieces that belong to a form and hides the rest
local function applyForm(character: Model, form: string)
	character:SetAttribute("Form", form)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local visibleIn = d:GetAttribute("VisibleIn")
			if visibleIn and visibleIn ~= "Both" then
				d.Transparency = (visibleIn == form) and 0 or 1
			end
		end
	end
end

local function lockMovement(character: Model, lock: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local st = info[character]
	if not humanoid or not st or not PowerConfig.LockMovement then
		return
	end
	if lock then
		st.WalkSpeed = st.WalkSpeed or humanoid.WalkSpeed
		st.JumpPower = st.JumpPower or humanoid.JumpPower
		st.JumpHeight = st.JumpHeight or humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	else
		if st.WalkSpeed then
			humanoid.WalkSpeed = st.WalkSpeed
			humanoid.JumpPower = st.JumpPower
			humanoid.JumpHeight = st.JumpHeight
		end
		st.WalkSpeed, st.JumpPower, st.JumpHeight = nil, nil, nil
	end
end

-- the hair lift that stays on when you're not charging: only while the Super Saiyan glow is up
local function idleWind(character: Model): number
	if character:GetAttribute("Form") ~= "SSJ" then
		return 0
	end
	return PowerConfig.SSJCalmWind * (character:GetAttribute("Breeze") or 0)
end

local function stopCharging(character: Model)
	character:SetAttribute("PowerState", "Idle")
	character:SetAttribute("Charge", 0)
	character:SetAttribute("AuraWind", idleWind(character))
	lockMovement(character, false)
end

-- A while after transforming, the hair stops flowing and the golden aura fades (both read the
-- Breeze attribute). token makes sure an old transformation never calms a newer one.
local function calmDown(character: Model, token: number)
	local st = state(character)
	local steps = math.max(1, math.floor(PowerConfig.SSJCalmTime / 0.1))
	for i = 1, steps do
		if not character.Parent or st.Token ~= token or character:GetAttribute("Form") ~= "SSJ" then
			return
		end
		if character:GetAttribute("PowerState") == "Idle" then
			local f = 1 - i / steps
			character:SetAttribute("Breeze", math.floor(f * 100 + 0.5) / 100)
			character:SetAttribute("AuraWind", PowerConfig.SSJCalmWind * f)
		end
		task.wait(0.1)
	end
end

local function burst(character: Model)
	local st = state(character)
	st.Token = (st.Token or 0) + 1
	local token = st.Token
	character:SetAttribute("PowerState", "Bursting")
	character:SetAttribute("Charge", 1)
	character:SetAttribute("AuraWind", 1)
	character:SetAttribute("Breeze", 1)
	character:SetAttribute("Ki", PowerConfig.KiMax)
	applyForm(character, "SSJ")
	task.delay(PowerConfig.BurstTime, function()
		if character.Parent and character:GetAttribute("PowerState") == "Bursting" then
			stopCharging(character)
		end
	end)
	task.delay(PowerConfig.BurstTime + PowerConfig.SSJCalmAfter, function()
		if character.Parent and st.Token == token then
			calmDown(character, token)
		end
	end)
end

remote.OnServerEvent:Connect(function(player: Player, action, value)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return
	end
	local powerState = character:GetAttribute("PowerState") or "Idle"
	local form = character:GetAttribute("Form") or "Base"
	local now = os.clock()
	local st = state(character)

	if action == "Start" then
		if powerState == "Idle" and form == "Base" then
			st.Started, st.LastUpdate = now, now
			character:SetAttribute("PowerState", "Charging")
			character:SetAttribute("Charge", 0)
			lockMovement(character, true)
		end
	elseif action == "Charge" then
		if powerState == "Charging" and typeof(value) == "number" and value == value then
			local previous = character:GetAttribute("Charge") or 0
			local allowedRise = PowerConfig.ChargePerTap * MAX_TAPS_PER_SECOND * (now - (st.LastUpdate or now)) + 0.02
			local charge = math.clamp(math.min(value, previous + allowedRise), 0, 1)
			st.LastUpdate = now
			character:SetAttribute("Charge", math.floor(charge * 100 + 0.5) / 100)
			character:SetAttribute("AuraWind", smoothstep(PowerConfig.HairStart, 1, charge))
			-- charging fills your ki
			local ki = character:GetAttribute("Ki") or 0
			character:SetAttribute("Ki", math.max(ki, math.floor(charge * PowerConfig.KiMax)))
		end
	elseif action == "Transform" then
		local charge = character:GetAttribute("Charge") or 0
		if powerState == "Charging" and charge >= 0.95 and now - (st.Started or now) >= PowerConfig.MinChargeTime - 0.2 then
			burst(character)
		end
	elseif action == "Cancel" then
		if powerState == "Charging" then
			stopCharging(character)
		end
	elseif action == "PowerDown" then
		if powerState == "Idle" and form == "SSJ" then
			st.Token = (st.Token or 0) + 1 -- cancels a pending calm-down
			applyForm(character, "Base")
			character:SetAttribute("AuraWind", 0)
			character:SetAttribute("Breeze", 0)
		end
	end
end)

-- a charging player who stopped talking (closed the game, lagged out) is cancelled; and ki
-- slowly refills
local kiClock = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for character, st in info do
		if not character.Parent then
			info[character] = nil
		elseif character:GetAttribute("PowerState") == "Charging" and now - (st.LastUpdate or now) > STALE_SECONDS then
			stopCharging(character)
		end
	end
	kiClock += dt
	if kiClock >= KI_STEP then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local ki = character and character:GetAttribute("Ki")
			if ki and ki < PowerConfig.KiMax and character:GetAttribute("PowerState") ~= "Charging" then
				character:SetAttribute("Ki", math.min(PowerConfig.KiMax, ki + PowerConfig.KiRegen * kiClock))
			end
		end
		kiClock = 0
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		info[player.Character] = nil
	end
end)
