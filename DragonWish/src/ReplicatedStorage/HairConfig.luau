--[[
	HairConfig  (ModuleScript — lives in ReplicatedStorage)

	Settings for everything on the character that moves with physics: the base hair, the
	Super Saiyan hair and the belt's ribbons. Read by CharacterSetup (which puts them on) and by
	HairPhysics on every player's computer (which moves them).

	Quick guide to the physics numbers (per piece, under Physics):
	  Stiffness     One number per bone, root first: how strongly each bone springs back to its
	                modeled shape. Spiky hair = high, ribbons = low.
	  MaxBend       One number per bone, in degrees: the most a joint can bend. Stops folding.
	  GravityCompensation  0..1: how much of gravity the spring cancels. 1 = sits exactly in its
	                modeled shape when still; lower = gravity pulls it down more (heavier hair).
	  Damping       0..1: how fast movement dies out. Bounce: how much it overshoots (keep low).
	  Inertia       0..1: how much it gets left behind when the body moves.
	  LocalWind     A steady breeze that turns with the head (studs/s²; X = the wearer's right,
	                Y = up, Z = behind them). Vector3.new(-70, 10, 0) blows it to their left.
	                LocalWindFlutter (0..1) / LocalWindFlutterSpeed: how much and how fast each
	                strand's breeze rises and falls, so the hair ripples.
	  AuraLift      How hard the power-up aura blows it upward (studs/s² at full power).
	  AuraSwirl     How hard the aura whips it around sideways (studs/s² at full power).
	  AuraSwirlSpeed  How fast that whipping wobbles.
	  BodyColliders Body parts it bumps into ("Head" is a ball, the rest are boxes).
]]

local HairConfig = {}

-- Folder the imported rigged models go in (looked for in ServerStorage, then ReplicatedStorage,
-- then Workspace).
HairConfig.ModelFolder = "CharacterParts"

-- The hair was made for a head this wide (studs); on a bigger/smaller head it's resized to match.
HairConfig.ReferenceHeadWidth = 1.2

-- Press this key (or the "Fit" button on phones) in Play to nudge the hair/belt into place.
HairConfig.FitToolKey = Enum.KeyCode.H
HairConfig.FitToolEnabled = true

HairConfig.Hairs = {
	BaseHair = {
		SignatureBone = "BS01_1", -- how the imported model is recognised
		TextureId = "", -- paste the original hair texture id here (optional)
		Color = Color3.fromRGB(24, 22, 28),
		Material = Enum.Material.SmoothPlastic,
		Offset = CFrame.new(0, 0, 0), -- nudge: CFrame.new(right, up, back) in studs
		Scale = 1,
		ScaleToHead = true,
		VisibleIn = "Base", -- which form shows this piece ("Base", "SSJ" or "Both")
		Physics = {
			Gravity = 30,
			GravityCompensation = 0.5, -- half of gravity is left to pull the spikes down
			Damping = 0.25,
			Bounce = 0.2,
			Inertia = 0.3,
			Stiffness = { 0.22, 0.15, 0.1 },
			ShapeFollow = 0.25,
			MaxBend = { 30, 30, 35 },
			MaxSpeed = 30,
			AuraLift = 600,
			AuraSwirl = 160,
			AuraSwirlSpeed = 9,
			SelfCollision = false,
			BodyColliders = { "Head", "UpperTorso" },
			SimulationDistance = 150,
		},
	},

	SSJHair = {
		SignatureBone = "SSJRoot", -- (older imports used "HairRoot", which clashed with the base hair)
		TextureId = "",
		Color = Color3.fromRGB(255, 214, 80),
		Material = Enum.Material.SmoothPlastic,
		Offset = CFrame.new(-0.05, -0.2, 0.15),
		Scale = 1,
		ScaleToHead = true,
		VisibleIn = "SSJ",
		Physics = {
			Gravity = 30,
			GravityCompensation = 0.4, -- heavier than the base hair: gravity pulls it more
			Damping = 0.25,
			Bounce = 0.2,
			Inertia = 0.3,
			Stiffness = { 0.18, 0.12, 0.08 },
			ShapeFollow = 0.25,
			MaxBend = { 32, 32, 38 },
			MaxSpeed = 30,
			-- a steady breeze to the wearer's left, each spike rippling on its own
			LocalWind = Vector3.new(-70, 10, 0),
			LocalWindFlutter = 0.7,
			LocalWindFlutterSpeed = 3.4,
			AuraLift = 500,
			AuraSwirl = 200,
			AuraSwirlSpeed = 3.5, -- slow: the Super Saiyan hair "flows calmly"
			SelfCollision = false,
			BodyColliders = { "Head", "UpperTorso" },
			SimulationDistance = 150,
		},
	},

	Belt = {
		SignatureBone = "RibbonL_1",
		TextureId = "",
		Color = Color3.fromRGB(38, 70, 170),
		Material = Enum.Material.Fabric,
		Offset = CFrame.new(0, 0, 0),
		Scale = 1, -- extra size on top of the automatic fit (1.05 = a little looser)
		ScaleToHead = false,
		-- the belt is sized so these body parts never poke through it, with FitGap studs of room
		FitAround = { "LowerTorso", "UpperTorso", "LeftUpperLeg", "RightUpperLeg" },
		FitGap = 0.04,
		VisibleIn = "Both",
		Physics = {
			Gravity = 30,
			GravityCompensation = 0.6, -- cloth ribbons hang a bit under their own weight
			Damping = 0.18,
			Bounce = 0.3,
			Inertia = 0.35,
			Stiffness = { 0.25, 0.15, 0.1 },
			ShapeFollow = 0.6,
			MaxBend = { 40, 45, 50 },
			MaxSpeed = 40,
			AuraLift = 220,
			AuraSwirl = 160,
			AuraSwirlSpeed = 11,
			SelfCollision = true,
			BodyColliders = { "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" },
			SimulationDistance = 150,
		},
	},
}

