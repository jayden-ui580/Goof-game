"""Bone layout + skin weights for each hair. Run through build.py."""
import numpy as np
from rigcore import *

HEAD = (14.92, 4.85, 11.72)   # estimated head centre in the exported OBJ (studs)

class Rig:
    def __init__(self, name, path):
        self.name = name
        V, VT, VN, faces = load_obj(path, HEAD)
        self.corner = faces                         # [(v, vt, vn) x3] per face
        self.P, self.inv = weld(V)
        self.tris = np.array([[self.inv[c[0]] for c in f] for f in faces])
        self.VT, self.VN = VT, VN
        self.cid = components(len(self.P), self.tris)
        self.adj = adjacency(len(self.P), self.tris, self.P)
        self.bones = [('HairRoot', np.zeros(3), np.array([0, 0.4, 0]), None)]
        self.W = {'HairRoot': np.ones(len(self.P))}
        self.chains = []                            # (chainName, [boneNames], [radii])

    def comp_stats(self):
        out = []
        for c in range(self.cid.max() + 1):
            idx = np.where(self.cid == c)[0]
            out.append((c, len(idx), self.P[idx].mean(0), self.P[idx].min(0), self.P[idx].max(0)))
        return out

    def add_chain(self, name, joints, verts, chain_w, static_w, radii):
        """joints: n+1 points (last = tip/End bone). verts: vertex ids skinned to this chain.
        chain_w: (len(verts), n) weights along the chain (rows sum to 1).
        static_w: per-vertex weight kept on HairRoot (0 = fully simulated)."""
        n = len(joints) - 1
        names = ['%s_%d' % (name, k + 1) for k in range(n)] + ['%s_End' % name]
        parent = 'HairRoot'
        for k, bn in enumerate(names):
            head = joints[k]
            tail = joints[k + 1] if k < n else joints[k] + (joints[k] - joints[k - 1]) * 0.35
            self.bones.append((bn, head, tail, parent)); parent = bn
            self.W.setdefault(bn, np.zeros(len(self.P)))
        dyn = 1 - static_w
        # remove the share that goes to this chain from whatever these verts had before
        for bn in self.W:
            if bn not in names: self.W[bn][verts] *= static_w if bn == 'HairRoot' else 1
        for k in range(n):
            self.W[names[k]][verts] += chain_w[:, k] * dyn
        # the very tip of each strand is also tied to the End bone. It always moves exactly
        # like the last bone (it is its child and never rotated), so this changes nothing visually
        # but stops Roblox's importer from deleting the End bone as an "unused" bone.
        u, _ = project(self.P[verts], joints)
        tipshare = 0.5 * smoothstep(n - 0.35, n, u) * self.W[names[n - 1]][verts]
        self.W[names[n - 1]][verts] -= tipshare
        self.W[names[n]][verts] += tipshare
        self.chains.append((name, names, list(radii)))

    def finish(self, smooth_iters=3):
        names = [b[0] for b in self.bones]
        W = np.stack([self.W[n] for n in names], 1)
        # blur the weights over the mesh a little (like Blender's "Smooth" weight tool) so
        # neighbouring vertices never jump between far-apart bones
        for _ in range(smooth_iters):
            Wn = W.copy()
            for i, nb in enumerate(self.adj):
                if nb: Wn[i] = 0.5 * W[i] + 0.5 * W[list(nb)].mean(0)
            W = Wn
        W = limit_influences(W, 4)
        self.Wmat, self.bone_names = W, names


def strand_joints(rig, comps, root_pt, n_seg, start_frac=0.0):
    cl = strand_centerline(rig.P, rig.adj, rig.cid, comps, root_pt)
    if start_frac > 0:
        seg = np.linalg.norm(np.diff(cl, axis=0), axis=1); s = np.r_[0, np.cumsum(seg)]
        t = s[-1] * start_frac
        j = np.searchsorted(s, t) - 1; f = (t - s[j]) / seg[j]
        cl = np.vstack([cl[j] + (cl[j + 1] - cl[j]) * f, cl[j + 1:]])
        return resample(cl, n_seg)
    return resample(cl, n_seg, start=root_pt)


def build_pigtails(path):
    rig = Rig('Pigtails', path)
    st = rig.comp_stats()
    for side, sgn in (('L', -1), ('R', 1)):
        tails = [c for c, n, m, lo, hi in st if m[0] * sgn > 0.7 and m[2] > -0.1]
        knots = [c for c, n, m, lo, hi in st if 0.45 < m[0] * sgn <= 0.7 and m[1] > 0.3]
        knot = np.mean([st[c][2] for c in knots], axis=0)
        longest = sorted(tails, key=lambda c: st[c][4][1] - st[c][3][1], reverse=True)[:3]
        joints = strand_joints(rig, longest, knot, 5)
        joints[0] = knot
        verts, u, d = project_strands(rig.P, rig.adj, rig.cid, tails, joints, knot)
        cw = chain_weights(u, 5)
        static = 1 - smoothstep(0.0, 0.45, u)
        rig.add_chain('Pig' + side, joints, verts, cw, static, [0.17, 0.17, 0.16, 0.15, 0.13, 0.11])
        print('Pig' + side, 'tails', tails, 'knot', np.round(knot, 3))
        print(np.round(joints, 3))
    rig.finish(); return rig


