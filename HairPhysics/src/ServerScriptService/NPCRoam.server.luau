--[[
	NPCRoam  (Script — lives in ServerScriptService)

	Test script: makes the rigs walk to random spots (inside the TestArena, if it's in
	Workspace), jump at random, pause, and sometimes turn around sharply — so you can see
	the hair swing, bounce and settle.
	It also plays Roblox's default walk / idle / jump / fall animations on them.

	Delete this script (or set ENABLED = false) once you're happy with the hair.
]]

----------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------
local ENABLED = true
local RIGS = { "MrPigtails", "MrLady" } -- rigs in Workspace to move around
local ARENA_NAME = "TestArena" -- if this model is in Workspace, they roam inside it
local ARENA_MARGIN = 5 -- keep this far (studs) from the arena walls
local ROAM_RADIUS = 30 -- with no arena: how far (studs) from their starting spot they wander
local WALK_SPEED_MIN = 8 -- they pick a random speed between these for each walk
local WALK_SPEED_MAX = 16
local JUMPS_PER_SECOND = 0.35 -- average number of random jumps per second while walking
local PAUSE_MIN = 0.4 -- seconds they stand still between walks
local PAUSE_MAX = 2.5
local TURN_AROUND_CHANCE = 0.3 -- chance to spin round on the spot after a walk (hair whip test)
local JUMP_IN_PLACE_CHANCE = 0.3 -- chance to jump while standing still

-- Roblox's default character animations (the same ones the built-in Animate script uses)
local ANIMATIONS = {
	R15 = {
		idle = "rbxassetid://507766666",
		walk = "rbxassetid://507777826",
		run = "rbxassetid://507767714",
		jump = "rbxassetid://507765000",
		fall = "rbxassetid://507767968",
	},
	R6 = {
		idle = "rbxassetid://180435571",
		walk = "rbxassetid://180426354",
		run = "rbxassetid://180426354",
		jump = "rbxassetid://125750702",
		fall = "rbxassetid://180436148",
	},
}
----------------------------------------------------------------------------------------

if not ENABLED then
	return
end

local Workspace = game:GetService("Workspace")

local rigModels = {}

local function setupAnimations(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local set = humanoid.RigType == Enum.HumanoidRigType.R6 and ANIMATIONS.R6 or ANIMATIONS.R15
	local tracks = {}
	for name, id in set do
		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok then
			track.Looped = name ~= "jump"
			track.Priority = Enum.AnimationPriority.Core
			tracks[name] = track
		else
			warn("[NPCRoam] couldn't load the " .. name .. " animation: " .. tostring(track))
		end
	end

	local current
	local function play(name: string, speed: number?)
		local track = tracks[name]
		if not track then
			return
		end
		if current ~= track then
			if current then
				current:Stop(0.2)
			end
			track:Play(0.2)
			current = track
		end
		track:AdjustSpeed(speed or 1)
	end

	local airborne = false
	humanoid.Running:Connect(function(speed: number)
		if airborne then
			return
		end
		if speed > 0.75 then
			if speed > 12 and tracks.run then
				play("run", speed / 16)
			else
				play("walk", math.clamp(speed / 10, 0.6, 1.6))
			end
		else
			play("idle")
		end
	end)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			airborne = true
			play("jump")
		elseif new == Enum.HumanoidStateType.Freefall then
			airborne = true
			task.delay(0.2, function()
				if airborne and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
					play("fall")
				end
			end)
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			airborne = false
			local speed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			if speed > 0.75 then
				play("walk", math.clamp(speed / 10, 0.6, 1.6))
			else
				play("idle")
			end
		end
	end)
	play("idle")
end

-- Random spot on the ground: inside the arena if there is one, otherwise near home
-- (raycasts down so they don't walk into the void).
local function pickGoal(home: Vector3, rng: Random): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = rigModels
	params.IgnoreWater = true -- aim for the floor under the arena's water, not the water surface
	local arena = Workspace:FindFirstChild(ARENA_NAME)
	local floor = arena and arena:FindFirstChild("Floor")
	for _ = 1, 12 do
		local probe
		if floor and floor:IsA("BasePart") then
			local size = arena:GetAttribute("InteriorSize") or Vector3.new(64, 24, 64)
			local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
			local hx, hz = size.X / 2 - ARENA_MARGIN, size.Z / 2 - ARENA_MARGIN
			probe = top * Vector3.new(rng:NextNumber(-hx, hx), size.Y - 2, rng:NextNumber(-hz, hz))
		else
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(6, ROAM_RADIUS)
			probe = home + Vector3.new(math.cos(angle) * dist, 40, math.sin(angle) * dist)
		end
		local hit = Workspace:Raycast(probe, Vector3.new(0, -120, 0), params)
		if hit and hit.Instance.CanCollide then
			return hit.Position
		end
	end
	return nil
end

local function tryJump(humanoid: Humanoid)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.Jump = true
	end
end

local function walkTo(humanoid: Humanoid, goal: Vector3, rng: Random)
	local done = false
	local connection = humanoid.MoveToFinished:Connect(function()
		done = true
	end)
	humanoid:MoveTo(goal)
	local started = os.clock()
	while not done and os.clock() - started < 8 and humanoid.Health > 0 do
		if rng:NextNumber() < JUMPS_PER_SECOND * 0.25 then
			tryJump(humanoid)
		end
		task.wait(0.25)
	end
	connection:Disconnect()
end

local function roam(rig: Model)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		warn("[NPCRoam] " .. rig.Name .. " needs a Humanoid and a HumanoidRootPart")
		return
	end

	-- rigs made with the Rig Builder are often anchored; they can't walk like that
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	-- the server drives them, so the server should own their physics (stops stutter near players)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	setupAnimations(humanoid)

	local rng = Random.new()
	task.wait(rng:NextNumber(1, 2)) -- lets ArenaSetup put them in the arena, and stops them moving in sync
	local home = root.Position

	while rig.Parent and humanoid.Health > 0 do
		local goal = pickGoal(home, rng)
		if goal then
			humanoid.WalkSpeed = rng:NextNumber(WALK_SPEED_MIN, WALK_SPEED_MAX)
			walkTo(humanoid, goal, rng)
		end

		if rng:NextNumber() < TURN_AROUND_CHANCE then
			-- step a little behind themselves: a fast 180° turn
			humanoid.WalkSpeed = WALK_SPEED_MAX
			local back = root.Position - root.CFrame.LookVector * 2.5
			walkTo(humanoid, back, rng)
		end
		if rng:NextNumber() < JUMP_IN_PLACE_CHANCE then
			tryJump(humanoid)
		end
		task.wait(rng:NextNumber(PAUSE_MIN, PAUSE_MAX))
	end
end

for _, name in RIGS do
	local rig = Workspace:WaitForChild(name, 20)
	if rig and rig:IsA("Model") then
		table.insert(rigModels, rig)
	else
		warn("[NPCRoam] no rig called '" .. name .. "' in Workspace")
	end
end
for _, rig in rigModels do
	task.spawn(roam, rig)
end
