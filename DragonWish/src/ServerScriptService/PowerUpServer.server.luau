--[[
	PowerUpServer  (Script — lives in ServerScriptService)

	The referee for powering up. Players' computers tell it "I started charging", "my bar is at
	X", "I'm full — transform", "cancel" and "power down"; it checks those make sense and sets
	attributes on the character that every player's screen reads to draw the aura, pose and
	hair:
	  Form        "Base" or "SSJ"
	  PowerState  "Idle", "Charging" or "Bursting" (the moment of transformation)
	  Charge      0..1, how full the power bar is
	  AuraWind    0..1, how hard the aura blows the hair and belt upward
	It also swaps the visible hair (base <-> Super Saiyan) and stops you walking while charging.
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

local info = {} -- [character] = { Started, LastUpdate, WalkSpeed, JumpPower, JumpHeight }

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
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

local function idleWind(character: Model): number
	return character:GetAttribute("Form") == "SSJ" and PowerConfig.SSJCalmWind or 0
end

local function stopCharging(character: Model)
	character:SetAttribute("PowerState", "Idle")
	character:SetAttribute("Charge", 0)
	character:SetAttribute("AuraWind", idleWind(character))
	lockMovement(character, false)
end

local function burst(character: Model)
	character:SetAttribute("PowerState", "Bursting")
	character:SetAttribute("Charge", 1)
	character:SetAttribute("AuraWind", 1)
	applyForm(character, "SSJ")
	task.delay(PowerConfig.BurstTime, function()
		if character.Parent and character:GetAttribute("PowerState") == "Bursting" then
			stopCharging(character)
		end
	end)
end

remote.OnServerEvent:Connect(function(player: Player, action, value)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return
	end
	local state = character:GetAttribute("PowerState") or "Idle"
	local form = character:GetAttribute("Form") or "Base"
	local now = os.clock()
	info[character] = info[character] or {}
	local st = info[character]

	if action == "Start" then
		if state == "Idle" and form == "Base" then
			st.Started, st.LastUpdate = now, now
			character:SetAttribute("PowerState", "Charging")
			character:SetAttribute("Charge", 0)
			lockMovement(character, true)
		end
	elseif action == "Charge" then
		if state == "Charging" and typeof(value) == "number" and value == value then
			local previous = character:GetAttribute("Charge") or 0
			local allowedRise = PowerConfig.ChargePerTap * MAX_TAPS_PER_SECOND * (now - (st.LastUpdate or now)) + 0.02
			local charge = math.clamp(math.min(value, previous + allowedRise), 0, 1)
			st.LastUpdate = now
			character:SetAttribute("Charge", math.floor(charge * 100 + 0.5) / 100)
			character:SetAttribute("AuraWind", smoothstep(PowerConfig.HairStart, 1, charge))
		end
	elseif action == "Transform" then
		local charge = character:GetAttribute("Charge") or 0
		if state == "Charging" and charge >= 0.95 and now - (st.Started or now) >= PowerConfig.MinChargeTime - 0.2 then
			burst(character)
		end
	elseif action == "Cancel" then
		if state == "Charging" then
			stopCharging(character)
		end
	elseif action == "PowerDown" then
		if state == "Idle" and form == "SSJ" then
			applyForm(character, "Base")
			character:SetAttribute("AuraWind", 0)
		end
	end
end)

-- a charging player who stopped talking (closed the game, lagged out) is cancelled
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for character, st in info do
		if not character.Parent then
			info[character] = nil
		elseif character:GetAttribute("PowerState") == "Charging" and now - (st.LastUpdate or now) > STALE_SECONDS then
			stopCharging(character)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		info[player.Character] = nil
	end
end)
