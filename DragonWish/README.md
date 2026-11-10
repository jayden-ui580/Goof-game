# Dragon Wish: Online: character + power-up kit

Every player spawns as the R15 rig **Base**, with their own clothes and accessories stripped. They start with the base hair, the belt and **fingers** on, and a Dragon Ball-style HUD on screen.

- **Walking and standing:** Roblox's cartoony idle, walk and run are replaced by a realistic coded one. Your feet plant on the ground and never slide, because the steps are worked out from how far you actually move. Standing, you breathe, shift your weight from leg to leg and look around. Moving, you walk, jog or run depending on your speed, arms swinging against your legs. When you stop, you take a settle step and your body rocks forward and back upright.
- **The Great Ape (Oozaru):** press **G** in base form. The screen goes black and cuts in on you as a 34-stud giant ape, already roaring at the sky with rings of sound pounding out of its mouth. Then it drops into a hunch. It walks with heavy steps that thud, shake the ground and kick up dust, and the walk matches its speed exactly. When it stops, its body carries on forward, rocks back and lets out a big breath. Your screen turns red and your UI disappears. **G** or **R** turns you back, and it wears off after a minute.

- **Fingers:** both hands have a thumb and four fingers, two joints each. Standing around, they hang relaxed, a little curled. Every few seconds one hand fidgets, bored: a quick open-close-open-close, drumming along the fingers, rubbing the thumb on the index, a stretch, or squeezing a fist and shaking it loose. They make fists when you power up, transform or use the Kaioken, and they trail behind your hands as your arms swing.

- **Power up:** press **R**. The camera swings round in front of you and you stand tall with your fists clenched at your waist.
- **Charge:** spam **Space**.
  - **Aura:** a ring of light flares up on the ground at your feet, and a sheet of blue fire rises from it all the way round you. It grows bigger and faster as the bar fills, with energy swirling round you and sparks floating up.
  - **Pose:** you hunch over with your head down and your elbows thrown wide, trembling.
  - **Around you:** your hair, bangs and the belt's ribbons get blown upward, dust kicks up and rocks lift off the ground.
  - **HUD:** the radar slides away and your Scouter counts your power level up.
- **Transform:** fill the bar and you **burst into Super Saiyan**, with a cutscene:
  - **Close-ups:** black bars slide in, the camera pans across your eyes, then sweeps up your hair as it turns gold.
  - **Explosion:** the power explodes out with a pillar of light and a shockwave. You throw your arms out and the camera pulls back from a low angle.
  - **Manga panels:** the screen turns into a manga page (black-and-white ink, screentone dots, a page border, an ink outline round you). A tall panel slides **down** into frame, "THIS IS—", then a second slides **up**, "SUPER SAIYAN!".
  - **The point:** the panels slide away and the camera cuts to the front. Your arms come in: right forearm up, your left fingertips on the inside of your right elbow. You coil for a beat, then swipe your left arm out into a point at the camera as it pushes in on you. Your right fist pulls back to your hip, and a third panel slams in: **"YOU'RE FINISHED!"**. Then the colour floods back.
  - **After:** you get control back with a strong golden aura. About 20 seconds later your hair stops flowing and the aura fades: you've calmed down.
- **Kaioken:** press **K** in base form. A red aura bursts up, your whole body glows red and you snap into a flex, shouting. Press **K** again to push it higher: ×2, ×3, ×4, ×10, ×20. Each level burns a ki pip and makes you stronger and faster, but it eats your health every second. Push it too far and your body gives out. **R** lets it go.

## Files you need

| File | What it is |
| --- | --- |
| `DragonWishKit.rbxmx` | All 20 scripts in one drag-in file. Its folders are named after the service each part goes in. |
| `models/BaseHair_Rigged.fbx` | The base hair: 1 root bone + 17 spikes + 9 bangs (87 bones). |
| `models/SSJHair_Rigged.fbx` | The Super Saiyan hair: 1 root bone (`SSJRoot`) + 22 spikes (84 bones). |
| `models/Belt_Rigged.fbx` | The belt: 1 root bone + the 2 hanging ribbons (4 bones each). |
| `models/LeftFingers_Rigged.fbx` | The left hand's fingers: 1 root bone (`LHandRoot`) + a knuckle bone, a middle-joint bone and a tip for each finger (16 bones). |
| `models/RightFingers_Rigged.fbx` | The same for the right hand (`RHandRoot`, `RThumb1` …). |
| `models/Oozaru_Rigged.fbx` | The Great Ape: 8 meshes (fur, skin, face, ink, mouth, teeth, inner ears, eyes; 60k triangles) sharing one skeleton of 103 bones, with an opening jaw. Made from your `GreatApe` model. |
| `docs/combat_design_notes.txt` | Our combat discussion, saved for later. |

