# Dragon Wish: Online: character + power-up kit

Every player spawns as the R15 rig **Base**, with their own clothes and accessories stripped. They start with the base hair and the belt on, and a Dragon Ball-style HUD on screen.

- **Power up:** press **R**. The camera swings round in front of you and you stand tall with your fists clenched at your waist.
- **Charge:** spam **Space**.
  - **Aura:** a ring of light flares up on the ground at your feet, and a sheet of blue fire rises from it all the way round you. It grows bigger and faster as the bar fills, with energy swirling round you and sparks floating up.
  - **Pose:** you hunch over with your head down and your elbows thrown wide, trembling.
  - **Around you:** your hair, bangs and the belt's ribbons get blown upward, dust kicks up and rocks lift off the ground.
  - **HUD:** your scouter counts your power level up.
- **Transform:** fill the bar and you **burst into Super Saiyan**, with a cutscene:
  - **Close-ups:** black bars slide in, the camera pans across your eyes, then sweeps up your hair as it turns gold.
  - **Explosion:** the power explodes out with a pillar of light and a shockwave. You throw your arms out and the camera pulls back from a low angle.
  - **Manga boxes:** "THIS IS—" drops in, then "SUPER SAIYAN!".
  - **After:** you get control back with a strong golden aura. About 20 seconds later your hair stops flowing and the aura fades: you've calmed down.

## Files you need

| File | What it is |
| --- | --- |
| `DragonWishKit.rbxmx` | All 12 scripts in one drag-in file. Its folders are named after the service each part goes in. |
| `models/BaseHair_Rigged.fbx` | The base hair: 1 root bone + 17 spikes + 9 bangs (87 bones). |
| `models/SSJHair_Rigged.fbx` | The Super Saiyan hair: 1 root bone (`SSJRoot`) + 22 spikes (84 bones). |
| `models/Belt_Rigged.fbx` | The belt: 1 root bone + the 2 hanging ribbons (4 bones each). |

The `.blend` files are the same rigs as Blender scenes. `models/source/` has your original `.obj` files.

## Setup

> **Updating from an earlier version?** Replace all the scripts with the ones in the new kit. Two of them are new: `HUD` (a LocalScript) and `SSJCutscene` (a ModuleScript); both go in StarterPlayerScripts. If you haven't yet, re-import the newer pieces, after deleting the old copy from `ServerStorage › CharacterParts`:
> - **`BaseHair_Rigged.fbx`** has bones in the bangs. The server looks for bone `BB01_1`, so an older import won't load.
> - **`SSJHair_Rigged.fbx`** has its root bone named `SSJRoot`. In the first version it was called `HairRoot`, the same as the base hair's, and Roblox ties a skinned mesh to the first bone with a matching name anywhere in the character. The SSJ hair was tied to the base hair's skeleton and never moved.
>
> The belt hasn't changed.

1. **The rig.** Keep your R15 rig in ReplicatedStorage, named `Base`, with a Humanoid in it.
2. **Import the three pieces.** In File › Import 3D, pick each `.fbx`. Set Rig Type to **Custom** and Scale Unit to Studs, and tick **Keep Zero Influence Bones**. Put all three imported models in `ServerStorage › CharacterParts`. The kit makes that folder for you.
3. **Drag in `DragonWishKit.rbxmx`.** Move each folder's contents into the service with the same name. `StarterPlayerScripts` is inside StarterPlayer. Then delete the empty kit folder.
4. **Untick `LoadCharacterAppearance`** in StarterPlayer's properties. The script tries to do it too, but some places block that.
5. **Press Play (F5).**

## Controls in Play

| Key | Phone | What it does |
| --- | --- | --- |
| **R** | POWER button | Start powering up. Press again while charging to cancel. As a Super Saiyan, it powers you back down. |
| **Space** | big TAP button | Spam it to fill the bar. Tap faster than it drains: it only rises above about 3 taps a second, and 8 a second gets you there in under 3 s. |
| **H** | — | Fit panel: nudge the hair or belt into place, then copy the `Offset` line it shows into `HairConfig`. |

On a phone, the charge bar sits at the top between the HUD and the radar, and the TAP button at the bottom between the thumbstick and the jump button, so neither covers the other.

## The HUD (`HUD`, your screen)

- **Top left:**
  - **Portrait:** your face inside a glossy 4-star **Dragon Ball**. It's a live 3D portrait: a copy of your character in a 3D view, re-taken when your hair changes.
  - **Name and form:** your name, with your form underneath.
  - **HP bar:** a red trail behind it shows damage you just took.
  - **Ki gauge:** five cells, blue in base form and gold as a Super Saiyan. Ki refills slowly and charging fills it fast.
