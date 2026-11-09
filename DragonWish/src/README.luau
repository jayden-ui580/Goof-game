--[[
	============================================================================
	 DRAGON WISH: ONLINE — CHARACTER + POWER-UP KIT   (this script is switched off; it's notes)
	============================================================================

	WHAT'S IN HERE
	  ReplicatedStorage      -> HairPhysics  (moves hair and belt ribbons)
	                            HairConfig   (hair/belt settings: colours, stiffness, aura reaction)
	                            PowerConfig  (power-up settings: keys, charge speed, aura colours)
	                            DragonUI     (the look of the screens: slabs, lettering, colours)
	  ServerScriptService    -> CharacterSetup (every player becomes the Base rig with hair, belt
	                                            and fingers)
	                            PowerUpServer  (referee for powering up / Super Saiyan / Kaioken)
	  StarterPlayerScripts   -> HairPhysicsClient (runs the hair + belt physics on each screen)
	                            PowerUpClient     (R / Space / K controls, front camera, power bar)
	                            PowerFX           (aura, animation, dust, rocks, the explosion)
	                            SSJCutscene       (ModuleScript: the transformation cutscene)
	                            HUD               (portrait card, HP, Ki, Scouter, Dragon Radar)
	                            HandFX            (the fingers: relaxed, fidgets, fists, the point)
	                            HairFitTool       (press H: nudge hair/belt into place)
	  ServerStorage          -> CharacterParts (empty: the imported rigged pieces go here)

	UPDATING FROM AN EARLIER VERSION
	  Replace every script with the ones in this kit. HandFX is new (a LocalScript: it goes in
	  StarterPlayerScripts). Import the two new finger files, LeftFingers_Rigged.fbx and
	  RightFingers_Rigged.fbx, into ServerStorage > CharacterParts like the hair (without them
	  you get plain hands). DragonUI (ReplicatedStorage) was new last time.
	  If you haven't yet, delete the old copies of these and import the new ones into
	  ServerStorage > CharacterParts:
	    BaseHair_Rigged.fbx  - the bangs now have bones
	    SSJHair_Rigged.fbx   - its root bone was renamed (the old name clashed with the base
	                           hair's, which tied it to the base hair's skeleton: it never moved)

	SETUP (once)
	  1. Your R15 rig must be in ReplicatedStorage and called "Base".
	  2. Import the five rigged pieces with File > Import 3D:
	       BaseHair_Rigged.fbx, SSJHair_Rigged.fbx, Belt_Rigged.fbx,
	       LeftFingers_Rigged.fbx, RightFingers_Rigged.fbx
	     (Rig Type: Custom, Scale Unit: Studs, tick "Keep Zero Influence Bones").
	     Drag all five imported models into ServerStorage > CharacterParts.
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
	  Space   spam it to fill the power bar (phones: the big TAP button at the bottom).
	          A ring of light flares at your feet and a sheet of fire rises round you, bigger
	          and faster as the bar fills; hair and belt blow upward. Once the bar is full it
	          stays full, and (after at least 2.5 s of charging) you transform: the cutscene
	          plays (your eyes, your hair, the explosion, then the screen turns into a manga
	          page while "THIS IS—" slides down and "SUPER SAIYAN!" slides up; then you swipe
	          into a point at the camera: "YOU'RE FINISHED!"), then the golden hair flows and
	          the gold aura burns until you calm down (~20 s).
	  K       Kaioken (base form): a red aura and glow, more power and speed. K again pushes
	          it higher (x2, x3, x4, x10, x20), each level burning a ki pip, but it eats your
	          health every second; push too far and your body gives out (exhausted for a few
	          seconds). R lets it go. (phones: the KAIOKEN button)
	  H       fit panel: nudge the hair/belt and copy the Offset line into HairConfig.

	TWEAKING
	  HairConfig: hair/belt colours (Color), textures (TextureId), placement (Offset),
	              how stiff/floppy (Stiffness) and heavy (GravityCompensation: lower = heavier),
	              the Super Saiyan hair's breeze to the left (LocalWind: make the X positive to
	              blow it right), how hard the aura blows them (AuraLift / AuraSwirl), and the
	              belt's room around the waist (FitGap; it's sized to the rig automatically).
	  PowerConfig: keys, how fast the bar fills/drains, minimum charge time, the cutscene
	               (Cutscene, CutsceneText, BurstTime, ExplodeAt), calming down (SSJCalmAfter),
	               aura colours, size and flicker, the HUD's numbers (ki, power level, radar
	               range), camera distance and shake.
	  PowerConfig also: when the "YOU'RE FINISHED!" point starts (PointAt) and everything about
	               the Kaioken (KaiokenLevels, KaiokenStrain, KaiokenSpeed, KaiokenKiCost ...).
	  DragonUI: the screens' colours (INK, PAPER, GI, HP, KI ...) and how far every slab
	            leans (SLANT).
	  HandFX (top of the script): finger poses (POSES) and idle fidgets (FIDGETS).
	  HairConfig: give LeftFingers / RightFingers a Color to stop them matching your hands.
	  HUD (top of the script): the portrait camera (PORTRAIT_FOV, PORTRAIT_EYE, PORTRAIT_LOOK).
]]
