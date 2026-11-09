"""Checks the UI dumps from ui_dump.luau: what must be on screen in each scenario.
usage: python3 check_ui.py idle.json charging.json cutscene_3.9.json [kaioken.json cutscene_5.4.json]"""
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
kaioken = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else None
finished = json.load(open(sys.argv[5])) if len(sys.argv) > 5 else None
ok = True
hud = gui(idle, 'DragonHUD')
ok &= check('HUD on screen with the plate, scouter and radar', bool(hud and hud['enabled'] and find(hud, 'Plate') and find(hud, 'Scouter') and find(hud, 'Radar')))
ok &= check('the portrait is a 3D view', bool(find(hud, 'Portrait') and find(hud, 'Portrait')['class'] == 'ViewportFrame'))
ok &= check('the HP bar is full and the ki pips are there', bool(find(find(hud, 'HP'), 'Fill')['visible'] and all(find(hud, 'Ki%d' % k) for k in range(1, 6))))
ok &= check('the name is on the plate', bool(find(find(hud, 'Name'), 'Text')['text']))
pu = gui(charging, 'PowerUpUI')
panel = find(pu, 'Charge')
ok &= check('charging shows the power bar panel', bool(panel and panel['visible'] and find(find(panel, 'Prompt'), 'Text')['text']))
radar = find(gui(charging, 'DragonHUD'), 'Radar')
ok &= check('the radar slides away while you power up', radar['pos'][0] == 1 and radar['pos'][1] > 100)
cs = gui(cut, 'SSJCutscene')
b1, b2 = find(cs, 'PanelThisIs'), find(cs, 'PanelSuperSaiyan')
ok &= check('cutscene layer on, HUD hidden', bool(cs and cs['enabled'] and not gui(cut, 'DragonHUD')['enabled']))
ok &= check('black bars in', find(cs, 'TopBar')['size'][2] > 0.1 and find(cs, 'BottomBar')['size'][2] > 0.1)
ok &= check('both manga panels on screen with their text', bool(b1 and b2 and b1['visible'] and b2['visible'] and find(b1, 'Text')['text'] and find(b2, 'Text')['text']))
ok &= check('the manga filter is on (grey, high contrast)', any(e['saturation'] <= -0.9 and e['contrast'] > 0.3 for e in cut.get('effects', [])))
if kaioken:
    form = find(find(gui(kaioken, 'DragonHUD'), 'Form'), 'Text')
    shout = find(gui(kaioken, 'PowerUpUI'), 'Kaioken')
    ok &= check('Kaioken: the HUD tag reads KAIOKEN x4', bool(form and form['text'] == 'KAIOKEN x4'))
    ok &= check('Kaioken: the "KAIOKEN x4!" shout is up', bool(shout and shout['visible'] and find(shout, 'Text')['text'] == 'KAIOKEN x4!'))
    kanji = find(gui(kaioken, 'DragonHUD'), 'Kanji')
    ok &= check('Kaioken: the gi badge reads 拳', bool(kanji and kanji['text'] == '拳'))
if finished:
    cs3 = gui(finished, 'SSJCutscene')
    p3 = find(cs3, 'PanelFinished')
    ok &= check('the third manga panel: YOU\'RE FINISHED!', bool(p3 and p3['visible'] and find(p3, 'Text')['text'].replace('\n', ' ') == "YOU'RE FINISHED!"))
    ok &= check('the first two panels have left', all(not find(cs3, n)['visible'] or find(cs3, n)['pos'][2] < -0.2 or find(cs3, n)['pos'][2] > 1.2 for n in ('PanelThisIs', 'PanelSuperSaiyan')))
sys.exit(0 if ok else 1)
