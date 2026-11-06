--[[
	PowerFX  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Draws powering up for EVERY character on this player's screen, from the attributes
	PowerUpServer sets (so everyone sees everyone's aura):
	  * the ready stance while charging (knees bent, fists clenched, trembling with power) and a
	    head-back, arms-out "scream" pose at the moment of transformation,
	  * the aura — flames licking upward around the body that get bigger, faster and denser
	    the fuller the power bar is; white for base form, gold for Super Saiyan,
	  * a glow that lights up the surroundings, dust blasting off the ground and rocks lifting
	    up at high power,
	  * the transformation burst: a flash, a shockwave ring across the ground and a big spray.
	The hair and belt being blown upward is HairPhysics reacting to the AuraWind attribute.
	Settings: ReplicatedStorage > PowerConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local ROCKS = 8
local S = PowerConfig.AuraSize

local folder = Instance.new("Folder")
folder.Name = "PowerFX"
folder.Parent = Workspace

----------------------------------------------------------------------------------------
-- the stance (rotations of each R15 joint; characters face -Z, so +X rotation = forward)
----------------------------------------------------------------------------------------
local STANCE = {
	Root = CFrame.new(0, -0.18, 0),
	Waist = CFrame.Angles(-0.14, 0, 0), -- hunched slightly forward, straining
	Neck = CFrame.Angles(0.08, 0, 0),
	LeftShoulder = CFrame.Angles(-0.25, 0, -0.38), -- upper arms back and out
	RightShoulder = CFrame.Angles(-0.25, 0, 0.38),
	LeftElbow = CFrame.Angles(1.05, 0, 0), -- forearms up, fists clenched by the hips
	RightElbow = CFrame.Angles(1.05, 0, 0),
	LeftWrist = CFrame.Angles(0.15, 0, 0),
	RightWrist = CFrame.Angles(0.15, 0, 0),
	LeftHip = CFrame.Angles(0.32, 0, -0.28), -- feet apart, knees bent
	RightHip = CFrame.Angles(0.32, 0, 0.28),
	LeftKnee = CFrame.Angles(-0.6, 0, 0),
	RightKnee = CFrame.Angles(-0.6, 0, 0),
	LeftAnkle = CFrame.Angles(0.28, 0, 0.1),
	RightAnkle = CFrame.Angles(0.28, 0, -0.1),
}
local SCREAM = { -- the moment of transformation: chest out, head back, arms flung wide
	Root = CFrame.new(0, -0.1, 0),
	Waist = CFrame.Angles(0.28, 0, 0),
	Neck = CFrame.Angles(0.45, 0, 0),
	LeftShoulder = CFrame.Angles(0.15, 0, -1.25),
	RightShoulder = CFrame.Angles(0.15, 0, 1.25),
	LeftElbow = CFrame.Angles(0.35, 0, 0),
	RightElbow = CFrame.Angles(0.35, 0, 0),
	LeftWrist = CFrame.identity,
	RightWrist = CFrame.identity,
	LeftHip = CFrame.Angles(0.25, 0, -0.32),
	RightHip = CFrame.Angles(0.25, 0, 0.32),
	LeftKnee = CFrame.Angles(-0.45, 0, 0),
	RightKnee = CFrame.Angles(-0.45, 0, 0),
	LeftAnkle = CFrame.Angles(0.2, 0, 0.1),
	RightAnkle = CFrame.Angles(0.2, 0, -0.1),
}

----------------------------------------------------------------------------------------
-- building one character's effects
----------------------------------------------------------------------------------------
local function fxPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = folder
	return p
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function newFX(character: Model)
	local fx = { Character = character, Intensity = 0, Pose = 0, Scream = 0, Color = PowerConfig.BaseAuraColor }
	fx.Aura = fxPart("Aura", Vector3.new(3.2, 5.6, 3.2) * S)
	fx.Flame = emitter(fx.Aura, {
		Texture = FIRE,
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.35, 0.65),
		Acceleration = Vector3.new(0, 14, 0),
		Drag = 0.5,
		SpreadAngle = Vector2.new(6, 6),
		Rotation = NumberRange.new(-30, 30),
		RotSpeed = NumberRange.new(-90, 90),
		Squash = NumberSequence.new(-0.6),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.2, 0.25),
			NumberSequenceKeypoint.new(0.75, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	fx.Haze = emitter(fx.Aura, {
		Texture = SMOKE,
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(20, 20),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) }),
	})
	fx.Sparks = emitter(fx.Aura, {
		Texture = SPARK,
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(30, 30),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * S), NumberSequenceKeypoint.new(1, 0) }),
	})
	fx.Light = Instance.new("PointLight")
	fx.Light.Shadows = false
	fx.Light.Brightness = 0
	fx.Light.Parent = fx.Aura

	fx.Ground = fxPart("GroundFX", Vector3.new(1, 0.2, 1))
	fx.Dust = emitter(fx.Ground, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(190, 180, 165)),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(88, 88),
		Speed = NumberRange.new(18, 28),
		Drag = 3,
		Acceleration = Vector3.new(0, 3, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * S), NumberSequenceKeypoint.new(1, 5 * S) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		LightInfluence = 1,
	})

	fx.Rocks = {}
	local rng = Random.new()
	for i = 1, ROCKS do
		local rock = fxPart("Rock", Vector3.new(1, 1, 1) * rng:NextNumber(0.35, 0.8) * S)
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(110, 104, 98)
		table.insert(fx.Rocks, {
			Part = rock,
			Angle = (i / ROCKS) * math.pi * 2 + rng:NextNumber(-0.3, 0.3),
			Radius = rng:NextNumber(3, 5.5) * S,
			Top = rng:NextNumber(1.2, 3.8),
			Height = 0,
			Spin = rng:NextNumber(-1.5, 1.5),
			Bob = rng:NextNumber(0, 6),
		})
	end

	-- the stance needs the character's joints (looked up once)
	fx.Motors = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and STANCE[d.Name] then
			fx.Motors[d.Name] = d
		end
	end
	fx.LastWritten = {}
	return fx
