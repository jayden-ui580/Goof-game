--[[
	SSJCutscene  (ModuleScript — lives in StarterPlayer > StarterPlayerScripts, next to
	PowerUpClient, which plays it)

	The transformation cutscene the transforming player sees:
	  0.0 s   black bars slide in; an extreme close-up pans across your eyes
	  1.0 s   the camera sweeps up over your hair as it turns gold and blows upward
	  2.2 s   (PowerConfig.ExplodeAt) the power explodes: a white flash, the camera slams back to
	          a low angle and pulls away, and manga focus lines frame you
	  2.6 s   the screen turns into a manga page: black and white, inked outlines, screentone
	          dots round the edges ... and a tall manga panel slides DOWN into frame: "THIS IS—"
	  3.25 s  a second panel slides UP into frame: "SUPER SAIYAN!"   (PowerConfig.CutsceneText)
	  4.3 s   (PowerConfig.PointAt) the panels slide away; cut to the front: your arms come in,
	          left fingers on the inside of your right elbow, then you swipe into a point at the
	          camera as it pushes in on you ... and a third panel slams in: "YOU'RE FINISHED!"
	  end     the panel goes, the colour floods back, the bars go and you get control
	The arm, hand and finger movements are PowerFX's and HandFX's; this script moves the camera
	and draws the screen.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local EXPLODE = PowerConfig.ExplodeAt or 2.2
local EYES_END = math.min(1, EXPLODE * 0.45) -- the eye close-up, then the hair until the explosion
local BAR = 0.13 -- height of each black bar (share of the screen)
local FOCUS_LINES = 40
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local PAPER = Color3.fromRGB(250, 247, 238)

local player = Players.LocalPlayer
local rng = Random.new()

local Cutscene = { Playing = false }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function easeOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

local function easeInOut(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function smooth(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

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

local function tween(inst: Instance, seconds: number, props, style, direction)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function fadeLine(parent: Instance) -- thin at the start, solid at the end
	return new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, parent)
end

----------------------------------------------------------------------------------------
-- the screen layer (built once, shown only during the cutscene)
----------------------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "SSJCutscene",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

-- manga focus lines: thin black wedges pointing in at you from the edges of the screen
local lines = new("Frame", {
	Name = "FocusLines",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
}, gui)

local flash = new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, gui)

-- the manga filter's screentone: halftone dots, bigger toward the edges of the screen
local tone = new("CanvasGroup", {
	Name = "Screentone",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	ZIndex = 3,
}, gui)

-- ... and a black panel border round the whole screen, like a page
local page = new("Frame", {
	Name = "PageBorder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -18, 1, -18),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, gui)
new("UIStroke", { Color = BLACK, Thickness = 5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, page)

local topBar = new("Frame", {
	Name = "TopBar",
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	ZIndex = 5,
}, gui)
local bottomBar = new("Frame", {
	Name = "BottomBar",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	ZIndex = 5,
}, gui)

-- the manga filter's colour: black and white, hard contrast, a touch of paper warmth
local grade = new("ColorCorrectionEffect", { Name = "MangaFilter", Enabled = false }, Lighting)

----------------------------------------------------------------------------------------
-- the manga panels: tall white panels with a double black border and a hard shadow
----------------------------------------------------------------------------------------
local function mangaPanel(name: string, size: UDim2, aspect: number, style: string)
	local holder = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	}, gui)
	new("UIAspectRatioConstraint", { AspectRatio = aspect }, holder)
	local scale = new("UIScale", { Scale = 1 }, holder)
	new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 10, 0.5, 10),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, holder)
	local panel = new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 11,
	}, holder)
	new("UIStroke", { Color = BLACK, Thickness = 6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local inner = new("Frame", {
		Name = "InnerBorder",
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.new(1, -18, 1, -18),
		BackgroundTransparency = 1,
		ZIndex = 14,
	}, panel)
	new("UIStroke", { Color = BLACK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)

	if style == "speed" then
		-- horizontal speed lines whooshing across
		for k = 1, 16 do
			local line = new("Frame", {
				Name = "Speed",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.08 + (k - 1) / 15 * 0.84 + rng:NextNumber(-0.02, 0.02)),
				Size = UDim2.new(rng:NextNumber(0.35, 0.95), 0, 0, rng:NextNumber(2, 5)),
				BackgroundColor3 = BLACK,
				BorderSizePixel = 0,
				ZIndex = 12,
			}, panel)
			fadeLine(line)
		end
	else
		-- focus lines bursting out from behind the words
		for k = 1, 28 do
			local a = (k - 1) / 28 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
			local d = rng:NextNumber(0.42, 0.5) -- (in panel widths) from the middle to the line's middle
			local line = new("Frame", {
				Name = "Burst",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(a) * d, 0.5 + math.sin(a) * d * aspect),
				Size = UDim2.new(0.62, 0, 0, rng:NextNumber(2, 6)),
				Rotation = math.deg(a),
				BackgroundColor3 = BLACK,
				BorderSizePixel = 0,
				ZIndex = 12,
			}, panel)
			fadeLine(line)
		end
	end
	-- screentone fading up from the bottom of the panel
	for row = 0, 6 do
		for col = 0, 9 do
			local size = 2 + row * 1.6
			local dot = new("Frame", {
				Name = "Tone",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new((col + 0.5 + (row % 2) * 0.5) / 10, 0, 0.66 + row * 0.052, 0),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = BLACK,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				ZIndex = 12,
			}, panel)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		end
	end
	local text = new("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.86, 0.62),
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		TextScaled = true,
		TextColor3 = BLACK,
		Text = "",
		ZIndex = 13,
	}, panel)
	new("UIStroke", { Color = PAPER, Thickness = 4 }, text) -- a paper-white halo so it reads over the lines
	return { Holder = holder, Scale = scale, Text = text }
