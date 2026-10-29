--[[
	HairFitTool  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	A little panel for lining the hair up on the heads while the game is running.
	Press H (or tap the "Fit" button on a phone) to open or close it.

	  Prev / Next   pick which rig's hair you're moving (it gets an outline)
	  Up, Down, Left, Right, Fwd, Back   move it 0.05 studs (hold Shift on a keyboard
	                                      for 0.01)
	  Reset         undo this session's nudges

	The box at the bottom shows the Offset line for HairConfig, e.g.
	    Offset = CFrame.new(0, 0.05, -0.02),
	Copy it into that hair's entry in ReplicatedStorage > HairConfig to keep it.
	(The nudges only change what you see in this play session.)

	Turn the tool off with HairConfig.FitToolEnabled = false.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HairConfig = require(ReplicatedStorage:WaitForChild("HairConfig"))
local HairPhysics = require(ReplicatedStorage:WaitForChild("HairPhysics"))

if not HairConfig.FitToolEnabled then
	return
end

local STEP = 0.05
local FINE_STEP = 0.01

local player = Players.LocalPlayer
local nudges = {} -- [hair part] = total nudge this session (head space: right, up, back)
local selectedIndex = 1
local gui, title, readout, highlight

local function tagged(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged(HairPhysics.TAG) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return list
end

local function selectedHair(): BasePart?
	local list = tagged()
	if #list == 0 then
		return nil
	end
	selectedIndex = (selectedIndex - 1) % #list + 1
	return list[selectedIndex]
end

-- The weld holding the hair to the head, and the head.
local function findWeld(hair: BasePart): (JointInstance?, BasePart?)
	for _, child in hair:GetChildren() do
		if child:IsA("JointInstance") then
			local other = child.Part0 == hair and child.Part1 or child.Part0
			if other and other.Name == "Head" then
				return child, other
			end
		end
	end
	return nil
end

local function rigName(hair: BasePart): string
	local node = hair.Parent
	while node and not (node:IsA("Model") and node:FindFirstChildOfClass("Humanoid")) do
		node = node.Parent
	end
	return node and node.Name or "?"
end

local function offsetLine(hair: BasePart): string
	local preset = hair:GetAttribute("HairPreset")
	local cfg = HairConfig.Hairs[preset]
	local base = cfg and cfg.Offset or CFrame.identity
	local p = base.Position + (nudges[hair] or Vector3.zero)
	local function n(x: number): string
		local str = string.format("%.2f", x)
		if str == "0.00" or str == "-0.00" then
			return "0"
		end
		return (str:gsub("0+$", ""):gsub("%.$", ""))
	end
	return ("Offset = CFrame.new(%s, %s, %s),"):format(n(p.X), n(p.Y), n(p.Z))
end

local function refresh()
	if not gui then
		return
	end
	local hair = selectedHair()
	if hair then
		title.Text = ("Hair fit: %s (%s)"):format(rigName(hair), tostring(hair:GetAttribute("HairPreset")))
		readout.Text = offsetLine(hair)
		highlight.Adornee = hair
	else
		title.Text = "Hair fit: no hair found yet"
		readout.Text = ""
		highlight.Adornee = nil
	end
end

-- Moves a hair by delta (head space: right, up, back) by adjusting the weld that holds it.
local function applyDelta(hair: BasePart, delta: Vector3)
	local weld, head = findWeld(hair)
	if not weld or not head then
		warn("[HairFitTool] couldn't find the weld holding " .. hair:GetFullName())
		return
	end
	if weld.Part0 == head then
		local current = weld.C0 * weld.C1:Inverse()
		weld.C0 = CFrame.new(delta) * current * weld.C1
	else
		local current = weld.C1 * weld.C0:Inverse()
		weld.C1 = CFrame.new(delta) * current * weld.C0
	end
	nudges[hair] = (nudges[hair] or Vector3.zero) + delta
	refresh()
end

local function nudge(direction: Vector3)
	local hair = selectedHair()
	if hair then
		local fine = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		applyDelta(hair, direction * (fine and FINE_STEP or STEP))
	end
end

local function reset()
	local hair = selectedHair()
	if hair and nudges[hair] then
		applyDelta(hair, -nudges[hair])
		nudges[hair] = Vector3.zero
		refresh()
	end
end

local function makeButton(parent: Instance, text: string, pos: UDim2, size: UDim2, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.Text = text
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextScaled = true
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	b.Activated:Connect(onClick)
	b.Parent = parent
	return b
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "HairFitTool"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 12, 1, -12)
	frame.Size = UDim2.fromOffset(300, 250)
	frame.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
	frame.BackgroundTransparency = 0.1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local w, h = 88, 32
	local function at(col: number, row: number)
		return UDim2.fromOffset(10 + col * (w + 6), 36 + row * (h + 6))
	end
	local size = UDim2.fromOffset(w, h)
	makeButton(frame, "Prev", at(0, 0), size, function()
		selectedIndex -= 1
		refresh()
	end)
	makeButton(frame, "Reset", at(1, 0), size, reset)
	makeButton(frame, "Next", at(2, 0), size, function()
		selectedIndex += 1
		refresh()
	end)
	makeButton(frame, "Up", at(1, 1), size, function()
		nudge(Vector3.yAxis)
	end)
	makeButton(frame, "Left", at(0, 2), size, function()
		nudge(-Vector3.xAxis)
	end)
	makeButton(frame, "Down", at(1, 2), size, function()
		nudge(-Vector3.yAxis)
	end)
	makeButton(frame, "Right", at(2, 2), size, function()
		nudge(Vector3.xAxis)
	end)
	makeButton(frame, "Fwd", at(0, 1), size, function()
		nudge(-Vector3.zAxis)
	end)
	makeButton(frame, "Back", at(2, 1), size, function()
		nudge(Vector3.zAxis)
	end)

	-- a TextBox so the line can be selected and copied
	readout = Instance.new("TextBox")
	readout.ClearTextOnFocus = false
	readout.TextEditable = false
	readout.Position = UDim2.fromOffset(10, 36 + 3 * (h + 6) + 4)
	readout.Size = UDim2.new(1, -20, 0, 30)
	readout.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
	readout.TextColor3 = Color3.fromRGB(140, 220, 160)
	readout.Font = Enum.Font.Code
	readout.TextScaled = true
	readout.Parent = frame
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 6)
	rc.Parent = readout

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(10, 36 + 3 * (h + 6) + 38)
	hint.Size = UDim2.new(1, -20, 0, 16)
	hint.Font = Enum.Font.Gotham
	hint.TextColor3 = Color3.fromRGB(170, 175, 185)
	hint.TextScaled = true
	hint.Text = "Copy this line into HairConfig to keep it"
	hint.Parent = frame

	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 200, 60)
	highlight.Enabled = false
	highlight.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function toggle(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not gui then
		buildGui()
	end
	gui.Enabled = not gui.Enabled
	highlight.Enabled = gui.Enabled
	refresh()
	if gui.Enabled then
		local hair = selectedHair()
		if hair then
			print("[HairFitTool] " .. tostring(hair:GetAttribute("HairPreset")) .. ": " .. offsetLine(hair))
		end
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("HairFitTool", toggle, true, HairConfig.FitToolKey or Enum.KeyCode.H)
ContextActionService:SetTitle("HairFitTool", "Fit")
ContextActionService:SetPosition("HairFitTool", UDim2.new(1, -70, 0, 10))
