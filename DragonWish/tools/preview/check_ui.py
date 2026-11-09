"""Checks the UI dumps from ui_dump.luau: what must be on screen in each scenario.
usage: python3 check_ui.py idle.json charging.json cutscene_3.9.json"""
import json, sys

def find(node, name):
    if node.get('name') == name:
        return node
    for c in node.get('children', []):
        r = find(c, name)
        if r:
            return r
    return None

def gui(data, name):
    return next((g for g in data['guis'] if g['name'] == name), None)

def check(what, ok):
    print(('PASS  ' if ok else 'FAIL  ') + what)
    return ok

idle, charging, cut = (json.load(open(p)) for p in sys.argv[1:4])
ok = True
hud = gui(idle, 'DragonHUD')
ok &= check('HUD on screen with the plate, scouter and radar', bool(hud and hud['enabled'] and find(hud, 'Plate') and find(hud, 'Scouter') and find(hud, 'Radar')))
ok &= check('the Dragon Ball portrait is a 3D view', bool(find(hud, 'Portrait') and find(hud, 'Portrait')['class'] == 'ViewportFrame'))
panel = find(gui(charging, 'PowerUpUI'), 'Charge')
ok &= check('charging shows the power bar panel', bool(panel and panel['visible']))
cs = gui(cut, 'SSJCutscene')
b1, b2 = find(cs, 'BoxThisIs'), find(cs, 'BoxSuperSaiyan')
ok &= check('cutscene layer on, HUD hidden', bool(cs and cs['enabled'] and not gui(cut, 'DragonHUD')['enabled']))
ok &= check('black bars in', find(cs, 'TopBar')['size'][2] > 0.1 and find(cs, 'BottomBar')['size'][2] > 0.1)
ok &= check('both manga boxes on screen with their text', bool(b1['visible'] and b2['visible'] and find(b1, 'Text')['text'] and find(b2, 'Text')['text']))
sys.exit(0 if ok else 1)
