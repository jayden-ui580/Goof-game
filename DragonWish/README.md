# Dragon Wish: Online: character + power-up kit

Every player spawns as the R15 rig **Base**, with their own clothes and accessories stripped. They start with the base hair and the belt on.

- **Power up:** press **R**. The camera swings round in front of you and you stand tall with your fists clenched at your waist.
- **Charge:** spam **Space**. An anime-style aura of flame tongues flickers on, then grows taller and faster and flares out into a teardrop. You hunch over with your head down and your elbows thrown wide, trembling. Your hair, bangs and the belt's ribbons get blown upward, dust kicks up and rocks lift off the ground.
- **Transform:** fill the bar and you **burst into Super Saiyan**. A pillar of light shoots up, the screen flashes, a shockwave rolls out and the golden hair swaps in. You lean back with your head up and arms spread and hold that pose, then you get control back. The golden hair then flows calmly in a soft gold aura.

## Files you need

| File | What it is |
| --- | --- |
| `DragonWishKit.rbxmx` | All 10 scripts in one drag-in file. Its folders are named after the service each part goes in. |
| `models/BaseHair_Rigged.fbx` | The base hair: 1 root bone + 17 spikes + 9 bangs (87 bones). |
| `models/SSJHair_Rigged.fbx` | The Super Saiyan hair: 1 root bone (`SSJRoot`) + 22 spikes (84 bones). |
| `models/Belt_Rigged.fbx` | The belt: 1 root bone + the 2 hanging ribbons (4 bones each). |

The `.blend` files are the same rigs as Blender scenes. `models/source/` has your original `.obj` files.

## Setup

> **Updating from an earlier version?** Re-import any piece that's newer than yours, after deleting the old copy from `ServerStorage › CharacterParts`:
> - **`BaseHair_Rigged.fbx`** now has bones in the bangs. The server looks for bone `BB01_1`, so an older import won't load.
> - **`SSJHair_Rigged.fbx`** has its root bone renamed to `SSJRoot`. In the first version it was called `HairRoot`, the same as the base hair's, and Roblox ties a skinned mesh to the first bone with a matching name anywhere in the character. The SSJ hair was tied to the base hair's skeleton and never moved.
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

## How it works

- **The morph (`CharacterSetup`, server).**
  - When the server starts, it copies `Base`, puts the three rigged pieces on the copy, and saves it as the `StarterCharacter`. That's Roblox's built-in way of giving every player a custom body.
  - Each piece is placed by matching its bones to where they sat on the original model, so it lands in the same spot on the head or waist as in your `.obj` files.
  - The belt is then sized to your rig's waist. The rig tools measured the inside of the band all the way round (`Ring` in `HairConfig`). The server measures the Base rig's LowerTorso, UpperTorso and upper legs where they cross the band, and grows or shrinks the belt until there's `FitGap` (0.04 studs) of room everywhere. On a standard blocky R15 it comes out at ×1.1. The modeled belt fit too tightly, so the torso's corners poked through.
  - Anything from a player's own avatar that still sneaks on (shirts, pants, hats, body colours) is deleted as it arrives.
- **The referee (`PowerUpServer`, server).**
  - Your game tells the server "I started", "my bar is at X", "I'm full" and "cancel".
  - The server checks each message: the bar can't rise faster than 16 taps a second, and you have to charge for at least 2.5 s. A hacked client can't skip straight to Super Saiyan.
  - It then sets four values on your character that everyone's screen reads: `Form`, `PowerState`, `Charge` and `AuraWind`.
  - It swaps the hair and freezes your walking while you charge.
- **Your controls (`PowerUpClient`).**
  - It handles the keys, the power bar and the front-view camera, which shakes harder as you charge.
  - The transformation flash and the "SUPER SAIYAN!" title also live here.
  - Space is grabbed at a higher priority than jumping, so spamming it doesn't make you hop.
- **The animation (`PowerFX`, every screen).** It's coded joint by joint, so there's no animation asset to upload. There are three key poses for each R15 joint:
  - **READY:** standing tall, fists at the waist, elbows out.
  - **STRAIN:** hunched over, head down, elbows wide, knees bent.
  - **RELEASE:** leaning back, head up, arms lowered and spread.

  While charging, it blends READY into STRAIN as the bar fills, with a tremble that grows with the effort. On the transformation it snaps into RELEASE and holds it for `BurstTime` (2.8 s), then blends back into your normal animations as you get control back. The pose is layered on top of the walk and idle animations, so it fades in and out smoothly.
- **The aura (`PowerFX`, every screen).**
  - **Flames:** it's built from about 30 **Beams**: tapered ribbons that always face the camera, so each reads as a sharp anime flame shape. There are three layers: big outer flames, tall thin spikes and a white-hot core. Each flame licks up on its own cycle, then thins out and starts again somewhere else.
  - **Shape:** the tips lean outward, so the aura is narrow at your feet and flares wide above your head. At higher power there are more flames and they're taller and faster.
  - **Visibility:** flames between the camera and you thin out so they don't hide you.
  - **Extras:** orange energy streaks swirl upward around you and light streaks shoot up. A glow lights the surroundings, and the colour changes from white-blue to gold as you transform.
  - **Burst:** a pillar of light, a flash, a shockwave ring, dust and a moment where every flame shoots extra high.
  - **Your screen only:** the picture gets slightly punchier as you charge and flashes warm and bright on the transformation.
- **The hair and belt (`HairPhysics`, every screen).**
  - This is the same physics as the earlier hair, with these additions.
  - **Gravity:** only part of gravity is cancelled by the springs (`GravityCompensation`): half for the base hair, 40% for the SSJ hair. The spikes hang a little heavier and swing more when you move, jump or stop.
  - **Aura:** an upward "wind", plus a swirl, is driven by `AuraWind`: 0 while calm, rising as the bar fills, 1 at the burst, and 0.12 as a Super Saiyan.
  - **Breeze:** the SSJ hair has a steady breeze to the wearer's left (`LocalWind`) that turns with the head. Each spike's share rises and falls on its own, so the hair ripples. It fades while the aura blasts upward.
  - A hidden hair (the SSJ hair while you're in base form) doesn't get simulated.

## Settings

- **`PowerConfig`:** keys, how much each tap fills, how fast the bar drains, minimum charge time, how long you hold the release pose (`BurstTime`), aura colours (main and tip colour for each form), aura size, how many flames (`AuraFlames`: lower it if lots of players lag), camera distance, height and shake.
- **`PowerFX`** (top of the script): the three key poses (`READY`, `STRAIN`, `RELEASE`) and the flame layers (`LAYERS`), if you want to restyle them.
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
- **Not tried in real Studio.** The scripts were run against fake characters in tests (`tools/test/`), not in a live Roblox server.

## Rebuilding

- `tools/rig/build_dbz.py` rigs the three `.obj` files with Blender's Python module and writes the `.fbx` and `.blend` files.
- `lune run tools/build_rbxmx.luau .` rebuilds `DragonWishKit.rbxmx` from `src/`.
- Tests, run from this folder with `lune run tools/test/<name>.luau`:
  - `server_mock`: the morph and the referee
  - `client_mock`: controls plus server, end to end
  - `fx_mock`: aura, stance and burst
  - `aura_harness <BaseHair|SSJHair|Belt>`: hair and belt physics through a power-up, walking, stopping and jumping (sag, swing, sideways sweep and ripple)
- `python3 -I tools/rig/belt_ring.py models/source/Belt.obj tools/rig/riginfo.json` re-measures the belt's band, then `tools/rig/emit_layouts.py` prints the `Layouts` table for `HairConfig`.
