--[[
	HUD  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Your screen, dressed like the Dragon Ball fighting games (the look itself lives in
	ReplicatedStorage > DragonUI: slanted slabs, ink / paper / gi orange, comic lettering):
	  top left   your face on a slanted gi-orange card: a live 3D portrait whose head pops out
	             over the top, a blue energy arc and a gi badge (気 "ki", or 超 "super" as a Super
	             Saiyan). Beside it, on a dark panel that fades out in halftone dots: your name,
	             your form, a yellow HP bar (a red chunk shows damage you just took) and your Ki
	             in five slanted pips, with a Dragon Ball whose stars count the full ones
	  under it   a Scouter readout of your POWER LEVEL: it scrambles and counts up as you power
	             up ... and warns you when it's over 9000
	  top right  a Dragon Radar: a sweeping green screen with a blip for every player nearby
	             (up on the radar = the way your camera faces)
	It slides in when you spawn and again when the transformation cutscene ends, shakes when you
	get hit, shrinks to fit phones, and hides during the cutscene.
	Numbers: ReplicatedStorage > PowerConfig (KiMax, BasePowerLevel, SSJMultiplier, RadarRange).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))
local DragonUI = require(ReplicatedStorage:WaitForChild("DragonUI"))

local new, Slab = DragonUI.new, DragonUI.Slab
local INK, PAPER, GI, GOLD = DragonUI.INK, DragonUI.PAPER, DragonUI.GI, DragonUI.GOLD
local K = DragonUI.SLANT

local player = Players.LocalPlayer
local rng = Random.new()

local KI_PIPS = 5
local BLIPS = 12
local RADAR_SCREEN = 124 -- pixels across the radar's green screen
local PLATE_X, PLATE_Y = 12, 4
local HEADROOM = 30 -- room above the plate for your head to pop out of the portrait card
local RADAR_MARGIN = 16
-- the portrait camera, from your head (head space: -Z is the way your face looks)
local PORTRAIT_FOV = 30
local PORTRAIT_EYE = Vector3.new(0.9, 0.3, -5.2)
local PORTRAIT_LOOK = Vector3.new(0, 0.35, 0) -- above your head's middle, so your hair fits

-- our own HP bar replaces Roblox's
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function label(parent: Instance, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = PAPER,
		TextScaled = true,
		Font = Enum.Font.Bangers,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function inkStroke(parent: Instance, thickness: number)
	return new("UIStroke", { Color = INK, Thickness = thickness }, parent)
end

local function circle(parent: Instance, props)
	local f = new("Frame", props, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end

-- the guide every row of the plate starts on: a slanted line, so the rows step out like the
-- slabs themselves (x where a row whose bottom is at y should start)
local function guideX(y: number): number
	return 140 + (70 - y) * K
end

----------------------------------------------------------------------------------------
-- the screen
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
	Position = UDim2.fromOffset(PLATE_X, PLATE_Y),
	Size = UDim2.fromOffset(500, 160),
	BackgroundTransparency = 1,
}, gui)
local plateScale = new("UIScale", {}, plate)

-- the dark panel behind your name and bars, fading out to the right in halftone dots
Slab.new(plate, "Panel", 92, 10, 356, 88, INK, { Transparency = 0.15, ZIndex = 1 })
DragonUI.Halftone(plate, "Dots", 406, 10, 7, 11, 8, 7.5, INK, { Transparency = 0.15, Lean = K, ZIndex = 1 })

-- the portrait card, its hard shadow and a two-tone shade
Slab.new(plate, "CardShadow", 7, 25, 134, 90, INK, { ZIndex = 3 })
local card = Slab.new(plate, "Card", 0, 18, 134, 90, GI, { ZIndex = 4 })
local cardShade = card:Band("Shade", 58, 90, DragonUI.GI_DARK)

