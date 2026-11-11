"""Recolours the golden hair texture. Every pixel is a blend of two of the drawing's four colours
(base, highlight, shadow, ink: anti-aliased edges are in-between), so each pixel is matched to the
closest blend and redrawn with the same blend of the new colours.
usage: python recolour.py <in.png> <out.png> black|<r,g,b;r,g,b;r,g,b;r,g,b>"""
import sys, itertools, numpy as np
from PIL import Image

OLD = np.array([(211, 160, 24), (244, 221, 181), (191, 122, 22), (1, 1, 0)], float)  # base, highlight, shadow, ink
PRESETS = {
    # black anime hair: near-black base with a cool tint, slate-blue highlights, deeper shadows
    'black': [(26, 26, 34), (74, 82, 106), (10, 10, 15), (0, 0, 0)],
    # (for later) SSJ God red
    'red': [(196, 32, 46), (255, 132, 120), (128, 12, 28), (12, 0, 0)],
}


def recolour(src, new):
    a = np.asarray(Image.open(src).convert('RGB')).astype(float)
    new = np.array(new, float)
    out = np.empty_like(a)
    pairs = list(itertools.combinations(range(4), 2))
    for r0 in range(0, a.shape[0], 256):
        c = a[r0:r0 + 256].reshape(-1, 3)
        best_d = np.full(len(c), np.inf)
        res = np.zeros_like(c)
        for i, j in pairs:
            d = OLD[j] - OLD[i]
            lam = np.clip(((c - OLD[i]) @ d) / (d @ d), 0, 1)
            dist = np.linalg.norm(c - (OLD[i] + lam[:, None] * d), axis=1)
            m = dist < best_d
            best_d[m] = dist[m]
            res[m] = new[i] + lam[m, None] * (new[j] - new[i])
        out[r0:r0 + 256] = res.reshape(-1, a.shape[1], 3)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


if __name__ == '__main__':
    spec = sys.argv[3]
    cols = PRESETS[spec] if spec in PRESETS else [tuple(int(x) for x in p.split(',')) for p in spec.split(';')]
    recolour(sys.argv[1], cols).save(sys.argv[2], optimize=True)
    print('saved', sys.argv[2])
