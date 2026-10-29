--[[
	ArenaControls  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Press Z (or tap the "Gate" button on a phone) to open / close the TestArena's drain gate.
	A small label at the top of the screen shows whether it's open.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local KEY = Enum.KeyCode.Z

local remote = ReplicatedStorage:WaitForChild("ArenaGate")
local arena = Workspace:WaitForChild("TestArena", 30)

local label = Instance.new("TextLabel")
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArenaControls"
	gui.ResetOnSpawn = false
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.fromOffset(420, 28)
	label.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = label
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function refresh()
	local open = arena and arena:GetAttribute("GateOpen")
	local level = arena and arena:GetAttribute("WaterLevel")
	local water = ""
	if level then
		local tap = arena:GetAttribute("TapOn")
		water = ("Water %.1f studs%s   ·   "):format(level, tap and " (filling)" or (open and level > 0.05 and " (draining)" or ""))
	end
	label.Text = ("%sDrain gate: %s   (press Z)"):format(water, open and "OPEN" or "closed")
	label.TextColor3 = open and Color3.fromRGB(120, 210, 255) or Color3.new(1, 1, 1)
end

if arena then
	arena:GetAttributeChangedSignal("GateOpen"):Connect(refresh)
	arena:GetAttributeChangedSignal("WaterLevel"):Connect(refresh)
	arena:GetAttributeChangedSignal("TapOn"):Connect(refresh)
end
refresh()

ContextActionService:BindAction("ArenaGate", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		remote:FireServer("Toggle")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, true, KEY)
ContextActionService:SetTitle("ArenaGate", "Gate")
