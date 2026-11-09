--[[
	PowerUpClient  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Your controls, camera and screen for powering up:
	  R      start powering up (the camera swings round to face you, you drop into a stance)
	         R again while charging cancels; R as a Super Saiyan powers down
	  Space  spam it to fill the power bar (phones: the big TAP button)
	When the bar is full you burst into Super Saiyan: the transformation cutscene plays
	(SSJCutscene: your eyes, your hair, the explosion, the manga panels), then you get control
	back. The prompt, bar and TAP button are drawn with ReplicatedStorage > DragonUI. The aura,
	pose and hair are drawn by PowerFX and HairPhysics for everyone, using the attributes
	PowerUpServer sets.
	Settings: ReplicatedStorage > PowerConfig.
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))
local remote = ReplicatedStorage:WaitForChild("PowerUp")
local player = Players.LocalPlayer

-- the transformation cutscene (if it's missing, transforming still works without it)
local okCutscene, Cutscene = pcall(function()
	return require(script.Parent:WaitForChild("SSJCutscene", 5))
end)
if not okCutscene then
	Cutscene = nil
end

local SEND_EVERY = 0.1 -- seconds between bar updates sent to the server

----------------------------------------------------------------------------------------
-- screen (the look comes from ReplicatedStorage > DragonUI)
----------------------------------------------------------------------------------------
local DragonUI = require(ReplicatedStorage:WaitForChild("DragonUI"))
local new, Slab = DragonUI.new, DragonUI.Slab
local INK, PAPER = DragonUI.INK, DragonUI.PAPER
local touch = UserInputService.TouchEnabled

local gui = new("ScreenGui", {
	Name = "PowerUpUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
}, player:WaitForChild("PlayerGui"))

-- comic text: Bangers with an ink outline (ink-coloured text goes without one)
local function text(parent: Instance, props): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		TextColor3 = PAPER,
		TextScaled = true,
	})
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	if l.TextColor3 ~= INK then
		new("UIStroke", { Color = INK, Thickness = 2 }, l)
	end
	return l
end

-- the hint along the bottom: a key cap and what it does
local hint = new("Frame", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(200, 30),
	BackgroundTransparency = 1,
}, gui)
local hintKey = Slab.new(hint, "Key", 0, 0, 40, 30, PAPER, { ZIndex = 2 })
local hintKeyText = text(hintKey.Holder, {
	Name = "Text",
	Position = UDim2.fromOffset(13, 4),
	Size = UDim2.new(1, -26, 1, -7),
	TextColor3 = INK,
	ZIndex = 3,
})
local hintAction = Slab.new(hint, "Action", 44, 3, 150, 24, INK, { Transparency = 0.15, ZIndex = 1 })
local hintActionText = text(hintAction.Holder, {
	Name = "Text",
	Position = UDim2.fromOffset(15, 2),
	Size = UDim2.new(1, -30, 1, -4),
	ZIndex = 2,
})

local function setHint(key: string?, action: string?)
	hint.Visible = key ~= nil
	if not key then
		return
	end
	local keyWidth = 26 + 13 * #key
	hintKeyText.Text = key
	hintActionText.Text = action or ""
	hintKey:SetWidth(keyWidth)
	hintAction.Holder.Position = UDim2.fromOffset(keyWidth - 6, 3)
	hint.Size = UDim2.fromOffset(keyWidth + 144, 30)
end
setHint(nil) -- (until your character arrives)

