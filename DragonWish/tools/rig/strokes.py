"""Finds the drawn highlights (the cream crescents) in the hair texture and saves a frame for
each: a centre line from the root end to the tip and a half-width. texmap.py lays each spike of
a hair along one of them.
usage: python strokes.py <texture.png> <out.json> [picture.png]"""
import sys, json, numpy as np
from PIL import Image
from scipy import ndimage

CREAM = (244, 221, 181)
ORIGIN = np.array([0.47, 0.28])  # where the drawn spikes grow from (the face gap of the drawing)
WIDEN = 2.4  # the frame is this many crescent half-widths wide each side (takes in the shadow
#              and ink lines drawn next to the highlight)


def find(path, N=512):
    a = np.asarray(Image.open(path).convert('RGB').resize((N, N), Image.BILINEAR)).astype(float)
    cream = np.linalg.norm(a - np.array(CREAM), axis=2) < 40
    lab, n = ndimage.label(cream, structure=np.ones((3, 3)))
    out = []
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        if len(xs) < 120:
            continue
        pts = np.c_[(xs + 0.5) / N, 1 - (ys + 0.5) / N]  # texture u, v (v up)
        m = pts.mean(0)
        ev, evec = np.linalg.eigh(np.cov((pts - m).T))
        ax = evec[:, -1]
        nx = np.array([-ax[1], ax[0]])
        p, q = (pts - m) @ ax, (pts - m) @ nx
        co = np.polyfit(p, q, 2)
        r = q - np.polyval(co, p)
        ps = np.linspace(p.min(), p.max(), 13)
        curve = m + ps[:, None] * ax + np.polyval(co, ps)[:, None] * nx
        if np.linalg.norm(curve[0] - ORIGIN) > np.linalg.norm(curve[-1] - ORIGIN):
            curve = curve[::-1]  # root end first: the end nearer the middle of the drawing
        half = float(np.percentile(np.abs(r), 95))
        chord = curve[-1] - curve[0]
        bow = np.abs((curve - curve[0]) @ (np.array([-chord[1], chord[0]]) / np.linalg.norm(chord))).max()
        if bow > 0.2 * np.linalg.norm(chord):
            continue  # a C-shaped stroke (or two strokes run together) would curl round a straight spike
        out.append({'curve': [[round(float(x), 5) for x in c] for c in curve],
                    'halfwidth': round(half * WIDEN, 5), 'area': int(len(xs))})
    return out


if __name__ == '__main__':
    frames = find(sys.argv[1])
    json.dump(frames, open(sys.argv[2], 'w'), indent=0)
    print('highlights found', len(frames))
    if len(sys.argv) > 3:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        im = np.asarray(Image.open(sys.argv[1]).convert('RGB').resize((512, 512)))
        fig, axp = plt.subplots(figsize=(10, 10))
        axp.imshow(im, extent=(0, 1, 0, 1))
        for f in frames:
            c = np.array(f['curve'])
            d = np.gradient(c, axis=0)
            nrm = np.c_[-d[:, 1], d[:, 0]] / (np.linalg.norm(d, axis=1, keepdims=True) + 1e-9)
            for sgn in (-1, 1):
                e = c + sgn * nrm * f['halfwidth']
                axp.plot(e[:, 0], e[:, 1], 'c-', lw=0.8)
            axp.plot(c[:, 0], c[:, 1], 'b-', lw=1.5)
            axp.plot(c[0, 0], c[0, 1], 'ro', ms=4)
        axp.set_xlim(0, 1)
        axp.set_ylim(0, 1)
        plt.savefig(sys.argv[3], dpi=60)