The `.blend` files are the same rigs as Blender scenes. `models/source/` has your original files, including `TakeTheFingers.obj` (the finger pieces), `R15_body.obj` (your body) and `GreatApe.fbx` (the ape you sent).

## Setup

> **Updating from an earlier version?** Replace all the scripts with the ones in the new kit. Six are new:
> - **ReplicatedStorage:** `Gait` and `PoseLayers` (ModuleScripts).
> - **ServerScriptService:** `Oozaru` and `OozaruRig` (ModuleScripts, next to `PowerUpServer`).
> - **StarterPlayerScripts:** `Locomotion` and `OozaruFX` (LocalScripts).
> - **Import `Oozaru_Rigged.fbx`** into `ServerStorage › CharacterParts`, the same way as the hair (step 2 below). Without it, G does nothing and the Output says why.
>
> `HandFX` and the two finger files were new last time; keep them.
>
> If you haven't yet, also re-import these newer pieces, after deleting the old copy from `ServerStorage › CharacterParts`:
> - **`BaseHair_Rigged.fbx`** has bones in the bangs. The server looks for bone `BB01_1`, so an older import won't load.
> - **`SSJHair_Rigged.fbx`** has its root bone named `SSJRoot`. In the first version it was called `HairRoot`, the same as the base hair's, and Roblox ties a skinned mesh to the first bone with a matching name anywhere in the character. The SSJ hair was tied to the base hair's skeleton and never moved.
>
> The belt hasn't changed.

1. **The rig.** Keep your R15 rig in ReplicatedStorage, named `Base`, with a Humanoid in it.
2. **Import the six pieces.** In File › Import 3D, pick each `.fbx` (the hair, the SSJ hair, the belt, the two finger files and the Great Ape). Set Rig Type to **Custom** and Scale Unit to Studs, and tick **Keep Zero Influence Bones**. Put all six imported models in `ServerStorage › CharacterParts`. The kit makes that folder for you. The Great Ape comes in as one model with eight meshes: keep them together. Its size doesn't matter; the server measures it and resizes it.
3. **Drag in `DragonWishKit.rbxmx`.** Move each folder's contents into the service with the same name. `StarterPlayerScripts` is inside StarterPlayer. Then delete the empty kit folder.
4. **Untick `LoadCharacterAppearance`** in StarterPlayer's properties. The script tries to do it too, but some places block that.
5. **Press Play (F5).**

## Controls in Play

| Key | Phone | What it does |
| --- | --- | --- |
| **R** | POWER button | Start powering up. Press again while charging to cancel. As a Super Saiyan, it powers you back down; in Kaioken, it lets the Kaioken go. |
| **Space** | big TAP button | Spam it to fill the bar. Tap faster than it drains: it only rises above about 3 taps a second, and 8 a second gets you there in under 3 s. |
| **K** | KAIOKEN button | Light the Kaioken (base form only), and press again to push it a level higher. |
| **G** | APE button | Become the Great Ape (base form, not in Kaioken, 60 ki). As the ape, G or R turns you back. |
| **H** | — | Fit panel: nudge the hair or belt into place, then copy the `Offset` line it shows into `HairConfig`. |

On a phone, the charge bar sits at the top right (the radar slides out of the way while you power up), and the TAP button, a big Dragon Ball, sits at the bottom between the thumbstick and the jump button, so nothing covers anything else.

## The look (`DragonUI`) and the HUD (`HUD`, your screen)

The screens borrow from the Dragon Ball fighting games (FighterZ, Sparking! ZERO) and from Persona 5's menus. The shared module `DragonUI` holds the look:
- **Slabs, not rounded boxes.** Every panel, bar and tag is a parallelogram, and they all lean the same way (24°).
- **Three colours plus meaning.** Ink black, warm paper and Goku's gi orange. Other colours only mean something: yellow is health, red is damage, blue is ki (gold as a Super Saiyan), green is the Scouter.
- **Comic lettering.** Bangers with an ink outline, printed twice with the second print offset behind it, like the Dragon Ball logo.
- **Manga touches.** Halftone dots, hard (unblurred) shadows and Dragon Balls.
- **No images.** It's all plain Frames and text, so there's nothing to upload.

The HUD, top left:
- **Portrait card:** a gi-orange slab with a hard shadow, gold as a Super Saiyan. Your face is a live 3D portrait with no frame round it, so your head and hair pop out over the top of the card. It's re-taken when your hair changes.
  - **Energy arc:** a blue swoosh under the card (gold as a Super Saiyan).
  - **Gi badge:** a kanji in a white circle, like the one on Goku's gi: 気 ("ki"), or 超 ("super") as a Super Saiyan.
- **Name panel:** a dark slanted panel that fades out in halftone dots, with your name in comic lettering and a tag with your form.
- **HP bar:** yellow, with a paper outline and a glint that runs along it. A red chunk shows the damage you just took and shrinks a moment later. Below 30% the bar throbs orange.
  - **Getting hit:** the plate shakes, the outline flashes red and your portrait flashes red.