end

local panel1 = mangaPanel("PanelThisIs", UDim2.fromScale(0.19, 0.66), 0.5, "speed")
local panel2 = mangaPanel("PanelSuperSaiyan", UDim2.fromScale(0.25, 0.7), 0.58, "burst")
local panel3 = mangaPanel("PanelFinished", UDim2.fromScale(0.38, 0.3), 1.7, "burst")
local PANEL1_AT, PANEL1_FROM = UDim2.fromScale(0.21, 0.5), UDim2.fromScale(0.21, -0.6) -- slides down
local PANEL2_AT, PANEL2_FROM = UDim2.fromScale(0.77, 0.5), UDim2.fromScale(0.77, 1.6) -- slides up
local PANEL3_AT, PANEL3_OUT = UDim2.fromScale(0.29, 0.65), UDim2.fromScale(0.29, 1.6) -- slams in
local POINT_AT = PowerConfig.PointAt
local POINT_LAND = 0.81 -- seconds after PointAt: the point lands (PowerFX's swipe)

-- "SUPER SAIYAN!" -> "SUPER\nSAIYAN!": one word per line fills a tall panel
local function stacked(text: string): string
	return (text:gsub("%s+", "\n"))
end

local function slideIn(panel, from: UDim2, at: UDim2, text: string)
	panel.Text.Text = stacked(text)
	panel.Holder.Visible = true
	panel.Holder.Position = from
	panel.Scale.Scale = 1
	tween(panel.Holder, 0.42, { Position = at }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.4, function()
		-- a little punch when it lands
		panel.Scale.Scale = 1.08
		tween(panel.Scale, 0.2, { Scale = 1 })
	end)
end

local function slideOut(panel, to: UDim2)
	tween(panel.Holder, 0.38, { Position = to }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end

-- the third panel doesn't slide: it slams down onto the page, like a stamp
local function slamIn(panel, at: UDim2, text: string)
	panel.Text.Text = stacked(text)
	panel.Holder.Visible = true
	panel.Holder.Position = at
	panel.Scale.Scale = 1.8
	tween(panel.Scale, 0.14, { Scale = 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.14, function()
		tween(panel.Scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

----------------------------------------------------------------------------------------
-- building the effects that depend on the screen size
----------------------------------------------------------------------------------------
local function screenSize(): Vector2
	local okSize, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if not okSize or not size or size.X < 10 then
		local camera = Workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	return size
end

local function buildFocusLines(size: Vector2)
	lines:ClearAllChildren()
	local centre = size / 2
	local inner = math.min(size.X, size.Y) * 0.36
	local outer = size.Magnitude * 0.6
	for k = 1, FOCUS_LINES do
		local a = (k - 1) / FOCUS_LINES * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local r0 = inner * rng:NextNumber(0.9, 1.3)
		local length = outer - r0
		local mid = centre + Vector2.new(math.cos(a), math.sin(a)) * (r0 + length / 2)
		local line = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Size = UDim2.fromOffset(length, rng:NextNumber(2, 7)),
			Rotation = math.deg(a),
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, lines)
		fadeLine(line)
	end
end

local toneBuiltFor = Vector2.zero
local function buildScreentone(size: Vector2)
	if (size - toneBuiltFor).Magnitude < 1 then
		return -- already made for this screen size
	end
	toneBuiltFor = size
	tone:ClearAllChildren()
	-- a halftone grid (every other row shifted half a step, like printed screentone); each dot
	-- grows with its distance from the middle of the screen, so the tone darkens to the edges
	local step = math.clamp(size.Y * 0.03, 14, 24)
	local centre = size / 2
	local row = 0
	for y = step / 2, size.Y, step * 0.87 do
		local shift = (row % 2) * step / 2
		row += 1
		for x = step / 2 + shift, size.X, step do
			local dx = (x - centre.X) / centre.X
			local dy = (y - centre.Y) / centre.Y
			local r = math.sqrt(dx * dx + dy * dy)
			local d = step * 0.95 * smooth(0.6, 1.3, r)
			if d >= 2 then
				local dot = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(d, d),
					BackgroundColor3 = BLACK,
					BackgroundTransparency = 0.12,
					BorderSizePixel = 0,
				}, tone)
				new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			end
		end
	end
end

local function setLines(transparency: number)
	for _, line in lines:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundTransparency = transparency
		end
	end
end

----------------------------------------------------------------------------------------
-- the manga filter: turns the screen into a manga page, then fades it back
----------------------------------------------------------------------------------------
local ink: Highlight? = nil

local function mangaOn(character: Model)
	grade.Enabled = true
	grade.Saturation, grade.Contrast, grade.Brightness, grade.TintColor = 0, 0, 0, WHITE
	tween(grade, 0.25, { Saturation = -1, Contrast = 0.65, Brightness = 0.04, TintColor = PAPER })
	tween(tone, 0.25, { GroupTransparency = 0 })
	page.Visible = true
	-- inked outline round your character
	if ink then
		ink:Destroy()
	end
	local okInk, made = pcall(function() -- (Roblox only draws so many highlights at once)
		return new("Highlight", {
			Name = "MangaInk",
			DepthMode = Enum.HighlightDepthMode.Occluded,
			OutlineColor = BLACK,
			OutlineTransparency = 1,
			FillColor = WHITE,
			FillTransparency = 1,
			Adornee = character,
		}, character)
	end)
	ink = okInk and made or nil
	if ink then
		tween(ink, 0.25, { OutlineTransparency = 0, FillTransparency = 0.78 })
	end
end

local function mangaOff(seconds: number)
	tween(grade, seconds, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE })
	tween(tone, seconds, { GroupTransparency = 1 })
	page.Visible = false
	if ink then
		tween(ink, seconds, { OutlineTransparency = 1, FillTransparency = 1 })
	end
end

local function mangaClear()
	grade.Enabled = false
	tone.GroupTransparency = 1
	page.Visible = false
	if ink then
		ink:Destroy()
		ink = nil
	end
end

----------------------------------------------------------------------------------------
-- the camera shots (all measured from your head / body as they move)
----------------------------------------------------------------------------------------
local function eyesShot(head: BasePart, u: number): (CFrame, number)
	local h = head.CFrame
	local e = easeInOut(u)
	local eye = h * Vector3.new(lerp(0.32, -0.32, e), 0.12, -1.45)
	local look = h * Vector3.new(lerp(0.12, -0.12, e), 0.1, 0)
	return CFrame.lookAt(eye, look, h.UpVector), lerp(24, 17, e)
end

local function hairShot(head: BasePart, u: number): (CFrame, number)
	local h = head.CFrame
	local e = easeInOut(u)
	local eye = h * Vector3.new(lerp(0.55, 0.2, e), lerp(0.25, 1.9, e), lerp(-2.1, -2.9, e))
	local look = h * Vector3.new(0, lerp(0.5, 2.2, e), 0)
	return CFrame.lookAt(eye, look, h.UpVector), lerp(42, 50, e)
end

local function pullShot(root: BasePart, u: number): (CFrame, number)
	local r = root.CFrame
	local e = easeOut(u * 1.6)
	local eye = r * Vector3.new(lerp(0.8, 2.6, e), lerp(-1.6, 0.3, e), lerp(-4.5, -13, e))
	local look = r * Vector3.new(0, lerp(1.9, 1.3, e), 0)
	return CFrame.lookAt(eye, look), lerp(80, 62, e)
end

-- the point: in front of you, a little to your left; it pushes in as your arm swipes out at the
-- lens (u = seconds since the point began)
local function pointShot(root: BasePart, u: number): (CFrame, number)
	local r = root.CFrame
	local e = easeInOut(math.clamp((u - 0.57) / 0.3, 0, 1))
	local eye = r * Vector3.new(lerp(-1.8, -1.1, e), lerp(0.9, 0.5, e), lerp(-8.4, -5.2, e))
	local look = r * Vector3.new(lerp(-0.4, -0.55, e), 1.1, lerp(-0.6, -1, e))
	return CFrame.lookAt(eye, look), lerp(46, 54, e)
end

----------------------------------------------------------------------------------------
-- playing it
----------------------------------------------------------------------------------------
local stopCurrent: (() -> ())? = nil

-- Plays the cutscene on character for duration seconds. onDone runs when it ends.
function Cutscene.Play(character: Model, duration: number, onDone: (() -> ())?)
	if stopCurrent then
		stopCurrent()
	end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not (head and root and camera) then
		if onDone then
			onDone()
		end
		return
	end
	local texts = PowerConfig.CutsceneText or { "THIS IS—", "SUPER SAIYAN!" }
	Cutscene.Playing = true
	player:SetAttribute("InCutscene", true)
	-- hide the phone's thumbstick and jump button for the cinematic
	local okModal, wasModal = pcall(function()
		return UserInputService.ModalEnabled
	end)
	pcall(function()
		UserInputService.ModalEnabled = true
	end)
	gui.Enabled = true
	local size = screenSize()
	buildFocusLines(size)
	buildScreentone(size) -- (made while the bars close in, hidden until the manga moment)
	setLines(1)
	mangaClear()
	flash.BackgroundTransparency = 1
	panel1.Holder.Visible = false
	panel2.Holder.Visible = false
	panel3.Holder.Visible = false
	-- the point needs room: PointAt, the swipe and a beat to hold it before the end
	local pointAt = (POINT_AT and duration >= POINT_AT + POINT_LAND + 0.6) and POINT_AT or nil
	topBar.Size = UDim2.fromScale(1, 0)
	bottomBar.Size = UDim2.fromScale(1, 0)
	tween(topBar, 0.3, { Size = UDim2.fromScale(1, BAR) })
	tween(bottomBar, 0.3, { Size = UDim2.fromScale(1, BAR) })

	local start = os.clock()
	local fired = {}
	local function once(key: string, at: number, t: number, fn: () -> ())
		if not fired[key] and t >= at then
			fired[key] = true
			fn()
		end
	end
	local shake = 0
	local finished = false
	local function stop()
		if finished then
			return
		end
		finished = true
		stopCurrent = nil
		RunService:UnbindFromRenderStep("DWCutsceneCamera")
		gui.Enabled = false
		mangaClear()
		Cutscene.Playing = false
		player:SetAttribute("InCutscene", false)
		pcall(function()
			UserInputService.ModalEnabled = okModal and wasModal or false
		end)
		if onDone then
			onDone()
		end
	end
	stopCurrent = stop

	RunService:BindToRenderStep("DWCutsceneCamera", Enum.RenderPriority.Camera.Value + 2, function()
		local t = os.clock() - start
		if t >= duration or not character.Parent or not head.Parent then
			stop()
			return
		end
		once("explode", EXPLODE, t, function()
			flash.BackgroundTransparency = 0
			tween(flash, 0.7, { BackgroundTransparency = 1 })
			shake = 0.6
			setLines(0.1)
		end)
		once("panel1", EXPLODE + 0.4, t, function()
			mangaOn(character)
			slideIn(panel1, PANEL1_FROM, PANEL1_AT, texts[1] or "")
		end)
		once("panel2", EXPLODE + 1.05, t, function()
			slideIn(panel2, PANEL2_FROM, PANEL2_AT, texts[2] or "")
			shake = math.max(shake, 0.25)
		end)
		if pointAt then
			once("panels away", pointAt - 0.2, t, function()
				slideOut(panel1, PANEL1_FROM)
				slideOut(panel2, PANEL2_FROM)
				setLines(1)
			end)
			once("finished", pointAt + POINT_LAND, t, function()
				slamIn(panel3, PANEL3_AT, texts[3] or "YOU'RE FINISHED!")
				flash.BackgroundTransparency = 0.55
				tween(flash, 0.3, { BackgroundTransparency = 1 })
				setLines(0.15)
				shake = math.max(shake, 0.35)
			end)
		end
		once("leave", duration - 0.5, t, function()
			slideOut(panel1, PANEL1_FROM) -- back up
			slideOut(panel2, PANEL2_FROM) -- back down
			if panel3.Holder.Visible then
				slideOut(panel3, PANEL3_OUT)
			end
			mangaOff(0.45) -- the colour comes back as the panels go
			tween(topBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(bottomBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			setLines(1)
		end)

		local cf, fov
		if t < EYES_END then
			cf, fov = eyesShot(head, t / EYES_END)
			shake = 0.008
		elseif t < EXPLODE then
			cf, fov = hairShot(head, (t - EYES_END) / (EXPLODE - EYES_END))
			shake = 0.02
		elseif pointAt and t >= pointAt then
			cf, fov = pointShot(root, t - pointAt)
		else
			cf, fov = pullShot(root, (t - EXPLODE) / math.max((pointAt or duration) - EXPLODE, 0.1))
		end
		local jolt = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shake
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cf + jolt
		camera.FieldOfView = fov
		if t >= EXPLODE then
			shake = math.max(shake * 0.9, 0.03)
		end
	end)
end

function Cutscene.Stop()
	if stopCurrent then
		stopCurrent()
	end
end

return Cutscene
