# Hair Physics

Rigged, physics-driven hair for two R15 test rigs: **MrPigtails** wears the pigtails, **MrLady** wears the long hair.

## Files you need

| File | What it is |
| --- | --- |
| `HairPhysicsKit.rbxmx` | Every script, in one drag-in model (folders named after the service each part goes in). |
| `models/Pigtails_Rigged.fbx` | The pigtails, rigged: 1 root bone + 2 strands of 5 bones. |
| `models/LadyHair_Rigged.fbx` | The long hair, rigged: 1 root bone + 5 strands down the back (5 bones each) + 2 front locks (4 bones each). |

The `.blend` files next to the FBXs are the same rigs as Blender scenes, in case you want to change the bones or weights yourself.

## Setup

1. **Import the hair.** In Studio go to File › Import 3D and pick `Pigtails_Rigged.fbx`. Leave Scale Unit = Studs, World Forward = Front, World Up = Top. Make sure Rig Type is **Custom**, not No Rig. Tick **Keep Zero Influence Bones**, and leave Upload to Roblox on. Then do the same for `LadyHair_Rigged.fbx`.
2. **Drag in `HairPhysicsKit.rbxmx`.** Move each folder's contents into the service with the same name. `StarterPlayerScripts` lives inside `StarterPlayer`.
3. **Put both imported hair models into `ServerStorage › HairModels`.** You don't need to clean them up or weld anything.
4. **Add the textures.** The `.obj` exports didn't include the hair textures. In `ReplicatedStorage › HairConfig`, paste each hair's original texture id into `TextureId`.
5. **Press Play (F5).** Don't use Run: the hair moves on the player's screen, so the game needs a player.

## How it works

- **Rig.** The hair cap, bangs and hair ties sit on a `HairRoot` bone that never moves. Each pigtail, each section of the long hair, and each front lock gets its own chain of bones. As in the video, the skin weights fade smoothly from the still root into the moving bones, so nothing tears where the moving part starts.
- **HairApplier** (server) finds the imported hair by its bones and copies only the mesh and bones. It compares where each bone actually landed against where it was modelled, which places the hair exactly on the head. This still works if the importer rescaled, re-centred or turned the mesh. It then wears the hair as a normal Hair accessory and tags it `HairPhysics`.
- **HairPhysics** (every player's computer) treats each strand as a string of beads. Every 1/60 s it applies momentum, gravity and head movement. Then it applies these rules:
  - **Length:** strands never stretch.
  - **Shape spring:** strands return to their modelled shape.
  - **Bend cap:** a joint can bend at most `MaxBend` degrees, so a strand can't fold back on itself.
  - **Body collision:** strands are pushed out of the head ball and out of the torso and upper-arm boxes.
  - **Strand-vs-strand collision:** every bone is a capsule, and capsules on different strands push each other apart so strands can't pass through each other or bunch up.

  Finally it turns the bones to follow the beads. It writes `Bone.Transform` right before each frame is drawn, which is the approach the DevForum recommends, because animations reset that value every frame.
- **NPCRoam** (server) is a test script. It un-anchors the rigs, plays Roblox's default animations, and makes the rigs wander, jump at random and sometimes spin around.

## Tuning

All settings are in `HairConfig`, and each one has a note explaining it. The ones you'll most likely change:

- `Offset`: the hair sits a little high, low, forward or back on the head.
- `Stiffness`: hair is too floppy or too stiff.
- `Inertia`: too much or too little swing when moving.
- `Wind` and `WindGust`: add a breeze.

## How it was tested

I couldn't open Roblox Studio here, so I tested the scripts outside it:

- **Physics:** the real `HairPhysics` code runs under the Luau runtime [Lune](https://github.com/lune-org/lune) against a fake R15 body that stands, walks, jumps, lands and spins. The script is `tools/test/harness.luau`. Results at 15, 30, 60, 144 and 240 FPS:
  - No NaNs.
  - When standing still, the hair stays in its modelled shape (under 0.02 studs off) and doesn't jitter.
  - No hair is left inside the body at 60 FPS.
  - Strands keep their left-to-right order, even with hurricane-strength side wind.
  - With strand collision turned off, strands overlapped by up to 0.34 studs and passed through each other on 148 frames. With it on, overlap stayed under 0.11 studs and there were 0 pass-throughs.
- **Applier:** `tools/test/applytest.luau` takes a fake import with a re-centred mesh, randomly rotated bones and a turned head. All 54 bones land within 0.0001 studs of where they belong.
- **Client runner:** `tools/test/clienttest.luau` checks that every simulated bone gets driven and that nothing warns.

The rigs are rebuilt with `tools/rig/build.py`, which runs under the Blender Python module (`pip install bpy`).