end

-- true if two joint angles are the same (reading one back can lose a hair of precision)
local function sameFrame(a: CFrame, b: CFrame): boolean
	local ca = { a:GetComponents() }
	local cb = { b:GetComponents() }
	for k = 1, 12 do
		if math.abs(ca[k] - cb[k]) > 1e-4 then
			return false
		end
	end
	return true
end

local function destroyFX(fx)
	fx.Aura:Destroy()
	fx.Ground:Destroy()
	for _, r in fx.Rocks do
		r.Part:Destroy()
	end
	for name, motor in fx.Motors do
		if motor.Parent and fx.LastWritten[name] and sameFrame(motor.Transform, fx.LastWritten[name]) then
			motor.Transform = CFrame.identity
		end
	end
end

----------------------------------------------------------------------------------------
-- the transformation burst
----------------------------------------------------------------------------------------
local function playBurst(fx, root: BasePart, groundY: number)
	fx.Flame:Emit(120)
	fx.Sparks:Emit(80)
	fx.Dust:Emit(60)
	fx.Light.Brightness = 14
	local color = PowerConfig.SSJAuraColor
	local ring = fxPart("Shockwave", Vector3.new(0.3, 2, 2))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.CFrame = CFrame.new(root.Position.X, groundY + 0.15, root.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 36 * S, 36 * S),
		Transparency = 1,
	}):Play()
	local ball = fxPart("Flash", Vector3.new(2, 2, 2))
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.new(1, 1, 0.9)
	ball.Transparency = 0.1
	ball.CFrame = root.CFrame
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(16, 16, 16) * S,
		Transparency = 1,
	}):Play()
	task.delay(0.9, function()
		ring:Destroy()
		ball:Destroy()
	end)
	fx.Scream = 1
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local active = {} -- [character] = fx
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function targetIntensity(character: Model): number
	local state = character:GetAttribute("PowerState")
	if state == "Charging" then
		local c = character:GetAttribute("Charge") or 0
		return c >= PowerConfig.AuraStart and math.max(c, 0.12) or 0
	elseif state == "Bursting" then
		return 1.3
	elseif character:GetAttribute("Form") == "SSJ" then
		return PowerConfig.SSJIdleAura
	end
	return 0
end