-- the charge panel: SPAM SPACE!, how far along you are, and the bar
local PANEL_W = touch and 300 or 420
local panel = new("Frame", {
	Name = "Charge",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -64),
	Size = UDim2.fromOffset(PANEL_W, 124),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local panelScale = new("UIScale", {}, panel) -- shrinks the panel on small screens
local prompt = DragonUI.Lettering(panel, "Prompt", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(1, -30, 0, 54),
	Text = "SPAM  SPACE!",
	TextXAlignment = Enum.TextXAlignment.Center,
	Stroke = 3,
	Offset = 4,
	ZIndex = 2,
})
local promptScale = new("UIScale", {}, prompt.Holder)
local stage = text(panel, {
	Name = "Stage",
	Position = UDim2.new(0, 0, 0, 58),
	Size = UDim2.new(1, 0, 0, 22),
	Text = "",
	ZIndex = 2,
})
local BAR_X, BAR_Y, BAR_H = 16, 90, 22
local BAR_W = PANEL_W - BAR_X - 68
Slab.around(panel, "BarEdge", BAR_X, BAR_Y, BAR_W, BAR_H, 3, PAPER, { ZIndex = 1 })
local barBack = Slab.new(panel, "Bar", BAR_X, BAR_Y, BAR_W, BAR_H, INK, { ZIndex = 2 })
local barFill = Slab.new(barBack.Holder, "Fill", 0, 0, BAR_W, BAR_H, DragonUI.KI, { ZIndex = 3 })
barFill:Band("Shade", 14, BAR_H, INK, { Transparency = 0.7, ZIndex = 4 })
barFill:Band("Shine", 3, 6, PAPER, { Transparency = 0.3, ZIndex = 4 })
barFill:SetFill(0)
local percent = text(panel, {
	Name = "Percent",
	Position = UDim2.fromOffset(BAR_X + BAR_W + 10, BAR_Y - 5),
	Size = UDim2.fromOffset(56, BAR_H + 10),
	Text = "0%",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
})

-- phones: a big Dragon Ball to tap
local TAP_SIZE = touch and 124 or 150
local tapButton = new("TextButton", {
	Name = "Tap",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -30, 1, -40),
	Size = UDim2.fromOffset(TAP_SIZE, TAP_SIZE),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
}, gui)
local tapBall = DragonUI.Orb(tapButton, "Ball", 0, 0, TAP_SIZE, 1)
DragonUI.Lettering(tapButton, "Label", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromScale(0.8, 0.42),
	Rotation = -8,
	Text = "TAP!",
	BackColor = DragonUI.DAMAGE,
	TextXAlignment = Enum.TextXAlignment.Center,
	Stroke = 3,
	Offset = 4,
	ZIndex = 5,
})

if touch then
	-- phones: the charge panel goes top right (the radar slides away while you power up) and
	-- the TAP button bottom middle, between the thumbstick and the jump button, so it never
	-- covers JUMP
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -60, 0, 62)
	tapButton.AnchorPoint = Vector2.new(0.5, 1)
	tapButton.Position = UDim2.new(0.5, 0, 1, -22)
end

local flash = new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)
-- the title when there's no cutscene
local bigText = DragonUI.Lettering(gui, "Title", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(700, 100),
	Text = "SUPER SAIYAN!",
	Color = DragonUI.GOLD,
	BackColor = DragonUI.DAMAGE,
	TextXAlignment = Enum.TextXAlignment.Center,
	Stroke = 4,
	Offset = 5,
	ZIndex = 11,
})
bigText.Holder.Visible = false
local bigScale = new("UIScale", {}, bigText.Holder)

-- a colour grade on this player's screen only: punchier as you charge, a warm flash on release
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "PowerUpGrade"
grade.Parent = Lighting

----------------------------------------------------------------------------------------
-- state
----------------------------------------------------------------------------------------
local character: Model? = nil
local charging = false
local bursting = false
local charge = 0
local full = false -- the bar filled up: it stays full until you transform
local startedAt = 0
local lastSend = 0
local transformSentAt = -math.huge
local savedCamera = nil
local camShake = 0
local fovKick = 0

local function attr(name: string)
	return character and character:GetAttribute(name)
end

local function refreshHint()
	local key = touch and "POWER" or PowerConfig.PowerKey.Name
	if charging or bursting then
		setHint(nil)
	elseif attr("Form") == "SSJ" then
		setHint(key, "POWER DOWN")
	else
		setHint(key, "POWER UP")
	end
end

----------------------------------------------------------------------------------------
-- camera: swings round in front of you while you power up
----------------------------------------------------------------------------------------
local function takeCamera()
	local camera = Workspace.CurrentCamera
	if not savedCamera then
		savedCamera = { Type = camera.CameraType, FOV = camera.FieldOfView }
	end
	camera.CameraType = Enum.CameraType.Scriptable
