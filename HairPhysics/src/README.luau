--[[
	============================================================================
	 HAIR PHYSICS KIT — READ ME   (this script is switched off; it's just notes)
	============================================================================

	WHAT'S IN HERE
	  ReplicatedStorage      -> HairPhysics (the simulator) + HairConfig (ALL settings)
	  ServerScriptService    -> HairApplier (puts the hair on the rigs)
	                            NPCRoam     (test: rigs walk, jump, turn around)
	  StarterPlayerScripts   -> HairPhysicsClient (starts the simulation for each player)
	  ServerStorage          -> HairModels (empty folder: the imported hair goes here)

	SETUP (once)
	  1. Import the two rigged hairs: File > Import 3D, pick Pigtails_Rigged.fbx.
	       - Rig Type: Custom (the importer usually picks this itself — just not "No Rig")
	       - Scale Unit: Studs        - World Forward: Front   - World Up: Top
	       - tick "Keep Zero Influence Bones"
	       - leave "Upload to Roblox" on (the mesh has to be uploaded to show up in
	         the published game)
	     Do the same for LadyHair_Rigged.fbx.
	  2. Drag both imported models into ServerStorage > HairModels.
	     (No need to clean them up or weld anything — HairApplier does all of that.)
	  3. Move the contents of each folder in this kit into the service with the same
	     name. StarterPlayerScripts is inside StarterPlayer. Then delete this kit folder.
	  4. The .obj exports didn't include the hair textures. Open HairConfig and paste
	     each hair's original texture id into TextureId (from the original accessory's
	     Handle). Until then they show in the Color set there.
	  5. Make sure Workspace has your two R15 rigs named MrPigtails and MrLady.
	  6. Press Play (F5). Not "Run" — the hair moves on the player's screen, so it needs
	     a player.

	TWEAKING
	  Everything is in ReplicatedStorage > HairConfig, with notes on what each number
	  does. Common ones:
	    - hair sits a bit high/low/forward on the head -> Offset
	    - hair too floppy / too stiff                  -> Stiffness
	    - too much / too little swing when moving      -> Inertia
	    - want a breeze                                -> Wind, WindGust
	  When you're done testing, delete NPCRoam (or set ENABLED = false at its top).

	IF SOMETHING'S OFF
	  - Output says it couldn't find the hair: step 2 wasn't done, or the import
	    dropped the bones (re-import with Rig Type = Custom).
	  - Hair is see-through from some angles: select the hair MeshPart in
	    HairModels and tick DoubleSided.
	  - Hair doesn't move: you pressed Run instead of Play, or the rig is anchored
	    (NPCRoam un-anchors them for you).
]]
