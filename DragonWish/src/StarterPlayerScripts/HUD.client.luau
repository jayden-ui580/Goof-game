--[[
	HUD  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Your Dragon Ball-style screen:
	  top left   your face inside a glossy 4-star Dragon Ball (a live 3D portrait), your name and
	             form, an HP bar (a red trail shows damage you just took) and a Ki gauge in five
	             cells (blue in base form, gold as a Super Saiyan)
	  below it   a Scouter lens reading your POWER LEVEL: it scrambles and counts up as you power
	             up ... and warns you when it's over 9000
	  top right  a Dragon Radar: a sweeping green screen with a blip for every player nearby
	             (up on the radar = the way your camera faces)
	It shrinks to fit phones, and hides during the transformation cutscene.
	Numbers: ReplicatedStorage > PowerConfig (KiMax, BasePowerLevel, SSJMultiplier, RadarRange).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local player = Players.LocalPlayer
local rng = Random.new()

local BASE_ACCENT = Color3.fromRGB(90, 200, 255)
local SSJ_ACCENT = Color3.fromRGB(255, 205, 60)
local DARK = Color3.fromRGB(10, 13, 28)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local KI_CELLS = 5
local BLIPS = 12
local RADAR_SCREEN = 128 -- pixels across the radar's green screen

-- our own HP bar replaces Roblox's
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function round(parent: Instance, radius: UDim?)
	return new("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = parent:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number)
	return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation }, parent)
end

local function text(parent: Instance, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, nil)
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

----------------------------------------------------------------------------------------
-- building the screen
----------------------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "DragonHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
}, player:WaitForChild("PlayerGui"))

-- top left: the fighter plate (everything inside shrinks together on small screens)
local plate = new("Frame", {
	Name = "Plate",
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.fromOffset(410, 214),
	BackgroundTransparency = 1,
}, gui)
local plateScale = new("UIScale", {}, plate)

-- name banner
local banner = new("Frame", {
	Name = "Banner",
	Position = UDim2.fromOffset(92, 8),
	Size = UDim2.fromOffset(300, 42),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1,
}, plate)
round(banner, UDim.new(0, 6))
new("UIGradient", {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 0.7) }),
}, banner)
local bannerStroke = stroke(banner, BASE_ACCENT, 1.5, 0.35)
local nameLabel = text(banner, {
	Name = "Name",
	Position = UDim2.fromOffset(34, 2),
	Size = UDim2.new(1, -44, 0, 26),
	Font = Enum.Font.Bangers,
	Text = string.upper(player.DisplayName),
})
stroke(nameLabel, BLACK, 1.5)
local formLabel = text(banner, {
	Name = "Form",
	Position = UDim2.fromOffset(35, 27),
	Size = UDim2.new(1, -44, 0, 12),
	Font = Enum.Font.GothamBlack,
	Text = "SAIYAN  ·  BASE FORM",
	TextColor3 = BASE_ACCENT,
})

-- HP bar
local hpBack = new("Frame", {
	Name = "HP",
	Position = UDim2.fromOffset(126, 58),
	Size = UDim2.fromOffset(266, 20),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
}, plate)
round(hpBack, UDim.new(0, 4))
stroke(hpBack, BLACK, 2)
local hpTrail = new("Frame", {
	Name = "Trail",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 90, 60),
}, hpBack)
round(hpTrail, UDim.new(0, 4))
local hpFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
}, hpBack)
round(hpFill, UDim.new(0, 4))
local hpGradient = gradient(hpFill, Color3.fromRGB(215, 255, 95), Color3.fromRGB(60, 200, 70), 90)
local hpShine = new("Frame", {
	Name = "Shine",
	Position = UDim2.fromOffset(4, 3),
	Size = UDim2.new(1, -8, 0, 4),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.55,
}, hpFill)
round(hpShine, UDim.new(0, 2))
local hpTag = text(hpBack, {
	Name = "Label",
	Position = UDim2.fromOffset(8, 1),
	Size = UDim2.new(0, 30, 1, -2),
	Font = Enum.Font.Bangers,
	Text = "HP",
})
stroke(hpTag, BLACK, 1.5)
local hpValue = text(hpBack, {
	Name = "Value",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 3),
	Size = UDim2.new(0, 110, 1, -6),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "100 / 100",
})
stroke(hpValue, BLACK, 1.2)

