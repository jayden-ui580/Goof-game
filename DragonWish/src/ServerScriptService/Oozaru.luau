--[[
	Oozaru  (ModuleScript — lives in ServerScriptService)

	Builds the Great Ape and swaps players in and out of it (PowerUpServer decides when).
	  * The giant is made once, from the rigged model imported from Oozaru_Rigged.fbx (put it in
	    ServerStorage > CharacterParts; it's found by its tail-tip bone, TAIL18). Its bones are
	    compared with where they were designed (OozaruRig) to learn how the importer sized and
	    turned it; it's then resized to PowerConfig.OozaruScale and stood upright on the spot.
	  * It gets a HumanoidRootPart (an invisible box round the body that does the walking and
	    bumping into things), a Humanoid, and everything welded on. Bone poses are drawn by
	    OozaruFX on every player's screen.
	  * Turning into it: a copy is put where you stand, facing your way, and becomes your
	    character; your own body is kept aside (with its hair, belt, health share and ki) and
	    put back exactly where the giant stands when you turn back.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local HairConfig = require(ReplicatedStorage:WaitForChild("HairConfig"))
local HairPhysics = require(ReplicatedStorage:WaitForChild("HairPhysics"))
local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))
local OozaruRig = require(script.Parent:WaitForChild("OozaruRig"))

local Oozaru = {}
Oozaru.Tag = "DW_Oozaru"

-- the attributes that carry over between your body and the giant
local CARRY = { "Ki" }

local template: Model? = nil
local problem: string? = nil
local stash = {} -- [player] = your own body while you're the giant
local stashFolder: Folder? = nil

local function log(message: string)
	print("[Oozaru] " .. message)
end

local function complain(message: string)
	warn("[Oozaru] " .. message)
end

local function partOfBone(bone: Instance): BasePart?
	local node = bone.Parent
	while node and not node:IsA("BasePart") do
		node = node.Parent
	end
	return node :: BasePart?
end

-- the imported model (searched the same places CharacterSetup looks)
local function findSource(): Bone?
	local signature = OozaruRig.SignatureBone
	for _, container in { ServerStorage, ReplicatedStorage, Workspace } do
		local folder = container:FindFirstChild(HairConfig.ModelFolder)
		local bone = folder and folder:FindFirstChild(signature, true)
		if bone and bone:IsA("Bone") then
			return bone
		end
	end
	for _, container in { ServerStorage, Workspace } do
		for _, d in container:GetDescendants() do
			if d.Name == signature and d:IsA("Bone") and not d:FindFirstAncestorWhichIsA("Humanoid") then
				local model = d:FindFirstAncestorWhichIsA("Model")
				if not (model and CollectionService:HasTag(model, Oozaru.Tag)) then
					return d
				end
			end
		end
	end
	return nil
end

-- a bone's name without anything an importer may have added ("Armature:WAIST" -> "WAIST")
local function canonical(name: string): string
	return string.upper(string.match(name, "[^:|/]+$") or name)
end

-- The skeleton: the fullest copy of it (an importer can give each mesh its own copy), as
-- name -> bone, plus the part holding it, how many bones it has, and how many copies there are
local function skeleton(model: Model)
	local perPart, total = {}, 0
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			local part = partOfBone(d)
			if part then
				perPart[part] = (perPart[part] or 0) + 1
			end
			total += 1
		end
	end
	local holder, most = nil, 0
	for part, n in perPart do
		if n > most then
			holder, most = part, n
		end
	end
	local map = {}
	if holder then
		for _, d in holder:GetDescendants() do
			if d:IsA("Bone") then
				local key = canonical(d.Name)
				map[key] = map[key] or d
			end
		end
	end
	return map, holder, most, (most > 0) and math.floor(total / most + 0.5) or 0
end

-- where each designed bone ended up (world positions), for fitting
local function bonePairs(model: Model)
	local design, actual = {}, {}
	local map = skeleton(model)
	for name, modeled in OozaruRig.Bones do
		local bone = map[name]
		local part = bone and partOfBone(bone)
		if part then
			local cf = HairPhysics.PartSpaceCFrame(bone, part)
			if cf then
				table.insert(design, modeled)
				table.insert(actual, (part.CFrame * cf).Position)
			end
		end
	end
	return design, actual
end

local COLOURS = { -- mesh name -> colour (the meshes are named by build_oozaru.py)
	{ "EarInner", Color3.fromRGB(150, 82, 52) },
	{ "Fur", nil }, -- PowerConfig.OozaruFur
	{ "Skin", nil }, -- PowerConfig.OozaruSkin
	{ "Face", nil },
	{ "Ink", Color3.fromRGB(22, 16, 16) },
	{ "Mouth", Color3.fromRGB(118, 26, 32) },
	{ "Teeth", Color3.fromRGB(245, 240, 226) },
	{ "Eyes", nil }, -- PowerConfig.OozaruEyes, glowing
}

local function paint(part: BasePart)
	for _, entry in COLOURS do
		local key = entry[1]
		if string.find(part.Name, key, 1, true) then
			local colour = entry[2]
			if key == "Fur" then
				colour = PowerConfig.OozaruFur
			elseif key == "Skin" or key == "Face" then
				colour = PowerConfig.OozaruSkin
			elseif key == "Eyes" then
				colour = PowerConfig.OozaruEyes
				part.Material = Enum.Material.Neon
				local glow = Instance.new("PointLight")
				glow.Name = "EyeGlow"
				glow.Color = PowerConfig.OozaruEyes
				glow.Brightness = 2.5
				glow.Range = 14
				glow.Shadows = false
				glow.Parent = part
			end
			if colour then
				part.Color = colour
			end
			if key ~= "Eyes" then
				part.Material = Enum.Material.SmoothPlastic
			end
			return
		end
	end
end

local function build(): Model
	local bone = findSource()
	if not bone then
		error(("couldn't find the Great Ape model (looking for its bone '%s'). Import Oozaru_Rigged.fbx (File > Import 3D) and put it in ServerStorage > %s."):format(
			OozaruRig.SignatureBone, HairConfig.ModelFolder), 0)
	end
	-- copy the whole imported model (all its meshes share one skeleton)
	local source: Instance? = bone:FindFirstAncestorWhichIsA("Model")
	if not source or source:IsA("WorldRoot") then
		local part = partOfBone(bone)
		source = part and part.Parent
	end
	if not source then
		error("found the Great Ape's bones but no model around them", 0)
	end
	local copy = (source :: Instance):Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	else
		model = Instance.new("Model")
		for _, child in copy:GetChildren() do
			child.Parent = model
		end
		copy:Destroy()
	end
	-- keep the meshes and bones; drop what the importer may have added (scripts, a Humanoid or
	-- AnimationController, joints holding the meshes together)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("AnimationController") or d:IsA("Animator")
			or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint")
		then
			d:Destroy()
		end
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		error("the Great Ape model has no meshes in it", 0)
	end

	-- how it came in: size and turn, from its bones
	local design, actual = bonePairs(model)
	if #design < 10 then
		local total = 0
		for _ in OozaruRig.Bones do
			total += 1
		end
		error(("the Great Ape is missing its bones (found %d of %d): re-import it with the rig"):format(#design, total), 0)
	end
	local fit = HairPhysics.FitRig(design, actual)
	local want = PowerConfig.OozaruScale or 3.2
	if math.abs(fit.Scale / want - 1) > 0.02 then
		local ok, err = pcall(function()
			model:ScaleTo(model:GetScale() * want / fit.Scale)
		end)
		if not ok then
			complain("couldn't resize the Great Ape (it keeps the size it was imported at): " .. tostring(err))
		end
		design, actual = bonePairs(model)
		fit = HairPhysics.FitRig(design, actual)
	end
	if fit.Error > 0.05 * fit.Scale then
		complain(("the Great Ape's bones don't match the expected layout (off by %.2f studs): re-import the latest Oozaru_Rigged.fbx"):format(fit.Error))
	end
	local s = fit.Scale

	-- stand it on the origin, upright, facing -Z (the way characters face)
	local placed = (CFrame.new(fit.Translation) * fit.Rotation):Inverse()
	for _, part in parts do
		part.CFrame = placed * part.CFrame
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		paint(part)
	end

	-- the body that walks: a box from just under the hips to the head
	local hipHeight = 4.0 * s
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4.0, 4.4, 2.6) * s
	root.CFrame = CFrame.new(0, hipHeight + root.Size.Y / 2, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.Anchored = false
	root.Parent = model
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.RequiresNeck = false -- (it has no neck joint: bones do the bending)
	humanoid.BreakJointsOnDeath = false
	humanoid.AutomaticScalingEnabled = false
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0 -- far too heavy to jump
	humanoid.WalkSpeed = PowerConfig.OozaruWalkSpeed
	humanoid.MaxHealth = PowerConfig.OozaruHealth
	humanoid.Health = PowerConfig.OozaruHealth
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.Name = "GreatApe"
	model.PrimaryPart = root
	model:SetAttribute("Oozaru", true)
	model:SetAttribute("OozaruScale", s)
	model:SetAttribute("Form", "Oozaru")
	model:SetAttribute("PowerState", "Idle")
	model:SetAttribute("Charge", 0)
	model:SetAttribute("AuraWind", 0)
	model:SetAttribute("Breeze", 0)
	model:SetAttribute("Kaioken", 0)
	model:SetAttribute("KaiokenMult", 1)
	model:SetAttribute("Exhausted", false)
	CollectionService:AddTag(model, Oozaru.Tag)
	local map, holder, count, copies = skeleton(model)
	local missing = {}
	for _, name in { "WAIST", "THIGH_L", "CLANK_L", "TOE1_L", "THIGH_R", "CLANK_R", "TOE1_R", "SPINE1", "HEAD", "CHIN" } do
		if not map[name] then
			table.insert(missing, name)
		end
	end
	log(("built the Great Ape: %d meshes, %d bones lined up, %.1f studs tall; skeleton of %d bones in %s%s"):format(
		#parts, #design, (OozaruRig.Bounds[2].Y - OozaruRig.Bounds[1].Y) * s, count, holder and holder.Name or "?",
		(copies > 1) and (" (%d copies)"):format(copies) or ""))
	if #missing > 0 then
		complain("its skeleton is missing " .. table.concat(missing, ", ") .. ": it won't animate. Re-import Oozaru_Rigged.fbx with Rig Type Custom and \"Keep Zero Influence Bones\" ticked")
	end
	return model
end

-- builds the giant the first time it's asked for; nil (and why) if it can't
function Oozaru.Available(): (boolean, string?)
	if template then
		return true
	end
	if problem then
		return false, problem
	end
	local ok, result = pcall(build)
	if ok then
		template = result
		return true
	end
	problem = tostring(result)
	complain(problem)
	return false, problem
end

local function groundUnder(character: Model, root: BasePart, humanoid: Humanoid): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(root.CFrame.Position, Vector3.new(0, -(humanoid.HipHeight + root.Size.Y) * 2 - 4, 0), params)
	if hit then
		return hit.Position.Y
	end
	return root.CFrame.Position.Y - humanoid.HipHeight - root.Size.Y / 2
end

local function facing(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	return CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
end

-- you become the giant; returns it (nil if it couldn't be built)
function Oozaru.SwapIn(player: Player): Model?
	local human = player.Character
	local humanoid = human and human:FindFirstChildOfClass("Humanoid")
	local root = human and human:FindFirstChild("HumanoidRootPart")
	if not (human and humanoid and root and Oozaru.Available()) then
		return nil
	end
	local ape = (template :: Model):Clone()
	ape.Name = player.Name
	local apeHumanoid = ape:FindFirstChildOfClass("Humanoid") :: Humanoid
	local apeRoot = ape:FindFirstChild("HumanoidRootPart") :: BasePart
	-- standing where you stood, facing your way (its root part sits HipHeight above the ground)
	local ground = groundUnder(human, root :: BasePart, humanoid)
	local up = apeHumanoid.HipHeight + apeRoot.Size.Y / 2
	local spot = CFrame.new(root.CFrame.Position.X, ground + up, root.CFrame.Position.Z) * facing(root :: BasePart)
	ape:PivotTo(spot * apeRoot.CFrame:Inverse() * ape:GetPivot())
	for _, name in CARRY do
		ape:SetAttribute(name, human:GetAttribute(name))
	end
	local share = (humanoid.MaxHealth > 0) and humanoid.Health / humanoid.MaxHealth or 1
	apeHumanoid.Health = math.max(1, apeHumanoid.MaxHealth * share)
	apeHumanoid.WalkSpeed = 0 -- (roaring first)
	ape:SetAttribute("OozaruAt", Workspace:GetServerTimeNow())
	ape:SetAttribute("OozaruUntil", (PowerConfig.OozaruTime or 0) > 0 and Workspace:GetServerTimeNow() + PowerConfig.OozaruTime or 0)
	ape.Parent = Workspace

	-- your body goes aside until you turn back
	if not stashFolder then
		stashFolder = Instance.new("Folder")
		stashFolder.Name = "DW_OozaruStash"
		stashFolder.Parent = ServerStorage
	end
	stash[player] = human
	player.Character = ape
	human.Parent = stashFolder
	pcall(function()
		apeRoot:SetNetworkOwner(player)
	end)
	return ape
end

-- every frame (PowerUpServer calls it): a giant that's been beaten goes back to the start like
-- any other death, and your body that was kept aside goes with it
function Oozaru.Step()
	for player, human in stash do
		local ape = player.Character
		local humanoid = ape and ape:FindFirstChildOfClass("Humanoid")
		if ape and ape:GetAttribute("Oozaru") and humanoid and humanoid.Health <= 0 and not ape:GetAttribute("Beaten") then
			ape:SetAttribute("Beaten", true)
			task.delay(Players.RespawnTime + 0.5, function()
				if player.Parent and player.Character == ape then
					player:LoadCharacter()
				end
				if stash[player] == human then
					stash[player] = nil
					human:Destroy()
				end
				if ape.Parent then
					ape:Destroy()
				end
			end)
		elseif not (ape and ape:GetAttribute("Oozaru")) then
			-- (respawned some other way while giant)
			stash[player] = nil
			human:Destroy()
		end
	end
end

-- you turn back into yourself where the giant stands; returns your body
function Oozaru.SwapOut(player: Player): Model?
	local ape = player.Character
	local human = stash[player]
	if not (ape and human and ape:GetAttribute("Oozaru")) then
		return nil
	end
	local apeHumanoid = ape:FindFirstChildOfClass("Humanoid")
	local apeRoot = ape:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = human:FindFirstChildOfClass("Humanoid")
	local root = human:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (apeHumanoid and apeRoot and humanoid and root) then
		return nil
	end
	local ground = apeRoot.CFrame.Position.Y - apeHumanoid.HipHeight - apeRoot.Size.Y / 2
	local spot = CFrame.new(apeRoot.CFrame.Position.X, ground + humanoid.HipHeight + root.Size.Y / 2, apeRoot.CFrame.Position.Z) * facing(apeRoot)
	human:PivotTo(spot * root.CFrame:Inverse() * human:GetPivot())
	for _, name in CARRY do
		human:SetAttribute(name, ape:GetAttribute(name))
	end
	local share = (apeHumanoid.MaxHealth > 0) and apeHumanoid.Health / apeHumanoid.MaxHealth or 1
	humanoid.Health = math.max(1, humanoid.MaxHealth * share)
	human:SetAttribute("Form", "Base")
	human:SetAttribute("PowerState", "Idle")
	stash[player] = nil
	human.Parent = Workspace
	player.Character = human
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	ape:SetAttribute("Gone", true)
	ape:Destroy()
	return human
end

function Oozaru.IsApe(character: Model?): boolean
	return character ~= nil and character:GetAttribute("Oozaru") == true
end

Players.PlayerRemoving:Connect(function(player)
	local human = stash[player]
	stash[player] = nil
	if human then
		human:Destroy()
	end
end)

return Oozaru