def build_hair1(path):
    rig = Rig('LadyHair', path)
    st = rig.comp_stats()
    main = max(st, key=lambda s: s[1])[0]
    locks = [c for c, n, m, lo, hi in st if c != main and m[2] < -0.3 and m[1] < 0 and n > 100]
    # ---- back sheet: five columns of bones, x positions per height chosen from the cross-sections
    cols = {
        'BackL2': [(-0.62, -0.15), (-0.74, -0.55), (-0.82, -0.95), (-0.86, -1.35), (-0.86, -1.70), (-0.82, -2.00)],
        'BackL1': [(-0.33, -0.15), (-0.38, -0.60), (-0.42, -1.05), (-0.45, -1.50), (-0.47, -1.95), (-0.50, -2.30)],
        'BackC':  [(0.00, -0.15), (0.00, -0.60), (0.00, -1.05), (0.00, -1.50), (0.00, -1.95), (0.02, -2.45)],
        'BackR1': [(0.33, -0.15), (0.38, -0.60), (0.42, -1.05), (0.43, -1.50), (0.45, -1.95), (0.48, -2.30)],
        'BackR2': [(0.62, -0.15), (0.74, -0.55), (0.82, -0.95), (0.88, -1.35), (0.86, -1.70), (0.80, -1.98)],
    }
    midx = np.where(rig.cid == main)[0]
    T = rig.P[rig.tris]                                 # dense surface samples for picking depth
    rng = np.random.default_rng(0); r = rng.random((len(T), 20, 2)); m = r.sum(2) > 1; r[m] = 1 - r[m]
    S = (T[:, None, 0] * (1 - r[..., :1] - r[..., 1:]) + T[:, None, 1] * r[..., :1] + T[:, None, 2] * r[..., 1:])
    S = S[rig.cid[rig.tris[:, 0]] == main].reshape(-1, 3)
    def depth(x, y):
        m = (np.abs(S[:, 1] - y) < 0.06) & (np.abs(S[:, 0] - x) < 0.1) & (S[:, 2] > 0.15)
        z = S[m, 2]
        if len(z) == 0: return None
        zo = z.max(); zi = z[z > zo - 0.55].min()
        return max(zo - 0.15, (zo + zi) / 2)
    joints = {}
    for name, pts in cols.items():
        J = []
        for x, y in pts:
            z = depth(x, y)
            if z is None: z = depth(x * 0.9, y) or J[-1][2]
            J.append([x, y, z])
        joints[name] = np.array(J)
        print(name); print(np.round(joints[name], 3))
    back = midx[rig.P[midx, 1] < 0.12]
    names = list(cols)
    U = []; D = []
    for nm in names:
        u, d = project(rig.P[back], joints[nm]); U.append(u); D.append(d)
    U = np.array(U).T; D = np.array(D).T
    order = np.argsort(D, axis=1)[:, :2]
    a, b = order[:, 0], order[:, 1]
    ia = np.arange(len(back))
    da, db = D[ia, a] + 1e-4, D[ia, b] + 1e-4
    wa = (1 / da ** 2) / (1 / da ** 2 + 1 / db ** 2)
    static = smoothstep(-0.45, 0.10, rig.P[back, 1])
    for ci, nm in enumerate(names):
        sel = (a == ci) | (b == ci)
        share = np.where(a == ci, wa, 1 - wa)[sel]
        verts = back[sel]
        cw = chain_weights(U[sel, ci], 5) * share[:, None]
        # static weight for these verts goes to HairRoot; chain share scaled by (1 - static).
        # add_chain multiplies HairRoot by static and adds cw*(1-static), so feed it per-vertex share.
        rig_add_shared(rig, nm, joints[nm], verts, cw, static[sel], [0.2, 0.19, 0.18, 0.17, 0.15, 0.13])
    # ---- the two front locks that rest on the chest
    for c in locks:
        side = 'L' if st[c][2][0] < 0 else 'R'
        idx = np.where(rig.cid == c)[0]
        top = rig.P[idx[np.argsort(-rig.P[idx, 1])[:4]]].mean(0)
        J = strand_joints(rig, [c], top, 4, start_frac=0.32)
        verts, u, d = project_strands(rig.P, rig.adj, rig.cid, [c], J, top)
        cw = chain_weights(u, 4)
        static = 1 - smoothstep(-0.6, 0.35, u)
        rig.add_chain('Lock' + side, J, verts, cw, static, [0.12, 0.12, 0.11, 0.1, 0.09])
        print('Lock' + side, 'comp', c); print(np.round(J, 3))
    rig.finish(); return rig


def rig_add_shared(rig, name, joints, verts, cw, static, radii):
    """Like Rig.add_chain but the vertex is shared between two neighbouring chains, so the
    HairRoot share is only set once (first time) and chain weights add on top."""
    n = len(joints) - 1
    names = ['%s_%d' % (name, k + 1) for k in range(n)] + ['%s_End' % name]
    if not any(c[0] == name for c in rig.chains):
        parent = 'HairRoot'
        for k, bn in enumerate(names):
            head = joints[k]
            tail = joints[k + 1] if k < n else joints[k] + (joints[k] - joints[k - 1]) * 0.35
            rig.bones.append((bn, head, tail, parent)); parent = bn
            rig.W.setdefault(bn, np.zeros(len(rig.P)))
        rig.chains.append((name, names, list(radii)))
    rig.W['HairRoot'][verts] = static
    dyn = 1 - static
    for k in range(n):
        rig.W[names[k]][verts] += cw[:, k] * dyn
    u, _ = project(rig.P[verts], joints)
    tip = 0.5 * smoothstep(n - 0.35, n, u) * cw[:, n - 1] * dyn
    rig.W[names[n - 1]][verts] -= tip
    rig.W[names[n]][verts] += tip