- **Scouter:** under that, a green Scouter lens reads your **POWER LEVEL**.
  - **Values:** 1,500 at rest, up to 7,500 as you charge, and 75,000 as a Super Saiyan.
  - **Animation:** it scrambles and counts up when it jumps, and flashes **IT'S OVER 9000!!** when you pass 9000.
- **Top right:** a **Dragon Radar**: a sweeping green screen with a blip for every player within 250 studs (gold blips are Super Saiyans). Up on the radar is the way your camera faces.
- **Behaviour:**
  - **Phones:** it shrinks to fit.
  - **Cutscene:** it hides while the cutscene plays.
  - **Roblox's health bar:** it replaces it.

## How it works

- **The morph (`CharacterSetup`, server).**
  - When the server starts, it copies `Base`, puts the three rigged pieces on the copy, and saves it as the `StarterCharacter`. That's Roblox's built-in way of giving every player a custom body.
  - Each piece is placed by matching its bones to where they sat on the original model, so it lands in the same spot on the head or waist as in your `.obj` files.
  - The belt is then sized to your rig's waist. The rig tools measured the inside of the band all the way round (`Ring` in `HairConfig`). The server measures the Base rig's LowerTorso, UpperTorso and upper legs where they cross the band, and grows or shrinks the belt until there's `FitGap` (0.04 studs) of room everywhere. On a standard blocky R15 it comes out at ×1.1.
  - Anything from a player's own avatar that still sneaks on (shirts, pants, hats, body colours) is deleted as it arrives.
- **The referee (`PowerUpServer`, server).**
  - Your game tells the server "I started", "my bar is at X", "I'm full" and "cancel".
  - The server checks each message: the bar can't rise faster than 16 taps a second, and you have to charge for at least 2.5 s. A hacked client can't skip straight to Super Saiyan.
  - It sets values on your character that every screen reads:
    - `Form`, `PowerState` and `Charge`: what you're doing.
    - `AuraWind`: how hard your hair is blown up.
    - `Breeze`: the Super Saiyan glow. It's 1 when you transform and fades to 0 when you calm down.
    - `Ki`: shown on the HUD.
  - It swaps the hair and freezes your walking while you charge and transform.
  - **Calming down:** `SSJCalmAfter` (20 s) after you get control back, it fades `Breeze` and the hair lift to 0 over `SSJCalmTime` (4 s). The hair stops flowing and the aura fades with it.
- **Your controls (`PowerUpClient`).** The keys, the power bar and the front-view camera, which shakes harder as you charge. When you transform it plays the cutscene. Space is grabbed at a higher priority than jumping, so spamming it doesn't make you hop.
- **The cutscene (`SSJCutscene`, only the player transforming sees it).**
  - **Camera:** it takes the camera for the transformation (`BurstTime`, 5.4 s). Every shot is measured from your head or body as they move:
    - **Eyes (0–1 s):** an extreme close-up panning across your eyes.
    - **Hair (1–2.2 s):** a sweep up your hair as it turns gold.
    - **Explosion (`ExplodeAt`, 2.2 s):** a white flash and manga focus lines, then a low-angle pull-back.
  - **Manga boxes:** white panels with a thick black border and a hard shadow. They drop in with a bounce: "THIS IS—" at 2.6 s, then "SUPER SAIYAN!" at 3.25 s. The text is `CutsceneText` in PowerConfig.
  - **Finish:** the boxes fly off, the bars slide away and you get control back.
  - **On screen:** black bars cover the top and bottom, and on a phone the thumbstick and jump button hide while it plays. Turn the cutscene off with `Cutscene = false`.
- **The animation (`PowerFX`, every screen).** It's coded joint by joint, so there's no animation asset to upload. Each R15 joint has three key poses:
  - **READY:** standing tall, fists at the waist, elbows out.
  - **STRAIN:** hunched over, head down, elbows wide, knees bent.
  - **RELEASE:** leaning back, head up, arms lowered and spread.
  - **Blending:** while charging it blends READY into STRAIN as the bar fills, with a tremble that grows with the effort. Transforming, you stay hunched as the power builds, snap into RELEASE at the explosion, and hold it until you get control back. The pose is layered on top of the walk and idle animations, so it fades in and out smoothly.
  - **Joints:** it works with both kinds of character joint. Roblox's "Avatar Joint Upgrade" gives characters **AnimationConstraint** joints instead of Motor6Ds.
