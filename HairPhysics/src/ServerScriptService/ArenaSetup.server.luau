--[[
	ArenaSetup  (Script — lives in ServerScriptService)

	Runs the TestArena (the sealed glass-roofed box in Workspace):
	  * moves MrPigtails and MrLady onto their spots inside it when the game starts,
	  * makes every player spawn inside it (and puts them back in if they ever end up outside),
	  * opens / closes the drain gate when a player presses Z (or taps "Gate" on a phone).

	The arena keeps two attributes the upcoming water system will read:
	  InteriorSize  size of the inside of the box (studs)
	  GateOpen      true while the drain gate is open
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

----------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------
local ARENA_NAME = "TestArena"
local RIGS = { "MrPigtails", "MrLady" } -- each goes to the part called RigSpot_<name>
local GATE_TIME = 1.2 -- seconds the gate takes to slide open or shut
local GATE_COOLDOWN = 0.4 -- ignore Z presses closer together than this
----------------------------------------------------------------------------------------

local arena = Workspace:WaitForChild(ARENA_NAME, 10)
if not arena then
	warn("[ArenaSetup] no model called " .. ARENA_NAME .. " in Workspace — drop the TestArena from the kit into Workspace")
	return
end

local floor = arena:WaitForChild("Floor") :: BasePart
local spawnPad = arena:FindFirstChild("ArenaSpawn")
local drain = arena:FindFirstChild("Drain")
local gate = drain and drain:FindFirstChild("Gate")

-- The inside of the box as a CFrame (centre of the floor's top surface) plus its size.
local function interior(): (CFrame, Vector3)
	local size = arena:GetAttribute("InteriorSize") or Vector3.new(64, 24, 64)
	local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	return top, size
end

local function isInside(position: Vector3): boolean
	local top, size = interior()
	local p = top:PointToObjectSpace(position)
	return math.abs(p.X) < size.X / 2 and math.abs(p.Z) < size.Z / 2 and p.Y > -1 and p.Y < size.Y
end

-- Stands a model on top of a spot part, facing the way the spot faces.
local function standOn(model: Model, spot: BasePart)
	local pivot = model:GetPivot()
	local boxCF, boxSize = model:GetBoundingBox()
	local feetBelowPivot = pivot.Position.Y - (boxCF.Position.Y - boxSize.Y / 2)
	local base = spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
	local facing = spot.CFrame.LookVector
	model:PivotTo(CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z)) + Vector3.new(0, feetBelowPivot + 0.05, 0))
end

-- 1) dummies into the arena
for _, name in RIGS do
	task.spawn(function()
		local rig = Workspace:WaitForChild(name, 10)
		local spot = arena:FindFirstChild("RigSpot_" .. name)
		if rig and rig:IsA("Model") and spot and spot:IsA("BasePart") then
			standOn(rig, spot)
		elseif not rig then
			warn("[ArenaSetup] no rig called " .. name .. " in Workspace")
		end
	end)
end

-- 2) players spawn inside
local function onCharacter(player: Player, character: Model)
	task.wait(0.2) -- let Roblox finish placing the character first
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and spawnPad and not isInside(root.Position) then
		character:PivotTo(spawnPad.CFrame + Vector3.new(0, 3.5, 0))
	end
end

local function onPlayer(player: Player)
	if spawnPad and spawnPad:IsA("SpawnLocation") then
		player.RespawnLocation = spawnPad
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

-- 3) the drain gate
local remote = ReplicatedStorage:FindFirstChild("ArenaGate")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ArenaGate"
	remote.Parent = ReplicatedStorage
end

if gate and gate:IsA("BasePart") then
	local closedCF = gate.CFrame
	local openCF = closedCF + closedCF.UpVector * (gate.Size.Y + 0.1) -- slides up inside the wall
	local lastToggle = 0
	local function setGate(open: boolean)
		arena:SetAttribute("GateOpen", open)
		TweenService:Create(gate, TweenInfo.new(GATE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CFrame = open and openCF or closedCF,
		}):Play()
	end
	remote.OnServerEvent:Connect(function(player: Player, action)
		if action ~= "Toggle" or os.clock() - lastToggle < GATE_COOLDOWN then
			return
		end
		lastToggle = os.clock()
		setGate(not arena:GetAttribute("GateOpen"))
		print(("[ArenaSetup] %s %s the drain gate"):format(player.Name, arena:GetAttribute("GateOpen") and "opened" or "closed"))
	end)
	setGate(false)
else
	warn("[ArenaSetup] the arena has no Drain > Gate part")
end
