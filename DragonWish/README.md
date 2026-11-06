# Dragon Wish: Online: character + power-up kit

Every player spawns as the R15 rig **Base**, with their own clothes and accessories stripped. They start with the base hair and the belt on. Press **R** and the camera swings round in front of you while you drop into a ready stance. **Spam Space** and an aura flickers on, then grows bigger and faster. Your hair and the belt's ribbons get blown upward, dust kicks up and rocks lift off the ground. Fill the bar and you **burst into Super Saiyan**: the screen flashes, a shockwave rolls out, the golden hair swaps in, and it then flows calmly in a soft golden aura.

## Files you need

| File | What it is |
| --- | --- |
| `DragonWishKit.rbxmx` | All 10 scripts in one drag-in file. Its folders are named after the service each part goes in. |
| `models/BaseHair_Rigged.fbx` | The base hair: 1 root bone + 17 spikes (60 bones). |
| `models/SSJHair_Rigged.fbx` | The Super Saiyan hair: 1 root bone + 22 spikes (84 bones). |
| `models/Belt_Rigged.fbx` | The belt: 1 root bone + the 2 hanging ribbons (4 bones each). |

The `.blend` files are the same rigs as Blender scenes. `models/source/` has your original `.obj` files.

## Setup

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
- **The effects (`PowerFX`, every screen).**
  - The aura is a column of flame particles around you, plus haze, sparks and a glow. It changes from white-blue to gold as you transform.
  - It also draws the ground dust, the floating rocks, the shockwave ring and flash, and the ready stance and scream pose. The stance is layered on top of your normal animations.
- **The hair and belt (`HairPhysics`, every screen).**
  - This is the same physics as the earlier hair, with two additions.
  - An upward "wind", plus a swirl, is driven by `AuraWind`: 0 while calm, rising as the bar fills, 1 at the burst, and 0.35 as a Super Saiyan, so the golden hair keeps flowing gently.
  - A hidden hair (the SSJ hair while you're in base form) doesn't get simulated.

## Settings

- **`PowerConfig`:** keys, how much each tap fills, how fast the bar drains, minimum charge time, burst length, aura colours and size, camera distance, height and shake.
- **`HairConfig`:** colour, texture id, placement (`Offset`) and size of each piece, and how stiff it is and how hard the aura blows it (`AuraLift`, `AuraSwirl`).

## Limits

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
  - `aura_harness <BaseHair|SSJHair|Belt>`: hair and belt physics through a power-up
