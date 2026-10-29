--[[
	HairConfig  (ModuleScript — lives in ReplicatedStorage)

	Every setting for the hair system lives here. Both the server (HairApplier, which
	puts the hair on) and every player's computer (HairPhysics, which moves it) read it.

	Quick guide to the physics numbers (per hair, under Physics):
	  Gravity              How hard the hair is pulled down while it swings (studs/s²).
	  GravityCompensation  0..1. 1 = when the character stands still the hair sits exactly in
	                       its modeled shape. 0 = gravity sags it below that shape.
	  Damping              0..1. How fast swinging dies out. Higher = calmer, lower = floppier.
	  Bounce               0..1. How much the hair overshoots when it springs back into shape.
	                       High values wobble like jelly; keep it low.
	  Inertia              0..1. How much the hair gets left behind when the head moves.
	                       Higher = more trailing/swinging when walking and jumping.
	  Stiffness            One number per bone, root first. How strongly each bone springs back
	                       to its modeled shape. Higher = stiffer hair.
	  ShapeFollow          0..1. 0 = every bone springs back to its modeled direction relative to
	                       the HEAD (hairstyle holds its shape). 1 = relative to the bone above it
	                       (bendy, rope-like).
	  MaxBend              One number per bone, root first, in degrees. The most each joint can
	                       bend away from its modeled shape. This is what stops strands folding.
	  MaxSpeed             No part of a strand moves faster than this (studs/s) — stops whipping.
	  SheetLinks           Pairs of neighbouring strands tied together like cloth, so a wide sheet
	                       of hair moves as one piece instead of separate strands squishing apart.
	  SheetSlack           How much (0.12 = 12%) the gap between linked strands may stretch/shrink.
	  ChainOverrides       Different Stiffness/MaxBend for some strands, matched by the start of
	                       the strand's name (e.g. "Lock" = LockL and LockR).
	  Wind / WindGust      Constant wind (studs/s², e.g. Vector3.new(8, 0, 0)) and how gusty it is.
	  SelfCollision        Strands bump into each other instead of passing through.
	  BodyColliders        Body parts the hair bumps into. "Head" is a ball, the rest are boxes.
	  SimulationDistance   Hair further than this from the camera stops simulating (saves FPS).
]]

local HairConfig = {}

-- Which hair goes on which rig (rigs are found in Workspace by name).
HairConfig.Assignments = {
	{ Rig = "MrPigtails", Hair = "Pigtails" },
	{ Rig = "MrLady", Hair = "LadyHair" },
}

-- Folder you put the imported rigged hair models in. Looked for in ServerStorage first, then
-- ReplicatedStorage, then Workspace.
HairConfig.ModelFolder = "HairModels"

-- The hair was made for a head this wide (studs). If a rig's head is bigger or smaller, the hair
-- is resized to match when ScaleToHead is on.
HairConfig.ReferenceHeadWidth = 1.2

-- Press this key (or the on-screen "Fit" button on phones) during Play to open the hair-fit
-- panel: nudge the hair on each head and it prints the Offset line to paste below.
HairConfig.FitToolKey = Enum.KeyCode.H
HairConfig.FitToolEnabled = true

