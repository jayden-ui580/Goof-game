"""Draws the UI written by ui_dump.luau the way Roblox lays it out: UDim2 position/size with
AnchorPoint, UIScale, UIAspectRatioConstraint, ScreenGui insets, UICorner, UIStroke, UIGradient,
Rotation (children turn with their parent), ClipsDescendants, ZIndex (sibling order) and
TextScaled text. Fonts are stand-ins (Bangers -> narrowed DejaVu Bold, Gotham -> Liberation), and
ViewportFrames show a placeholder face. On a phone-sized screen it adds the safe-area insets and
Roblox's touch controls on top, to check nothing collides.
usage: python3 render_ui.py in.json out.png [title]"""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

DEJAVU = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LIB_BOLD = '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'
LIB_REG = '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'
MONO = '/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf'
CJK = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf'
FONTS = {  # (file, horizontal squeeze)
    'Bangers': (DEJAVU, 0.78), 'GothamBlack': (LIB_BOLD, 1.0), 'GothamBold': (LIB_BOLD, 1.0),
    'GothamMedium': (LIB_REG, 1.0), 'Gotham': (LIB_REG, 1.0), 'Code': (MONO, 1.0), 'Sarpanch': (DEJAVU, 0.92),
}
_font_cache = {}
def font(name, size, text):
    path, squeeze = FONTS.get(name, (LIB_BOLD, 1.0))
    if any(0x2E80 <= ord(c) <= 0x9FFF or 0xFF00 <= ord(c) <= 0xFFEF for c in text):
        path, squeeze = CJK, 1.0  # kanji / kana
    elif any(ord(c) > 0x2000 and c not in '—·' for c in text):
        path = DEJAVU  # (has the ★ glyph)
    key = (path, int(size))
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, max(1, int(size)))
    return _font_cache[key], squeeze

def kids(node, cls):
    return [c for c in node.get('children', []) if c['class'] == cls]

def interp(keys, t, n):
    ts = [k[0] for k in keys]
    return [float(np.interp(t, ts, [k[i] for k in keys])) for i in range(1, n + 1)]

def rounded_mask(w, h, r, ss=3):
    W, H = max(1, int(round(w * ss))), max(1, int(round(h * ss)))
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, W - 1, H - 1], radius=max(0, r * ss), fill=255)
    return np.asarray(m.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS), np.float32) / 255

def corner_radius(node, w, h, k):
    c = kids(node, 'UICorner')
    if not c:
        return 0
    s, o = c[0]['radius']
    return min(s * min(w, h) + o * k, min(w, h) / 2)

def gradient(node, w, h):
    """per-pixel colour multiplier and transparency for a UIGradient child"""
    g = [c for c in kids(node, 'UIGradient')]
    if not g or w < 1 or h < 1:
        return None, None
    g = g[0]
    ys, xs = np.mgrid[0:max(1, int(round(h))), 0:max(1, int(round(w)))]
    u = (xs + 0.5) / max(w, 1) - 0.5
    v = (ys + 0.5) / max(h, 1) - 0.5
    a = math.radians(g['rot'])
    t = 0.5 + u * math.cos(a) + v * math.sin(a) - (g['offset'][0] * math.cos(a) + g['offset'][1] * math.sin(a))
    t = np.clip(t, 0, 1)
    cols = g['colors']; trs = g['trans']
    col = np.stack([np.interp(t, [k[0] for k in cols], [k[i] for k in cols]) for i in (1, 2, 3)], -1)
    tr = np.interp(t, [k[0] for k in trs], [k[1] for k in trs])
    return col, tr

def paste(layer, img_arr, x, y):
    """alpha-composite a float RGBA array (h,w,4; straight alpha) onto layer at x, y"""
    im = Image.fromarray(np.clip(img_arr * 255, 0, 255).astype(np.uint8), 'RGBA')
    tmp = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    tmp.paste(im, (int(round(x)), int(round(y))))
    layer.alpha_composite(tmp)

