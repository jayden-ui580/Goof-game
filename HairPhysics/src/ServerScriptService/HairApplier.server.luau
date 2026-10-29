--[[
	HairApplier  (Script — lives in ServerScriptService)

	Puts the rigged hair on the rigs listed in HairConfig.Assignments
	(MrPigtails gets Pigtails, MrLady gets LadyHair) when the game starts.

	For each rig it:
	  1. finds the imported hair model (in ServerStorage > HairModels) by its bones,
	  2. copies just the hair MeshPart and its bones,
	  3. works out from the bone positions exactly where the hair sits on the head
	     (this also fixes the hair if the importer scaled or turned it),
	  4. wears it as a normal hair Accessory,
	  5. tags it "HairPhysics" so every player's computer starts simulating it.

	Nothing to edit here — settings are in HairConfig.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local HairConfig = require(ReplicatedStorage:WaitForChild("HairConfig"))
local HairPhysics = require(ReplicatedStorage:WaitForChild("HairPhysics"))

local RIG_WAIT_TIME = 20 -- seconds to wait for a rig to exist before giving up

local function log(message: string)
	print("[HairApplier] " .. message)
end

local function complain(message: string)
	warn("[HairApplier] " .. message)
end

-- The MeshPart that owns a bone (the first part above it).
local function partOfBone(bone: Instance): BasePart?
	local node = bone.Parent
	while node and not node:IsA("BasePart") do
		node = node.Parent
	end
	return node :: BasePart?
end

local function isInsideCharacter(inst: Instance): boolean
	local node = inst.Parent
	while node and node ~= game do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Finds the imported hair by looking for its signature bone. Returns that bone.
local function findHairSource(hairName: string, hairCfg): (Bone?, string?)
	local signature = hairCfg.SignatureBone
	local places = {}
	for _, container in { ServerStorage, ReplicatedStorage, Workspace } do
		local folder = container:FindFirstChild(HairConfig.ModelFolder)
		if folder then
			table.insert(places, folder)
		end
	end
	for _, place in places do
		local bone = place:FindFirstChild(signature, true)
		if bone and bone:IsA("Bone") then
			return bone, place:GetFullName()
		end
	end
	-- forgiving fallback: the imported model was left loose in Workspace
	for _, d in Workspace:GetDescendants() do
		if d.Name == signature and d:IsA("Bone") and not isInsideCharacter(d) then
			local part = partOfBone(d)
			if part then
				complain(
					("found the %s hair loose in Workspace (%s). It works, but move the model into ServerStorage > %s so it doesn't float around in your map."):format(
						hairName,
						part:GetFullName(),
						HairConfig.ModelFolder
					)
				)
				return d, "Workspace"
			end
		end
	end
	return nil
end

-- Bone positions inside the hair part, paired with where they were modeled (head space).
local function collectBonePairs(hairPart: BasePart, layout)
	local design, actual = {}, {}
	for boneName, modeled in layout.Bones do
		local bone = hairPart:FindFirstChild(boneName, true)
		if bone and bone:IsA("Bone") then
			local cf = HairPhysics.PartSpaceCFrame(bone, hairPart)
			if cf then
				table.insert(design, modeled)
				table.insert(actual, cf.Position)
			end
		end
	end
	return design, actual
end

-- Makes a copy of the hair MeshPart with all of its bones inside it. Normally the importer
-- already puts the bones inside the mesh; if it put them in a separate part instead, they're
-- moved into the mesh at exactly the same spot, so the skinning is unchanged.
local function copyHairMesh(signatureBone: Bone): BasePart?
	local original = partOfBone(signatureBone)
	if not original then
		return nil
	end
	local holder: Instance = signatureBone:FindFirstAncestorWhichIsA("Model") or original
	if holder:IsA("Workspace") then
		holder = original -- Workspace counts as a Model; never copy the whole map
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
					local world = bonePart.CFrame * child.CFrame
					child.CFrame = mesh.CFrame:ToObjectSpace(world)
					child.Parent = mesh
				end
			end
		end
	end
	if mesh ~= copy then
		mesh.Parent = nil
		copy:Destroy()
	end
	return mesh
end

local function removeOldHair(rig: Model, hairCfg)
	for _, child in rig:GetChildren() do
		if child:GetAttribute("HairPhysicsHair") then
			child:Destroy()
		elseif hairCfg.RemoveOtherHair and child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			local isHair = child.AccessoryType == Enum.AccessoryType.Hair
				or (handle and handle:FindFirstChild("HairAttachment") ~= nil)
			if isHair then
				child:Destroy()
			end
		end
	end
end

local function applyHair(rig: Model, hairName: string)
	local hairCfg = HairConfig.Hairs[hairName]
	local layout = HairConfig.Layouts[hairName]
	if not hairCfg or not layout then
		complain(("no settings called '%s' in HairConfig.Hairs / HairConfig.Layouts"):format(hairName))
		return
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local head = rig:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		complain(rig.Name .. " has no Head part, so it can't wear hair")
		return
	end

	local sourceBone, where = findHairSource(hairName, hairCfg)
	if not sourceBone then
		complain(
			("couldn't find the rigged %s hair. Import %s.fbx with the 3D Importer and put the model in ServerStorage > %s (looking for a bone named %s)."):format(
				hairName,
				hairName == "LadyHair" and "LadyHair_Rigged" or hairName .. "_Rigged",
				HairConfig.ModelFolder,
				hairCfg.SignatureBone
			)
		)
		return
	end

	-- copy just the hair mesh and its bones (and its SurfaceAppearance, if the importer made one)
	local hairPart = copyHairMesh(sourceBone)
	if not hairPart then
		complain(("found the %s bones in %s but no hair mesh next to them"):format(hairName, where or "?"))
		return
	end
	for _, d in hairPart:GetDescendants() do
		if d.Parent and not (d:IsA("Bone") or d:IsA("SurfaceAppearance")) then
			d:Destroy()
		end
	end
	hairPart.Name = "Handle"
	hairPart.Anchored = false
	hairPart.CanCollide = false
	hairPart.CanTouch = false
	hairPart.CanQuery = false
	hairPart.Massless = true
	if hairPart:IsA("MeshPart") then
		if hairCfg.TextureId and hairCfg.TextureId ~= "" then
			hairPart.TextureID = hairCfg.TextureId
		end
	end
	if hairCfg.Color then
		hairPart.Color = hairCfg.Color
	end

	-- where does it go? compare modeled bone positions with the imported ones
	local design, actual = collectBonePairs(hairPart, layout)
	if #design < 3 then
		complain(("the %s hair from %s is missing its bones (found %d). Re-import the FBX and make sure the importer kept the rig."):format(hairName, where or "?", #design))
		hairPart:Destroy()
		return
	end
	local fit = HairPhysics.FitRig(design, actual)
	local wantScale = hairCfg.Scale or 1
	if hairCfg.ScaleToHead and head:IsA("MeshPart") then
		-- the hair was made for a head ReferenceHeadWidth wide: match this rig's head
		local ratio = (head.Size.X + head.Size.Z) * 0.5 / (HairConfig.ReferenceHeadWidth or 1.2)
		if ratio > 0.5 and ratio < 3 then
			wantScale *= ratio
		end
	end
	if math.abs(fit.Scale / wantScale - 1) > 0.02 then
		-- the importer used a different unit size (or you changed Scale): resize the hair + bones
		local holder = Instance.new("Model")
		hairPart.Parent = holder
		local ok, err = pcall(function()
			holder:ScaleTo(holder:GetScale() * wantScale / fit.Scale)
		end)
		hairPart.Parent = nil
		holder:Destroy()
		if ok then
			log(("resized the %s hair by x%.3f to fit %s's head"):format(hairName, wantScale / fit.Scale, rig.Name))
			design, actual = collectBonePairs(hairPart, layout)
			fit = HairPhysics.FitRig(design, actual)
		else
			complain("couldn't resize the hair: " .. tostring(err))
		end
	end
	if fit.Error > 0.05 * math.max(fit.Scale, 0.01) then
		complain(("the %s hair's bones don't match the expected layout (off by %.2f studs on average). It may sit wrong — was the rig changed in Blender?"):format(hairName, fit.Error))
	end
	-- the rig's HeadCenter point goes on the centre of the head, then your Offset nudge on top
	local headCenter = (layout.HeadCenter or Vector3.zero) * fit.Scale
	local headToHair = hairCfg.Offset * CFrame.new(-headCenter) * HairPhysics.HeadToPart(fit)

	-- wear it
	removeOldHair(rig, hairCfg)
	local accessory = Instance.new("Accessory")
	accessory.Name = hairName .. "Hair"
	accessory.AccessoryType = Enum.AccessoryType.Hair
	accessory:SetAttribute("HairPhysicsHair", true)
	hairPart:SetAttribute("HairPreset", hairName)
	CollectionService:AddTag(hairPart, HairPhysics.TAG)
	hairPart.CFrame = head.CFrame * headToHair
	hairPart.Parent = accessory

	local headAttachment = head:FindFirstChild("HairAttachment")
	if humanoid and headAttachment and headAttachment:IsA("Attachment") then
		-- standard accessory route: Roblox welds our HairAttachment onto the head's HairAttachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "HairAttachment"
		attachment.CFrame = headToHair:Inverse() * headAttachment.CFrame
		attachment.Parent = hairPart
		humanoid:AddAccessory(accessory)
	else
		accessory.Parent = rig
	end

	-- make sure it really is attached (and attach it ourselves if not)
	local attached = false
	for _, d in hairPart:GetChildren() do
		if (d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("RigidConstraint")) then
			attached = true
		end
	end
	if not attached then
		if accessory.Parent ~= rig then
			accessory.Parent = rig
		end
		local weld = Instance.new("Weld")
		weld.Name = "AccessoryWeld"
		weld.Part0 = head
		weld.Part1 = hairPart
		weld.C0 = headToHair
		weld.Parent = hairPart
	end

	log(("%s is wearing %s (%d bones lined up, error %.3f studs)"):format(rig.Name, hairName, #design, fit.Error))
end

for _, assignment in HairConfig.Assignments do
	task.spawn(function()
		local rig = Workspace:WaitForChild(assignment.Rig, RIG_WAIT_TIME)
		if not rig then
			complain(("no rig called '%s' in Workspace"):format(assignment.Rig))
			return
		end
		local ok, err = pcall(applyHair, rig, assignment.Hair)
		if not ok then
			complain(("putting %s on %s failed: %s"):format(assignment.Hair, assignment.Rig, tostring(err)))
		end
	end)
end