HairConfig.Hairs = {
	Pigtails = {
		-- the imported model is found by this bone, so it works whatever the model is named
		SignatureBone = "PigL_1",
		-- paste the original hair texture here, e.g. "rbxassetid://1234567890"
		-- (leave "" to keep whatever the imported MeshPart already has)
		TextureId = "",
		Color = Color3.fromRGB(86, 58, 42), -- only shows when there's no texture
		Offset = CFrame.new(0, 0, 0), -- nudge the hair on the head: CFrame.new(right, up, back) in studs
		Scale = 1, -- extra size multiplier (1 = the size it was made at)
		ScaleToHead = true, -- resize to the rig's head width (see ReferenceHeadWidth)
		RemoveOtherHair = true, -- take off any hair the rig is already wearing
		Physics = {
			Gravity = 30,
			GravityCompensation = 1,
			Damping = 0.28,
			Bounce = 0.15,
			Inertia = 0.2,
			Stiffness = { 0.5, 0.35, 0.22, 0.15, 0.12 },
			ShapeFollow = 0.3,
			MaxBend = { 20, 18, 20, 22, 25 },
			MaxSpeed = 25,
			Wind = Vector3.zero,
			WindGust = 0,
			SelfCollision = true,
			BodyColliders = { "Head", "UpperTorso", "Torso", "LeftUpperArm", "RightUpperArm" },
			SimulationDistance = 150,
		},
	},

	LadyHair = {
		SignatureBone = "BackC_1",
		TextureId = "",
		Color = Color3.fromRGB(120, 80, 50),
		Offset = CFrame.new(0, 0, 0),
		Scale = 1,
		ScaleToHead = true,
		RemoveOtherHair = true,
		Physics = {
			Gravity = 30,
			GravityCompensation = 1,
			Damping = 0.28,
			Bounce = 0.15,
			Inertia = 0.2,
			Stiffness = { 0.35, 0.22, 0.15, 0.11, 0.09 },
			ShapeFollow = 0.3,
			MaxBend = { 20, 18, 20, 22, 25 },
			MaxSpeed = 25,
			-- the five strands down the back move together as one sheet of hair
			SheetLinks = {
				{ "BackL2", "BackL1" },
				{ "BackL1", "BackC" },
				{ "BackC", "BackR1" },
				{ "BackR1", "BackR2" },
			},
			SheetSlack = 0.12,
			ChainOverrides = {
				-- the two front locks that rest on the chest
				Lock = { Stiffness = { 0.4, 0.3, 0.2, 0.15 }, MaxBend = { 16, 16, 20, 24 } },
			},
			Wind = Vector3.zero,
			WindGust = 0,
			SelfCollision = true,
			BodyColliders = { "Head", "UpperTorso", "Torso", "LeftUpperArm", "RightUpperArm" },
			SimulationDistance = 150,
		},
	},
}

