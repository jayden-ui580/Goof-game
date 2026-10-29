--[[
	============================================================================
	 HAIR PHYSICS + TEST ARENA + WATER KIT — READ ME   (this script is switched off; it's notes)
	============================================================================

	WHAT'S IN HERE
	  Workspace              -> TestArena (sealed glass-roofed test box, tap, drain gate)
	  ReplicatedStorage      -> HairPhysics, HairConfig   (hair)
	                            WaterSim, WaterConfig     (water)
	  ServerScriptService    -> HairApplier (puts the hair on the rigs)
	                            ArenaSetup  (spawns everyone in the arena, runs the drain gate)
	                            WaterServer (runs the water and turns it into terrain water)
	                            NPCRoam     (test: rigs walk, jump, turn around inside the arena)
	  StarterPlayerScripts   -> HairPhysicsClient (starts the hair simulation for each player)
	                            HairFitTool       (press H: nudge the hair on the heads)
	                            ArenaControls     (press Z: open / close the drain gate)
	                            WaterClient       (tap stream, splashes, waterfall, floating foam)
	  ServerStorage          -> HairModels (the imported hair goes here)

	SETUP (once)
	  1. Hair (skip if already done): import Pigtails_Rigged.fbx and LadyHair_Rigged.fbx with
	     File > Import 3D (Rig Type: Custom, Scale Unit: Studs, tick "Keep Zero Influence Bones")
	     and drag both models into ServerStorage > HairModels.
	  2. Move the contents of each folder in this kit into the service with the same name
	     (StarterPlayerScripts is inside StarterPlayer). REPLACE older copies — including the
	     old TestArena in Workspace (the new one has a thicker floor and the tap).
	     Then delete this kit folder.
	  3. Press Play (F5). You and both rigs start inside the arena and the tap starts filling it.

	CONTROLS (in Play)
	  Z   open / close the drain gate ("Gate" button on phones). Open = the water rushes out of
	      the hole and pours down the side of the arena. Shut = the tap fills it back up.
	  H   hair fit panel ("Fit" button on phones).

	THE WATER
	  It's real Roblox terrain water (so it looks like Roblox water and you can swim in it),
	  moved around by a flow simulation on the server. The arena floor is split into 4×4-stud
	  cells; water flows from higher cells to lower ones, so it pours in, spreads across the
	  floor, sloshes, levels out, and runs toward the hole when the gate opens.
	  Settings are in ReplicatedStorage > WaterConfig (how deep, how fast it fills, how fast it
	  drains, the water colour...). Note: Roblox has one water look per place, so the colour /
	  clearness settings change ALL terrain water in the place (turn ApplyWaterLook off if you
	  have other water you don't want changed).
	  Keep the TestArena unrotated and on the 4-stud grid (its floor-top centre at whole
	  multiples of 4) — terrain water can only sit on that grid.

	IF SOMETHING'S OFF
	  - No water: check Output for [WaterServer] messages. The arena needs its Floor, Inlet >
	    InletMouth and Drain > GateOpening parts.
	  - Hair: Output says it couldn't find the hair -> step 1. Hair see-through -> tick
	    DoubleSided on the hair MeshPart. Hair not moving -> you pressed Run, not Play.
]]
