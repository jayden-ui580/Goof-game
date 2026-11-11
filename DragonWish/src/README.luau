--[[
	============================================================================
	 DRAGON WISH: ONLINE — CHARACTER + POWER-UP KIT   (this script is switched off; it's notes)
	============================================================================

	WHAT'S IN HERE
	  ReplicatedStorage      -> HairPhysics  (moves hair and belt ribbons)
	                            HairConfig   (hair/belt settings: colours, stiffness, aura reaction)
	                            PowerConfig  (power-up settings: keys, charge speed, aura colours)
	                            DragonUI     (the look of the screens: slabs, lettering, colours)
	                            Gait         (feet that plant and never slide: the walking engine)
	                            PoseLayers   (stacks the walk and the power-up poses in order)
	  ServerScriptService    -> CharacterSetup (every player becomes the Base rig with hair, belt
	                                            and fingers)
	                            PowerUpServer  (referee for powering up / Super Saiyan / Kaioken)
	  StarterPlayerScripts   -> HairPhysicsClient (runs the hair + belt physics on each screen)
	                            PowerUpClient     (R / Space / K controls, front camera, power bar)
	                            PowerFX           (aura, animation, dust, rocks, the explosion)
	                            SSJCutscene       (ModuleScript: the transformation cutscene)
	                            HUD               (portrait card, HP, Ki, Scouter, Dragon Radar)
	                            HandFX            (the fingers: relaxed, fidgets, fists, the point)
	                            Locomotion        (realistic idle / walk / run for everyone, in
	                                               place of Roblox's cartoony ones)
	                            HairFitTool       (press H: nudge hair/belt into place)
	  ServerStorage          -> CharacterParts (empty: the imported rigged pieces go here)

	UPDATING FROM AN EARLIER VERSION
	  Replace every script with the ones in this kit.
	  The hairs are now .glb files with their textures inside (black base hair, gold Super
	  Saiyan hair) and there are two new ones, SSJ2 and SSJ3. Delete the old BaseHair_Rigged
	  and SSJHair_Rigged models from ServerStorage > CharacterParts and import these four there:
	    BaseHair_Rigged.glb, SSJHair_Rigged.glb, SSJ2Hair_Rigged.glb, SSJ3Hair_Rigged.glb
	  (if an old untextured copy is left behind, the textured one is used).
	  The Great Ape is parked for now: delete
	  Oozaru and OozaruRig (ServerScriptService), OozaruFX (StarterPlayerScripts) and the
	  imported Oozaru_Rigged model (ServerStorage > CharacterParts) from your game.
	  Gait and PoseLayers (ReplicatedStorage) and Locomotion (StarterPlayerScripts) stay: they
	  are the realistic walk. HandFX and the two finger files came the round before.

	SETUP (once)
	  1. Your R15 rig must be in ReplicatedStorage and called "Base".
	  2. Import the rigged pieces with File > Import 3D:
	       BaseHair_Rigged.glb, SSJHair_Rigged.glb, SSJ2Hair_Rigged.glb, SSJ3Hair_Rigged.glb
	       (the hairs: their textures come with them), Belt_Rigged.fbx,
	       LeftFingers_Rigged.fbx, RightFingers_Rigged.fbx
	     (Rig Type: Custom, Scale Unit: Studs, tick "Keep Zero Influence Bones", leave
	     "Upload to Roblox" on so the textures upload).
	     Drag all seven imported models into ServerStorage > CharacterParts. The SSJ2 and
	     SSJ3 hair show when you reach those forms.
	  3. Move the contents of each folder in this kit into the service with the same name
	     (StarterPlayerScripts is inside StarterPlayer). Then delete this kit folder.
	  4. In StarterPlayer's properties, untick LoadCharacterAppearance (the script tries to do
	     this itself, but some places don't allow it from a script).
	  5. Press Play (F5).

	CONTROLS (in Play)
	  R       power up: the camera swings round to face you and you stand tall, fists at
	          your waist. As the bar fills you hunch over, head down, elbows wide; when you
	          transform you lean back, head up, arms spread, and hold it a moment.
	          R again cancels. As a Super Saiyan, R powers up again: fill the bar to go
	          Super Saiyan 2, and again for Super Saiyan 3 (no cutscene, just the power-up).
	  F       power down to base form (phones: the DOWN button).
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
	          Picking a hair you can't see right now (SSJ2, SSJ3) shows it on you.
	  Walking: your feet plant and never slide; walk, jog or run by speed (Roblox's default
	          speed, 16, is a run for someone your size); a settle step when you stop.

	TWEAKING
	  HairConfig: placement (Offset), a texture id to replace a hair's own (TextureId),
	              colours for pieces with no texture (Color),
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
	  Locomotion (top): how people walk (HUMAN). Gait's DEFAULTS explains every walking setting.
	  HairConfig: give LeftFingers / RightFingers a Color to stop them matching your hands.
	  HUD (top of the script): the portrait camera (PORTRAIT_FOV, PORTRAIT_EYE, PORTRAIT_LOOK).
]]