--------------------------------------------------------------------------------------------
-- Rig layouts (generated from the Blender rigs — only change these if you re-rig the hair).
-- Radii = how thick each joint's collision ball is, root to tip, in studs.
--------------------------------------------------------------------------------------------
HairConfig.Layouts = {
	Pigtails = {
		Size = Vector3.new(2.8167, 1.7064, 1.5286), -- size of the whole hair mesh in studs (used to check the import scale)
		HeadCenter = Vector3.new(0, -0.3, 0), -- the point in the rig that sits on the centre of the head
		Chains = {
			{ Name = "PigL", Bones = { "PigL_1", "PigL_2", "PigL_3", "PigL_4", "PigL_5" }, Tip = "PigL_End", Radii = { 0.17, 0.17, 0.16, 0.15, 0.13, 0.11 } },
			{ Name = "PigR", Bones = { "PigR_1", "PigR_2", "PigR_3", "PigR_4", "PigR_5" }, Tip = "PigR_End", Radii = { 0.17, 0.17, 0.16, 0.15, 0.13, 0.11 } },
		},
		-- where every bone sits relative to the centre of the head, as modeled
		Bones = {
			HairRoot = Vector3.new(0, 0, 0),
			PigL_1 = Vector3.new(-0.5638, 0.4368, 0.1196),
			PigL_2 = Vector3.new(-0.846, 0.5531, 0.1636),
			PigL_3 = Vector3.new(-1.0887, 0.4157, 0.1346),
			PigL_4 = Vector3.new(-1.1602, 0.1517, 0.1955),
			PigL_5 = Vector3.new(-1.1986, -0.3404, 0.2088),
			PigL_End = Vector3.new(-1.0193, -0.8233, 0.3105),
			PigR_1 = Vector3.new(0.5629, 0.4368, 0.1196),
			PigR_2 = Vector3.new(0.8451, 0.5531, 0.1636),
			PigR_3 = Vector3.new(1.0878, 0.4157, 0.1346),
			PigR_4 = Vector3.new(1.1593, 0.1517, 0.1956),
			PigR_5 = Vector3.new(1.1976, -0.3404, 0.2088),
			PigR_End = Vector3.new(1.0184, -0.8233, 0.3105),
		},
	},
	LadyHair = {
		Size = Vector3.new(2.076, 3.4076, 2.1828), -- size of the whole hair mesh in studs (used to check the import scale)
		HeadCenter = Vector3.new(0, -0.3, 0), -- the point in the rig that sits on the centre of the head
		Chains = {
			{ Name = "BackL2", Bones = { "BackL2_1", "BackL2_2", "BackL2_3", "BackL2_4", "BackL2_5" }, Tip = "BackL2_End", Radii = { 0.2, 0.19, 0.18, 0.17, 0.15, 0.13 } },
			{ Name = "BackL1", Bones = { "BackL1_1", "BackL1_2", "BackL1_3", "BackL1_4", "BackL1_5" }, Tip = "BackL1_End", Radii = { 0.2, 0.19, 0.18, 0.17, 0.15, 0.13 } },
			{ Name = "BackC", Bones = { "BackC_1", "BackC_2", "BackC_3", "BackC_4", "BackC_5" }, Tip = "BackC_End", Radii = { 0.2, 0.19, 0.18, 0.17, 0.15, 0.13 } },
			{ Name = "BackR1", Bones = { "BackR1_1", "BackR1_2", "BackR1_3", "BackR1_4", "BackR1_5" }, Tip = "BackR1_End", Radii = { 0.2, 0.19, 0.18, 0.17, 0.15, 0.13 } },
			{ Name = "BackR2", Bones = { "BackR2_1", "BackR2_2", "BackR2_3", "BackR2_4", "BackR2_5" }, Tip = "BackR2_End", Radii = { 0.2, 0.19, 0.18, 0.17, 0.15, 0.13 } },
			{ Name = "LockL", Bones = { "LockL_1", "LockL_2", "LockL_3", "LockL_4" }, Tip = "LockL_End", Radii = { 0.12, 0.12, 0.11, 0.1, 0.09 } },
			{ Name = "LockR", Bones = { "LockR_1", "LockR_2", "LockR_3", "LockR_4" }, Tip = "LockR_End", Radii = { 0.12, 0.12, 0.11, 0.1, 0.09 } },
		},
		-- where every bone sits relative to the centre of the head, as modeled
		Bones = {
			HairRoot = Vector3.new(0, 0, 0),
			BackL2_1 = Vector3.new(-0.62, -0.15, 0.3433),
			BackL2_2 = Vector3.new(-0.74, -0.55, 0.3308),
			BackL2_3 = Vector3.new(-0.82, -0.95, 0.5197),
			BackL2_4 = Vector3.new(-0.86, -1.35, 0.746),
			BackL2_5 = Vector3.new(-0.86, -1.7, 0.9121),
			BackL2_End = Vector3.new(-0.82, -2, 0.9265),
			BackL1_1 = Vector3.new(-0.33, -0.15, 0.6132),
			BackL1_2 = Vector3.new(-0.38, -0.6, 0.5796),
			BackL1_3 = Vector3.new(-0.42, -1.05, 0.841),
			BackL1_4 = Vector3.new(-0.45, -1.5, 0.9071),
			BackL1_5 = Vector3.new(-0.47, -1.95, 0.8829),
			BackL1_End = Vector3.new(-0.5, -2.3, 1.0244),
			BackC_1 = Vector3.new(0, -0.15, 0.7083),
			BackC_2 = Vector3.new(0, -0.6, 0.6556),
			BackC_3 = Vector3.new(0, -1.05, 0.9106),
			BackC_4 = Vector3.new(0, -1.5, 1.0237),
			BackC_5 = Vector3.new(0, -1.95, 0.931),
			BackC_End = Vector3.new(0.02, -2.45, 1.0134),
			BackR1_1 = Vector3.new(0.33, -0.15, 0.5744),
			BackR1_2 = Vector3.new(0.38, -0.6, 0.5635),
			BackR1_3 = Vector3.new(0.42, -1.05, 0.802),
			BackR1_4 = Vector3.new(0.43, -1.5, 0.9555),
			BackR1_5 = Vector3.new(0.45, -1.95, 0.857),
			BackR1_End = Vector3.new(0.48, -2.3, 0.8719),
			BackR2_1 = Vector3.new(0.62, -0.15, 0.2777),
			BackR2_2 = Vector3.new(0.74, -0.55, 0.3935),
			BackR2_3 = Vector3.new(0.82, -0.95, 0.6891),
			BackR2_4 = Vector3.new(0.88, -1.35, 0.799),
			BackR2_5 = Vector3.new(0.86, -1.7, 0.8013),
			BackR2_End = Vector3.new(0.8, -1.98, 0.6448),
			LockL_1 = Vector3.new(-0.528, -0.1344, -0.3899),
			LockL_2 = Vector3.new(-0.6425, -0.3985, -0.3458),
			LockL_3 = Vector3.new(-0.5729, -0.7506, -0.4994),
			LockL_4 = Vector3.new(-0.2833, -0.8532, -0.8317),
			LockL_End = Vector3.new(-0.362, -1.1536, -0.8885),
			LockR_1 = Vector3.new(0.4965, -0.2442, -0.407),
			LockR_2 = Vector3.new(0.714, -0.4511, -0.4188),
			LockR_3 = Vector3.new(0.5634, -0.7236, -0.5763),
			LockR_4 = Vector3.new(0.2541, -0.8523, -0.8463),
			LockR_End = Vector3.new(0.3207, -1.1437, -0.8975),
		},
	},
}

return HairConfig