end

local function releaseCamera()
	local camera = Workspace.CurrentCamera
	if savedCamera then
		camera.CameraType = savedCamera.Type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or savedCamera.Type
		TweenService:Create(camera, TweenInfo.new(0.4), { FieldOfView = savedCamera.FOV }):Play()
		savedCamera = nil
	end
end

RunService:BindToRenderStep("DWPowerCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not savedCamera or not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not root then
		return
	end
	local intensity = bursting and 1 or charge
	local distance = PowerConfig.CameraDistance * (bursting and 1.25 or (1 - 0.18 * charge))
	local base = root.CFrame
	local eye = base * Vector3.new(0, PowerConfig.CameraHeight - 0.3 * intensity, -distance) -- in front (characters face -Z)
	local look = base.Position + Vector3.new(0, PowerConfig.CameraLookHeight, 0)
	camShake = math.max(camShake - dt * 2, intensity * PowerConfig.CameraShake)
	local shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (2 * camShake)
	local target = CFrame.lookAt(eye + shake, look)
	camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-dt * 7))
	fovKick = math.max(0, fovKick - dt * 12)
	camera.FieldOfView = (savedCamera.FOV or 70) + fovKick
end)

----------------------------------------------------------------------------------------
-- charging
----------------------------------------------------------------------------------------
local function tap()
	if not charging then
		return
	end
	charge = math.min(1, charge + PowerConfig.ChargePerTap)
	if charge >= 1 then
		full = true
	end
	promptScale.Scale = 1.18
	tapBall.Scale.Scale = 1.12
end

local function setTapBinding(on: boolean)
	if on then
		-- higher priority than the jump button, and "Sink" so spamming Space doesn't jump
		ContextActionService:BindActionAtPriority("DWTap", function(_, state)
			if state == Enum.UserInputState.Begin then
				tap()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, PowerConfig.TapKey)
	else
		ContextActionService:UnbindAction("DWTap")
	end
	tapButton.Visible = on and touch
end

local function startCharging()
	local okSize, viewport = pcall(function()
		return Workspace.CurrentCamera.ViewportSize
	end)
	panelScale.Scale = (okSize and viewport and viewport.Y > 100) and math.clamp(viewport.Y / 720, 0.66, 1.15) or 1
	charging = true
	charge = 0
	full = false
	startedAt = os.clock()
	transformSentAt = -math.huge
	remote:FireServer("Start")
	takeCamera()
	panel.Visible = true
	prompt:SetText(touch and "TAP!  TAP!  TAP!" or ("SPAM  " .. string.upper(PowerConfig.TapKey.Name) .. "!"))
	setTapBinding(true)
	refreshHint()
end

local function stopCharging(sendCancel: boolean)
	if charging and sendCancel then
		remote:FireServer("Cancel")
	end
	charging = false
	charge = 0
	full = false
	panel.Visible = false
	setTapBinding(false)
	grade.Contrast, grade.Saturation = 0, 0
	if not bursting then
		releaseCamera()
	end
	refreshHint()
end