-- Ki gauge: five cells
local kiFrame = new("Frame", {
	Name = "Ki",
	Position = UDim2.fromOffset(126, 85),
	Size = UDim2.fromOffset(266, 16),
	BackgroundTransparency = 1,
}, plate)
local kiFills, kiStrokes = {}, {}
local cellWidth = (266 - (KI_CELLS - 1) * 4) / KI_CELLS
for k = 1, KI_CELLS do
	local cell = new("Frame", {
		Name = "Cell" .. k,
		Position = UDim2.fromOffset((k - 1) * (cellWidth + 4), 0),
		Size = UDim2.fromOffset(cellWidth, 16),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
	}, kiFrame)
	round(cell, UDim.new(0, 3))
	kiStrokes[k] = stroke(cell, BLACK, 1.5)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = BASE_ACCENT,
	}, cell)
	round(fill, UDim.new(0, 3))
	gradient(fill, WHITE, Color3.fromRGB(200, 200, 200), 90)
	kiFills[k] = fill
end
local kiValue = text(plate, {
	Name = "KiValue",
	Position = UDim2.fromOffset(128, 104),
	Size = UDim2.fromOffset(200, 14),
	Font = Enum.Font.GothamBlack,
	Text = "KI  30 / 100",
	TextColor3 = BASE_ACCENT,
})
stroke(kiValue, BLACK, 1)

-- the Dragon Ball with your portrait (made after the bars so it sits on top of them)
local orb = new("Frame", {
	Name = "Orb",
	Size = UDim2.fromOffset(120, 120),
	BackgroundTransparency = 1,
}, plate)
local orbGlow = new("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 12, 1, 12),
	BackgroundColor3 = BASE_ACCENT,
	BackgroundTransparency = 0.7,
}, orb)
round(orbGlow)
local ball = new("Frame", {
	Name = "Ball",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
}, orb)
round(ball)
gradient(ball, Color3.fromRGB(255, 214, 110), Color3.fromRGB(232, 100, 18), 45)
stroke(ball, Color3.fromRGB(110, 45, 10), 2.5)
local portrait = new("ViewportFrame", {
	Name = "Portrait",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.7, 0.7),
	BackgroundColor3 = Color3.fromRGB(255, 196, 110),
	Ambient = Color3.fromRGB(175, 165, 150),
	LightColor = Color3.fromRGB(255, 245, 225),
	LightDirection = Vector3.new(-0.5, -1, -0.7),
}, ball)
round(portrait)
local gloss = new("Frame", {
	Name = "Gloss",
	Position = UDim2.fromScale(0.15, 0.09),
	Size = UDim2.fromScale(0.3, 0.16),
	Rotation = -28,
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.4,
}, ball)
round(gloss)
for k, angle in { 62, 82, 102, 122 } do -- four stars along the bottom of the ball
	local a = math.rad(angle)
	local star = text(ball, {
		Name = "Star" .. k,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + 0.41 * math.cos(a), 0.5 + 0.41 * math.sin(a)),
		Size = UDim2.fromOffset(19, 19),
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "★",
		TextColor3 = Color3.fromRGB(230, 30, 30),
	})
	stroke(star, Color3.fromRGB(90, 0, 0), 1)
end

