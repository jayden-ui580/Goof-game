--[[
	WaterConfig  (ModuleScript — lives in ReplicatedStorage)

	Settings for the flowing water in the TestArena. Read by WaterServer (which runs the water)
	and WaterClient (which draws the pouring stream, the waterfall and the floating foam).
]]

local WaterConfig = {}

WaterConfig.Enabled = true
WaterConfig.ArenaName = "TestArena"

---------------------------------------------------------------------------------------------
-- Filling and draining
---------------------------------------------------------------------------------------------
WaterConfig.FillLevel = 10 -- how deep (studs) the water gets when the arena is "full"
WaterConfig.FillSeconds = 45 -- how long the tap takes to fill the arena from empty
WaterConfig.AutoFill = true -- the tap turns on by itself whenever the gate is shut and it's not full
WaterConfig.RefillDelay = 2 -- seconds after the gate shuts before the tap starts again
WaterConfig.TapWhileGateOpen = false -- keep pouring while the gate is open?
WaterConfig.DrainSpeed = 5 -- how fast water escapes through the hole (1 = real-world, higher = quicker)

---------------------------------------------------------------------------------------------
-- How the water moves (you rarely need to touch these)
---------------------------------------------------------------------------------------------
WaterConfig.Gravity = 35 -- studs/s². Lower than Roblox's 196 because 1 stud ≈ 0.28 m; this is real gravity
WaterConfig.Friction = 0.5 -- how quickly sloshing calms down (per second)
WaterConfig.PipeDepth = 16 -- how freely water flows between cells (higher = faster waves)
WaterConfig.Smoothing = 60 -- irons out bumps between neighbouring cells
WaterConfig.DrainDip = 0.3 -- the floor dips slightly into the hole so the last of the water runs out

WaterConfig.SimRate = 30 -- simulation steps per second (server)
WaterConfig.TerrainRate = 10 -- terrain water updates per second (these replicate to players)
WaterConfig.NetworkRate = 8 -- flow updates per second sent to players for splashes and foam

---------------------------------------------------------------------------------------------
-- Look. Roblox has one water look per place, so these change ALL terrain water in the place.
---------------------------------------------------------------------------------------------
WaterConfig.ApplyWaterLook = true
WaterConfig.WaterColor = Color3.fromRGB(32, 120, 150)
WaterConfig.WaterTransparency = 0.55 -- 0 = murky, 1 = invisible
WaterConfig.WaterReflectance = 0.45
WaterConfig.WaterWaveSize = 0.12 -- studs (indoor water barely ripples)
WaterConfig.WaterWaveSpeed = 12

---------------------------------------------------------------------------------------------
-- Effects drawn on each player's screen
---------------------------------------------------------------------------------------------
WaterConfig.StreamWidth = 2.2 -- thickness of the water pouring from the tap
WaterConfig.StreamColor = Color3.fromRGB(150, 205, 230)
WaterConfig.FoamCount = 80 -- floating foam flecks that show which way the water is flowing
WaterConfig.FoamSize = 0.45
WaterConfig.SplashRate = 60 -- mist particles per second where the tap's stream hits the water

return WaterConfig
