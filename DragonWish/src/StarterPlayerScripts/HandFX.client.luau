--[[
	HandFX  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Moves everyone's fingers on this player's screen (the finger pieces CharacterSetup puts on
	the hands from LeftFingers_Rigged.fbx and RightFingers_Rigged.fbx):
	  standing     relaxed: each finger a little curled (the pinky most, the index least), the
	               thumb hanging forward. Every few seconds one hand fidgets, bored: a quick
	               open-close-open-close, drumming along the fingers, rubbing the thumb on the
	               index finger, a big stretch, or squeezing a fist and shaking it loose
	  moving       relaxed, the fingers trailing behind the hand as the arms swing
	  powering up  fists, squeezing harder and trembling as the bar fills
	  transforming fists ... then the left hand rests flat on the inside of the right elbow and
	               swipes out into a point for "YOU'RE FINISHED!" (PowerFX moves the arm)
	  Super Saiyan fists while the golden aura burns, loosening as you calm down
	  Kaioken      fists, straining harder the higher you push it
	  exhausted    limp
	Every finger joint moves on a spring, so fingers overshoot a touch and settle instead of
	snapping, and each finger starts a moment after its neighbour.
	Poses and fidgets: the POSES and FIDGETS tables below (degrees).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local FINGERS = { "Thumb", "Index", "Middle", "Ring", "Pinky" }
local VIEW_DISTANCE = 120 -- fingers further than this from the camera aren't animated
local rng = Random.new()

----------------------------------------------------------------------------------------
-- poses: for each finger { knuckle bend, middle-joint bend, spread } in degrees.
-- Bend: + curls toward the palm. Spread: + swings the finger toward the front.
----------------------------------------------------------------------------------------
local POSES = {
	Relaxed = { Thumb = { 6, 6, 16 }, Index = { 12, 16, 0 }, Middle = { 15, 20, 0 }, Ring = { 18, 24, 0 }, Pinky = { 22, 28, 0 } },
	Loose = { Thumb = { 3, 4, 12 }, Index = { 8, 10, 0 }, Middle = { 10, 13, 0 }, Ring = { 12, 15, 0 }, Pinky = { 14, 18, 0 } },
	Open = { Thumb = { -4, 0, 10 }, Index = { -6, -2, 2 }, Middle = { -6, -2, 0 }, Ring = { -6, -2, -1 }, Pinky = { -6, -2, -2 } },
	Stretch = { Thumb = { -10, -4, 24 }, Index = { -16, -8, 9 }, Middle = { -16, -8, 3 }, Ring = { -16, -8, -3 }, Pinky = { -16, -8, -9 } },
	Fist = { Thumb = { 80, 30, 30 }, Index = { 50, 120, 0 }, Middle = { 52, 122, 0 }, Ring = { 54, 122, 0 }, Pinky = { 56, 120, 0 } },
	Tight = { Thumb = { 86, 36, 32 }, Index = { 56, 126, 0 }, Middle = { 58, 128, 0 }, Ring = { 60, 128, 0 }, Pinky = { 62, 126, 0 } },
	Claw = { Thumb = { 20, 30, 14 }, Index = { 25, 70, 0 }, Middle = { 28, 72, 0 }, Ring = { 30, 74, 0 }, Pinky = { 32, 72, 0 } },
	Point = { Thumb = { 78, 28, 28 }, Index = { -3, 0, 0 }, Middle = { 52, 122, 0 }, Ring = { 54, 122, 0 }, Pinky = { 56, 120, 0 } },
	Flat = { Thumb = { 4, 4, 12 }, Index = { 8, 10, 0 }, Middle = { 9, 12, 0 }, Ring = { 10, 13, 0 }, Pinky = { 12, 15, 0 } },
	Rub = { Thumb = { 38, 34, 26 }, Index = { 24, 40, 0 }, Middle = { 17, 22, 0 }, Ring = { 19, 25, 0 }, Pinky = { 23, 29, 0 } },
	Rub2 = { Thumb = { 30, 44, 18 }, Index = { 28, 46, 0 }, Middle = { 17, 22, 0 }, Ring = { 19, 25, 0 }, Pinky = { 23, 29, 0 } },
}

-- Idle fidgets: key poses over time (seconds). Order + Stagger: each finger runs a little behind
-- the one before it, from the pinky (or the index) along the hand. Shake: a strained tremble.
local FIDGETS = {
	Flex = { -- quick open, close, open, close
		Weight = 3, Order = "pinky", Stagger = 0.022,
		Keys = { { 0, "Relaxed" }, { 0.1, "Open" }, { 0.26, "Fist" }, { 0.38, "Open" }, { 0.54, "Fist" }, { 0.68, "Open" }, { 1.0, "Relaxed" } },
	},
	Drum = { -- drumming along the fingers, pinky to index, twice
		Weight = 2, Order = "pinky", Stagger = 0.075, KeepThumb = true,
		Keys = { { 0, "Relaxed" }, { 0.08, "Claw" }, { 0.2, "Relaxed" }, { 0.5, "Relaxed" }, { 0.58, "Claw" }, { 0.7, "Relaxed" } },
	},
	Rub = { -- rubbing the thumb against the side of the index finger
		Weight = 2, Order = "index", Stagger = 0,
		Keys = { { 0, "Relaxed" }, { 0.15, "Rub" }, { 0.3, "Rub2" }, { 0.45, "Rub" }, { 0.6, "Rub2" }, { 0.75, "Rub" }, { 1.05, "Relaxed" } },
	},
	Stretch = { -- fingers spread wide and straight, held, then let go
		Weight = 1.5, Order = "index", Stagger = 0.03, Shake = 0.6,
		Keys = { { 0, "Relaxed" }, { 0.22, "Stretch" }, { 0.75, "Stretch" }, { 1.1, "Relaxed" } },
	},
	Squeeze = { -- squeeze a tight fist, then shake it loose
		Weight = 1.5, Order = "pinky", Stagger = 0.03, Shake = 1,
		Keys = { { 0, "Relaxed" }, { 0.18, "Tight" }, { 0.6, "Tight" }, { 0.72, "Open" }, { 0.8, "Claw" }, { 0.9, "Open" }, { 1.2, "Relaxed" } },
	},
}
-- as a Super Saiyan the bored fidgets are tense ones
local SSJ_FIDGETS = {
	Clench = {
		Weight = 2, Order = "pinky", Stagger = 0.02, Shake = 1.2,
		Keys = { { 0, "Fist" }, { 0.15, "Tight" }, { 0.75, "Tight" }, { 1.0, "Fist" } },
	},
	Crack = {
		Weight = 1, Order = "index", Stagger = 0.05,
		Keys = { { 0, "Fist" }, { 0.16, "Claw" }, { 0.36, "Claw" }, { 0.5, "Tight" }, { 0.8, "Fist" } },
	},
}
local ORDER = {
	pinky = { Pinky = 0, Ring = 1, Middle = 2, Index = 3, Thumb = 4 },
	index = { Index = 0, Middle = 1, Ring = 2, Pinky = 3, Thumb = 0.5 },
}

-- springs: how fast each joint follows its target, and how much it overshoots
local OMEGA = { Thumb = 22, Index = 30, Middle = 29, Ring = 28, Pinky = 27 }
local DAMPING = 0.55 -- 1 = no overshoot, lower = more bounce
local LAG = 3 -- how much the fingers trail behind when the hand speeds up or slows down

----------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function mix(a, b, t: number)
	local out = {}
	for _, f in FINGERS do
		local pa, pb = a[f], b[f]
		out[f] = { pa[1] + (pb[1] - pa[1]) * t, pa[2] + (pb[2] - pa[2]) * t, pa[3] + (pb[3] - pa[3]) * t }
	end
	return out
end

-- one finger's angles from a fidget's key poses at time t
local function sampleKeys(keys, finger: string, t: number)
	if t <= keys[1][1] then
		return POSES[keys[1][2]][finger]
	end
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t < k1[1] then
			local x = smooth((t - k0[1]) / (k1[1] - k0[1]))
			local a, b = POSES[k0[2]][finger], POSES[k1[2]][finger]
			return { a[1] + (b[1] - a[1]) * x, a[2] + (b[2] - a[2]) * x, a[3] + (b[3] - a[3]) * x }
		end
	end
	return POSES[keys[#keys][2]][finger]
end

local function fidgetLength(fidget): number
	local last = fidget.Keys[#fidget.Keys][1]
	return last + (fidget.Stagger or 0) * 4
end

local function pick(set)
	local total = 0
	for _, f in set do
		total += f.Weight
	end
	local r = rng:NextNumber(0, total)
	local last
	for _, f in set do
		last = f
		r -= f.Weight
		if r <= 0 then
			return f
		end
	end
	return last
end

-- a bone's resting CFrame inside the MeshPart it lives in
local function restInMesh(bone: Bone, mesh: BasePart): CFrame?
	local cf = CFrame.identity
	local node: Instance? = bone
	while node and node ~= mesh do
		if not node:IsA("Bone") then
			return nil
		end
		cf = (node :: Bone).CFrame * cf
		node = node.Parent
	end
	return node == mesh and cf or nil
end

----------------------------------------------------------------------------------------
-- one hand: its bones, and the hand's sideways / front-back axes seen from each bone
----------------------------------------------------------------------------------------
local function setupHand(character: Model, side: string)
	local holder = character:FindFirstChild("DW_" .. side .. "Fingers")
	local mesh = holder and holder:FindFirstChild(side .. "Fingers")
	local hand = character:FindFirstChild(side .. "Hand")
	if not (mesh and mesh:IsA("BasePart") and hand and hand:IsA("BasePart")) then
		return nil
	end
	local prefix = side:sub(1, 1)
	-- the hand's axes inside the mesh (welded, so this never changes)
	local handToMesh = hand.CFrame:ToObjectSpace(mesh.CFrame).Rotation
	local xMesh = handToMesh:VectorToObjectSpace(Vector3.xAxis)
	local zMesh = handToMesh:VectorToObjectSpace(Vector3.zAxis)
	local fingers = {}
	for _, f in FINGERS do
		local b1 = mesh:FindFirstChild(prefix .. f .. "1", true)
		local b2 = mesh:FindFirstChild(prefix .. f .. "2", true)
		if not (b1 and b1:IsA("Bone") and b2 and b2:IsA("Bone")) then
			return nil
		end
		local r1, r2 = restInMesh(b1, mesh), restInMesh(b2, mesh)
		if not (r1 and r2) then
			return nil
		end
		-- which way the fingertip moves (along the hand's X) when the finger curls: the four
		-- fingers sit on the outer edge and curl inward, the thumb on the inner edge curls outward
		local outward = side == "Right" and 1 or -1
		local dir = (f == "Thumb") and outward or -outward
		fingers[f] = {
			B1 = b1,
			B2 = b2,
			X1 = r1.Rotation:VectorToObjectSpace(xMesh),
			Z1 = r1.Rotation:VectorToObjectSpace(zMesh),
			Z2 = r2.Rotation:VectorToObjectSpace(zMesh),
			Dir = dir,
			Angle = { 0, 0, 0 }, -- knuckle, middle, spread (radians)
			Speed = { 0, 0, 0 },
		}
	end
	return {
		Side = side,
		Mesh = mesh,
		Hand = hand,
		Fingers = fingers,
		Fidget = nil,
		FidgetAt = 0,
		NextFidget = os.clock() + rng:NextNumber(1.5, 5),
		LastPos = nil,
		LastVel = Vector3.zero,
	}
end

local rigs = {} -- [character] = { Left = hand, Right = hand, BurstAt, ... }

local function rigFor(character: Model)
	local rig = rigs[character]
	if rig and (rig.Left or rig.Right) and (not rig.Left or rig.Left.Mesh.Parent) and (not rig.Right or rig.Right.Mesh.Parent) then
		return rig
	end
	if rig and os.clock() < (rig.RetryAt or 0) then
		return rig
	end
	rig = rig or {}
	rig.Left = setupHand(character, "Left")
	rig.Right = setupHand(character, "Right")
	rig.RetryAt = os.clock() + 2 -- (no fingers yet: look again in a bit)
	rigs[character] = rig
	return rig
end

----------------------------------------------------------------------------------------
-- what each hand should be doing right now
----------------------------------------------------------------------------------------
local function startFidget(hand, set, now: number)
	hand.Fidget = pick(set)
	hand.FidgetAt = now
	hand.NextFidget = now + fidgetLength(hand.Fidget) + rng:NextNumber(2.5, 7)
end

-- target angles (degrees) for one hand, plus how much it trembles
local function target(character: Model, rig, hand, now: number, standing: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return POSES.Loose, 0
	end
	local state = character:GetAttribute("PowerState")
	local kaioken = character:GetAttribute("Kaioken") or 0
	if state == "Charging" then
		local charge = character:GetAttribute("Charge") or 0
		return mix(POSES.Fist, POSES.Tight, charge), 0.6 + 1.4 * charge
	elseif state == "Bursting" then
		local t = now - (rig.BurstAt or now)
		local pointAt = PowerConfig.PointAt
		if hand.Side == "Left" and pointAt and t >= pointAt then
			-- the "YOU'RE FINISHED!" point, in step with PowerFX's arm
			local p = t - pointAt
			if p < 0.62 then
				return mix(POSES.Fist, POSES.Flat, smooth(p / 0.24)), 0
			elseif p < 0.7 then
				return mix(POSES.Flat, POSES.Open, smooth((p - 0.62) / 0.08)), 0
			end
			return mix(POSES.Open, POSES.Point, smooth((p - 0.7) / 0.1)), 0
		end
		return POSES.Tight, t < (PowerConfig.ExplodeAt or 0) and 1.5 or 0.4
	elseif kaioken > 0 then
		return POSES.Tight, 0.4 + 0.35 * kaioken
	elseif character:GetAttribute("Exhausted") then
		return POSES.Loose, 0
	end
	local ssj = character:GetAttribute("Form") == "SSJ"
	local base = POSES.Relaxed
	if ssj then
		-- fists while the golden aura burns, loosening as you calm down
		local breeze = character:GetAttribute("Breeze") or 0
		base = mix(mix(POSES.Relaxed, POSES.Claw, 0.35), POSES.Fist, breeze)
	end
	if not standing then
		hand.Fidget = nil
		return base, 0
	end
	-- bored: now and then a fidget
	if not hand.Fidget and now >= hand.NextFidget then
		startFidget(hand, ssj and SSJ_FIDGETS or FIDGETS, now)
		-- sometimes the other hand joins in a moment later
		local other = hand.Side == "Left" and rig.Right or rig.Left
		if other and not other.Fidget and rng:NextNumber() < 0.3 then
			other.Fidget = hand.Fidget
			other.FidgetAt = now + 0.12
			other.NextFidget = hand.NextFidget + 0.3
		end
	end
	local fidget = hand.Fidget
	if fidget then
		local t = now - hand.FidgetAt
		if t > fidgetLength(fidget) then
			hand.Fidget = nil
		elseif t >= 0 then
			local out = {}
			local order = ORDER[fidget.Order] or ORDER.pinky
			for _, f in FINGERS do
				if f == "Thumb" and fidget.KeepThumb then
					out[f] = base[f]
				else
					out[f] = sampleKeys(fidget.Keys, f, t - order[f] * (fidget.Stagger or 0))
				end
			end
			local shake = 0
			if fidget.Shake then
				local len = fidget.Keys[#fidget.Keys][1]
				shake = fidget.Shake * smooth(t / (len * 0.25)) * (1 - smooth((t - len * 0.6) / (len * 0.25)))
			end
			return out, shake
		end
	end
	return base, 0
end

----------------------------------------------------------------------------------------
-- every frame, after the character's animations have played
----------------------------------------------------------------------------------------
local function stepHand(character: Model, rig, hand, now: number, dt: number, standing: boolean)
	-- how the hand is speeding up or slowing down, in its own axes (the fingers trail behind)
	local bottom = hand.Hand.CFrame * Vector3.new(0, -0.2, 0)
	local accel = Vector3.zero
	if hand.LastPos and dt > 0 then
		local vel = (bottom - hand.LastPos) / dt
		if vel.Magnitude > 60 then -- teleported or respawned: no kick
			vel = Vector3.zero
			hand.LastVel = Vector3.zero
		end
		accel = hand.Hand.CFrame:VectorToObjectSpace((vel - hand.LastVel) / dt)
		if accel.Magnitude > 300 then
			accel = accel.Unit * 300
		end
		hand.LastVel = vel
	end
	hand.LastPos = bottom

	local goal, shake = target(character, rig, hand, now, standing)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for i, f in FINGERS do
		local finger = hand.Fingers[f]
		local g = goal[f]
		local w = OMEGA[f]
		local k, c = w * w, 2 * DAMPING * w
		local tremble = shake > 0 and math.rad(3) * shake * math.sin(now * 53 + i * 1.7) or 0
		local targets = { math.rad(g[1]) + tremble, math.rad(g[2]) + tremble * 0.7, math.rad(g[3]) }
		-- trailing: sideways speeding-up bends the finger back, front-back speeding-up fans it
		local push = { -finger.Dir * LAG * accel.X, -finger.Dir * LAG * 0.6 * accel.X, LAG * 0.5 * accel.Z }
		for _ = 1, steps do
			for j = 1, 3 do
				local a = k * (targets[j] - finger.Angle[j]) - c * finger.Speed[j] + push[j]
				finger.Speed[j] += a * h
				finger.Angle[j] += finger.Speed[j] * h
			end
		end
		finger.B1.Transform = CFrame.fromAxisAngle(finger.X1, finger.Angle[3]) * CFrame.fromAxisAngle(finger.Z1, finger.Dir * finger.Angle[1])
		finger.B2.Transform = CFrame.fromAxisAngle(finger.Z2, finger.Dir * finger.Angle[2])
	end
end

local okPre, preRender = pcall(function()
	return RunService.PreRender
end)
local renderSignal = (okPre and preRender) or RunService.RenderStepped
local lastColour = 0

renderSignal:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local seen = {}
	local recolour = now - lastColour > 1.5
	if recolour then
		lastColour = now
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (not camPos or (root.Position - camPos).Magnitude < VIEW_DISTANCE) then
			seen[character] = true
			local rig = rigFor(character)
			-- when the transformation started (for the point)
			if character:GetAttribute("PowerState") == "Bursting" then
				rig.BurstAt = rig.BurstAt or now
			else
				rig.BurstAt = nil
			end
			local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
			local standing = flat.Magnitude < 1.5
			for _, hand in { rig.Left, rig.Right } do
				if hand and hand.Mesh.Parent then
					stepHand(character, rig, hand, now, dt, standing)
					if recolour and hand.Mesh:GetAttribute("KeepColour") ~= true then
						hand.Mesh.Color = hand.Hand.Color -- (skin colour changes follow the hand)
					end
				end
			end
		end
	end
	for character in rigs do
		if not seen[character] and not character.Parent then
			rigs[character] = nil
		end
	end
end)