-- the Scouter
local scouter = new("Frame", {
	Name = "Scouter",
	Position = UDim2.fromOffset(4, 138),
	Size = UDim2.fromOffset(222, 66),
	Rotation = -2,
	BackgroundColor3 = Color3.fromRGB(40, 255, 120),
	BackgroundTransparency = 0.8,
}, plate)
round(scouter, UDim.new(0, 8))
stroke(scouter, Color3.fromRGB(90, 255, 150), 2, 0.15)
for k = 1, 6 do -- scan lines
	new("Frame", {
		Name = "Scan" .. k,
		Position = UDim2.new(0, 6, 0, 6 + (k - 1) * 10),
		Size = UDim2.new(1, -12, 0, 1),
		BackgroundColor3 = Color3.fromRGB(150, 255, 180),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, scouter)
end
text(scouter, {
	Name = "Title",
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.fromOffset(150, 12),
	Font = Enum.Font.Code,
	Text = "POWER LEVEL",
	TextColor3 = Color3.fromRGB(170, 255, 190),
})
local powerValue = text(scouter, {
	Name = "Value",
	Position = UDim2.fromOffset(12, 19),
	Size = UDim2.new(1, -24, 0, 40),
	Font = Enum.Font.Sarpanch,
	Text = commas(PowerConfig.BasePowerLevel),
	TextColor3 = Color3.fromRGB(120, 255, 150),
})
stroke(powerValue, Color3.fromRGB(0, 60, 20), 1, 0.3)
local warn9000 = text(scouter, {
	Name = "Over9000",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.new(1, -10, 0, 34),
	Font = Enum.Font.Bangers,
	TextXAlignment = Enum.TextXAlignment.Center,
	Text = "IT'S OVER 9000!!",
	TextColor3 = Color3.fromRGB(255, 60, 40),
	Visible = false,
	ZIndex = 3,
})
stroke(warn9000, BLACK, 2)

-- top right: the Dragon Radar
local radar = new("Frame", {
	Name = "Radar",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 8),
	Size = UDim2.fromOffset(156, 180),
	BackgroundTransparency = 1,
}, gui)
local radarScale = new("UIScale", {}, radar)
local nub = new("Frame", {
	Name = "Button",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(32, 14),
	BackgroundColor3 = Color3.fromRGB(205, 210, 222),
}, radar)
round(nub, UDim.new(0, 4))
stroke(nub, Color3.fromRGB(35, 40, 58), 2)
local bezel = new("Frame", {
	Name = "Bezel",
	Position = UDim2.fromOffset(0, 9),
	Size = UDim2.fromOffset(156, 156),
	BackgroundColor3 = WHITE,
}, radar)
round(bezel)
gradient(bezel, Color3.fromRGB(250, 251, 255), Color3.fromRGB(165, 170, 186), 60)
stroke(bezel, Color3.fromRGB(35, 40, 58), 3)
local screen = new("Frame", {
	Name = "Screen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RADAR_SCREEN, RADAR_SCREEN),
	BackgroundColor3 = WHITE,
}, bezel)
round(screen)
gradient(screen, Color3.fromRGB(78, 178, 104), Color3.fromRGB(20, 66, 38), 45)
stroke(screen, Color3.fromRGB(18, 38, 24), 2)
do -- the grid, each line cut to fit inside the round screen
	local r = RADAR_SCREEN / 2
	for k = -2, 2 do
		local d = k * RADAR_SCREEN / 6
		local chord = 2 * math.sqrt(math.max(r * r - d * d, 0)) - 4
		for _, vertical in { false, true } do
			new("Frame", {
				Name = "Grid",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = vertical and UDim2.new(0.5, d, 0.5, 0) or UDim2.new(0.5, 0, 0.5, d),
				Size = vertical and UDim2.fromOffset(1, chord) or UDim2.fromOffset(chord, 1),
				BackgroundColor3 = Color3.fromRGB(140, 235, 160),
				BackgroundTransparency = k == 0 and 0.35 or 0.6,
				BorderSizePixel = 0,
			}, screen)
		end
	end
