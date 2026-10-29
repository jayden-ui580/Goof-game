# Hair Physics + Test Arena + Flowing Water

Rigged, physics-driven hair for two R15 test rigs, inside a sealed test arena that fills with flowing water. **MrPigtails** wears the pigtails and **MrLady** wears the long hair. A tap fills the arena, and pressing **Z** opens a hole in the wall so the water rushes out.

## Files you need

| File | What it is |
| --- | --- |
| `HairPhysicsKit.rbxmx` | Every script (hair, arena, water) plus the TestArena model, in one drag-in file. Its folders are named after the service each part goes in. |
| `models/Pigtails_Rigged.fbx` | The pigtails rig: 1 root bone + 2 strands of 5 bones. |
| `models/LadyHair_Rigged.fbx` | The long hair rig: 1 root bone, 5 strands down the back (5 bones each) and 2 front locks (4 bones each). |

The `.blend` files are the same rigs as Blender scenes.

## Setup

1. **Import the hair.** Skip this if you already imported it; the rigs haven't changed. Otherwise go to File › Import 3D and pick `Pigtails_Rigged.fbx`. Set Rig Type to **Custom** and Scale Unit to Studs, tick **Keep Zero Influence Bones**, and leave Upload to Roblox on. Do the same for `LadyHair_Rigged.fbx`. Put both imported models in `ServerStorage › HairModels`.
2. **Drag in `HairPhysicsKit.rbxmx`.** Move each folder's contents into the service with the same name. `StarterPlayerScripts` is inside StarterPlayer, and `TestArena` goes in Workspace. Replace any older copies of the scripts and of the TestArena; the new arena has a thicker floor and the tap.
3. **Add the textures.** Paste each hair's texture id into `TextureId` in `HairConfig`.
4. **Press Play (F5).** You and both rigs start inside the arena.

## Controls in Play

| Key | Phone button | What it does |
| --- | --- | --- |
| **Z** | Gate | Opens or closes the drain gate at the bottom of the arena wall. Open: the water rushes out of the hole and pours down the side. Shut: the tap fills the arena back up. |
| **H** | Fit | Opens the hair-fit panel. Pick a rig, nudge its hair, and the panel shows an `Offset = CFrame.new(...)` line to paste into `HairConfig`. |

## The water

**What you see:**
- When the game starts, water pours from a pipe high on the back wall. It splashes, spreads across the floor in a moving front, and fills the arena to 10 studs in about 45 seconds.
- Press **Z** and the gate slides up. The pool slopes toward the hole and pours out over the lip in a waterfall. Foam on the surface drifts along with the current. The arena is down to 1 stud in about 35 seconds and empty in about 75.
- Shut the gate and the tap refills it.

**How it works:**
- **The water is real Roblox terrain water.** You get Roblox's water look and underwater view, and you can swim in it.
- **`WaterServer` moves it with a flow simulation.** The floor is a grid of 4 × 4-stud cells, one per terrain-water cube. Water flows between neighbouring cells through imaginary pipes, pushed by the height difference. This is the "pipe method" the DevForum recommends for game water. The drain uses the real-world formulas for water spilling over a ledge or squirting through a submerged hole.
- **Only real changes go out.** The server rewrites the terrain-water cubes 10 times a second, and only when the water has visibly changed. While the water is still, nothing is sent.
- **`WaterClient` draws the effects on each player's screen:**
  - the tap stream, whose front falls from the pipe when it turns on and whose tail falls after it when it stops,
  - mist and droplets where it lands,
  - the waterfall out of the hole,
  - foam flecks that follow the flow.
- **Settings are in `WaterConfig`:** depth, fill time, drain speed, colour and clarity.

**Limits:**
- **Roblox allows one water look per place.** The colour and clarity settings change all terrain water in the place; turn off `ApplyWaterLook` if that's a problem.
- **The arena must stay on the 4-stud grid.** Terrain water can only sit on that grid, so the TestArena must stay unrotated, with its floor-top centre on whole multiples of 4. The script warns you if it isn't.

## Hair changes in the previous version

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
- `tools/test/watertest.luau` runs the water simulation: fill time, drain time, the bump under the stream, smoothness, no negative or invalid depths, and exact water volume (error about 0.02 studs³ out of 41,000).
- `tools/test/waterserver_mock.luau` runs the real `WaterServer` against the real arena model, with a fake Terrain and fake network. It checks filling, the tap shutting off, opening the gate, draining, refilling, that nothing is sent while the water is still, the grid and drain-hole placement, and the terrain-water fill values.
- `tools/test/waterclient_mock.luau` runs `WaterServer` and `WaterClient` together. It checks that the stream's front falls and lands, the waterfall appears facing outward and reaches the ground, and the foam behaves.

The rigs are rebuilt with `tools/rig/build.py`, which needs the Blender Python module (`pip install bpy`). `tools/build_rbxmx.luau` packs the kit, with the arena geometry coming from `tools/arena.luau`.
