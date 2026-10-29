--[[
	============================================================================
	 HAIR PHYSICS + TEST ARENA KIT — READ ME   (this script is switched off; it's just notes)
	============================================================================

	WHAT'S IN HERE
	  Workspace              -> TestArena (sealed glass-roofed test box with a drain gate)
	  ReplicatedStorage      -> HairPhysics (the simulator) + HairConfig (ALL hair settings)
	  ServerScriptService    -> HairApplier (puts the hair on the rigs)
	                            ArenaSetup  (spawns everyone in the arena, runs the drain gate)
	                            NPCRoam     (test: rigs walk, jump, turn around inside the arena)
	  StarterPlayerScripts   -> HairPhysicsClient (starts the hair simulation for each player)
	                            HairFitTool       (press H: nudge the hair on the heads)
	                            ArenaControls     (press Z: open / close the drain gate)
	  ServerStorage          -> HairModels (the imported hair goes here)

	SETUP (once)
	  1. Import the two rigged hairs (skip if you already did): File > Import 3D,
	     pick Pigtails_Rigged.fbx, Rig Type: Custom, Scale Unit: Studs, tick
	     "Keep Zero Influence Bones", leave "Upload to Roblox" on. Same for LadyHair_Rigged.fbx.
	     Drag both imported models into ServerStorage > HairModels.
	  2. Move the contents of each folder in this kit into the service with the same
	     name (StarterPlayerScripts is inside StarterPlayer). REPLACE the old copies of
	     HairPhysics, HairConfig, HairApplier, NPCRoam and HairPhysicsClient if you have them.
	     Then delete this kit folder.
	  3. Paste each hair's texture id into TextureId in HairConfig (the .obj files didn't
	     include textures).
	  4. Press Play (F5). You and both rigs start inside the arena.

	CONTROLS (in Play)
	  Z   open / close the drain gate in the arena wall ("Gate" button on phones)
	  H   hair fit panel ("Fit" button on phones): pick a rig with Prev/Next, nudge its hair,
	      then copy the Offset line it shows into that hair's entry in HairConfig.

	TWEAKING
	  Hair: everything is in ReplicatedStorage > HairConfig, with notes on each number.
	    - hair sits wrong on the head      -> use the H panel, then paste the Offset it gives
	    - too floppy / too stiff           -> Stiffness, Damping
	    - wobbles too much                 -> raise Damping, lower Bounce
	    - too much / too little swing      -> Inertia
	  Arena: move/resize the TestArena model freely; scripts read its Floor part and its
	  InteriorSize attribute (update that if you change the walls).
	  When you're done testing, delete NPCRoam (or set ENABLED = false at its top).

	IF SOMETHING'S OFF
	  - Output says it couldn't find the hair: the imported models aren't in
	    ServerStorage > HairModels, or the import dropped the bones (re-import, Rig Type Custom).
	  - Hair is see-through from some angles: tick DoubleSided on the hair MeshPart in HairModels.
	  - Hair doesn't move: you pressed Run instead of Play.
]]
