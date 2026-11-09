--[[
	PowerUpClient  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Your controls, camera and screen for powering up:
	  R      start powering up (the camera swings round to face you, you drop into a stance)
	         R again while charging cancels; R as a Super Saiyan powers down
	  Space  spam it to fill the power bar (phones: the big TAP button)
	When the bar is full you burst into Super Saiyan: the transformation cutscene plays
	(SSJCutscene: your eyes, your hair, the explosion, the manga boxes), then you get control
	back. The aura, pose and hair are drawn by PowerFX and HairPhysics for everyone, using the
	attributes PowerUpServer sets.
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
-- screen
----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PowerUpUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextStrokeTransparency = 0.4
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local hint = label(gui, {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(360, 26),
	Font = Enum.Font.GothamMedium,
	TextTransparency = 0.15,
})

local panel = Instance.new("Frame")
panel.Name = "Charge"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -60)
panel.Size = UDim2.fromOffset(420, 130)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui
local panelScale = Instance.new("UIScale") -- shrinks the panel on small screens
panelScale.Parent = panel
local prompt = label(panel, {
	Name = "Prompt",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 52),
	Text = "SPAM  SPACE!",
})
local promptScale = Instance.new("UIScale")
promptScale.Parent = prompt
local stage = label(panel, {
	Name = "Stage",
	Position = UDim2.new(0, 0, 0, 56),
	Size = UDim2.new(1, 0, 0, 22),
	Font = Enum.Font.GothamBold,
	Text = "",
})
local barBack = Instance.new("Frame")
barBack.Position = UDim2.new(0, 0, 0, 88)
barBack.Size = UDim2.new(1, 0, 0, 24)
barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
barBack.BackgroundTransparency = 0.2
barBack.Parent = panel
Instance.new("UICorner").Parent = barBack
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(1, 1, 1)
stroke.Thickness = 2
stroke.Parent = barBack
local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = PowerConfig.BaseAuraColor
barFill.Parent = barBack
Instance.new("UICorner").Parent = barFill

local tapButton = Instance.new("TextButton")
tapButton.Name = "Tap"
tapButton.AnchorPoint = Vector2.new(1, 1)
tapButton.Position = UDim2.new(1, -30, 1, -40)
tapButton.Size = UDim2.fromOffset(150, 150)
tapButton.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
tapButton.Text = "TAP!"
tapButton.Font = Enum.Font.GothamBlack
tapButton.TextScaled = true
tapButton.TextColor3 = Color3.fromRGB(40, 20, 0)
tapButton.Visible = false
tapButton.Parent = gui
local tapCorner = Instance.new("UICorner")
tapCorner.CornerRadius = UDim.new(1, 0)
tapCorner.Parent = tapButton
local tapStroke = Instance.new("UIStroke")
tapStroke.Color = Color3.fromRGB(120, 60, 0)
tapStroke.Thickness = 3
tapStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
tapStroke.Parent = tapButton

if UserInputService.TouchEnabled then
	-- phones: the charge bar goes at the top (between the HUD and the radar) and the TAP button
	-- at the bottom middle, between the thumbstick and the jump button, so it never covers JUMP
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.6, 0, 0, 62)
	panel.Size = UDim2.fromOffset(300, 130)
	tapButton.AnchorPoint = Vector2.new(0.5, 1)
	tapButton.Position = UDim2.new(0.5, 0, 1, -22)
	tapButton.Size = UDim2.fromOffset(124, 124)
end

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.ZIndex = 10
flash.Parent = gui
local bigText = label(gui, {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(700, 90),
	Text = "SUPER SAIYAN!",
	TextColor3 = PowerConfig.SSJAuraColor,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	ZIndex = 11,
})

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
	if charging or bursting then
		hint.Text = ""
	elseif attr("Form") == "SSJ" then
		hint.Text = UserInputService.TouchEnabled and "POWER button  —  power down" or "R  —  power down"
	else
		hint.Text = UserInputService.TouchEnabled and "POWER button  —  power up" or "R  —  power up"
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
	tapButton.Visible = on and UserInputService.TouchEnabled
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
	prompt.Text = UserInputService.TouchEnabled and "TAP!  TAP!  TAP!" or "SPAM  SPACE!"
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
			bigText.TextTransparency = 0
			bigText.TextStrokeTransparency = 0.2
			bigText.Size = UDim2.fromOffset(500, 70)
			TweenService:Create(bigText, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(760, 100) }):Play()
			task.delay(1.6, function()
				TweenService:Create(bigText, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
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
	barFill.Size = UDim2.new(charge, 0, 1, 0)
	grade.Contrast = 0.12 * charge
	grade.Saturation = 0.2 * charge
	barFill.BackgroundColor3 = PowerConfig.BaseAuraColor:Lerp(PowerConfig.SSJAuraColor, charge)
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