- **Ki:** five slanted pips, blue in base form and gold as a Super Saiyan. Each pip pops white when it fills. Next to them is a Dragon Ball whose stars count your full pips. At full ki it's a 5-star ball and it pulses.
- **Scouter:** under the bars, a dark green readout with scan lines shows your **POWER LEVEL**.
  - **Values:** 1,500 at rest, up to 7,500 as you charge, and 75,000 as a Super Saiyan.
  - **Animation:** it scrambles and counts up when it jumps, and flashes **IT'S OVER 9000!!** when you pass 9000.

Top right: a **Dragon Radar**, a sweeping green screen with a blip for every player within 250 studs (gold blips are Super Saiyans). Up on the radar is the way your camera faces.

Behaviour:
- **Motion:** the plate slides in from the left (and the radar from the right) when you spawn, and again when the cutscene ends. The radar slides away while you power up.
- **Phones:** it shrinks to fit.
- **Cutscene:** it hides while the cutscene plays.
- **Roblox's health bar:** it replaces it.

- **Kaioken:** the card, pips and arc turn red, the badge reads 拳 ("fist", from 界王拳, Kaiōken) and the tag reads **KAIOKEN x3**. The HP bar's outline throbs as the strain eats your health, and the Scouter multiplies your power level (×10 is 15,000: over 9000!). When your body gives out the tag reads **EXHAUSTED** and the card goes grey.

The power-up controls (`PowerUpClient`) use the same look:
- **Charging:** the **SPAM SPACE!** prompt in comic lettering, and a slanted charge bar that turns from ki blue to gold as your hair starts lifting (with a % readout).
- **Phones:** a big Dragon Ball **TAP!** button.
- **Hints:** key caps along the bottom (**R** / **POWER UP**, **K** / **KAIOKEN**).
- **Kaioken:** a red **KAIOKEN x4!** shout pops up each time it's lit or pushed higher, with a red flash and a kick of the camera.
- **Notices:** short lines when a key can't work: NOT ENOUGH KI!, BASE FORM ONLY!, TOO TIRED!, LET THE KAIOKEN GO FIRST!

## Walking and standing (`Locomotion` + `Gait`, every screen)

Roblox's own idle, walk and run animations are stopped as they start and replaced by a coded one, on every R15 character. Jumping, falling, climbing, swimming and sitting still use Roblox's animations; the walk fades out while you're off your feet and back in when you land. Emotes, and anything an attack plays at Action priority, take over while they play.

- **The feet never slide.** This is the usual problem with walk cycles in games: the animation loops at its own pace while the character moves at another, so the feet skate. Here each foot stays exactly where it landed until it steps again, and the legs bend to reach it (two-bone IK: hip, knee, ankle). The steps come from the distance you actually travel, not from a clock.
- **How long a step is** depends on your speed and the length of your legs, the rule real animals follow (step length grows with the Froude number, speed² / (gravity × leg length)). So a person takes quick steps and the 34-stud ape takes long, slow ones, each at its own natural pace.
- **Landing ahead.** Each step lands where your hips will be when the foot comes down, so speeding up, slowing down and turning don't leave a foot behind. If one gets left behind anyway, it lifts off early.
- **Heel to toe.** A foot lands on its heel with the toes up, rolls flat, then the heel peels up and it pushes off its toes. A swinging foot always clears the ground.
- **Walk → jog → run** blends by speed. Running, the feet spend less time on the ground, there's a moment with both in the air, the heel kicks up behind and the knee drives forward; the arms bend to about 90°.
  - **About Roblox's speed:** the default WalkSpeed (16 studs/s) is about 5 m/s for a person your size, which is a run. So that's what you'll see at full speed. Slower speeds give a jog, then a walk: when you're exhausted (×0.55) you walk. For a walk at full stick, lower WalkSpeed to about 8 and add a sprint key.
- **Stopping.** The swinging foot comes down beside the other one. If the back foot is still trailing, it takes one short settle step to come in. Your body carries on forward a little and rocks back upright.
- **Turning on the spot.** The feet shuffle round one at a time once they're turned too far from your body.
- **Standing:** slow breathing, your weight shifting from one leg to the other every few seconds (that hip drops, the other knee softens, the shoulders tilt against it), the head looking around, arms hanging with soft elbows, a tiny balance sway.
- **Moving:** the hips rise and fall, sway over the standing foot and turn with the swinging leg. The chest turns against the hips, the head stays level and facing where you're going, and you lean into turns.
- **Layers.** `PoseLayers` runs the walk first and `PowerFX`'s power-up poses on top, every frame, in that order.

## The Great Ape (`Oozaru` on the server, `OozaruFX` on every screen)