def draw_box(layer, node, x, y, w, h, k):
    if w < 0.5 or h < 0.5:
        return
    r = corner_radius(node, w, h, k)
    iw, ih = max(1, int(round(w))), max(1, int(round(h)))
    # outline (Border mode) drawn outside the box
    for s in kids(node, 'UIStroke'):
        if s['mode'] != 'Border' and node['class'] in ('TextLabel', 'TextButton'):
            continue
        t = s['thick'] * k
        outer = rounded_mask(w + 2 * t, h + 2 * t, r + t if r > 0 else 0)
        inner = np.zeros_like(outer)
        im_ = rounded_mask(w, h, r)
        ti = int(round(t))
        inner[ti:ti + im_.shape[0], ti:ti + im_.shape[1]] = im_[:inner.shape[0] - ti, :inner.shape[1] - ti]
        ring = np.clip(outer - inner, 0, 1)
        arr = np.zeros(ring.shape + (4,), np.float32)
        arr[..., :3] = s['color']; arr[..., 3] = ring * (1 - s['t'])
        gcol, gtr = gradient(s, ring.shape[1], ring.shape[0])  # a UIGradient inside the stroke
        if gcol is not None:
            arr[..., :3] = arr[..., :3] * gcol
            arr[..., 3] = arr[..., 3] * (1 - gtr)
        paste(layer, arr, x - t, y - t)
    if node['bgT'] < 1:
        mask = rounded_mask(w, h, r)
        col, tr = gradient(node, iw, ih)
        arr = np.zeros((ih, iw, 4), np.float32)
        base = np.array(node['bg'], np.float32)
        arr[..., :3] = base if col is None else base * col
        alpha = (1 - node['bgT']) * mask
        if tr is not None:
            alpha = alpha * (1 - tr)
        arr[..., 3] = alpha
        paste(layer, arr, x, y)

def draw_viewport(layer, x, y, w, h):
    """placeholder for a 3D portrait: a face with spiky hair"""
    d = ImageDraw.Draw(layer)
    cx, cy, s = x + w / 2, y + h * 0.58, min(w, h)
    d.rounded_rectangle([cx - s * 0.22, cy - s * 0.22, cx + s * 0.22, cy + s * 0.22], radius=s * 0.08, fill=(245, 205, 60, 255))
    for i in range(7):
        a = math.pi * (0.15 + 0.7 * i / 6)
        tip = (cx - math.cos(a) * s * 0.45, cy - s * 0.2 - math.sin(a) * s * 0.42)
        d.polygon([(cx - s * 0.2 + i * s * 0.066, cy - s * 0.18), (cx - s * 0.14 + i * s * 0.066, cy - s * 0.18), tip], fill=(25, 25, 30, 255))
    d.ellipse([cx - s * 0.1, cy - s * 0.04, cx - s * 0.05, cy + s * 0.02], fill=(20, 20, 20, 255))
    d.ellipse([cx + s * 0.05, cy - s * 0.04, cx + s * 0.1, cy + s * 0.02], fill=(20, 20, 20, 255))
    d.text((x + 3, y + h - 12), '3D', fill=(0, 0, 0, 120))

def draw_text(layer, node, x, y, w, h, k):
    txt = node.get('text', '')
    if not txt or node['tT'] >= 1 or w < 2 or h < 2:
        return
    strokes = [s for s in kids(node, 'UIStroke') if s['mode'] == 'Contextual']
    sw = int(round(strokes[0]['thick'] * k)) if strokes else (1 if node['strokeT'] < 1 else 0)
    lines = txt.split('\n')
    def measure(f):
        asc, desc = f.getmetrics()
        widths = [f.getbbox(l or ' ', stroke_width=sw)[2] - f.getbbox(l or ' ', stroke_width=sw)[0] for l in lines]
        return max(widths), (asc + desc) * len(lines), asc + desc
    if node['scaled']:
        lo, hi = 2, 100
        while lo < hi:
            mid = (lo + hi + 1) // 2
            f, sq = font(node['font'], mid, txt)
            mw, mh, _ = measure(f)
            if mw * sq <= w and mh <= h * 1.02:
                lo = mid
            else:
                hi = mid - 1
        size = lo
    else:
        size = node['tsize'] * k
    f, sq = font(node['font'], size, txt)
    mw, mh, lh = measure(f)
    tw, th = mw + 2 * sw + 4, mh + 2 * sw + 2
    timg = Image.new('RGBA', (int(tw), int(th)), (0, 0, 0, 0))
    col = tuple(int(255 * c) for c in node['tc']) + (int(255 * (1 - node['tT'])),)
    if strokes:
        sc = tuple(int(255 * c) for c in strokes[0]['color']) + (int(255 * (1 - strokes[0]['t']) * (1 - node['tT'])),)
    else:
        sc = tuple(int(255 * c) for c in node['strokeC']) + (int(255 * (1 - node['strokeT']) * (1 - node['tT'])),)
    td = ImageDraw.Draw(timg)
    for li, line in enumerate(lines):
        lb = f.getbbox(line or ' ', stroke_width=sw)
        lw = lb[2] - lb[0]
        lx = {'Left': 0, 'Right': mw - lw}.get(node['xa'], (mw - lw) / 2)
        td.text((sw - lb[0] + 2 + lx, sw + 1 + li * lh), line, font=f, fill=col, stroke_width=sw, stroke_fill=sc)
    if sq != 1:
        timg = timg.resize((max(1, int(tw * sq)), int(th)), Image.LANCZOS)
    tw = timg.size[0]
    if node['xa'] == 'Left':
        tx = x
    elif node['xa'] == 'Right':
        tx = x + w - tw
    else:
        tx = x + (w - tw) / 2
    ty = y + (h - th) / 2 if node['ya'] == 'Center' else (y if node['ya'] == 'Top' else y + h - th)
    tmp = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    tmp.paste(timg, (int(round(tx)), int(round(ty))))
    layer.alpha_composite(tmp)