local function playBurst()
	bursting = true
	charging = false
	panel.Visible = false
	setTapBinding(false)
	local cutscene = PowerConfig.Cutscene and Cutscene and character
	if cutscene then
		gui.Enabled = false -- the cutscene has the screen to itself
		Cutscene.Play(character, PowerConfig.BurstTime - 0.05, function()
			gui.Enabled = true
		end)
	end
	-- the moment the power explodes out
	task.delay(PowerConfig.ExplodeAt or 0, function()
		if not bursting then
			return
		end
		camShake = PowerConfig.CameraShake * 4
		fovKick = 18
		grade.Brightness = 0.3
		grade.Contrast = 0.25
		grade.Saturation = 0.35
		grade.TintColor = Color3.fromRGB(255, 236, 200)
		TweenService:Create(grade, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
		if not cutscene then
			flash.BackgroundTransparency = 0
			TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			bigText.Holder.Visible = true
			bigScale.Scale = 0.5
			TweenService:Create(bigScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			task.delay(1.6, function()
				TweenService:Create(bigScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.01 }):Play()
				task.delay(0.26, function()
					bigText.Holder.Visible = false
				end)
			end)
		end
	end)
	task.delay(PowerConfig.BurstTime, function()
		bursting = false
		releaseCamera()
		refreshHint()
	end)
end

local function onPowerKey(_, state)
	if state ~= Enum.UserInputState.Begin or not character then
		return Enum.ContextActionResult.Pass
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or bursting then
		return Enum.ContextActionResult.Sink
	end
	if charging then
		stopCharging(true)
	elseif attr("Form") == "SSJ" then
		remote:FireServer("PowerDown")
	else
		startCharging()
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("DWPower", onPowerKey, true, PowerConfig.PowerKey)
ContextActionService:SetTitle("DWPower", "Power")

tapButton.Activated:Connect(tap)

local STAGES = {
	{ 0.0, "Gather your energy..." },
	{ PowerConfig.AuraStart, "Aura rising!" },
	{ PowerConfig.HairStart, "Power surging!" },
	{ 0.6, "Faster!!" },
	{ 0.85, "BREAK THROUGH!!!" },
}

RunService.RenderStepped:Connect(function(dt)
	if not charging then
		return
	end
	if os.clock() - startedAt > 1.2 and attr("PowerState") ~= "Charging" then
		stopCharging(false) -- the server didn't accept (e.g. already transforming)
		return
	end
	if full then
		charge = 1
	else
		charge = math.max(0, charge - PowerConfig.ChargeDecay * dt)
	end
	promptScale.Scale += (1 - promptScale.Scale) * math.min(1, dt * 10)
	tapBall.Scale.Scale += (1 - tapBall.Scale.Scale) * math.min(1, dt * 12)
	barFill:SetFill(charge)
	-- ki blue, turning Super Saiyan gold once your hair starts lifting
	barFill:SetColor(DragonUI.KI:Lerp(DragonUI.GOLD, math.clamp((charge - PowerConfig.HairStart) / 0.5, 0, 1)))
	percent.Text = math.floor(charge * 100 + 0.5) .. "%"
	stage.TextColor3 = PAPER:Lerp(DragonUI.GOLD, math.clamp((charge - 0.5) * 2, 0, 1))
	grade.Contrast = 0.12 * charge
	grade.Saturation = 0.2 * charge
	local text = STAGES[1][2]
	for _, s in STAGES do
		if charge >= s[1] then
			text = s[2]
		end
	end
	stage.Text = text
	local now = os.clock()
	if now - lastSend >= SEND_EVERY then
		lastSend = now
		remote:FireServer("Charge", charge)
	end
	if full and now - startedAt >= PowerConfig.MinChargeTime and now - transformSentAt > 0.6 then
		transformSentAt = now
		remote:FireServer("Charge", 1)
		remote:FireServer("Transform")
	end
end)

----------------------------------------------------------------------------------------
-- follow the character and the server's verdicts
----------------------------------------------------------------------------------------
local function onCharacter(newCharacter: Model)
	character = newCharacter
	charging, bursting = false, false
	panel.Visible = false
	setTapBinding(false)
	if Cutscene then
		Cutscene.Stop()
	end
	gui.Enabled = true
	releaseCamera()
	newCharacter:GetAttributeChangedSignal("PowerState"):Connect(function()
		local state = newCharacter:GetAttribute("PowerState")
		if state == "Bursting" and not bursting then
			playBurst()
		elseif state == "Idle" and charging then
			stopCharging(false) -- the server cancelled us
		end
		refreshHint()
	end)
	newCharacter:GetAttributeChangedSignal("Form"):Connect(refreshHint)
	local humanoid = newCharacter:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			stopCharging(false)
			bursting = false
			if Cutscene then
				Cutscene.Stop()
			end
			releaseCamera()
		end)
	end
	refreshHint()
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
