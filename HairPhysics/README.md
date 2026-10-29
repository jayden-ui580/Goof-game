# Hair Physics + Test Arena

Rigged, physics-driven hair for two R15 test rigs, inside a sealed test arena. **MrPigtails** wears the pigtails and **MrLady** wears the long hair. The arena's drain gate is built ready for the water feature.

## Files you need

| File | What it is |
| --- | --- |
| `HairPhysicsKit.rbxmx` | Every script plus the TestArena model, in one drag-in file. Its folders are named after the service each part goes in. |
| `models/Pigtails_Rigged.fbx` | The pigtails rig: 1 root bone + 2 strands of 5 bones. |
| `models/LadyHair_Rigged.fbx` | The long hair rig: 1 root bone, 5 strands down the back (5 bones each) and 2 front locks (4 bones each). |

The `.blend` files are the same rigs as Blender scenes.

## Setup

1. **Import the hair.** Skip this if you already imported it; the rigs haven't changed. Otherwise go to File › Import 3D and pick `Pigtails_Rigged.fbx`. Set Rig Type to **Custom** and Scale Unit to Studs, tick **Keep Zero Influence Bones**, and leave Upload to Roblox on. Do the same for `LadyHair_Rigged.fbx`. Put both imported models in `ServerStorage › HairModels`.
2. **Drag in `HairPhysicsKit.rbxmx`.** Move each folder's contents into the service with the same name. `StarterPlayerScripts` is inside StarterPlayer, and `TestArena` goes in Workspace. Replace any older copies of the scripts.
3. **Add the textures.** Paste each hair's texture id into `TextureId` in `HairConfig`.
4. **Press Play (F5).** You and both rigs start inside the arena.

## Controls in Play

| Key | Phone button | What it does |
| --- | --- | --- |
| **Z** | Gate | Opens or closes the drain gate at the bottom of the arena wall. |
| **H** | Fit | Opens the hair-fit panel. Pick a rig, nudge its hair, and the panel shows an `Offset = CFrame.new(...)` line to paste into `HairConfig`. |

## What changed in this version

- **Less jelly.** I measured the wobble with a test (`tools/test/jelly.luau`) that drives a fake R15 body through a sudden stop, a jump and a 180° spin.
  - **Before:** after each stop the hair reversed direction 7–13 times and took 0.7–1.1 s to settle. Neighbouring strands of the long hair spread up to 3× their normal gap, which made the mesh between them squish.
  - **Now:** 0–1 reversals, settled in about 0.4 s. The long hair's strands stay within about 14% of their normal gap.
  - **What was changed (scripts only, the bones are untouched):**
    - Much heavier damping.
    - A spring that eases back into shape instead of overshooting.
    - Strands hold their styled direction relative to the head.
    - The 5 back strands of the long hair are tied together like cloth.
    - A top speed so nothing whips.
    - The hair's lag follows a smoothed copy of the head's motion, so NPC network jitter no longer makes it shiver (1.2 → 0.09 studs/s in the jitter test).
- **Fit.** My first estimate put the head centre too high inside the hair, which made the hair sit about 0.3 studs too low. I checked where both hairs' bangs end and where a standard R15 head sits above the floor, then corrected it with `HeadCenter` in the rig layouts. The hair also resizes to each rig's head width (`ScaleToHead`). For any remaining difference, use the **H** panel.
- **Arena.**
  - A sealed 64 × 64 × 24 box: concrete floor, walls, glass ceiling, and a depth gauge on one wall every 2 studs.
  - It stands on legs 8 studs off the ground.
  - The drain is an 8 × 4 hole at the base of the +X wall. A gate slides up into the wall to open it, and a grate stops players squeezing through.
  - `ArenaSetup` moves the rigs inside, makes every player spawn inside, runs the gate, and keeps two attributes on the arena for the water system to read: `InteriorSize` and `GateOpen`.
  - `NPCRoam` keeps the rigs wandering inside the arena.

## Tuning

Everything for the hair is in `HairConfig`, with a note on each setting.

| Problem | Setting to change |
| --- | --- |
| Hair sits wrong on the head | Use the H panel, then paste its `Offset` line. |
| Too floppy or too stiff | `Stiffness`, `Damping` |
| Wobbles | Raise `Damping`, lower `Bounce`. |
| Too much or too little swing | `Inertia` |

The arena can be moved freely, because the scripts read its `Floor` part. If you resize the walls, update the arena's `InteriorSize` attribute to match.

## How it was tested

I couldn't open Roblox Studio here, so all of this ran under the Luau runtime [Lune](https://github.com/lune-org/lune):

- `tools/test/harness.luau` runs the real solver on a fake R15 body that stands, walks, jumps and spins, at 15, 30, 60, 144 and 240 FPS. Results:
  - No NaNs.
  - The hair holds its modelled shape at rest (0.003–0.006 studs of droop).
  - No hair ends up inside the body.
  - Strands keep apart even in hurricane-strength wind. With strand collision turned off, they overlapped by 0.29 studs on 106 frames.
- `tools/test/jelly.luau` is the wobble, strand-spread and shiver test described above.
- `tools/test/applytest.luau` checks placement. It feeds the applier a re-centred mesh with randomly rotated bones and a turned head; all 54 bones land within 0.0001 studs of their target.
- `tools/test/clienttest.luau` checks that every simulated bone gets driven.

The rigs are rebuilt with `tools/rig/build.py`, which needs the Blender Python module (`pip install bpy`). `tools/build_rbxmx.luau` packs the kit, with the arena geometry coming from `tools/arena.luau`.