GUI_CLASSES = ('Frame', 'TextLabel', 'TextButton', 'ImageLabel', 'ViewportFrame', 'ScrollingFrame', 'CanvasGroup')

def layout(node, prect, k):
    px, py, pw, ph = prect
    sx, ox, sy, oy = node['size']
    w, h = sx * pw + ox * k, sy * ph + oy * k
    ar = kids(node, 'UIAspectRatioConstraint')
    if ar:
        ratio = ar[0]['ratio']
        if w / max(h, 1e-6) > ratio:
            w = h * ratio
        else:
            h = w / ratio
    psx, pox, psy, poy = node['pos']
    ax, ay = node['anchor']
    anchor_x, anchor_y = px + psx * pw + pox * k, py + psy * ph + poy * k
    us = kids(node, 'UIScale')
    kk = k
    if us:
        s = us[0]['scale']
        w, h, kk = w * s, h * s, k * s
    return (anchor_x - ax * w, anchor_y - ay * h, w, h), kk

def draw_node(layer, node, prect, k):
    if node['class'] not in GUI_CLASSES or not node.get('visible', True):
        return
    rect, kk = layout(node, prect, k)
    x, y, w, h = rect
    rot = node.get('rot', 0) or 0
    group = node['class'] == 'CanvasGroup'
    if group and node.get('groupT', 0) >= 1:
        return
    target = Image.new('RGBA', layer.size, (0, 0, 0, 0)) if (rot or group) else layer
    draw_box(target, node, x, y, w, h, kk)
    if node['class'] == 'ViewportFrame':
        draw_viewport(target, x, y, w, h)
    if node['class'] in ('TextLabel', 'TextButton'):
        draw_text(target, node, x, y, w, h, kk)
    children = sorted([c for c in node['children'] if c['class'] in GUI_CLASSES], key=lambda c: c.get('z', 1))
    if node.get('clip'):
        sub = Image.new('RGBA', layer.size, (0, 0, 0, 0))
        for c in children:
            draw_node(sub, c, rect, kk)
        m = Image.new('L', layer.size, 0)
        ImageDraw.Draw(m).rectangle([x, y, x + w, y + h], fill=255)
        sub.putalpha(Image.fromarray((np.asarray(sub)[..., 3] * (np.asarray(m) / 255)).astype(np.uint8)))
        target.alpha_composite(sub)
    else:
        for c in children:
            draw_node(target, c, rect, kk)
    if group:  # a CanvasGroup fades its whole contents together
        a = np.asarray(target).copy()
        a[..., 3] = (a[..., 3] * (1 - node.get('groupT', 0))).astype(np.uint8)
        target = Image.fromarray(a, 'RGBA')
    if rot:
        target = target.rotate(-rot, center=(x + w / 2, y + h / 2), resample=Image.BICUBIC)
    if rot or group:
        layer.alpha_composite(target)

