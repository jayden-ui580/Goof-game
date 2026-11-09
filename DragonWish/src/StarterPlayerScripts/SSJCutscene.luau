--[[
	SSJCutscene  (ModuleScript — lives in StarterPlayer > StarterPlayerScripts, next to
	PowerUpClient, which plays it)

	The transformation cutscene the transforming player sees:
	  0.0 s   black bars slide in; an extreme close-up pans across your eyes
	  1.0 s   the camera sweeps up over your hair as it turns gold and blows upward
	  2.2 s   (PowerConfig.ExplodeAt) the power explodes: a white flash, the camera slams back to
	          a low angle and pulls away, and manga focus lines frame you
	  2.6 s   a manga box drops in: "THIS IS—"
	  3.25 s  ...then a bigger one: "SUPER SAIYAN!"   (PowerConfig.CutsceneText)
	  end     the boxes fly off, the bars slide away and you get control back
]]

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
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, gui)

local topBar = new("Frame", {
	Name = "TopBar",
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 5,
}, gui)
local bottomBar = new("Frame", {
	Name = "BottomBar",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 5,
}, gui)

-- a manga text box: a white panel with a thick black border and a hard black shadow
local function mangaBox(name: string, width: number, aspect: number, rotation: number)
	local holder = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(width, width * 3),
		BackgroundTransparency = 1,
		Rotation = rotation,
		Visible = false,
		ZIndex = 10,
	}, gui)
	new("UIAspectRatioConstraint", { AspectRatio = aspect }, holder)
	local scale = new("UIScale", { Scale = 1 }, holder)
	new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 8, 0.5, 8),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, holder)
	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 11,
	}, holder)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local text = new("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		TextScaled = true,
		TextColor3 = Color3.new(0, 0, 0),
		Text = "",
		ZIndex = 12,
	}, panel)
	return { Holder = holder, Scale = scale, Text = text, Rotation = rotation }
end

local box1 = mangaBox("BoxThisIs", 0.3, 4.2, -4)
local box2 = mangaBox("BoxSuperSaiyan", 0.46, 4.6, 3)
local BOX1_AT = UDim2.fromScale(0.27, 0.28)
local BOX2_AT = UDim2.fromScale(0.66, 0.72)

local function buildFocusLines()
	lines:ClearAllChildren()
	local okSize, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if not okSize or not size or size.X < 10 then
		local camera = Workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
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
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 1,
		}, lines)
		-- thin and faint at the inner end, thick and solid at the edge of the screen
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}, line)
	end
end

local function setLines(transparency: number)
	for _, line in lines:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundTransparency = transparency
		end
	end
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

local function dropIn(box, at: UDim2, text: string)
	box.Text.Text = text
	box.Holder.Visible = true
	box.Holder.Position = UDim2.new(at.X.Scale, at.X.Offset, at.Y.Scale - 0.55, at.Y.Offset)
	box.Holder.Rotation = box.Rotation - 14
	box.Scale.Scale = 1
	tween(box.Holder, 0.38, { Position = at, Rotation = box.Rotation }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.36, function()
		-- a little punch when it lands
		box.Scale.Scale = 1.14
		tween(box.Scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
end

local function flyOut(box)
	local at = box.Holder.Position
	tween(box.Holder, 0.35, {
		Position = UDim2.new(at.X.Scale, at.X.Offset, at.Y.Scale - 0.7, at.Y.Offset),
		Rotation = box.Rotation + 10,
	}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
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
	buildFocusLines()
	setLines(1)
	flash.BackgroundTransparency = 1
	box1.Holder.Visible = false
	box2.Holder.Visible = false
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
		once("box1", EXPLODE + 0.4, t, function()
			dropIn(box1, BOX1_AT, texts[1] or "")
		end)
		once("box2", EXPLODE + 1.05, t, function()
			dropIn(box2, BOX2_AT, texts[2] or "")
			shake = math.max(shake, 0.25)
		end)
		once("leave", duration - 0.5, t, function()
			flyOut(box1)
			flyOut(box2)
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
		else
			cf, fov = pullShot(root, (t - EXPLODE) / math.max(duration - EXPLODE, 0.1))
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
