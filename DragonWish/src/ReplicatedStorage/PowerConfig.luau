--[[
	PowerConfig  (ModuleScript — lives in ReplicatedStorage)

	Settings for powering up and turning Super Saiyan.
	How it plays: press R -> the camera swings round in front of you and you drop into a ready
	stance -> spam Space (or tap the TAP button on a phone) -> the aura appears, then grows
	bigger and faster, your hair and belt get blown upward -> fill the bar and you burst into
	Super Saiyan; the golden hair then flows calmly. Press R again as a Super Saiyan to power down.
]]

local PowerConfig = {}

PowerConfig.BaseRigName = "Base" -- the R15 rig in ReplicatedStorage every player becomes

-- controls
PowerConfig.PowerKey = Enum.KeyCode.R -- start powering up / cancel / power down
PowerConfig.TapKey = Enum.KeyCode.Space -- spam this to charge

-- charging
PowerConfig.ChargePerTap = 0.05 -- how much each tap fills the bar (0..1)
PowerConfig.ChargeDecay = 0.16 -- how much the bar drains per second if you stop tapping
PowerConfig.MinChargeTime = 2.5 -- you have to charge at least this long before transforming
PowerConfig.AuraStart = 0.06 -- bar level where the aura flickers on
PowerConfig.HairStart = 0.25 -- bar level where the hair and belt start lifting
PowerConfig.LockMovement = true -- you can't walk or jump while powering up

-- the transformation
PowerConfig.BurstTime = 2.8 -- seconds you hold the release pose before you get control back
PowerConfig.SSJCalmWind = 0.12 -- a gentle upward lift that stays on as a Super Saiyan (0..1); the
-- sideways breeze is the SSJ hair's LocalWind in HairConfig
PowerConfig.SSJIdleAura = 0.22 -- a soft golden aura stays on after transforming (0 = none)

-- looks
PowerConfig.BaseAuraColor = Color3.fromRGB(200, 228, 255) -- main colour of the flames
PowerConfig.BaseAuraEdge = Color3.fromRGB(95, 160, 255) -- colour at the flame tips
PowerConfig.SSJAuraColor = Color3.fromRGB(255, 210, 70)
PowerConfig.SSJAuraEdge = Color3.fromRGB(255, 125, 25)
PowerConfig.AuraSize = 1 -- scales the whole aura
PowerConfig.AuraFlames = 1 -- how many flame tongues (1 = normal; lower it if lots of players lag)
PowerConfig.AuraFrameRate = 15 -- how many times a second the aura's flames change shape. Low
-- (12-15) flickers like hand-drawn anime frames; 60 is smooth

-- camera (front view while powering up)
PowerConfig.CameraDistance = 9 -- studs in front of you
PowerConfig.CameraHeight = 0.8 -- studs above your waist
PowerConfig.CameraLookHeight = 1.4 -- the camera looks at this height above your waist
PowerConfig.CameraShake = 0.22 -- strongest shake (studs) at full power

return PowerConfig
