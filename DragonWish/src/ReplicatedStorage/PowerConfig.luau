--[[
	PowerConfig  (ModuleScript — lives in ReplicatedStorage)

	Settings for powering up: turning Super Saiyan, and the Kaioken.
	How it plays: press R -> the camera swings round in front of you and you drop into a ready
	stance -> spam Space (or tap the TAP button on a phone) -> the aura appears, then grows
	bigger and faster, your hair and belt get blown upward -> fill the bar and you burst into
	Super Saiyan (and point at the camera: "YOU'RE FINISHED!"); the golden hair then flows
	calmly. Press R again as a Super Saiyan to power down.
	Kaioken (base form only): press K to light it, again to push it higher. More power, faster
	legs, a red aura ... and it eats your health every second. R lets it go.
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
PowerConfig.BurstTime = 6.9 -- seconds the transformation takes (the cutscene plays during it);
-- you get control back after it
PowerConfig.ExplodeAt = 2.2 -- seconds into the transformation when the power explodes out (pillar
-- of light, shockwave, you throw your arms out)
PowerConfig.PointAt = 4.3 -- seconds into the transformation when you start the "YOU'RE FINISHED!"
-- point: left hand on the inside of your right elbow, then a swipe into a point at the camera.
-- It lands 0.8 s later; keep BurstTime at least 1.8 s after this so it holds a moment
PowerConfig.SSJCalmWind = 0.12 -- a gentle upward lift on the hair while the Super Saiyan aura is up
-- (0..1); the sideways breeze is the SSJ hair's LocalWind in HairConfig
PowerConfig.SSJIdleAura = 0.75 -- how strong the golden aura stays after transforming (0 = none)
PowerConfig.SSJCalmAfter = 20 -- seconds after you get control back until your hair and aura calm down
PowerConfig.SSJCalmTime = 4 -- seconds the calming down takes

-- the transformation cutscene (only the player transforming sees it)
PowerConfig.Cutscene = true
PowerConfig.CutsceneText = { "THIS IS—", "SUPER SAIYAN!", "YOU'RE FINISHED!" } -- the three manga panels

-- Kaioken (King Kai's technique; base form only). Each press of K lights it or pushes it a
-- level higher: every level burns one ki pip (KaiokenKiCost), multiplies your power level and
-- walk speed, and strains your body: you lose health every second. If your health falls to
-- KaiokenFloor your body gives out: the Kaioken stops and you're exhausted (slow, no powering
-- up) for KaiokenExhaustTime seconds. R lets it go. (Roblox heals you 1 health a second on its
-- own, so the lowest level barely hurts.)
PowerConfig.KaiokenKey = Enum.KeyCode.K
PowerConfig.KaiokenLevels = { 2, 3, 4, 10, 20 } -- the multiplier at each level: x2, x3, x4, x10, x20
PowerConfig.KaiokenStrain = { 1.5, 2.5, 4, 8, 16 } -- health lost per second at each level
PowerConfig.KaiokenSpeed = { 1.15, 1.2, 1.25, 1.4, 1.6 } -- walk speed multiplier at each level
PowerConfig.KaiokenAura = { 0.55, 0.65, 0.75, 0.95, 1.15 } -- how big the red aura burns at each level
PowerConfig.KaiokenKiCost = 20 -- ki each level costs (one of the five pips on the HUD)
PowerConfig.KaiokenCooldown = 0.6 -- seconds between level-ups
PowerConfig.KaiokenFloor = 10 -- health at which your body gives out
PowerConfig.KaiokenExhaustTime = 4 -- seconds you're exhausted afterwards
PowerConfig.ExhaustedSpeed = 0.55 -- walk speed multiplier while exhausted

-- HUD
PowerConfig.KiMax = 100
PowerConfig.KiStart = 30 -- ki when you spawn
PowerConfig.KiRegen = 1.5 -- ki per second while you're not charging (charging fills it fast)
PowerConfig.BasePowerLevel = 1500 -- what the scouter reads in base form at rest
PowerConfig.ChargePowerBoost = 4 -- charging multiplies it up to this much more
PowerConfig.SSJMultiplier = 50 -- Super Saiyan power level = base x this
PowerConfig.RadarRange = 250 -- studs the Dragon Radar can see other players

-- looks
PowerConfig.BaseAuraColor = Color3.fromRGB(110, 205, 255) -- main colour of the flames
PowerConfig.BaseAuraEdge = Color3.fromRGB(30, 115, 255) -- colour at the flame tips
PowerConfig.SSJAuraColor = Color3.fromRGB(255, 210, 70)
PowerConfig.SSJAuraEdge = Color3.fromRGB(255, 125, 25)
PowerConfig.KaiokenAuraColor = Color3.fromRGB(255, 72, 52)
PowerConfig.KaiokenAuraEdge = Color3.fromRGB(205, 0, 28)
PowerConfig.KaiokenGlow = Color3.fromRGB(255, 40, 40) -- the red glow over your whole body
PowerConfig.AuraSize = 1 -- scales the whole aura
PowerConfig.AuraFlames = 1 -- how many flame tongues (1 = normal; lower it if lots of players lag)
PowerConfig.AuraFrameRate = 24 -- how many times a second the aura's flames change shape. Low
-- (12-15) flickers like hand-drawn anime frames; 60 is smooth

-- camera (front view while powering up)
PowerConfig.CameraDistance = 9 -- studs in front of you
PowerConfig.CameraHeight = 0.8 -- studs above your waist
PowerConfig.CameraLookHeight = 1.4 -- the camera looks at this height above your waist
PowerConfig.CameraShake = 0.22 -- strongest shake (studs) at full power

return PowerConfig