- **The aura (`PowerFX`, every screen).**
  - **Ground ring:** a ring of glowing pieces on the ground at your feet, flickering, with ripples pulsing out of it along the ground at higher power.
  - **Fire:** about 30 flames are rooted on the ring all the way round you. They overlap into one sheet of fire, brightest at its edges where you look through the most flames. They lean outward as they rise, fade at their tips and lick up and down, and the whole fire slowly turns round you.
    - **Streaks:** thin bright streaks shoot up through it.
    - **Licks:** flames break off near the ground and rise along the fire, shrinking as they go.
    - **What they're made of:** each flame is a **Beam**, a tapered ribbon that always faces the camera.
  - **Extras:** energy streaks swirl round you, sparks float up and light streaks shoot past. A glow lights the surroundings, and dust and rocks lift at high power.
  - **Visibility:** flames between the camera and you thin right down so they don't hide you.
  - **Colour:** blue in base form, gold as a Super Saiyan. After transforming the gold aura stays strong (`SSJIdleAura`) until you calm down.
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
  - **the transformation:** how long it takes (`BurstTime`), when it explodes (`ExplodeAt`), the cutscene on/off and its text (`Cutscene`, `CutsceneText`)
  - **calming down:** when it happens and how long it takes (`SSJCalmAfter`, `SSJCalmTime`), how strong the gold aura stays until then (`SSJIdleAura`)
  - **aura looks:** main and tip colour for each form, size, how many flames (`AuraFlames`: lower it if lots of players lag), flicker (`AuraFrameRate`)
  - **HUD:** ki (`KiMax`, `KiStart`, `KiRegen`), power level (`BasePowerLevel`, `ChargePowerBoost`, `SSJMultiplier`), radar range (`RadarRange`)
  - **camera:** distance, height and shake
- **`PowerFX`** (top of the script): the three key poses (`READY`, `STRAIN`, `RELEASE`), the aura's sizes (`RING_RADIUS`, `FLAME_HEIGHT`, `FLAME_LEAN`) and its flame groups (`GROUPS`), if you want to restyle them.
- **`HUD`** (top of the script): its accent colours.
- **`HairConfig`:**
  - colour, texture id, placement (`Offset`) and size of each piece
  - how stiff and heavy it is (`Stiffness`, `GravityCompensation`); the bangs have their own softer settings (`ChainOverrides`, chains `BB01`–`BB09`)
  - the SSJ breeze (`LocalWind`, `LocalWindFlutter`); flip the X to `70` to blow it to the right
  - how hard the aura blows it (`AuraLift`, `AuraSwirl`)
  - the belt's room around the waist (`FitGap`, or `Scale` for extra size on top)

## Limits

- **Bone names must be unique across every piece worn together.** Roblox ties each skinned mesh to its bones by name across the whole character. `CharacterSetup` warns in the Output if two pieces share a bone name.
- **No textures.** The `.mtl` files point at `Handle1_diff.png`, which wasn't in the zip. The pieces use flat colours instead: black base hair, gold SSJ hair, blue belt. Paste a texture id into `TextureId` in `HairConfig` if you have one.
- **Hair placement is worked out from the model files.** The head centre for each piece comes from its shape. If a piece sits a little off on your rig, press **H** and nudge it.
- **No sounds yet.** No charge hum, scream or burst sound.
- **Not tried in real Studio.** The scripts were run against fake characters in tests (`tools/test/`), and the UI was drawn by a stand-in renderer (`tools/preview/`), not in a live Roblox server. The renderer uses stand-in fonts and can't show the 3D portrait.

## Rebuilding and checking

- `tools/rig/build_dbz.py` rigs the three `.obj` files with Blender's Python module and writes the `.fbx` and `.blend` files. Add piece names to rebuild only those.
- `lune run tools/build_rbxmx.luau .` rebuilds `DragonWishKit.rbxmx` from `src/`.
- Tests, run from this folder with `lune run tools/test/<name>.luau`:
  - `server_mock`: the morph, the referee, ki and calming down
  - `client_mock`: controls plus server, end to end, including the cutscene starting
  - `fx_mock`: aura, ring, animation and explosion timing (add `"" motor6d` to test old-style joints)
  - `aura_harness <BaseHair|SSJHair|Belt>`: hair and belt physics through a power-up, walking, stopping and jumping
  - `wake_mock`: the SSJ hair waking up when it's shown
  - `compile <files...>`: every script compiles
- UI previews:
  - `lune run tools/preview/ui_dump.luau <idle|charging|ssj|cutscene:SECONDS> <width> <height> out.json` runs the real HUD, controls and cutscene scripts and writes out what's on screen.
  - `python3 tools/preview/render_ui.py out.json out.png` draws it the way Roblox lays it out, with phone safe areas and touch controls.
  - `python3 tools/preview/check_ui.py idle.json charging.json cutscene.json` checks the important pieces are there.
- `python3 -I tools/rig/belt_ring.py models/source/Belt.obj tools/rig/riginfo.json` re-measures the belt's band, then `tools/rig/emit_layouts.py` prints the `Layouts` table for `HairConfig`.