- **Turning into it (G).** The server checks you're in base form, not in Kaioken or exhausted, with 60 ki (`OozaruKiCost`). Your screen fades to black, and a copy of the giant is put where you stand, facing your way. It becomes your character. Your own body, with its hair, belt and fingers, is kept aside. You keep the same share of your health (out of `OozaruHealth`, 500) and your ki.
- **The entrance.** The screen cuts straight in on it already roaring:
  - leaning back, head thrown up at the sky, jaw wide open, a chatter of rage in it;
  - arms flung out wide, fingers curled in rage (clawed, not fists), toes gripping the ground, trembling;
  - rings of sound pounding out of its mouth, a ring of dust blasting off the ground, the ground shaking for everyone near, the roar sound.
  
  Then it drops forward into its hunch: back rounded, head up, knees bent, feet wide apart, arms hanging heavy. You can move after `OozaruIntro` (4.4 s).
- **Standing:** deep slow breaths with a puff of breath on each one, its weight rolling from foot to foot, looking around (at the nearest person in front of it, if there is one), now and then a snarl and a shake of the head. The tail sways on its own.
- **Walking:** heavy steps from `Gait`, at `OozaruWalkSpeed` (11 studs/s), about 1.2 steps a second. Each step lands with a dip of the whole body, a deep thud, a ring of dust and the camera shaking for anyone near. The hips sway in a rolling waddle, the shoulders roll, the arms swing, the tail swings behind and trails through turns. It's slow to get going.
- **Stopping (the pause):** the swinging foot comes down, its body carries on forward and rocks back, it lets out a big breath, then settles. If a foot's left behind, it takes a slow settle step.
- **Turning:** it can't spin on the spot. It turns at `OozaruTurnSpeed` (140°/s), slows down while it turns hard, and shuffles its feet round.
- **Your screen while you're the giant:**
  - a red tint, with a dark red edge that throbs with its breathing;
  - your UI gone (the HUD, the power-up screen, the backpack and player list; the chat stays);
  - the camera pulled back to take it all in;
  - a few seconds before it wears off (`OozaruTime`, 60 s), your vision starts to swim.
- **Turning back:** press **G** or **R** (not mid-roar), or wait it out. The screen goes black and you're back in your own body where the giant stood, with its share of health and the ki you have. Everyone else sees it vanish in a cloud of smoke. If the giant is beaten, you respawn as normal.
- **Its eyes glow red** (a light at night too).

## The fingers (`HandFX`, every screen)

- **Where they come from.** The 20 finger pieces from your `TakeTheFingers` rig, moved onto your R15 body's hands. Both rigs' arms end at the same height, so they line up exactly. Each hand is one skinned mesh with a knuckle bone and a middle-joint bone per finger. The segments stay rigid, like separate parts on hinges.
- **How they bend.** The four fingers sit on the outer edge of the bottom of the hand and the thumb on the inner edge, so they curl toward each other: a fist folds the fingers into the palm with the thumb across them.
- **Who moves them.** `HandFX` poses every player's fingers on your screen. The joints move on springs, so a finger overshoots a touch and settles instead of snapping, and each finger starts a moment after its neighbour.
  - **Standing:** relaxed, the pinky curled most and the index least, the thumb hanging forward. Every 2.5–7 s one hand (sometimes both) does a bored fidget: `Flex` (open-close-open-close), `Drum`, `Rub` (thumb on the index), `Stretch` or `Squeeze` (a tight fist, then shaken loose).
  - **Moving:** relaxed, trailing behind the hand as your arms swing.
  - **Powering up, transforming, Kaioken:** fists, squeezing harder as the bar fills.
  - **Super Saiyan:** fists while the golden aura burns, loosening as you calm down, with tense fidgets (`Clench`, `Crack`).
  - **The point:** the left hand goes flat on your elbow, opens on the swipe, then snaps into a point.
  - **Exhausted:** limp.
