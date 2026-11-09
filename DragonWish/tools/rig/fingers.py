"""Fingers for the R15 body's hands.

The 20 finger pieces come from TakeTheFingers.obj (an R6 test rig with a thumb and four fingers
on each hand, two blocky segments each). Both rigs' arms end at the same height, so the pieces
move straight across onto the R15 body's hands (R15_body.obj). Each hand becomes one skinned
mesh with a root bone and, per finger, a knuckle bone (1), a middle-joint bone (2) and a tip
bone. The segments are rigid: every vertex follows exactly one bone, like separate parts on
hinges.

Coordinates: Roblox space (Y up, front = -Z, X = the character's right), relative to the centre
of the R15 hand the fingers go on.
"""
import numpy as np
from rigcore import weld

FINGERS = ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']
# centre of the arm's bottom block in TakeTheFingers.obj (it plays the R15 hand there)
SOURCE_CENTRE = {'R': np.array([29.5, 2.1935, -34.0]), 'L': np.array([26.5, 2.1935, -34.0])}
# the R15 hands in R15_body.obj: RightHand x 18..19, LeftHand x 15..16, y 2..2.387, z -38..-37
HAND_BOUNDS = {'R': ((18, 2, -38), (19, 2.387, -37)), 'L': ((15, 2, -38), (16, 2.387, -37))}


def load_groups(path):
    V, VT, VN, groups, cur = [], [], [], {}, None
    for line in open(path):
        p = line.split()
        if not p:
            continue
        if p[0] == 'v':
            V.append([float(x) for x in p[1:4]])
        elif p[0] == 'vt':
            VT.append([float(x) for x in p[1:3]])
        elif p[0] == 'vn':
            VN.append([float(x) for x in p[1:4]])
        elif p[0] == 'g':
            cur = p[1]
            groups.setdefault(cur, [])
        elif p[0] == 'f':
            groups[cur].append([tuple(int(i) - 1 if i else -1 for i in (t.split('/') + ['', ''])[:3]) for t in p[1:]])
    return np.array(V), np.array(VT), np.array(VN), groups


def fit_circle(P):
    """least-squares circle through 2D points: (centre x, centre y)"""
    A = np.c_[P[:, 0], P[:, 1], np.ones(len(P))]
    b = -(P[:, 0] ** 2 + P[:, 1] ** 2)
    D, E, F = np.linalg.lstsq(A, b, rcond=None)[0]
    return np.array([-D / 2, -E / 2])


def hand_centre(r15_path, side):
    """centre of the hand's box in R15_body.obj, measured (falls back to the known bounds)"""
    lo, hi = (np.array(b, float) for b in HAND_BOUNDS[side])
    if r15_path:
        V, _, _, groups = load_groups(r15_path)
        for faces in groups.values():
            idx = sorted({c[0] for f in faces for c in f})
            P = V[idx]
            plo, phi = P.min(0), P.max(0)
            if np.allclose(plo, lo, atol=0.02) and np.allclose(phi, hi, atol=0.05):
                lo, hi = plo, phi
                break
    return (lo + hi) / 2


class FingerRig:
    """same fields the Blender exporter in build_dbz.py reads from the hair rigs"""

    def __init__(self, side, fingers_path, r15_path=None):
        V, VT, VN, groups = load_groups(fingers_path)
        self.VT, self.VN = VT, VN
        self.name = ('Left' if side == 'L' else 'Right') + 'Fingers'
        self.side = side
        self.root = side + 'HandRoot'
        # TakeTheFingers -> R15 hand, then relative to the hand's centre
        shift = -SOURCE_CENTRE[side]
        centre = hand_centre(r15_path, side)
        self.hand_centre = centre
        P_all, tris, corner, owner = [], [], [], []
        bottom = -(centre[1] - 2.0)  # the hand's bottom face, relative to its centre
        self.bones = [(self.root, np.array([0, bottom, 0]), np.array([0, bottom + 0.1, 0]), None)]
        self.chains = []
        self.pivots = {}
        for f in FINGERS:
            segs = {}
            for k, suffix in (('prox', '11'), ('dist', '21')):
                faces = groups[side + f.lower() + suffix]
                idx = sorted({c[0] for face in faces for c in face})
                local = {i: n for n, i in enumerate(idx)}
                P = V[idx] + shift
                Pw, inv = weld(P)  # merge duplicate corners inside this segment only
                base = sum(len(x) for x in P_all)
                P_all.append(Pw)
                for face in faces:
                    for t in range(1, len(face) - 1):
                        tri = (face[0], face[t], face[t + 1])
                        ids = [base + int(inv[local[c[0]]]) for c in tri]
                        if len(set(ids)) < 3:
                            continue  # merging duplicate corners collapsed this sliver: drop it
                        tris.append(ids)
                        corner.append(list(tri))
                segs[k] = Pw
                owner.append((base, base + len(Pw), side + f + ('1' if k == 'prox' else '2')))
            prox, dist = segs['prox'], segs['dist']
            top, width = prox[:, 1].max(), prox[:, 0].max() - prox[:, 0].min()
            zc = (prox[:, 2].min() + prox[:, 2].max()) / 2
            knuckle = fit_circle(prox[prox[:, 1] > top - width / 2 + 0.005][:, :2])  # the rounded top
            middle = fit_circle(dist[dist[:, 1] > dist[:, 1].max() - 0.19][:, :2])  # the knuckle ball
            tipy = dist[:, 1].min()
            mcp = np.array([knuckle[0], knuckle[1], zc])
            pip = np.array([middle[0], middle[1], zc])
            tip = np.array([(dist[:, 0].min() + dist[:, 0].max()) / 2, tipy, zc])
            names = [side + f + '1', side + f + '2', side + f + 'Tip']
            self.bones.append((names[0], mcp, pip, self.root))
            self.bones.append((names[1], pip, tip, names[0]))
            self.bones.append((names[2], tip, tip + np.array([0, -0.1, 0]), names[1]))
            self.chains.append((side + f, names, [0.1, 0.1, 0.1]))
            self.pivots[f] = (mcp, pip, tip)
        self.P = np.vstack(P_all)
        self.tris = np.array(tris)
        self.corner = corner
        self.bone_names = [b[0] for b in self.bones]
        W = np.zeros((len(self.P), len(self.bones)))
        for a, b, bone in owner:
            W[a:b, self.bone_names.index(bone)] = 1.0
        self.Wmat = W

    def finish(self):  # (the hair rigs smooth their weights here; finger segments stay rigid)
        return self


def build_fingers(side, fingers_path, r15_path=None):
    rig = FingerRig(side, fingers_path, r15_path)
    print(rig.name, 'verts', len(rig.P), 'tris', len(rig.tris), 'hand centre', np.round(rig.hand_centre, 4))
    for f, (mcp, pip, tip) in rig.pivots.items():
        print('  %-6s knuckle %s middle %s tip %s' % (f, np.round(mcp, 3), np.round(pip, 3), np.round(tip, 3)))
    return rig
