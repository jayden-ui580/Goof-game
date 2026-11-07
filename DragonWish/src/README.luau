--[[
	============================================================================
	 DRAGON WISH: ONLINE — CHARACTER + POWER-UP KIT   (this script is switched off; it's notes)
	============================================================================

	WHAT'S IN HERE
	  ReplicatedStorage      -> HairPhysics  (moves hair and belt ribbons)
	                            HairConfig   (hair/belt settings: colours, stiffness, aura reaction)
	                            PowerConfig  (power-up settings: keys, charge speed, aura colours)
	  ServerScriptService    -> CharacterSetup (every player becomes the Base rig with hair + belt)
	                            PowerUpServer  (referee for powering up / Super Saiyan)
	  StarterPlayerScripts   -> HairPhysicsClient (runs the hair + belt physics on each screen)
	                            PowerUpClient     (R / Space controls, front camera, power bar)
	                            PowerFX           (aura, stance, dust, rocks, transformation burst)
	                            HairFitTool       (press H: nudge hair/belt into place)
	  ServerStorage          -> CharacterParts (empty: the imported rigged pieces go here)

	UPDATING FROM AN EARLIER VERSION
	  Delete the old copies and import the new ones into ServerStorage > CharacterParts:
	    BaseHair_Rigged.fbx  - the bangs now have bones
	    SSJHair_Rigged.fbx   - its root bone was renamed (the old name clashed with the base
	                           hair's, which tied it to the base hair's skeleton: it never moved)

	SETUP (once)
	  1. Your R15 rig must be in ReplicatedStorage and called "Base".
	  2. Import the three rigged pieces with File > Import 3D:
	       BaseHair_Rigged.fbx, SSJHair_Rigged.fbx, Belt_Rigged.fbx
	     (Rig Type: Custom, Scale Unit: Studs, tick "Keep Zero Influence Bones").
	     Drag all three imported models into ServerStorage > CharacterParts.
	  3. Move the contents of each folder in this kit into the service with the same name
	     (StarterPlayerScripts is inside StarterPlayer). Then delete this kit folder.
	  4. In StarterPlayer's properties, untick LoadCharacterAppearance (the script tries to do
	     this itself, but some places don't allow it from a script).
	  5. Press Play (F5).

	CONTROLS (in Play)
	  R       power up: the camera swings round to face you and you stand tall, fists at
	          your waist. As the bar fills you hunch over, head down, elbows wide; when you
	          transform you lean back, head up, arms spread, and hold it a moment.
	          R again cancels. As a Super Saiyan, R powers back down to base.
	          (phones: the round POWER button on the right does the same as R)
	  Space   spam it to fill the power bar (phones: the big TAP button).
	          The aura grows bigger and faster, hair and belt blow upward. Once the bar is
	          full it stays full, and (after at least 2.5 s of charging) you burst into
	          Super Saiyan; the golden hair then flows calmly.
	  H       fit panel: nudge the hair/belt and copy the Offset line into HairConfig.

	TWEAKING
	  HairConfig: hair/belt colours (Color), textures (TextureId), placement (Offset),
	              how stiff/floppy (Stiffness) and heavy (GravityCompensation: lower = heavier),
	              the Super Saiyan hair's breeze to the left (LocalWind: make the X positive to
	              blow it right), how hard the aura blows them (AuraLift / AuraSwirl), and the
	              belt's room around the waist (FitGap; it's sized to the rig automatically).
	  PowerConfig: keys, how fast the bar fills/drains, minimum charge time, aura colours and
	               size, camera distance and shake.
]]