-- the energy arc swooping round the bottom of the card: three rings inside each other (an ink
-- edge so it shows on a bright sky, the ki colour, a white-hot core); only their lower-left part
-- shows
local function ring(parent: Instance, name: string, grow: number, color: Color3, thickness: number)
	local r = circle(parent, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, grow, 1, grow),
		BackgroundTransparency = 1,
		ZIndex = 5,
	})
	local stroke = new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, r)
	new("UIGradient", {
		Rotation = 125,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.85, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, stroke)
	return r, stroke
end
local arcHolder = new("Frame", {
	Name = "Arc",
	Position = UDim2.fromOffset(-7, -3),
	Size = UDim2.fromOffset(138, 138),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, plate)
local arcInk = ring(arcHolder, "Edge", 0, INK, 9)
local arcKi, arcStroke = ring(arcInk, "Ki", 2, DragonUI.KI, 7)
ring(arcKi, "Core", 5, Color3.new(1, 1, 1), 1.5)

-- your live 3D portrait: no background, and taller than the card, so your head pops out
local portrait = new("ViewportFrame", {
	Name = "Portrait",
	Position = UDim2.fromOffset(12, -30),
	Size = UDim2.fromOffset(110, 138), -- its bottom edge is the card's
	BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(175, 165, 150),
	LightColor = Color3.fromRGB(255, 245, 225),
	LightDirection = Vector3.new(-0.5, -1, -0.7),
	ZIndex = 6,
}, plate)

-- the gi badge: a kanji in a white circle, like the one on Goku's gi
local badge = circle(plate, {
	Name = "Badge",
	Position = UDim2.fromOffset(78, 80),
	Size = UDim2.fromOffset(42, 42),
	BackgroundColor3 = PAPER,
	ZIndex = 7,
})
local badgeStroke = new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
local badgeKanji = label(badge, {
	Name = "Kanji",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromScale(0.74, 0.74),
	Font = Enum.Font.GothamBlack,
	Text = "気",
	TextColor3 = INK,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 8,
})

-- your name, and a tag with your form
local nameText = DragonUI.Lettering(plate, "Name", {
	Position = UDim2.fromOffset(guideX(42), 12),
	Size = UDim2.fromOffset(178, 30),
	Text = string.upper(player.DisplayName),
	ZIndex = 8,
})
local formTag = Slab.new(plate, "Form", 336, 17, 104, 20, PAPER, { ZIndex = 8 })
local formText = label(formTag.Holder, {
	Name = "Text",
	Position = UDim2.fromOffset(10, 2),
	Size = UDim2.new(1, -20, 1, -3),
	Text = "BASE FORM",
	TextColor3 = INK,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 9,
})

-- HP: paper outline, ink back, a red chunk for damage you just took, the yellow bar on top
local HP_X, HP_Y, HP_W, HP_H = guideX(70), 48, 272, 22
local hpEdge = Slab.around(plate, "HPEdge", HP_X, HP_Y, HP_W, HP_H, 3, PAPER, { ZIndex = 8 })
local hpBack = Slab.new(plate, "HP", HP_X, HP_Y, HP_W, HP_H, INK, { ZIndex = 9 })
local hpTrail = Slab.new(hpBack.Holder, "Trail", 0, 0, HP_W, HP_H, DragonUI.DAMAGE, { ZIndex = 10 })
local hpFill = Slab.new(hpBack.Holder, "Fill", 0, 0, HP_W, HP_H, DragonUI.HP, { ZIndex = 11 })
hpFill:Band("Shade", 14, HP_H, DragonUI.GI_DARK, { Transparency = 0.6, ZIndex = 12 })
hpFill:Band("Shine", 3, 6, PAPER, { Transparency = 0.25, ZIndex = 12 })
local hpGlint = Slab.new(hpFill.Holder, "Glint", 0, 0, 18, HP_H, PAPER, { Transparency = 0.35, ZIndex = 13 })
label(hpBack.Holder, {
	Name = "Label",
	Position = UDim2.fromOffset(14, 2),
	Size = UDim2.fromOffset(30, HP_H - 3),
	Text = "HP",
	ZIndex = 14,
})
local hpValue = label(hpBack.Holder, {
	Name = "Value",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 2),
	Size = UDim2.fromOffset(100, HP_H - 3),
	Text = "100",
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 14,
})
for _, l in hpBack.Holder:GetChildren() do
	if l:IsA("TextLabel") then
		inkStroke(l, 2)
	end
end

-- Ki: five slanted pips, and a Dragon Ball whose stars count the full ones
local PIP_Y, PIP_W, PIP_H, PIP_GAP = 78, 46, 12, 5
local pips = {}
for k = 1, KI_PIPS do
	local x = guideX(PIP_Y + PIP_H) + (k - 1) * (PIP_W + PIP_GAP)
	local edge = Slab.around(plate, "KiEdge" .. k, x, PIP_Y, PIP_W, PIP_H, 2, PAPER, { ZIndex = 7 })
	edge.Holder.Visible = false
	local back = Slab.new(plate, "Ki" .. k, x, PIP_Y, PIP_W, PIP_H, DragonUI.INK_SOFT, { ZIndex = 8 })
	local fill = Slab.new(back.Holder, "Fill", 0, 0, PIP_W, PIP_H, DragonUI.KI, { ZIndex = 9 })
	fill:Band("Shine", 2, 4, PAPER, { Transparency = 0.3, ZIndex = 10 })
	pips[k] = { Edge = edge, Back = back, Fill = fill, Full = false, PopAt = -1 }
end
local kiBall = DragonUI.Orb(plate, "KiBall", guideX(PIP_Y + PIP_H) + KI_PIPS * (PIP_W + PIP_GAP) + 2, PIP_Y - 14, 38, 9)

-- the Scouter: a dark green readout with scan lines
local SC_Y, SC_W, SC_H = 106, 226, 50
local SC_X = guideX(SC_Y + SC_H)
local scouter = new("Frame", {
	Name = "Scouter",
	Position = UDim2.fromOffset(SC_X, SC_Y),
	Size = UDim2.fromOffset(SC_W, SC_H),
	BackgroundTransparency = 1,
	ZIndex = 8,
}, plate)
Slab.around(scouter, "Edge", 0, 0, SC_W, SC_H, 3, INK, { ZIndex = 8 })
local glass = Slab.new(scouter, "Glass", 0, 0, SC_W, SC_H, Color3.fromRGB(22, 80, 46), { ZIndex = 9 })
for a = 4, SC_H - 2, 5 do
	glass:Band("Scan", a, a + 1, Color3.fromRGB(150, 255, 180), { Transparency = 0.86, ZIndex = 10 })
end
glass:Band("Glare", 0, 9, Color3.new(1, 1, 1), { Transparency = 0.88, ZIndex = 10 })
label(scouter, {
	Name = "Title",
	Position = UDim2.fromOffset(SC_H * K + 4, 4),
	Size = UDim2.fromOffset(110, 11),
	Font = Enum.Font.Code,
	Text = "POWER LEVEL",
	TextColor3 = Color3.fromRGB(170, 255, 190),
	ZIndex = 11,
})
local powerValue = label(scouter, {
	Name = "Value",
	Position = UDim2.fromOffset(SC_H * K - 2, 15),
	Size = UDim2.fromOffset(SC_W - SC_H * K - 14, 32),
	Font = Enum.Font.Sarpanch,
	Text = commas(PowerConfig.BasePowerLevel),
	TextColor3 = Color3.fromRGB(120, 255, 150),
	ZIndex = 11,
})
new("UIStroke", { Color = Color3.fromRGB(0, 60, 20), Thickness = 1, Transparency = 0.3 }, powerValue)
local warn9000 = DragonUI.Lettering(scouter, "Over9000", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.55, 0.56),
	Size = UDim2.fromOffset(SC_W - 20, 36),
	Rotation = -4,
	Text = "IT'S OVER 9000!!",
	Color = DragonUI.DAMAGE,
	BackColor = INK,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 12,
})
warn9000.Holder.Visible = false