local function characters()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local moveParts, moveFrames = {}, {}

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	table.clear(moveParts)
	table.clear(moveFrames)
	local seen = {}
	local finished = {}
	local filter = characters()
	table.insert(filter, folder)
	groundParams.FilterDescendantsInstances = filter
	local now = os.clock()

	for _, character in characters() do
		seen[character] = true
		local root = character:FindFirstChild("HumanoidRootPart")
		local want = targetIntensity(character)
		local state = character:GetAttribute("PowerState")
		local fx = active[character]
		if not fx and (want > 0 or state == "Charging") and root then
			fx = newFX(character)
			active[character] = fx
		end
		if fx and root then
			-- smooth ramps: fast up, slower down
			local rate = want > fx.Intensity and 5 or 2
			fx.Intensity += (want - fx.Intensity) * (1 - math.exp(-dt * rate))
			local i = fx.Intensity
			local gold = character:GetAttribute("Form") == "SSJ" or state == "Bursting"
			local targetColor = gold and PowerConfig.SSJAuraColor or PowerConfig.BaseAuraColor
			fx.Color = fx.Color:Lerp(targetColor, 1 - math.exp(-dt * 6))

			if state == "Bursting" and not fx.Burst then
				fx.Burst = true
				local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
				playBurst(fx, root, hit and hit.Position.Y or root.Position.Y - 3)
			elseif state ~= "Bursting" then
				fx.Burst = false
			end

			-- aura
			local visible = i > 0.02
			local sizeMul = (0.8 + 0.9 * i) * S
			fx.Aura.Size = Vector3.new(3 * sizeMul, (4.8 + 2.4 * i) * S, 3 * sizeMul)
			table.insert(moveParts, fx.Aura)
			table.insert(moveFrames, root.CFrame * CFrame.new(0, -0.4 + 0.5 * i, 0))
			fx.Flame.Rate = visible and (30 + 300 * i) or 0
			fx.Flame.Speed = NumberRange.new(4 + 11 * i, 8 + 18 * i)
			fx.Flame.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.9 * sizeMul),
				NumberSequenceKeypoint.new(0.4, 1.7 * sizeMul),
				NumberSequenceKeypoint.new(1, 0.15),
			})
			fx.Flame.Color = ColorSequence.new(Color3.new(1, 1, 1), fx.Color)
			fx.Haze.Rate = visible and (6 + 20 * i) or 0
			fx.Haze.Size = NumberSequence.new(4 * sizeMul)
			fx.Haze.Color = ColorSequence.new(fx.Color)
			fx.Sparks.Rate = i > 0.5 and 60 * (i - 0.5) or 0
			fx.Sparks.Color = ColorSequence.new(fx.Color)
			fx.Light.Color = fx.Color
			fx.Light.Range = visible and (6 + 14 * i) or 0
			fx.Light.Brightness += ((visible and (0.8 + 4 * i) or 0) - fx.Light.Brightness) * (1 - math.exp(-dt * 6))

			-- ground: dust and lifting rocks (only if there's ground close below)
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), groundParams)
			local groundY = hit and hit.Position.Y
			if groundY then
				table.insert(moveParts, fx.Ground)
				table.insert(moveFrames, CFrame.new(root.Position.X, groundY + 0.2, root.Position.Z))
			end
			fx.Dust.Rate = (groundY and i > 0.55) and 40 * (i - 0.55) / 0.45 or 0
			for _, rock in fx.Rocks do
				local lift = (groundY and i > 0.7) and rock.Top * math.clamp((i - 0.7) / 0.3, 0, 1) or 0
				if lift > rock.Height then
					rock.Height += (lift - rock.Height) * (1 - math.exp(-dt * 1.5))
				else
					rock.Height = math.max(lift, rock.Height - dt * 6) -- falls back down
				end
				if rock.Height > 0.02 and groundY then
					rock.Part.Transparency = 0
					rock.Angle += dt * 0.25
					local pos = root.Position + Vector3.new(math.cos(rock.Angle), 0, math.sin(rock.Angle)) * rock.Radius
					local bob = math.sin(now * 2 + rock.Bob) * 0.15 * math.min(1, rock.Height)
					table.insert(moveParts, rock.Part)
					table.insert(moveFrames, CFrame.new(pos.X, groundY + rock.Part.Size.Y / 2 + rock.Height + bob, pos.Z)
						* CFrame.Angles(now * rock.Spin, now * rock.Spin * 0.7, 0))
				else
					rock.Part.Transparency = 1
				end
			end

			-- stance blending
			local wantPose = (state == "Charging" or state == "Bursting") and 1 or 0
			fx.Pose += (wantPose - fx.Pose) * (1 - math.exp(-dt * 7))
			fx.Scream = (state == "Bursting") and math.max(fx.Scream - dt * 0.6, 0) or math.max(fx.Scream - dt * 3, 0)
			fx.Tremble = i

			-- tidy up once fully calm
			if want <= 0 and fx.Intensity < 0.01 and fx.Pose < 0.01 and state ~= "Charging" then
				table.insert(finished, fx)
				active[character] = nil
			end
		end
	end
	for character, fx in active do
		if not seen[character] or not character.Parent then
			table.insert(finished, fx)
			active[character] = nil
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- removed only after this frame's moves, so nothing moves a part that's already gone
	for _, fx in finished do
		destroyFX(fx)
	end
end)

-- The pose goes on after Roblox has played the character's animations for this frame, blended
-- with them by how far into the stance we are.
RunService.Stepped:Connect(function()
	local t = os.clock()
	for _, fx in active do
		if fx.Pose > 0.001 then
			local w = math.min(fx.Pose, 1)
			local tremble = (fx.Tremble or 0) * 0.025
			for name, motor in fx.Motors do
				if motor.Parent then
					local current = motor.Transform
					-- if the animator didn't touch this joint since our last write, blend from rest
					if fx.LastWritten[name] and sameFrame(current, fx.LastWritten[name]) then
						current = CFrame.identity
					end
					local pose = STANCE[name]:Lerp(SCREAM[name], fx.Scream)
					if tremble > 0 and (name == "Waist" or name == "Neck" or name == "Root") then
						pose *= CFrame.Angles(math.sin(t * 41) * tremble, math.sin(t * 37) * tremble, math.sin(t * 29) * tremble)
					end
					local final = current:Lerp(pose, w)
					motor.Transform = final
					fx.LastWritten[name] = final
				end
			end
		else
			table.clear(fx.LastWritten)
		end
	end
end)
