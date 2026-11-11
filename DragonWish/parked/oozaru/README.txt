THE GREAT APE (OOZARU) - PARKED

Taken out of the game for now. Everything it needs is kept here and in the repo:
  Oozaru.luau          ModuleScript (ServerScriptService): builds the giant from the
                       imported model and swaps players in and out
  OozaruRig.luau       ModuleScript (ServerScriptService): where its bones were designed
  OozaruFX.client.luau LocalScript (StarterPlayerScripts): roar, hunch, heavy walk, tail,
                       the red screen
  ape_mock.luau        its test (run from DragonWish: lune run parked/oozaru/ape_mock.luau,
                       after moving OozaruFX back into src/StarterPlayerScripts)
  ../../models/Oozaru_Rigged.fbx, ../../models/source/GreatApe.fbx,
  ../../tools/rig/build_oozaru.py, emit_oozaru.py, oozaru.json   the model and how it's made

To bring it back, put the three scripts back in src/ and restore the wiring in
PowerUpServer (the "Oozaru" action, PowerDown turning you back, Oozaru.Step in the
Heartbeat), PowerUpClient (the G key and its hint), HUD (hiding while giant), PowerConfig
(the Oozaru settings) and server_mock (its checks), as they were in commit 47823d3
("Great Ape: build it the way the hair and fingers are built").

Where it got to: built and swapped in fine, the camera followed, but in Studio it still
stood in its bind (T) pose. The last change (a skeleton copy inside every mesh, and an
Animator) was never tested in Studio. Also: the model looks ripped from a commercial game,
so swap in one you have the rights to before publishing.