--------------------------------------------------------------------------------------------
-- Rig layouts (generated from the Blender rigs — only change these if you re-rig).
--------------------------------------------------------------------------------------------
HairConfig.Layouts = {
	BaseHair = {
		Attach = "Head", -- the body part it is fixed to
		Size = Vector3.new(2.989, 2.1756, 2.858),
		HeadCenter = Vector3.zero, -- the rig point that sits on the centre of that body part
		Chains = {
			{ Name = "BS01", Bones = { "BS01_1", "BS01_2" }, Tip = "BS01_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS02", Bones = { "BS02_1", "BS02_2", "BS02_3" }, Tip = "BS02_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS03", Bones = { "BS03_1", "BS03_2", "BS03_3" }, Tip = "BS03_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS04", Bones = { "BS04_1", "BS04_2" }, Tip = "BS04_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS05", Bones = { "BS05_1", "BS05_2", "BS05_3" }, Tip = "BS05_End", Radii = { 0.12, 0.12, 0.12, 0.12 } },
			{ Name = "BS06", Bones = { "BS06_1", "BS06_2", "BS06_3" }, Tip = "BS06_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS07", Bones = { "BS07_1", "BS07_2" }, Tip = "BS07_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS08", Bones = { "BS08_1", "BS08_2" }, Tip = "BS08_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS09", Bones = { "BS09_1", "BS09_2" }, Tip = "BS09_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS10", Bones = { "BS10_1", "BS10_2", "BS10_3" }, Tip = "BS10_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS11", Bones = { "BS11_1", "BS11_2", "BS11_3" }, Tip = "BS11_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS12", Bones = { "BS12_1", "BS12_2" }, Tip = "BS12_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS13", Bones = { "BS13_1", "BS13_2" }, Tip = "BS13_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS14", Bones = { "BS14_1", "BS14_2" }, Tip = "BS14_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS15", Bones = { "BS15_1", "BS15_2" }, Tip = "BS15_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "BS16", Bones = { "BS16_1", "BS16_2", "BS16_3" }, Tip = "BS16_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "BS17", Bones = { "BS17_1", "BS17_2", "BS17_3" }, Tip = "BS17_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
		},
		Bones = {
			HairRoot = Vector3.new(0, 0, 0),
			BS01_1 = Vector3.new(-0.202, -0.0945, 0.6431),
			BS01_2 = Vector3.new(-0.2758, -0.122, 1.0165),
			BS01_End = Vector3.new(-0.4116, -0.1307, 1.4653),
			BS02_1 = Vector3.new(-0.3541, 0.0453, 0.6764),
			BS02_2 = Vector3.new(-0.4882, 0.0653, 1.0161),
			BS02_3 = Vector3.new(-0.5644, 0.0919, 1.3883),
			BS02_End = Vector3.new(-0.7006, 0.108, 1.7363),
			BS03_1 = Vector3.new(-0.3902, 0.149, 0.431),
			BS03_2 = Vector3.new(-0.5912, 0.1758, 0.7788),
			BS03_3 = Vector3.new(-0.7332, 0.3101, 1.1363),
			BS03_End = Vector3.new(-0.8756, 0.4639, 1.4323),
			BS04_1 = Vector3.new(-0.5037, -0.1674, 0.3663),
			BS04_2 = Vector3.new(-0.9384, -0.1833, 0.3116),
			BS04_End = Vector3.new(-1.3556, -0.1364, 0.2863),
			BS05_1 = Vector3.new(-0.5011, 0.1416, 0.2878),
			BS05_2 = Vector3.new(-0.8646, 0.0177, 0.3561),
			BS05_3 = Vector3.new(-1.1297, 0.2494, 0.3014),
			BS05_End = Vector3.new(-1.5016, 0.3351, 0.2163),
			BS06_1 = Vector3.new(-0.4077, 0.3873, 0.1365),
			BS06_2 = Vector3.new(-0.7729, 0.5159, 0.1935),
			BS06_3 = Vector3.new(-1.1349, 0.6196, 0.2123),
			BS06_End = Vector3.new(-1.5016, 0.7099, 0.2233),
			BS07_1 = Vector3.new(-0.3502, 0.4687, 0.1361),
			BS07_2 = Vector3.new(-0.7538, 0.6814, 0.2004),
			BS07_End = Vector3.new(-1.2026, 0.7879, 0.2133),
			BS08_1 = Vector3.new(-0.1652, 0.988, -0.0729),
			BS08_2 = Vector3.new(-0.0694, 1.3999, -0.2529),
			BS08_End = Vector3.new(0.1244, 1.7516, -0.4717),
			BS09_1 = Vector3.new(0.1037, 0.5093, -0.4568),
			BS09_2 = Vector3.new(0.3096, 0.6658, -0.7783),
			BS09_End = Vector3.new(0.7154, 0.1373, -1.1167),
			BS10_1 = Vector3.new(0.1045, 0.5939, -0.0192),
			BS10_2 = Vector3.new(0.1558, 1.0696, -0.1705),
			BS10_3 = Vector3.new(0.3618, 1.5076, -0.3036),
			BS10_End = Vector3.new(0.7354, 1.7515, -0.5557),
			BS11_1 = Vector3.new(0.3317, 0.5005, -0.3174),
			BS11_2 = Vector3.new(0.6928, 0.7685, -0.3999),
			BS11_3 = Vector3.new(1.0527, 1.0563, -0.6003),
			BS11_End = Vector3.new(1.4874, 0.9908, -0.8818),
			BS12_1 = Vector3.new(0.428, -0.1755, 0.4068),
			BS12_2 = Vector3.new(0.8486, -0.17, 0.2771),
			BS12_End = Vector3.new(1.2614, -0.1428, 0.1033),
			BS13_1 = Vector3.new(0.5791, 0.1939, 0.2275),
			BS13_2 = Vector3.new(1.0133, 0.3374, 0.1928),
			BS13_End = Vector3.new(1.4874, 0.3053, -0.0837),
			BS14_1 = Vector3.new(0.6056, 0.4328, 0.1774),
			BS14_2 = Vector3.new(1.0248, 0.6767, 0.0664),
			BS14_End = Vector3.new(1.4854, 0.7338, -0.1007),
			BS15_1 = Vector3.new(0.5113, -0.1764, 0.5061),
			BS15_2 = Vector3.new(0.7293, -0.1995, 0.778),
			BS15_End = Vector3.new(0.8934, -0.1917, 1.1603),
			BS16_1 = Vector3.new(0.4, 0.0944, 0.5696),
			BS16_2 = Vector3.new(0.5914, 0.0656, 0.9322),
			BS16_3 = Vector3.new(0.7205, 0.0497, 1.3143),
			BS16_End = Vector3.new(0.8794, 0.0108, 1.6522),
			BS17_1 = Vector3.new(0.4871, 0.2009, 0.5535),
			BS17_2 = Vector3.new(0.7449, 0.233, 0.8611),
			BS17_3 = Vector3.new(0.8778, 0.1862, 1.2324),
			BS17_End = Vector3.new(1.0254, 0.151, 1.6153),
		},
	},
	SSJHair = {
		Attach = "Head", -- the body part it is fixed to
		Size = Vector3.new(2.82, 2.9528, 3.1868),
		HeadCenter = Vector3.zero, -- the rig point that sits on the centre of that body part
		Chains = {
			{ Name = "SS01", Bones = { "SS01_1", "SS01_2", "SS01_3" }, Tip = "SS01_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS02", Bones = { "SS02_1", "SS02_2", "SS02_3" }, Tip = "SS02_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS03", Bones = { "SS03_1", "SS03_2", "SS03_3" }, Tip = "SS03_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS04", Bones = { "SS04_1", "SS04_2", "SS04_3" }, Tip = "SS04_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS05", Bones = { "SS05_1", "SS05_2", "SS05_3" }, Tip = "SS05_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS06", Bones = { "SS06_1", "SS06_2", "SS06_3" }, Tip = "SS06_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS07", Bones = { "SS07_1", "SS07_2", "SS07_3" }, Tip = "SS07_End", Radii = { 0.12, 0.12, 0.12, 0.12 } },
			{ Name = "SS08", Bones = { "SS08_1", "SS08_2", "SS08_3" }, Tip = "SS08_End", Radii = { 0.12, 0.12, 0.12, 0.12 } },
			{ Name = "SS09", Bones = { "SS09_1", "SS09_2" }, Tip = "SS09_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "SS10", Bones = { "SS10_1", "SS10_2" }, Tip = "SS10_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "SS11", Bones = { "SS11_1", "SS11_2" }, Tip = "SS11_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "SS12", Bones = { "SS12_1", "SS12_2", "SS12_3" }, Tip = "SS12_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS13", Bones = { "SS13_1", "SS13_2", "SS13_3" }, Tip = "SS13_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS14", Bones = { "SS14_1", "SS14_2", "SS14_3" }, Tip = "SS14_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS15", Bones = { "SS15_1", "SS15_2" }, Tip = "SS15_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "SS16", Bones = { "SS16_1", "SS16_2", "SS16_3" }, Tip = "SS16_End", Radii = { 0.12, 0.12, 0.12, 0.12 } },
			{ Name = "SS17", Bones = { "SS17_1", "SS17_2", "SS17_3" }, Tip = "SS17_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS18", Bones = { "SS18_1", "SS18_2", "SS18_3" }, Tip = "SS18_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS19", Bones = { "SS19_1", "SS19_2" }, Tip = "SS19_End", Radii = { 0.12, 0.12, 0.12 } },
			{ Name = "SS20", Bones = { "SS20_1", "SS20_2", "SS20_3" }, Tip = "SS20_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
			{ Name = "SS21", Bones = { "SS21_1", "SS21_2", "SS21_3" }, Tip = "SS21_End", Radii = { 0.12, 0.12, 0.12, 0.12 } },
			{ Name = "SS22", Bones = { "SS22_1", "SS22_2", "SS22_3" }, Tip = "SS22_End", Radii = { 0.16, 0.16, 0.16, 0.16 } },
		},
		Bones = {
			SSJRoot = Vector3.new(0, 0, 0),
			SS01_1 = Vector3.new(-0.5884, 1.2323, -0.1123),
			SS01_2 = Vector3.new(-0.0136, 1.5285, 0.546),
			SS01_3 = Vector3.new(-0.4082, 2.0635, 0.7624),
			SS01_End = Vector3.new(-0.369, 2.7406, 1.3788),
			SS02_1 = Vector3.new(-0.2625, -0.0673, 0.4878),
			SS02_2 = Vector3.new(-0.4263, 0.1364, 0.7988),
			SS02_3 = Vector3.new(-0.637, 0.4434, 0.934),
			SS02_End = Vector3.new(-0.839, 0.5598, 1.2981),
			SS03_1 = Vector3.new(-0.5673, 0.1345, 0.3817),
			SS03_2 = Vector3.new(-0.8717, 0.5933, 0.4295),
			SS03_3 = Vector3.new(-0.8632, 0.7539, 0.873),
			SS03_End = Vector3.new(-0.95, 1.0731, 1.3914),
			SS04_1 = Vector3.new(-0.567, 0.9062, 0.6521),
			SS04_2 = Vector3.new(-0.5471, 1.3695, 0.8346),
			SS04_3 = Vector3.new(-0.5316, 1.758, 1.1378),
			SS04_End = Vector3.new(-0.623, 2.1704, 1.3242),
			SS05_1 = Vector3.new(-0.5134, 0.3304, -0.4534),
			SS05_2 = Vector3.new(-0.8624, 0.7321, 0.0019),
			SS05_3 = Vector3.new(-1.0398, 1.2276, 0.298),
			SS05_End = Vector3.new(-1.15, 1.7561, 0.6038),
			SS06_1 = Vector3.new(-0.533, 0.0832, -0.2112),
			SS06_2 = Vector3.new(-0.8424, 0.2581, 0.0656),
			SS06_3 = Vector3.new(-1.1409, 0.4728, 0.316),
			SS06_End = Vector3.new(-1.41, 0.785, 0.4974),
			SS07_1 = Vector3.new(-0.563, 0.759, -0.4886),
			SS07_2 = Vector3.new(-0.6977, 1.1098, -0.4499),
			SS07_3 = Vector3.new(-0.8622, 1.4267, -0.3032),
			SS07_End = Vector3.new(-0.958, 1.8544, -0.1884),
			SS08_1 = Vector3.new(-0.1959, 0.8546, -0.7933),
			SS08_2 = Vector3.new(-0.0942, 1.3294, -0.6614),
			SS08_3 = Vector3.new(-0.2886, 1.6909, -0.5895),
			SS08_End = Vector3.new(-0.191, 2.2185, -0.3497),
			SS09_1 = Vector3.new(-0.3262, 0.6085, -0.7405),
			SS09_2 = Vector3.new(-0.4687, 0.6122, -1.0081),
			SS09_End = Vector3.new(-0.403, 0.6884, -1.2252),
			SS10_1 = Vector3.new(-0.1667, 0.5752, -0.7883),
			SS10_2 = Vector3.new(-0.368, 0.7763, -0.9677),
			SS10_End = Vector3.new(-0.413, 0.9363, -1.0871),
			SS11_1 = Vector3.new(0.0672, 0.5781, -0.8141),
			SS11_2 = Vector3.new(0.3266, 0.6639, -1.157),
			SS11_End = Vector3.new(0.246, 0.8778, -1.3128),
			SS12_1 = Vector3.new(0.2472, 0.8367, -0.753),
			SS12_2 = Vector3.new(0.4766, 1.134, -0.9568),
			SS12_3 = Vector3.new(0.6507, 1.4071, -1.0899),
			SS12_End = Vector3.new(0.91, 1.4422, -1.4187),
			SS13_1 = Vector3.new(0.5969, 0.7532, -0.4864),
			SS13_2 = Vector3.new(0.7691, 1.1858, -0.39),
			SS13_3 = Vector3.new(0.794, 1.625, -0.3037),
			SS13_End = Vector3.new(0.861, 2.0641, -0.2332),
			SS14_1 = Vector3.new(0.5911, 0.3399, -0.439),
			SS14_2 = Vector3.new(0.9278, 0.4261, 0.0444),
			SS14_3 = Vector3.new(1.0584, 0.9398, 0.0867),
			SS14_End = Vector3.new(1.41, 1.3869, 0.2468),
			SS15_1 = Vector3.new(0.546, -0.1279, 0.0092),
			SS15_2 = Vector3.new(0.8301, 0.1123, 0.2869),
			SS15_End = Vector3.new(1.137, 0.1646, 0.5025),
			SS16_1 = Vector3.new(0.6295, 0.0771, -0.1413),
			SS16_2 = Vector3.new(0.8993, 0.2437, 0.1181),
			SS16_3 = Vector3.new(1.1236, 0.4173, 0.3028),
			SS16_End = Vector3.new(1.387, 0.7009, 0.4151),
			SS17_1 = Vector3.new(0.414, 0.0748, 0.4637),
			SS17_2 = Vector3.new(0.63, 0.3368, 0.8211),
			SS17_3 = Vector3.new(0.7338, 0.7006, 1.0604),
			SS17_End = Vector3.new(0.989, 0.9215, 1.4),
			SS18_1 = Vector3.new(0.632, 0.144, 0.24),
			SS18_2 = Vector3.new(0.6538, 0.7049, 0.6446),
			SS18_3 = Vector3.new(0.8875, 1.0269, 0.9281),
			SS18_End = Vector3.new(1.057, 1.5728, 1.3089),
			SS19_1 = Vector3.new(0.396, -0.1056, 0.3684),
			SS19_2 = Vector3.new(0.3941, 0.1522, 0.8314),
			SS19_End = Vector3.new(0.498, 0.2878, 1.3276),
			SS20_1 = Vector3.new(0.8343, 0.9175, 0.1651),
			SS20_2 = Vector3.new(0.5965, 1.3659, 0.5662),
			SS20_3 = Vector3.new(0.6023, 1.678, 0.7969),
			SS20_End = Vector3.new(0.481, 2.1338, 1.2438),
			SS21_1 = Vector3.new(0.2466, 1.3057, -0.5375),
			SS21_2 = Vector3.new(0.4982, 1.6225, 0.0252),
			SS21_3 = Vector3.new(0.2974, 1.9441, -0.046),
			SS21_End = Vector3.new(0.149, 2.4732, 0.3849),
			SS22_1 = Vector3.new(-0.134, 0.2652, 0.7066),
			SS22_2 = Vector3.new(0.1562, 0.8166, 1.1274),
			SS22_3 = Vector3.new(0.0933, 1.404, 1.357),
			SS22_End = Vector3.new(0.083, 1.9593, 1.7681),
		},
	},
	Belt = {
		Attach = "LowerTorso", -- the body part it is fixed to
		Size = Vector3.new(2.1584, 1.5278, 1.3154),
		HeadCenter = Vector3.zero, -- the rig point that sits on the centre of that body part
		Chains = {
			{ Name = "RibbonL", Bones = { "RibbonL_1", "RibbonL_2", "RibbonL_3" }, Tip = "RibbonL_End", Radii = { 0.12, 0.11, 0.1, 0.09 } },
			{ Name = "RibbonR", Bones = { "RibbonR_1", "RibbonR_2", "RibbonR_3" }, Tip = "RibbonR_End", Radii = { 0.12, 0.11, 0.1, 0.09 } },
		},
		-- inside of the band: distance from the centre every 2 degrees (from +X towards +Z)
		Ring = {
			Bottom = -0.195, Top = 0.205, Step = 2,
			Radii = {
				1.048, 1.049, 1.05, 1.053, 1.058, 1.063, 1.068, 1.073, 1.079, 1.087, 1.096, 1.106, 1.1, 1.085, 1.058,
				1.005, 0.957, 0.915, 0.875, 0.837, 0.803, 0.772, 0.745, 0.72, 0.699, 0.682, 0.666, 0.652, 0.639, 0.627,
				0.617, 0.607, 0.599, 0.591, 0.585, 0.579, 0.574, 0.57, 0.567, 0.564, 0.563, 0.561, 0.561, 0.561, 0.561,
				0.562, 0.564, 0.566, 0.568, 0.572, 0.576, 0.581, 0.586, 0.593, 0.599, 0.606, 0.614, 0.623, 0.631, 0.64,
				0.65, 0.661, 0.673, 0.686, 0.701, 0.718, 0.736, 0.754, 0.774, 0.796, 0.82, 0.847, 0.877, 0.909, 0.945,
				0.984, 1.028, 1.068, 1.082, 1.098, 1.093, 1.084, 1.077, 1.071, 1.066, 1.063, 1.059, 1.055, 1.052, 1.05,
				1.05, 1.05, 1.051, 1.053, 1.056, 1.06, 1.063, 1.067, 1.073, 1.081, 1.089, 1.099, 1.094, 1.08, 1.065,
				1.008, 0.958, 0.913, 0.872, 0.834, 0.8, 0.771, 0.745, 0.722, 0.7, 0.683, 0.667, 0.652, 0.639, 0.627,
				0.616, 0.606, 0.597, 0.589, 0.58, 0.573, 0.566, 0.56, 0.555, 0.551, 0.548, 0.545, 0.543, 0.542, 0.541,
				0.541, 0.541, 0.542, 0.544, 0.547, 0.55, 0.554, 0.559, 0.565, 0.571, 0.578, 0.587, 0.596, 0.604, 0.613,
				0.623, 0.635, 0.647, 0.661, 0.676, 0.693, 0.711, 0.731, 0.754, 0.779, 0.807, 0.838, 0.873, 0.911, 0.952,
				0.999, 1.052, 1.074, 1.088, 1.098, 1.088, 1.079, 1.072, 1.066, 1.061, 1.058, 1.055, 1.051, 1.049, 1.048,
			},
		},
		Bones = {
			BeltRoot = Vector3.new(0, 0, 0),
			RibbonL_1 = Vector3.new(-0.0599, -0.0362, -0.5875),
			RibbonL_2 = Vector3.new(-0.3441, -0.2849, -0.6367),
			RibbonL_3 = Vector3.new(-0.376, -0.5028, -0.6831),
			RibbonL_End = Vector3.new(-0.3753, -0.8674, -0.6786),
			RibbonR_1 = Vector3.new(0.0011, 0.0313, -0.5735),
			RibbonR_2 = Vector3.new(0.2298, -0.3562, -0.6256),
			RibbonR_3 = Vector3.new(0.4271, -0.7697, -0.6787),
			RibbonR_End = Vector3.new(0.4635, -1.2052, -0.6707),
		},
	},
}

return HairConfig
