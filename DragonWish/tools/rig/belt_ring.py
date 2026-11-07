"""Measures the inside of the belt's band and stores it in riginfo.json (key "ring" on the Belt).

The band is sliced at many heights; at every angle around the waist we keep the distance from
the waist centre to the nearest bit of band. CharacterSetup uses this to size the belt so the
body never pokes through it.

usage: python3 -I tools/rig/belt_ring.py models/source/Belt.obj tools/rig/riginfo.json
"""
import json, sys
import numpy as np

CENTER = (23.006, 2.205, -5.485)  # same as dbz.CENTERS['Belt']
BOTTOM, TOP = -0.195, 0.205       # the band (its very bottom rim curls inward and is ignored)
STEP = 2                          # degrees between stored radii
NEAREST = 0.45                    # anything closer to the centre than this is inside the body, not band


def load(path):
    V, F = [], []
    for line in open(path):
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('f '):
            idx = [int(t.split('/')[0]) for t in line.split()[1:]]
            idx = [i - 1 if i > 0 else len(V) + i for i in idx]
            for k in range(1, len(idx) - 1):
                F.append((idx[0], idx[k], idx[k + 1]))
    return np.array(V) - np.array(CENTER), np.array(F)


def slice_at(V, F, y):
    segs = []
    for tri in F:
        P = V[list(tri)]
        d = P[:, 1] - y
        pts = []
        for i, j in ((0, 1), (1, 2), (2, 0)):
            if (d[i] < 0) != (d[j] < 0):
                t = d[i] / (d[i] - d[j])
                pts.append((P[i] + (P[j] - P[i]) * t)[[0, 2]])
        if len(pts) == 2:
            segs.append(pts)
    return segs


def nearest_along(segs, th):
    d = np.array([np.cos(th), np.sin(th)])
    best = np.inf
    for p, q in segs:
        e = q - p
        M = np.array([[d[0], -e[0]], [d[1], -e[1]]])
        if abs(np.linalg.det(M)) < 1e-12:
            continue
        t, u = np.linalg.solve(M, p)
        if t > NEAREST and -1e-9 <= u <= 1 + 1e-9:
            best = min(best, t)
    return best


def main(obj_path, info_path):
    V, F = load(obj_path)
    fine = np.radians(np.arange(0, 360, 0.5))
    prof = np.full(len(fine), np.inf)
    for y in np.arange(BOTTOM, TOP + 1e-9, 0.005):
        segs = slice_at(V, F, y)
        prof = np.minimum(prof, [nearest_along(segs, th) for th in fine])
    assert np.isfinite(prof).all(), 'the band has a hole'
    radii = []
    for k in range(0, 360, STEP):
        window = [(int(round((k + a) / 0.5))) % len(fine) for a in np.arange(-1, 1.01, 0.5)]
        radii.append(round(float(prof[window].min()) - 0.0005, 3))  # rounded down: never optimistic
    info = json.load(open(info_path))
    for h in info:
        if h['name'] == 'Belt':
            h['ring'] = {'bottom': BOTTOM, 'top': TOP, 'step': STEP, 'radii': radii}
    json.dump(info, open(info_path, 'w'), indent=1)
    print('ring radii (every %d deg from +X towards +Z):' % STEP, radii)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