def scene(W, H):
    """a stand-in game view to judge contrast: sky, ground, horizon"""
    img = np.zeros((H, W, 3), np.float32)
    t = np.linspace(0, 1, H)[:, None]
    sky = np.array([0.42, 0.62, 0.86]) * (1 - t) + np.array([0.72, 0.82, 0.92]) * t
    img[:] = sky[:, None, :] if sky.ndim == 2 else sky
    horizon = int(H * 0.58)
    ground = np.array([0.45, 0.47, 0.5])
    img[horizon:] = ground
    im = Image.fromarray((img * 255).astype(np.uint8)).convert('RGBA')
    d = ImageDraw.Draw(im)
    for i in range(-12, 13):  # floor grid
        d.line([(W / 2 + i * W * 0.03, horizon), (W / 2 + i * W * 0.2, H)], fill=(120, 124, 130, 255), width=1)
    cx, cy = W / 2, H * 0.62  # a character in the middle
    s = H * 0.055
    d.rectangle([cx - s, cy - 2.6 * s, cx + s, cy], fill=(230, 110, 30, 255))
    d.rectangle([cx - 0.6 * s, cy - 3.9 * s, cx + 0.6 * s, cy - 2.7 * s], fill=(245, 205, 50, 255))
    d.rectangle([cx - s, cy, cx + s, cy + 2.2 * s], fill=(230, 110, 30, 255))
    return im

def render(data, title=''):
    W, H = data['width'], data['height']
    touch = data.get('touch')
    img = scene(W, H)
    for e in data.get('effects', []):  # ColorCorrection on the 3D view (approximate)
        a = np.asarray(img, np.float32)[..., :3] / 255
        grey = a @ np.array([0.299, 0.587, 0.114])
        a = grey[..., None] + (a - grey[..., None]) * (1 + e['saturation'])
        a = (a - 0.5) * (1 + e['contrast']) + 0.5 + e['brightness']
        a = np.clip(a * np.array(e['tint']), 0, 1)
        img = Image.fromarray((a * 255).astype(np.uint8)).convert('RGBA')
    # where ScreenGuis that don't ignore the inset may draw (Roblox's top bar, a phone's notch)
    notch = 47 if W >= 800 else 0  # notched phones are wider; an iPhone SE has no side insets
    inset = (notch, 58, notch, 21 if notch else 0) if touch else (0, 58, 0, 0)  # left, top, right, bottom
    for g in data['guis']:
        if g['class'] != 'ScreenGui' or not g.get('enabled', True):
            continue
        if g.get('ignoreInset'):
            rect = (0, 0, W, H)
        else:
            rect = (inset[0], inset[1], W - inset[0] - inset[2], H - inset[1] - inset[3])
        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        for c in sorted(g['children'], key=lambda c: c.get('z', 1)):
            draw_node(layer, c, rect, 1.0)
        img.alpha_composite(layer)
    over = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    # Roblox's own top-bar buttons
    d.rounded_rectangle([12, 12, 56, 56], radius=12, fill=(20, 20, 20, 150))
    d.rounded_rectangle([64, 12, 108, 56], radius=12, fill=(20, 20, 20, 150))
    if touch:
        # thumbstick, jump button and the Power action button Roblox adds
        jx, jy, jr = W - inset[2] - 70, H - inset[3] - 70, 45
        d.ellipse([jx - jr, jy - jr, jx + jr, jy + jr], outline=(255, 255, 255, 200), width=3, fill=(0, 0, 0, 60))
        d.text((jx - 14, jy - 6), 'JUMP', fill=(255, 255, 255, 220))
        tx, ty, tr = inset[0] + 110, H - inset[3] - 100, 70
        d.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], outline=(255, 255, 255, 140), width=3, fill=(0, 0, 0, 40))
        d.text((tx - 30, ty - 6), 'THUMBSTICK', fill=(255, 255, 255, 200))
        px_, py_, pr = W - inset[2] - 165, H - inset[3] - 115, 30
        d.ellipse([px_ - pr, py_ - pr, px_ + pr, py_ + pr], outline=(255, 255, 255, 200), width=2, fill=(0, 0, 0, 60))
        d.text((px_ - 15, py_ - 6), 'Power', fill=(255, 255, 255, 220))
        d.rectangle([0, 0, inset[0], H], fill=(0, 0, 0, 90))  # the notch side
    img.alpha_composite(over)
    if title:
        ImageDraw.Draw(img).text((W // 2 - 60, H - 16), title, fill=(0, 0, 0, 255))
    return img

if __name__ == '__main__':
    data = json.load(open(sys.argv[1]))
    render(data, sys.argv[3] if len(sys.argv) > 3 else data.get('scenario', '')).convert('RGB').save(sys.argv[2])