- **Colour.** They take the colour of your hands (the rig's BodyColors), unless you give them a `Color` in `HairConfig`.

## Kaioken

King Kai's technique, in base form only. It's built to fit the combat plan in `docs/combat_design_notes.txt` as an "amplifier": more power for health, an answer to being out-traded, and one with built-in counterplay (the strain clock).
- **Levels:** ×2, ×3, ×4, ×10, ×20 (`KaiokenLevels`). Each press of K climbs one level and costs one ki pip, 20 ki (`KaiokenKiCost`). Five pips, five levels, so a full ki bar takes you all the way to ×20. There's a 0.6 s pause between levels (`KaiokenCooldown`).
- **What you get:** your power level × the multiplier, and faster legs (`KaiokenSpeed`: ×1.15 at ×2 up to ×1.6 at ×20).
- **What it costs:** health every second while it burns (`KaiokenStrain`: 1.5 at ×2 up to 16 at ×20). Roblox heals you 1 health a second on its own, so ×2 barely hurts and ×20 is a few seconds of glory. Ki doesn't refill while it burns.
- **Your body gives out:** if your health falls to 10 (`KaiokenFloor`), the Kaioken stops and you're **exhausted** for 4 s (`KaiokenExhaustTime`). You're bent over breathing hard, slow (`ExhaustedSpeed`, ×0.55) and can't power up. The strain never kills you outright, but you'll be at 10 health.
- **R** lets it go any time. You can't power up into Super Saiyan while it burns.
- **What everyone sees (`PowerFX`):**
  - a red aura sized by the level;
  - a red glow over your whole body, throbbing like a heartbeat, faster the higher you go;
  - a red shockwave and a flex (chest out, head back, fists driven down) each time it climbs;
  - a strained tremble at ×10 and ×20.
  
  Your hair lifts in the red aura.

## How it works

- **The morph (`CharacterSetup`, server).**
  - When the server starts, it copies `Base`, puts the five rigged pieces on the copy (hair, SSJ hair, belt and both hands' fingers), and saves it as the `StarterCharacter`. That's Roblox's built-in way of giving every player a custom body.
  - Each piece is placed by matching its bones to where they sat on the original model, so it lands in the same spot on the head, waist or hand as in your `.obj` files. The fingers aren't given to the hair physics; `HandFX` poses them.
  - The belt is then sized to your rig's waist. The rig tools measured the inside of the band all the way round (`Ring` in `HairConfig`). The server measures the Base rig's LowerTorso, UpperTorso and upper legs where they cross the band, and grows or shrinks the belt until there's `FitGap` (0.04 studs) of room everywhere. On a standard blocky R15 it comes out at ×1.1.
  - Anything from a player's own avatar that still sneaks on (shirts, pants, hats, body colours) is deleted as it arrives.
- **The referee (`PowerUpServer`, server).**
  - Your game tells the server "I started", "my bar is at X", "I'm full", "cancel", "power down" and "Kaioken".
  - The server checks each message: the bar can't rise faster than 16 taps a second, and you have to charge for at least 2.5 s. A hacked client can't skip straight to Super Saiyan.
  - It sets values on your character that every screen reads:
    - `Form`, `PowerState` and `Charge`: what you're doing.
    - `AuraWind`: how hard your hair is blown up.
    - `Breeze`: the Super Saiyan glow. It's 1 when you transform and fades to 0 when you calm down.
    - `Ki`: shown on the HUD.
    - `Kaioken` (0–5, the level), `KaiokenMult` (the multiplier) and `Exhausted`.
  - It swaps the hair and freezes your walking while you charge and transform. In Kaioken it checks your ki and the pause between levels, speeds you up, drains your health, and exhausts you when your body gives out.
  - **Calming down:** `SSJCalmAfter` (20 s) after you get control back, it fades `Breeze` and the hair lift to 0 over `SSJCalmTime` (4 s). The hair stops flowing and the aura fades with it.
- **Your controls (`PowerUpClient`).** The keys, the power bar and the front-view camera, which shakes harder as you charge. When you transform it plays the cutscene. Space is grabbed at a higher priority than jumping, so spamming it doesn't make you hop.
- **The Great Ape (`Oozaru`, server).** The first time someone presses G, it finds the imported model by its tail-tip bone (`TAIL18`). It compares every bone with where it was designed (`OozaruRig`, generated from the rig) to learn how the importer sized and turned it, resizes it to `OozaruScale`, and stands it upright. Then it adds an invisible root part (a box from the hips to the head: it does the walking and the bumping into things) and a Humanoid, and welds everything on. Each player who transforms gets a copy.
- **The cutscene (`SSJCutscene`, only the player transforming sees it).**
  - **Camera:** it takes the camera for the transformation (`BurstTime`, 6.9 s). Every shot is measured from your head or body as they move:
    - **Eyes (0–1 s):** an extreme close-up panning across your eyes.
    - **Hair (1–2.2 s):** a sweep up your hair as it turns gold.
    - **Explosion (`ExplodeAt`, 2.2 s):** a white flash and manga focus lines, then a low-angle pull-back.
    - **The point (`PointAt`, 4.3 s):** a cut to the front, a little to your left, pushing in as your arm swipes out at the lens.
  - **Manga panels:** tall white panels with a thick black border, an inner border and a hard shadow. The first has speed lines and slides **down** into frame at 2.6 s ("THIS IS—"). The second has burst lines and slides **up** at 3.25 s ("SUPER SAIYAN!"). The text is `CutsceneText` in PowerConfig.
  - **Third panel:** the first two slide away just before the point, and when the point lands (0.81 s after `PointAt`) a third panel slams down like a stamp: "YOU'RE FINISHED!" (the third line of `CutsceneText`).
  - **Manga filter:** with the first panel, the 3D view turns into a manga page: the colour drains to black and white with hard contrast and a paper tint, screentone dots fill in round the edges, a page border appears and you get an ink outline. It stays through the point and fades back with the last panel.
  - **Finish:** the panel slides away, the colour floods back, the bars slide away and you get control back.
  - **On screen:** black bars cover the top and bottom, and on a phone the thumbstick and jump button hide while it plays. Turn the cutscene off with `Cutscene = false`.
- **The animation (`PowerFX`, every screen).** It's coded joint by joint, so there's no animation asset to upload. Each R15 joint has three key poses:
  - **READY:** standing tall, fists at the waist, elbows out.
  - **STRAIN:** hunched over, head down, elbows wide, knees bent.
  - **RELEASE:** leaning back, head up, arms lowered and spread.
  - **Blending:** while charging it blends READY into STRAIN as the bar fills, with a tremble that grows with the effort. Transforming, you stay hunched as the power builds, snap into RELEASE at the explosion, and hold it until the point. The pose is layered on top of the walk and idle animations, so it fades in and out smoothly.
  - **The point (`POINT_TOUCH`, `POINT_HIT`):** from RELEASE your arms come in to TOUCH (right forearm up, left fingertips on the inside of the right elbow) and you coil for a beat (`POINT_COIL`). Then the swipe to HIT: the left arm straight out at the camera, the right fist pulled back to the hip, the body turned three-quarters.
    - **Weight:** every joint follows on its own delay and overshoots a little before settling (`POINT_TIMING`): the hips lead, then the shoulder, elbow and wrist, like a whip. The body sinks into the stance and bobs back, the head nods, and you breathe while holding it.
    - **Aim:** the angles were solved so the fingertips really land on the elbow and the index aims just beside the lens, so you see the finger's length.
  - **Kaioken flex (`KAIOKEN_FLEX`) and exhausted slump (`SLUMP`):** two more layers, with heavy breathing in the slump.
  - **Joints:** it works with both kinds of character joint. Roblox's "Avatar Joint Upgrade" gives characters **AnimationConstraint** joints instead of Motor6Ds.
- **The aura (`PowerFX`, every screen).**
  - **Ground ring:** a ring of glowing pieces on the ground at your feet, flickering, with ripples pulsing out of it along the ground at higher power.
  - **Fire:** about 30 flames are rooted on the ring all the way round you. They overlap into one sheet of fire, brightest at its edges where you look through the most flames. They lean outward as they rise, fade at their tips and lick up and down, and the whole fire slowly turns round you.
    - **Streaks:** thin bright streaks shoot up through it.
    - **Licks:** flames break off near the ground and rise along the fire, shrinking as they go.
    - **What they're made of:** each flame is a **Beam**, a tapered ribbon that always faces the camera.
  - **Extras:** energy streaks swirl round you, sparks float up and light streaks shoot past. A glow lights the surroundings, and dust and rocks lift at high power.
  - **Visibility:** flames between the camera and you thin right down so they don't hide you.
  - **Colour:** blue in base form, gold as a Super Saiyan, red in Kaioken (it stays red as it dies away). After transforming the gold aura stays strong (`SSJIdleAura`) until you calm down.
  - **Explosion:** a pillar of light, a flash, a shockwave ring, dust and a moment where every flame shoots extra high.
  - **Flicker:** the flames change shape `AuraFrameRate` times a second (24) with a little random wobble, a touch of anime flicker. 12–15 is choppier, 60 is smooth.
- **The hair and belt (`HairPhysics`, every screen).**
  - **Gravity:** only part of gravity is cancelled by the springs (`GravityCompensation`): half for the base hair, 40% for the SSJ hair. The spikes hang a little heavier and swing more when you move, jump or stop.
  - **Aura:** an upward "wind" and a swirl, driven by `AuraWind`.
  - **Breeze:** the SSJ hair has a steady breeze to the wearer's left (`LocalWind`) that turns with the head, each spike rippling on its own. It's multiplied by `Breeze`, so it stops when you calm down.
  - A hidden hair (the SSJ hair while you're in base form) doesn't get simulated.

## Settings

- **`PowerConfig`:**
  - **controls and charging:** keys, how much each tap fills, how fast the bar drains, minimum charge time
  - **the transformation:** how long it takes (`BurstTime`), when it explodes (`ExplodeAt`), when the point starts (`PointAt`), the cutscene on/off and its three lines (`Cutscene`, `CutsceneText`)
  - **Kaioken:** the key, levels, strain, speed, aura size, ki cost, pause between levels, the health floor and how long you're exhausted (`KaiokenKey` … `ExhaustedSpeed`), and its colours (`KaiokenAuraColor`, `KaiokenAuraEdge`, `KaiokenGlow`)
  - **calming down:** when it happens and how long it takes (`SSJCalmAfter`, `SSJCalmTime`), how strong the gold aura stays until then (`SSJIdleAura`)
  - **aura looks:** main and tip colour for each form, size, how many flames (`AuraFlames`: lower it if lots of players lag), flicker (`AuraFrameRate`)
  - **HUD:** ki (`KiMax`, `KiStart`, `KiRegen`), power level (`BasePowerLevel`, `ChargePowerBoost`, `SSJMultiplier`), radar range (`RadarRange`)
  - **camera:** distance, height and shake
- **`PowerFX`** (top of the script): the key poses (`READY`, `STRAIN`, `RELEASE`, the point's `POINT_TOUCH` / `POINT_HIT` / `POINT_TIMING`, `KAIOKEN_FLEX`, `SLUMP`), the aura's sizes (`RING_RADIUS`, `FLAME_HEIGHT`, `FLAME_LEAN`) and its flame groups (`GROUPS`), if you want to restyle them.
- **`PowerConfig` › the Great Ape:** the key, ki cost, how long it lasts, size, health, walk and turn speed, how long it roars, its colours, and the roar and footstep sounds (`OozaruKey` … `OozaruStepSound`).
- **`Locomotion`** (top of the script): how people walk (`HUMAN`: stride, stance width, toe-out, hip sway and bob, settle-step time). Every setting is explained in `Gait`'s `DEFAULTS`.
- **`OozaruFX`** (top of the script): how the giant walks (`APE`), its hands (`HANDS`: relaxed, rage, loose) and its toes.
- **`HandFX`** (top of the script): the finger poses (`POSES`, in degrees: knuckle bend, middle-joint bend, spread), the idle fidgets (`FIDGETS`, `SSJ_FIDGETS`: key poses over time, which finger leads, how far behind each one follows), and how springy the fingers are (`OMEGA`, `DAMPING`, `LAG`).
- **`DragonUI`** (top of the script): the screens' colours (`INK`, `PAPER`, `GI`, `HP`, `KI` …) and how far every slab leans (`SLANT`).
- **`HUD`** (top of the script): the portrait camera (`PORTRAIT_FOV`, `PORTRAIT_EYE`, `PORTRAIT_LOOK`), if your head sits too high or low on the card.
- **`HairConfig`:**
  - colour, texture id, placement (`Offset`) and size of each piece
  - how stiff and heavy it is (`Stiffness`, `GravityCompensation`); the bangs have their own softer settings (`ChainOverrides`, chains `BB01`–`BB09`)
  - the SSJ breeze (`LocalWind`, `LocalWindFlutter`); flip the X to `70` to blow it to the right
  - how hard the aura blows it (`AuraLift`, `AuraSwirl`)
  - the belt's room around the waist (`FitGap`, or `Scale` for extra size on top)
  - the fingers (`LeftFingers`, `RightFingers`): give them a `Color` to stop them matching your hands

## Limits

- **Bone names must be unique across every piece worn together.** Roblox ties each skinned mesh to its bones by name across the whole character. `CharacterSetup` warns in the Output if two pieces share a bone name.
- **No textures.** The `.mtl` files point at `Handle1_diff.png`, which wasn't in the zip. The pieces use flat colours instead: black base hair, gold SSJ hair, blue belt. Paste a texture id into `TextureId` in `HairConfig` if you have one.
- **Hair placement is worked out from the model files.** The head centre for each piece comes from its shape. If a piece sits a little off on your rig, press **H** and nudge it.
- **Sounds.** Only the Great Ape has any. Its footsteps are Roblox's own landing thud played deep and slow (`rbxasset://sounds/action_jump_land.mp3`). The roar is "Monster Roar - Sound Effect" from the Creator Store (`rbxassetid://2139510606`), uploaded by another creator. I couldn't check from here that it plays in your game: if it's silent, search the Creator Store's Audio for "roar" and paste the id into `OozaruRoarSound`. There's still no charge hum, scream or burst sound.
- **The Great Ape model.** The ape you sent looks ripped from a commercial Dragon Ball game (the bone names and toon materials point that way). Roblox removes assets that get a copyright claim, and can moderate the game too. It's fine for testing. Before you publish, swap in a model you made or have the rights to. The scripts only need the same bone names, and `tools/rig/build_oozaru.py` shows how this one was prepared.
- **The Great Ape's look.** The original toon shading and textures aren't in the `.fbx`; the meshes get flat colours from `PowerConfig` (fur, skin) and the server (ink lines, mouth, teeth, glowing eyes).
- **Not tried in real Studio.** The scripts were run against fake characters in tests (`tools/test/`), and the UI was drawn by a stand-in renderer (`tools/preview/`), not in a live Roblox server. The walk and the Great Ape were checked with renders of your R15 body and the ape mesh posed by the scripts' own numbers.
  - **Swapping characters:** turning into the giant sets `Player.Character` to a new model and keeps your body in ServerStorage, the standard way to morph. The camera, controls and network ownership should follow, but this couldn't be run in a real server here.
  - **Roblox's walk animations:** they're stopped as they start (the `idle`, `walk` and `run` animations of the `Animate` script). If you replace `Animate` with your own, rename those or the walk won't take over. The renderer uses stand-in fonts, and it can't show the 3D portrait, the ink outline round you or the colour filter exactly. The portrait camera's framing is a best guess: if your head sits wrong on the card, change `PORTRAIT_EYE` / `PORTRAIT_LOOK` in `HUD`.
- **Slanted edges are a little jagged.** Roblox doesn't smooth the edges of turned frames, and each slab's slanted ends are turned frames.
- **The kanji** (気, 超 and 拳) use Roblox's built-in fallback font for Japanese, since Bangers and Gotham don't have them.
- **The fingers, the point and Kaioken weren't watched in Roblox.**
  - **Fingers:** the poses were drawn in a stand-in renderer, and `hands_mock` checks where every fingertip lands in a fake game, with the bones deliberately imported at random angles.
  - **The point:** worked out on a stand-in of your R15 body, with the joints' pivots estimated from `R15_body.obj`. If the left hand stops a little short of the elbow, or the finger aims off the lens, nudge `POINT_TOUCH` / `POINT_HIT` in `PowerFX` and `pointShot` in `SSJCutscene`.
- **A fist is fingers folded under the hand.** The hand block is as wide as the fingers are long, so a curled finger mostly tucks under it. Close up it reads as a closed hand, not a chunky cartoon fist.
- **Kaioken's body glow is a Highlight.** Roblox only draws about 31 Highlights at once, so in a crowd of Kaioken users some won't glow (their red aura still shows).

## Rebuilding and checking

- `tools/rig/build_oozaru.py` prepares the Great Ape from `models/source/GreatApe.fbx` with Blender's Python module: it re-weights the jaw to the chin bone so the mouth opens, drops unused bones, thins the fur to fit Roblox's 20k-triangle limit per mesh, joins the pieces by colour, and exports `Oozaru_Rigged.fbx` plus `oozaru.json`. `tools/rig/emit_oozaru.py` turns `oozaru.json` into `OozaruRig`.
- `tools/rig/build_dbz.py` rigs the `.obj` files with Blender's Python module and writes the `.fbx` and `.blend` files (`BaseHair`, `SSJHair`, `Belt`, `LeftFingers`, `RightFingers`). Add piece names to rebuild only those. `tools/rig/fingers.py` moves the finger pieces onto your R15 hands and finds each joint's hinge from the pieces' rounded knuckles. `tools/rig/verify_dbz.py` re-imports the files and checks the bones.
- `lune run tools/build_rbxmx.luau .` rebuilds `DragonWishKit.rbxmx` from `src/`.
- Tests, run from this folder with `lune run tools/test/<name>.luau`:
  - `server_mock`: the morph (all five pieces), the referee, ki, calming down, the Kaioken (levels, ki, strain, the body giving out, speed), and the Great Ape (built from a fake import turned and placed elsewhere, swapped in and out, the roar lock, the time limit, refusals)
  - `client_mock`: controls plus server, end to end, including the cutscene starting and the K and G keys
  - `gait_mock`: the feet don't slide at 4–22 studs/s, steps match the distance, stopping, turning on the spot, curving, sideways, backward, speeding up, jumping
  - `locomotion_mock`: the real walk on a stand-in of your R15 body: standing (weight shifts, looking around), running, jogging and walking with no sliding, arms against the legs, the head steady, the stop, jumping (add `"" motor6d` for old-style joints)
  - `ape_mock`: the real Great Ape script on a stand-in built from the rig: the roar, the hunch, the walk with planted feet, the stop, turning, and your screen
  - `fx_mock`: aura, ring, animation, explosion timing, the point, and Kaioken's red aura, glow and flex (add `"" motor6d` to test old-style joints)
  - `hands_mock`: the fingers: relaxed, fidgets, fists, the point, Kaioken, limp, and trailing when the arm swings
  - `aura_harness <BaseHair|SSJHair|Belt>`: hair and belt physics through a power-up, walking, stopping and jumping
  - `wake_mock`: the SSJ hair waking up when it's shown
  - `compile <files...>`: every script compiles
- UI previews:
  - `lune run tools/preview/ui_dump.luau <idle|charging|ssj|hit|kaioken|exhausted|cutscene:SECONDS> <width> <height> out.json` runs the real HUD, controls and cutscene scripts (and `DragonUI`) and writes out what's on screen.
  - `python3 tools/preview/render_ui.py out.json out.png` draws it the way Roblox lays it out, with phone safe areas and touch controls.
  - `python3 tools/preview/check_ui.py idle.json charging.json cutscene_3.9.json [kaioken.json cutscene_5.4.json]` checks the important pieces are there.
- `python3 -I tools/rig/belt_ring.py models/source/Belt.obj tools/rig/riginfo.json` re-measures the belt's band, then `tools/rig/emit_layouts.py` prints the `Layouts` table for `HairConfig`.
