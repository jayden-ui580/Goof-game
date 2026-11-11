"""Rigs for Dragon Wish: Online — base hair, SSJ hair (spike chains) and the belt (ribbon chains)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from rigcore import *
import hairs
from spikes import spike_segments

# Where the wearer's head / waist centre was in each exported .obj (see the fit analysis).
CENTERS = {
    'BaseHair': (23.006, 4.5, -5.485),   # same character as the belt: standard R15 standing on y = 0
    'SSJHair': (17.4645, 4.5, -6.7),     # centred by the hair's inner ring; same head height
    'Belt': (23.006, 2.205, -5.485),     # LowerTorso centre = middle of the belt band
    # SSJ2 / SSJ3 (the user's hairs, exported from another spot in the place): x from the hair's
    # left/right symmetry, y = lowest point + 0.42 and z where a 1.2-stud head overlaps the hair
    # least. The same recipe gives the base hair's centre and the SSJ hair's centre (after the
    # user's fit-tool nudge) to within 0.03 studs.
    'SSJ2Hair': (31.986, 4.424, -36.50),
    'SSJ3Hair': (23.72, 4.445, -37.33),
}

class DRig(hairs.Rig):
    def __init__(self, name, path, center, root):
        V, VT, VN, faces = load_obj(path, center)
        self.name = name
        self.corner = faces
        self.P, self.inv = weld(V)
        self.tris = np.array([[self.inv[c[0]] for c in f] for f in faces])
        self.VT, self.VN = VT, VN
        self.cid = components(len(self.P), self.tris)
        self.adj = adjacency(len(self.P), self.tris, self.P)
        self.root = root
        self.bones = [(root, np.zeros(3), np.array([0, 0.4, 0]), None)]
        self.W = {root: np.ones(len(self.P))}
        self.chains = []
        self.chain_verts = {}

    def add_chain(self, name, joints, verts, chain_w, static_w, radii):
        # same as hairs.Rig.add_chain but with a configurable root bone name
        n = len(joints) - 1
        names = ['%s_%d' % (name, k + 1) for k in range(n)] + ['%s_End' % name]
        parent = self.root
        for k, bn in enumerate(names):
            head = joints[k]
            tail = joints[k + 1] if k < n else joints[k] + (joints[k] - joints[k - 1]) * 0.35
            self.bones.append((bn, head, tail, parent)); parent = bn
            self.W.setdefault(bn, np.zeros(len(self.P)))
        dyn = 1 - static_w
        self.W[self.root][verts] *= static_w
        for k in range(n):
            self.W[names[k]][verts] += chain_w[:, k] * dyn
        u, _ = project(self.P[verts], joints)
        tipshare = 0.5 * smoothstep(n - 0.35, n, u) * self.W[names[n - 1]][verts]
        self.W[names[n - 1]][verts] -= tipshare
        self.W[names[n]][verts] += tipshare
        self.chains.append((name, names, list(radii)))
        self.chain_verts[name] = np.array(verts)  # (texmap.py lays the texture out per chain)


def add_bangs(rig, prefix='BB', min_len=0.4, min_verts=12):
    """Bangs hang DOWN over the forehead, so the spike finder (which looks for tips pointing
    away from the head) skips them. Here every front vertex not already in a spike follows its
    lowest neighbour downhill; the vertices that end at the same lowest point form one lock,
    which gets a 2-bone chain fixed at the hairline and free at the tip."""
    P = rig.P
    free = rig.W[rig.root] > 0.999
    front = free & (P[:, 2] < -0.25) & (P[:, 1] < 0.7)
    down = np.arange(len(P))
    for v in np.where(front)[0]:
        best, by = v, P[v, 1]
        for u in rig.adj[v]:
            if front[u] and P[u, 1] < by - 1e-6:
                best, by = u, P[u, 1]
        down[v] = best
    locks = {}
    for v in np.where(front)[0]:
        x = v
        for _ in range(5000):
            if down[x] == x:
                break
            x = down[x]
        locks.setdefault(x, []).append(v)
    found = []
    for t, vs in locks.items():
        vs = np.array(vs)
        top, length = P[vs, 1].max(), P[vs, 1].max() - P[t, 1]
        if length >= min_len and len(vs) >= min_verts:
            found.append((t, vs, top, length))
    found.sort(key=lambda f: P[f[0], 0])  # left to right
    nb = 2
    for k, (t, vs, top, length) in enumerate(found):
        # centre line: average of the lock's vertices at decreasing height, ending at the tip
        bins = np.linspace(top, P[t, 1], 7)
        pts = []
        for a, b in zip(bins[:-1], bins[1:]):
            m = (P[vs, 1] <= a) & (P[vs, 1] > b)
            if m.any():
                pts.append(P[vs][m].mean(0))
        pts.append(P[t])
        joints = resample(np.vstack(pts), nb)
        joints[-1] = P[t]
        u = (top - P[vs, 1]) / max(length, 1e-3) * nb
        cw = chain_weights(u, nb)
        static = 1 - smoothstep(0.0, 0.4, u)  # the top stays fixed to the hairline
        rig.add_chain('%s%02d' % (prefix, k + 1), joints, vs, cw, static, [0.1] * (nb + 1))
    print('%s bang locks %d' % (rig.name, len(found)))


def spike_rig(name, path, prefix, min_tip_r, min_len, root, extra=None, bone_len=None, max_bones=3,
              bang_prefix=None, radius=None):
    # bone_len: aim for bones about this long (long spikes get more bones, up to max_bones); without
    # it a spike gets 2 bones under 0.9 studs, else 3 (how the base and SSJ hair were built).
    # bang_prefix: spikes whose tip hangs low in front of the face are named with this instead, so
    # they can be given floppier settings (HairConfig ChainOverrides).
    # every piece worn at the same time needs its own bone names: Roblox ties a skinned mesh to
    # the first bone with a matching name anywhere in the character, so two "HairRoot"s clash
    rig = DRig(name, path, CENTERS[name], root)
    P = rig.P
    r = np.linalg.norm(P * np.array([1, 0.9, 1]), axis=1)
    spikes, _ = spike_segments(P, rig.adj, r, min_len, 0.7)
    spikes = [(t, vs) for t, vs in spikes if r[t] >= min_tip_r]
    # stable order: by direction around the head, then height
    def key(s):
        p = P[s[0]]
        return (round(np.degrees(np.arctan2(p[0], -p[2])) / 10), p[1])
    spikes.sort(key=key)
    for n_, (t, vs) in enumerate(spikes):
        rt = r[t]
        rb = max(r[vs].min() + 0.05, 0.62)
        length = rt - rb
        if bone_len:
            nb = int(np.clip(round(length / bone_len), 2, max_bones))
        else:
            nb = 2 if length < 0.9 else 3
        # spike centre line: average of the spike's vertices at increasing distance from the head
        bins = np.linspace(rb, rt, 8)
        pts = []
        for a, b in zip(bins[:-1], bins[1:]):
            m = (r[vs] >= a) & (r[vs] < b)
            if m.any(): pts.append(P[vs][m].mean(0))
        pts.append(P[t])
        base_m = np.abs(r[vs] - rb) < 0.12
        root = P[vs][base_m].mean(0) if base_m.any() else pts[0]
        line = np.vstack([root] + pts[1:])
        joints = resample(line, nb)
        joints[-1] = P[t]
        u = (r[vs] - rb) / max(length, 1e-3) * nb
        cw = chain_weights(u, nb)
        static = 1 - smoothstep(0.0, 0.45, u)
        rad = radius(length) if radius else (0.16 if length > 1 else 0.12)
        tip = P[t]
        if bang_prefix and tip[2] < -0.6 and tip[1] < 0.6:
            chain_name = '%s%02d' % (bang_prefix, sum(1 for c in rig.chains if c[0].startswith(bang_prefix)) + 1)
        else:
            chain_name = '%s%02d' % (prefix, sum(1 for c in rig.chains if c[0].startswith(prefix)) + 1)
        rig.add_chain(chain_name, joints, vs, cw, static, [rad] * (nb + 1))
    print(name, 'spike chains', len(spikes), 'bones', sum(len(c[1]) for c in rig.chains))
    if extra:
        extra(rig)
    rig.finish()
    ensure_influence(rig)
    return rig


def ensure_influence(rig, share=0.12):
    """Roblox's importer deletes bones that move no vertex, and a missing bone breaks its chain.
    On low-poly spikes a bone can end up with no vertex (or only a sliver), so give the vertex
    of its chain nearest to the bone a small share of it."""
    W = rig.Wmat
    names = rig.bone_names
    head = {b[0]: np.array(b[1]) for b in rig.bones}
    fixed = []
    for cname, bones, _ in rig.chains:
        cols = [names.index(b) for b in bones]
        verts = np.where(W[:, cols].sum(1) > 0.01)[0]
        for b, j in zip(bones, cols):
            if W[:, j].max() >= 0.05 or len(verts) == 0:
                continue
            v = verts[np.argmin(np.linalg.norm(rig.P[verts] - head[b], axis=1))]
            row = W[v] * (1 - share)
            row[j] += share
            keep = np.argsort(row)[::-1][:4]
            if j not in keep:
                keep[-1] = j
            out = np.zeros_like(row); out[keep] = row[keep]
            W[v] = out / out.sum()
            fixed.append(b)
    if fixed:
        print(rig.name, 'gave a little weight to', len(fixed), 'bones that moved nothing:', fixed)


def build_base_hair(path):
    return spike_rig('BaseHair', path, 'BS', 1.15, 0.45, 'HairRoot', extra=add_bangs)


def build_ssj_hair(path):
    return spike_rig('SSJHair', path, 'SS', 1.2, 0.45, 'SSJRoot')


def build_ssj2_hair(path):
    # 2-3 bones per spike like the SSJ hair; the single bang that hangs over the forehead is
    # named S2B01 so it can be floppier than the spikes
    return spike_rig('SSJ2Hair', path, 'S2P', 1.2, 0.45, 'SSJ2Root', bang_prefix='S2B')


def build_ssj3_hair(path):
    # SSJ3 = the front piece (spikes, bangs) and the long mane that fans out behind and down to
    # the ankles, merged into one mesh. Tiny spikes near the scalp stay fixed (fewer chains to
    # simulate); long clumps get a bone every ~0.9 studs, up to 4.
    return spike_rig('SSJ3Hair', path, 'S3P', 1.3, 0.6, 'SSJ3Root', bone_len=0.9, max_bones=4,
                     bang_prefix='S3B', radius=lambda L: 0.12 if L < 1 else (0.16 if L < 2.2 else 0.22))


def build_belt(path):
    rig = DRig('Belt', path, CENTERS['Belt'], 'BeltRoot')
    st = rig.comp_stats()
    ribbons = [c for c, n, m, lo, hi in st if hi[1] - lo[1] > 0.6]  # the long hanging pieces
    for c in ribbons:
        side = 'L' if st[c][2][0] < 0 else 'R'
        idx = np.where(rig.cid == c)[0]
        top = rig.P[idx[np.argsort(-rig.P[idx, 1])[:3]]].mean(0)
        J = hairs.strand_joints(rig, [c], top, 3)
        verts, u, d = project_strands(rig.P, rig.adj, rig.cid, [c], J, top)
        cw = chain_weights(u, 3)
        static = 1 - smoothstep(-0.2, 0.3, u)
        rig.add_chain('Ribbon' + side, J, verts, cw, static, [0.12, 0.11, 0.1, 0.09])
        print('Ribbon' + side, np.round(J, 3).tolist())
    rig.finish()
    return rig