-- top right: the Dragon Radar
local radar = new("Frame", {
	Name = "Radar",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -RADAR_MARGIN, 0, 6),
	Size = UDim2.fromOffset(164, 198),
	BackgroundTransparency = 1,
}, gui)
local radarScale = new("UIScale", {}, radar)
circle(radar, { -- hard shadow
	Name = "Shadow",
	Position = UDim2.fromOffset(9, 19),
	Size = UDim2.fromOffset(152, 152),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.2,
	ZIndex = 1,
})
local nub = new("Frame", {
	Name = "Button",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromOffset(76, 0),
	Size = UDim2.fromOffset(30, 14),
	BackgroundColor3 = PAPER,
	ZIndex = 2,
}, radar)
new("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, nub)
local bezel = circle(radar, {
	Name = "Bezel",
	Position = UDim2.fromOffset(0, 10),
	Size = UDim2.fromOffset(152, 152),
	BackgroundColor3 = Color3.new(1, 1, 1),
	ZIndex = 3,
})
new("UIGradient", { Color = ColorSequence.new(PAPER, Color3.fromRGB(176, 172, 164)), Rotation = 60 }, bezel)
new("UIStroke", { Color = INK, Thickness = 3.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bezel)
local screen = circle(bezel, {
	Name = "Screen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RADAR_SCREEN, RADAR_SCREEN),
	BackgroundColor3 = Color3.new(1, 1, 1),
	ZIndex = 4,
})
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(86, 186, 108), Color3.fromRGB(18, 62, 36)), Rotation = 45 }, screen)
new("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, screen)
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
				BackgroundColor3 = Color3.fromRGB(150, 240, 170),
				BackgroundTransparency = k == 0 and 0.35 or 0.62,
				BorderSizePixel = 0,
				ZIndex = 5,
			}, screen)
		end
	end
