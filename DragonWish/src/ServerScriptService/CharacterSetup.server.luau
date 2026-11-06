--[[
	CharacterSetup  (Script — lives in ServerScriptService)

	Turns every player into the "Base" rig (ReplicatedStorage > Base) with the base hair and
	the belt on:
	  1. When the server starts it copies Base, puts the rigged base hair, the (hidden) Super
	     Saiyan hair and the belt on it, and makes that copy the StarterCharacter — Roblox's
	     built-in way of giving every player a custom character.
	  2. Players' own avatars are not loaded onto it, and anything that still sneaks on
	     (clothing, accessories, body colours from their avatar) is stripped off when they spawn.

	The rigged pieces are found in ServerStorage > CharacterParts (import the three .fbx files
	there). Settings: ReplicatedStorage > HairConfig and PowerConfig.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local HairConfig = require(ReplicatedStorage:WaitForChild("HairConfig"))
local HairPhysics = require(ReplicatedStorage:WaitForChild("HairPhysics"))
local PowerConfig = require(ReplicatedStorage:WaitForChild("PowerConfig"))

local PIECES = { "BaseHair", "SSJHair", "Belt" }
local OWNED = "DWOwned" -- marks things that belong to the Base rig (never stripped)

local function log(message: string)
	print("[CharacterSetup] " .. message)
end

local function complain(message: string)
	warn("[CharacterSetup] " .. message)
end

----------------------------------------------------------------------------------------
-- finding and copying the imported rigged pieces
----------------------------------------------------------------------------------------
local function partOfBone(bone: Instance): BasePart?
	local node = bone.Parent
	while node and not node:IsA("BasePart") do
		node = node.Parent
	end
	return node :: BasePart?
end

local function findSource(signature: string): (Bone?, string?)
	for _, container in { ServerStorage, ReplicatedStorage, Workspace } do
		local folder = container:FindFirstChild(HairConfig.ModelFolder)
		if folder then
			local bone = folder:FindFirstChild(signature, true)
			if bone and bone:IsA("Bone") then
				return bone, folder:GetFullName()
			end
		end
	end
	-- forgiving: imported but left loose in Workspace / ServerStorage
	for _, container in { Workspace, ServerStorage } do
		for _, d in container:GetDescendants() do
			if d.Name == signature and d:IsA("Bone") then
				return d, container.Name
			end
		end
	end
	return nil
end

-- A copy of the mesh with all its bones inside it (moves bones in if the importer put them
-- in a separate part — same place in the world, so the skinning is unchanged).
local function copyMesh(signatureBone: Bone): BasePart?
	local original = partOfBone(signatureBone)
	if not original then
		return nil
	end
	local holder: Instance = signatureBone:FindFirstAncestorWhichIsA("Model") or original
	if holder:IsA("Workspace") then
		holder = original
	end
	local copy = holder:Clone() or original:Clone()
	if not copy then
		return nil
	end
	local bone = copy:FindFirstChild(signatureBone.Name, true)
	local bonePart = bone and partOfBone(bone)
	if not bonePart then
		copy:Destroy()
		return nil
	end
	local mesh = bonePart
	if not bonePart:IsA("MeshPart") then
		local found = copy:IsA("MeshPart") and copy or copy:FindFirstChildWhichIsA("MeshPart", true)
		if found then
			mesh = found
			for _, child in bonePart:GetChildren() do
				if child:IsA("Bone") then
					child.CFrame = mesh.CFrame:ToObjectSpace(bonePart.CFrame * child.CFrame)
					child.Parent = mesh
				end
			end
		end
	end
	if mesh ~= copy then
		mesh.Parent = nil
		copy:Destroy()
	end
	for _, d in mesh:GetDescendants() do
		if d.Parent and not (d:IsA("Bone") or d:IsA("SurfaceAppearance")) then
			d:Destroy()
		end
	end
	return mesh
end

local function bonePairs(mesh: BasePart, layout)
	local design, actual = {}, {}
	for name, modeled in layout.Bones do
		local bone = mesh:FindFirstChild(name, true)
		if bone and bone:IsA("Bone") then
			local cf = HairPhysics.PartSpaceCFrame(bone, mesh)
			if cf then
				table.insert(design, modeled)
				table.insert(actual, cf.Position)
			end
		end
	end
	return design, actual
end

----------------------------------------------------------------------------------------
-- putting one piece on the rig
----------------------------------------------------------------------------------------
local function attachPiece(rig: Model, name: string): boolean
	local cfg = HairConfig.Hairs[name]
	local layout = HairConfig.Layouts[name]
	local attachPart = rig:FindFirstChild(layout.Attach)
	if not (attachPart and attachPart:IsA("BasePart")) then
		complain(("the Base rig has no %s part to put the %s on"):format(layout.Attach, name))
		return false
	end
	local bone, where = findSource(cfg.SignatureBone)
	if not bone then
		complain(
			("couldn't find the rigged %s. Import %s_Rigged.fbx (File > Import 3D) and put it in ServerStorage > %s."):format(
				name,
				name,
				HairConfig.ModelFolder
			)
		)
		return false
	end
	local mesh = copyMesh(bone)
	if not mesh then
		complain(("found the %s bones in %s but no mesh next to them"):format(name, where or "?"))
		return false
	end
	mesh.Name = name
	mesh.Anchored = false
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.Massless = true
	if mesh:IsA("MeshPart") and cfg.TextureId and cfg.TextureId ~= "" then
		mesh.TextureID = cfg.TextureId
	end
	if cfg.Color then
		mesh.Color = cfg.Color
	end
	if cfg.Material then
		mesh.Material = cfg.Material
	end

	-- where it goes: compare the modeled bone positions with the imported ones
	local design, actual = bonePairs(mesh, layout)
	if #design < 3 then
		complain(("the %s is missing its bones (found %d) — re-import it and keep the rig"):format(name, #design))
		mesh:Destroy()
		return false
	end
	local fit = HairPhysics.FitRig(design, actual)
	local wantScale = cfg.Scale or 1
	if cfg.ScaleToHead and attachPart:IsA("MeshPart") then
		local ratio = (attachPart.Size.X + attachPart.Size.Z) * 0.5 / (HairConfig.ReferenceHeadWidth or 1.2)
		if ratio > 0.5 and ratio < 3 then
			wantScale *= ratio
		end
	end
	if math.abs(fit.Scale / wantScale - 1) > 0.02 then
		local temp = Instance.new("Model")
		mesh.Parent = temp
		local ok, err = pcall(function()
			temp:ScaleTo(temp:GetScale() * wantScale / fit.Scale)
		end)
		mesh.Parent = nil
		temp:Destroy()
		if ok then
			design, actual = bonePairs(mesh, layout)
			fit = HairPhysics.FitRig(design, actual)
		else
			complain("couldn't resize the " .. name .. ": " .. tostring(err))
		end
	end
	if fit.Error > 0.05 * math.max(fit.Scale, 0.01) then
		complain(("the %s's bones don't match the expected layout (off by %.2f studs)"):format(name, fit.Error))
	end
	local centre = (layout.HeadCenter or Vector3.zero) * fit.Scale
	local attachToMesh = cfg.Offset * CFrame.new(-centre) * HairPhysics.HeadToPart(fit)

	local holder = Instance.new("Model")
	holder.Name = "DW_" .. name
	holder:SetAttribute(OWNED, true)
	mesh.CFrame = attachPart.CFrame * attachToMesh
	mesh.Parent = holder
	local weld = Instance.new("Weld")
	weld.Name = "DWWeld"
	weld.Part0 = attachPart
	weld.Part1 = mesh
	weld.C0 = attachToMesh
	weld.Parent = mesh
	mesh:SetAttribute("HairPreset", name)
	mesh:SetAttribute("VisibleIn", cfg.VisibleIn or "Both")
	mesh.Transparency = (cfg.VisibleIn == "SSJ") and 1 or 0
	CollectionService:AddTag(mesh, HairPhysics.TAG)
	holder.Parent = rig
	log(("put the %s on the %s (%d bones lined up)"):format(name, layout.Attach, #design))
	return true
end

----------------------------------------------------------------------------------------
-- build the StarterCharacter
----------------------------------------------------------------------------------------
local base = ReplicatedStorage:WaitForChild(PowerConfig.BaseRigName, 20)
if not (base and base:IsA("Model") and base:FindFirstChildOfClass("Humanoid")) then
	complain(("there's no R15 rig called '%s' (with a Humanoid) in ReplicatedStorage"):format(PowerConfig.BaseRigName))
	return
end

local template = base:Clone()
for _, d in template:GetDescendants() do
	-- the rig's own clothes / accessories are kept; only the players' avatar items get stripped
	if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("CharacterMesh") then
		d:SetAttribute(OWNED, true)
	end
	if d:IsA("BasePart") then
		d.Anchored = false
	end
end
for _, name in PIECES do
	local ok, err = pcall(attachPiece, template, name)
	if not ok then
		complain(("putting on the %s failed: %s"):format(name, tostring(err)))
	end
end
template:SetAttribute("Form", "Base")
template:SetAttribute("PowerState", "Idle")
template:SetAttribute("Charge", 0)
template:SetAttribute("AuraWind", 0)
template.Name = "StarterCharacter"

local old = StarterPlayer:FindFirstChild("StarterCharacter")
if old then
	old:Destroy()
end
template.Parent = StarterPlayer

-- players' own avatars shouldn't be loaded onto the rig
local okAppearance = pcall(function()
	StarterPlayer.LoadCharacterAppearance = false
end)
if not okAppearance then
	complain("couldn't switch off StarterPlayer.LoadCharacterAppearance from a script — untick it in StarterPlayer's properties")
end
log("players now spawn as " .. PowerConfig.BaseRigName)

----------------------------------------------------------------------------------------
-- strip anything from the player's avatar that still gets added
----------------------------------------------------------------------------------------
local function isAvatarItem(inst: Instance): boolean
	return (
		inst:IsA("Accessory")
		or inst:IsA("Clothing")
		or inst:IsA("ShirtGraphic")
		or inst:IsA("BodyColors")
		or inst:IsA("CharacterMesh")
	) and not inst:GetAttribute(OWNED)
end

local function onCharacter(character: Model)
	for _, d in character:GetDescendants() do
		if isAvatarItem(d) then
			d:Destroy()
		end
	end
	-- avatar items can arrive a moment after spawning
	local connection = character.DescendantAdded:Connect(function(d)
		if isAvatarItem(d) then
			task.defer(function()
				if d.Parent then
					d:Destroy()
				end
			end)
		end
	end)
	task.delay(15, function()
		connection:Disconnect()
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		-- spawned before the morph was ready (can happen when testing in Studio): respawn
		if not player.Character:FindFirstChild("DW_Belt") and not player.Character:FindFirstChild("DW_BaseHair") then
			player:LoadCharacter()
		else
			onCharacter(player.Character)
		end
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