end
local sweep = new("Frame", {
	Name = "Sweep",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RADAR_SCREEN - 6, 2),
	BackgroundColor3 = Color3.fromRGB(190, 255, 205),
	BorderSizePixel = 0,
}, screen)
new("UIGradient", { -- only the half from the centre outward shows, brightest at the rim
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.51, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, sweep)
local blips = {}
for k = 1, BLIPS do
	local blip = new("Frame", {
		Name = "Blip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.fromRGB(255, 70, 50),
		Visible = false,
		ZIndex = 2,
	}, screen)
	round(blip)
	stroke(blip, Color3.fromRGB(90, 0, 0), 1)
	blips[k] = blip
end
local you = new("Frame", { -- you, in the middle
	Name = "You",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(9, 9),
	Rotation = 45,
	BackgroundColor3 = Color3.fromRGB(255, 225, 60),
	ZIndex = 3,
}, screen)
stroke(you, BLACK, 1)
local radarLabel = text(radar, {
	Name = "Label",
	Position = UDim2.fromOffset(0, 167),
	Size = UDim2.new(1, 0, 0, 13),
	Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Center,
	Text = "DRAGON RADAR  ·  " .. PowerConfig.RadarRange .. "m",
})
stroke(radarLabel, BLACK, 1.2)

----------------------------------------------------------------------------------------
-- the portrait: a copy of your character in the Dragon Ball, looking at your face
----------------------------------------------------------------------------------------
local portraitModel: Model? = nil
local portraitForm = nil

local function buildPortrait(character: Model)
	if portraitModel then
		portraitModel:Destroy()
		portraitModel = nil
	end
	local archivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or not copy then
		return
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			if CollectionService:HasTag(d, "HairPhysics") then
				CollectionService:RemoveTag(d, "HairPhysics") -- no hair physics for the copy
			end
		end
	end
	local head = copy:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		copy:Destroy()
		return
	end
	copy.Parent = portrait
	local camera = portrait:FindFirstChildOfClass("Camera") or new("Camera", { FieldOfView = 34 }, portrait)
	portrait.CurrentCamera = camera
	local h = head.CFrame
	local look = h.Position + h.UpVector * 0.55
	camera.CFrame = CFrame.lookAt(h * Vector3.new(0.35, 0.6, -4.6), look)
	portraitModel = copy
	portraitForm = character:GetAttribute("Form")
end

----------------------------------------------------------------------------------------
-- every frame
----------------------------------------------------------------------------------------
local shownHealth, trailHealth, trailWait = 1, 1, 0
local shownKi = 0
local shownPower = PowerConfig.BasePowerLevel
local scrambleUntil = 0
local over9000Until = 0
local lastTarget = PowerConfig.BasePowerLevel
local accent = BASE_ACCENT
local sweepAngle = 0
local character: Model? = nil

local function powerTarget(c: Model): number
	local base = PowerConfig.BasePowerLevel
	local state = c:GetAttribute("PowerState")
	if c:GetAttribute("Form") == "SSJ" then
		return base * PowerConfig.SSJMultiplier
	elseif state == "Charging" or state == "Bursting" then
		return base * (1 + PowerConfig.ChargePowerBoost * (c:GetAttribute("Charge") or 0))
	end
	return base
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local now = os.clock()
	local hidden = player:GetAttribute("InCutscene")
	gui.Enabled = not hidden
	if hidden then
		-- frozen while the cutscene plays, so afterwards you see the Scouter count your new
		-- power level up (and tell you it's over 9000)
		return
	end
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = math.clamp(viewport.Y / 720, 0.68, 1.15)
	plateScale.Scale = scale
	radarScale.Scale = scale

	character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then
		return
	end

	-- colours follow your form
	local ssj = character:GetAttribute("Form") == "SSJ"
	local target = ssj and SSJ_ACCENT or BASE_ACCENT
	accent = accent:Lerp(target, 1 - math.exp(-dt * 6))
	bannerStroke.Color = accent
	formLabel.TextColor3 = accent
	formLabel.Text = ssj and "SAIYAN  ·  SUPER SAIYAN" or "SAIYAN  ·  BASE FORM"
	orbGlow.BackgroundColor3 = accent
	kiValue.TextColor3 = accent
	if portraitForm ~= character:GetAttribute("Form") and character:FindFirstChild("Head") then
		-- re-take the portrait a moment after your form changes, once the new hair shows
		portraitForm = character:GetAttribute("Form")
		local c = character
		task.delay(0.4, function()
			if player.Character == c then
				buildPortrait(c)
			end
		end)
	end

	-- HP: the bar drops at once; the red trail behind it catches up a moment later
	local health = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	if health < shownHealth - 0.001 then
		trailWait = 0.5
	end
	shownHealth = health
	trailWait -= dt
	if trailWait <= 0 then
		trailHealth += (shownHealth - trailHealth) * (1 - math.exp(-dt * 4))
	end
	trailHealth = math.max(trailHealth, shownHealth)
	hpFill.Size = UDim2.fromScale(shownHealth, 1)
	hpTrail.Size = UDim2.fromScale(trailHealth, 1)
	if health < 0.3 then
		hpGradient.Color = ColorSequence.new(Color3.fromRGB(255, 150, 80), Color3.fromRGB(220, 40, 30))
	else
		hpGradient.Color = ColorSequence.new(Color3.fromRGB(215, 255, 95), Color3.fromRGB(60, 200, 70))
	end
	hpValue.Text = ("%d / %d"):format(math.ceil(humanoid.Health), math.floor(humanoid.MaxHealth))

	-- Ki: five cells filling one after another
	local ki = character:GetAttribute("Ki") or 0
	shownKi += (ki - shownKi) * (1 - math.exp(-dt * 8))
	local share = math.clamp(shownKi / PowerConfig.KiMax, 0, 1) * KI_CELLS
	for k = 1, KI_CELLS do
		local f = math.clamp(share - (k - 1), 0, 1)
		kiFills[k].Size = UDim2.fromScale(f, 1)
		kiFills[k].BackgroundColor3 = accent
		kiStrokes[k].Color = f >= 1 and accent or BLACK
	end
	kiValue.Text = ("KI  %d / %d"):format(math.floor(shownKi + 0.5), PowerConfig.KiMax)

	-- the Scouter: counts toward your power level, scrambling when it jumps
	local wanted = powerTarget(character)
	if wanted > lastTarget * 1.3 then
		scrambleUntil = now + 0.35
	end
	if lastTarget <= 9000 and wanted > 9000 then
		over9000Until = now + 1.6
	end
	lastTarget = wanted
	shownPower += (wanted - shownPower) * (1 - math.exp(-dt * 3))
	if now < scrambleUntil then
		powerValue.Text = commas(rng:NextInteger(10 ^ (#tostring(math.floor(wanted)) - 1), 10 ^ #tostring(math.floor(wanted)) - 1))
	else
		local wobble = (character:GetAttribute("PowerState") == "Idle") and 1 or (1 + rng:NextNumber(-0.01, 0.01))
		powerValue.Text = commas(shownPower * wobble)
	end
	local warning = now < over9000Until
	warn9000.Visible = warning and (math.floor(now * 8) % 2 == 0)
	powerValue.TextTransparency = warning and 0.75 or 0

	-- the Dragon Radar
	sweepAngle = (sweepAngle + dt * 150) % 360
	sweep.Rotation = sweepAngle
	local root = character:FindFirstChild("HumanoidRootPart")
	local used = 0
	if root and camera then
		local look = camera.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local turn = CFrame.Angles(0, -yaw, 0)
		for _, other in Players:GetPlayers() do
			local oc = other ~= player and other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if oroot and used < BLIPS then
				local rel = turn * (oroot.Position - root.Position)
				local flat = Vector2.new(rel.X, rel.Z) / PowerConfig.RadarRange
				if flat.Magnitude <= 1 then
					used += 1
					local blip = blips[used]
					blip.Visible = true
					blip.Position = UDim2.new(0.5, flat.X * (RADAR_SCREEN / 2 - 6), 0.5, flat.Y * (RADAR_SCREEN / 2 - 6))
					local pulse = 0.5 + 0.5 * math.sin(now * 6 + used)
					blip.Size = UDim2.fromOffset(7 + 3 * pulse, 7 + 3 * pulse)
					blip.BackgroundColor3 = (oc:GetAttribute("Form") == "SSJ") and SSJ_ACCENT or Color3.fromRGB(255, 70, 50)
				end
			end
		end
	end
	for k = used + 1, BLIPS do
		blips[k].Visible = false
	end
end)

player.CharacterAdded:Connect(function(c)
	portraitForm = nil
	task.delay(1, function()
		if player.Character == c then
			buildPortrait(c)
		end
	end)
end)
if player.Character then
	task.defer(buildPortrait, player.Character)
end