end
local sweep = new("Frame", {
	Name = "Sweep",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RADAR_SCREEN - 6, 2),
	BackgroundColor3 = Color3.fromRGB(200, 255, 215),
	BorderSizePixel = 0,
	ZIndex = 5,
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
	local blip = circle(screen, {
		Name = "Blip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = DragonUI.DAMAGE,
		Visible = false,
		ZIndex = 6,
	})
	new("UIStroke", { Color = INK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, blip)
	blips[k] = blip
end
local you = new("Frame", { -- you, in the middle
	Name = "You",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(9, 9),
	Rotation = 45,
	BackgroundColor3 = DragonUI.HP,
	ZIndex = 7,
}, screen)
new("UIStroke", { Color = INK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, you)
Slab.new(radar, "Tag", 2, 170, 150, 24, INK, { ZIndex = 8 })
DragonUI.Lettering(radar, "Title", {
	Position = UDim2.fromOffset(18, 173),
	Size = UDim2.fromOffset(92, 18),
	Text = "DRAGON RADAR",
	Offset = 2,
	ZIndex = 9,
})
local range = Slab.new(radar, "Range", 112, 174, 50, 17, GI, { ZIndex = 9 })
label(range.Holder, {
	Name = "Text",
	Position = UDim2.fromOffset(6, 1),
	Size = UDim2.new(1, -12, 1, -2),
	Text = PowerConfig.RadarRange .. "m",
	TextColor3 = INK,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 10,
})

----------------------------------------------------------------------------------------
-- the portrait: a copy of your character in a 3D view, looking at your face
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
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
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
	local camera = portrait:FindFirstChildOfClass("Camera") or new("Camera", {}, portrait)
	camera.FieldOfView = PORTRAIT_FOV
	portrait.CurrentCamera = camera
	local h = head.CFrame
	camera.CFrame = CFrame.lookAt(h * PORTRAIT_EYE, h * PORTRAIT_LOOK)
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
local ssjMix = 0 -- 0 = base colours, 1 = Super Saiyan colours
local sweepAngle = 0
local enterAt = os.clock() -- the plate slides in from here
local radarAway = 0 -- 1 = the radar has slid off screen (while you power up)
local hitAt = -math.huge
local wasHidden = false
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
		-- frozen while the cutscene plays, so afterwards the HUD slides back in and the Scouter
		-- counts your new power level up (and tells you it's over 9000)
		wasHidden = true
		return
	end
	if wasHidden then
		wasHidden = false
		enterAt = now
	end
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = math.clamp(viewport.Y / 720, 0.68, 1.15)
	plateScale.Scale = scale
	radarScale.Scale = scale

	-- sliding in, and shaking when you get hit
	local enter = DragonUI.BackOut((now - enterAt) / 0.5)
	local shake = math.max(0, 1 - (now - hitAt) / 0.3)
	local jitter = shake > 0 and Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * (6 * shake) or Vector2.zero
	plate.Position = UDim2.fromOffset(PLATE_X - (1 - enter) * (520 * scale + 40) + jitter.X, PLATE_Y + HEADROOM * scale + jitter.Y)

	character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then
		return
	end

	-- the radar slides away while you power up (the charge bar takes its place on phones)
	local state = character:GetAttribute("PowerState")
	local busy = state == "Charging" or state == "Bursting"
	radarAway += ((busy and 1 or 0) - radarAway) * (1 - math.exp(-dt * 10))
	local away = math.max(1 - enter, radarAway)
	radar.Position = UDim2.new(1, -RADAR_MARGIN + away * (200 * scale + 40), 0, 6)

	-- colours follow your form
	local ssj = character:GetAttribute("Form") == "SSJ"
	ssjMix += ((ssj and 1 or 0) - ssjMix) * (1 - math.exp(-dt * 6))
	local kiColor = DragonUI.KI:Lerp(DragonUI.KI_SSJ, ssjMix)
	card:SetColor(GI:Lerp(GOLD, ssjMix))
	cardShade:SetColor(DragonUI.GI_DARK:Lerp(Color3.fromRGB(214, 128, 16), ssjMix))
	arcStroke.Color = kiColor
	formTag:SetColor(PAPER:Lerp(GOLD, ssjMix))
	formText.Text = ssj and "SUPER SAIYAN" or "BASE FORM"
	badgeKanji.Text = ssj and "超" or "気"
	badgeStroke.Color = INK
	nameText:SetColors(nil, GI:Lerp(DragonUI.DAMAGE, ssjMix))
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

	-- HP: the bar drops at once; the red chunk behind it catches up a moment later
	local health = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	if health < shownHealth - 0.001 then
		trailWait = 0.5
		hitAt = now
	end
	shownHealth = health
	trailWait -= dt
	if trailWait <= 0 then
		trailHealth += (shownHealth - trailHealth) * (1 - math.exp(-dt * 4))
	end
	trailHealth = math.max(trailHealth, shownHealth)
	hpFill:SetFill(shownHealth)
	hpTrail:SetFill(trailHealth)
	if health < 0.3 then -- low: the bar throbs orange (red is the damage chunk's colour)
		hpFill:SetColor(DragonUI.HP:Lerp(DragonUI.HP_LOW, 0.5 + 0.5 * math.sin(now * 9)))
	else
		hpFill:SetColor(DragonUI.HP)
	end
	hpEdge:SetColor(PAPER:Lerp(DragonUI.DAMAGE, shake))
	portrait.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 90, 90), shake)
	hpValue.Text = tostring(math.ceil(humanoid.Health))
	-- a glint runs along the bar every few seconds
	local fillWidth = hpFill.Width or 0
	local run = ((now % 2.8) / 0.45)
	if run < 1 and fillWidth > 30 then
		local x = -18 + (fillWidth + 18) * DragonUI.QuadOut(run)
		local left, right = math.max(x, 0), math.min(x + 18, fillWidth)
		hpGlint.Holder.Position = UDim2.fromOffset(left, 0)
		hpGlint:SetWidth(math.max(right - left, 0))
	else
		hpGlint:SetWidth(0)
	end

	-- Ki: five pips filling one after another; each pops when it fills up
	local ki = character:GetAttribute("Ki") or 0
	shownKi += (ki - shownKi) * (1 - math.exp(-dt * 8))
	local share = math.clamp(shownKi / PowerConfig.KiMax, 0, 1) * KI_PIPS
	local full = 0
	for k, pip in pips do
		local f = math.clamp(share - (k - 1), 0, 1)
		pip.Fill:SetFill(f)
		local isFull = f >= 0.999
		if isFull and not pip.Full then
			pip.PopAt = now
		end
		pip.Full = isFull
		pip.Edge.Holder.Visible = isFull
		local pop = math.max(0, 1 - (now - pip.PopAt) / 0.25)
		pip.Fill:SetColor(kiColor:Lerp(PAPER, pop))
		if isFull then
			full += 1
		end
	end
	kiBall:SetStars(full)
	kiBall.Scale.Scale = full >= KI_PIPS and (1 + 0.06 * math.sin(now * 6)) or 1

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
		local digits = #tostring(math.floor(wanted))
		powerValue.Text = commas(rng:NextInteger(10 ^ (digits - 1), 10 ^ digits - 1))
	else
		local wobble = (character:GetAttribute("PowerState") == "Idle") and 1 or (1 + rng:NextNumber(-0.01, 0.01))
		powerValue.Text = commas(shownPower * wobble)
	end
	local warning = now < over9000Until
	warn9000.Holder.Visible = warning and (math.floor(now * 8) % 2 == 0)
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
					blip.BackgroundColor3 = (oc:GetAttribute("Form") == "SSJ") and DragonUI.KI_SSJ or DragonUI.DAMAGE
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
	enterAt = os.clock()
	shownHealth, trailHealth = 1, 1
	task.delay(1, function()
		if player.Character == c then
			buildPortrait(c)
		end
	end)
end)
if player.Character then
	task.defer(buildPortrait, player.Character)
end
