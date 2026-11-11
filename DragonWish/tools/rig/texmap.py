"""Puts the hair texture (Handle1_diff.png, which came with SSJ2/SSJ3: an anime drawing of
golden spikes with cream highlights, brown shadows and ink lines on a plain golden base) on a
hair that wasn't made for it (the old SSJ hair, the base hair).

strokes.py found the drawn highlights in the texture and saved a frame for each (hair_strokes.json):
a centre line from its root end to its tip, and a half-width that takes in the shadow and ink
lines drawn beside it. Then for the hair:
  1. every chain (spike / bang) gets its own measuring frame: s along it (0 at the root, 1 at the
     tip) and t across its flat side (-1 one edge, +1 the other);
  2. each chain is paired with a drawn highlight pointing the same way in a front view (the
     drawing is the hair seen from the front), longer spikes with longer highlights, and each
     highlight is shared out as evenly as possible (a reused one is mirrored);
  3. every triangle belongs to one chain (or to the scalp), and its corners land on that chain's
     highlight at their own (s, t). So the highlight runs along the spike, and spikes never smear
     into each other: each spike is its own island in the texture.
The scalp between spikes (and the big dome of the base hair) shows the drawing as seen from the
front, scaled so the drawn spikes fan out from the face like the hair does: front-on it reads as
strands sweeping up and out, from the side as strands combed back. Each spike blends into it at
its root.
"""
import json
import numpy as np
from rigcore import project, smoothstep

FRONT = np.array([0.0, 0.0, 1.0])
UP = np.array([0.0, 1.0, 0.0])
# where the head centre lands in the drawing, and texture units per stud (measured from the SSJ2
# and SSJ3 UVs, which are close to a front view of the hair at about this scale)
CAP_CENTRE = np.array([0.45, 0.30])
CAP_SCALE = 0.2


def cap_uv(X):
    """The drawing seen from the front: the wearer's right is on the left of the drawing."""
    return CAP_CENTRE + CAP_SCALE * np.c_[-X[:, 0], X[:, 1]]


def _axes(J):
    seg = np.diff(J, axis=0)
    return seg / (np.linalg.norm(seg, axis=1, keepdims=True) + 1e-9)


def _lateral(J, X):
    """Distance along the chain (u, in segments) and the sideways offset of points X."""
    n = len(J) - 1
    u, _ = project(X, J)
    uc = np.clip(u, 0, n - 1e-6)
    k = np.floor(uc).astype(int)
    f = uc - k
    C = J[k] + (J[k + 1] - J[k]) * f[:, None]
    A = _axes(J)[k]
    L = X - C
    L -= (L * A).sum(1, keepdims=True) * A
    return u, L, A


class Chain:
    """One spike's measuring frame: s along it, t across its flat side."""

    def __init__(self, J, X):
        self.J = np.asarray(J, float)
        self.n = len(J) - 1
        u, L, A = _lateral(self.J, X)
        # the spike's flat direction (anime spikes are blades): the main spread of the sideways
        # offsets, signed so that +t is on the same side for every spike seen from the front
        w = np.linalg.eigh(L.T @ L)[1][:, -1]
        a = self.J[-1] - self.J[0]
        self.length = float(np.linalg.norm(np.diff(self.J, axis=0), axis=1).sum())
        a /= np.linalg.norm(a) + 1e-9
        ref = np.cross(a, FRONT)
        if np.linalg.norm(ref) < 0.3:
            ref = np.cross(a, UP)
        if w @ ref < 0:
            w = -w
        self.w = w
        self.axis = a
        # half width along the spike (90th percentile of the offsets, per sixth of its length)
        s = u / self.n
        tw = np.abs(self._across(L, A))
        edges = np.linspace(0, 1, 7)
        mids, hw = [], []
        for lo, hi in zip(edges[:-1], edges[1:]):
            m = (s >= lo) & (s < hi)
            if m.sum() >= 3:
                mids.append((lo + hi) / 2)
                hw.append(np.percentile(tw[m], 90))
        if not mids:
            mids, hw = [0.5], [max(np.percentile(tw, 90), 0.05)]
        self.hw_s = np.array(mids)
        self.hw = np.maximum(np.array(hw), 0.03)

    def _across(self, L, A):
        wk = self.w[None, :] - (self.w[None, :] * A).sum(1, keepdims=True) * A
        wk /= np.linalg.norm(wk, axis=1, keepdims=True) + 1e-9
        return (L * wk).sum(1)

    def coords(self, X):
        u, L, A = _lateral(self.J, X)
        s = u / self.n
        hw = np.interp(np.clip(s, 0, 1), self.hw_s, self.hw)
        return s, self._across(L, A) / hw

    def front_direction(self):
        """Which way the spike points in the drawing (u right, v up; the drawing faces the
        viewer, so the wearer's right is on the left) and how much of it shows from the front."""
        d = np.array([-self.axis[0], self.axis[1]])
        return d / (np.linalg.norm(d) + 1e-9), float(np.linalg.norm(d))


class Highlight:
    """A drawn highlight: uv(s, t) = point s along its centre line, t half-widths to the side."""

    def __init__(self, frame):
        self.curve = np.array(frame['curve'], float)
        self.half = float(frame['halfwidth'])
        seg = np.linalg.norm(np.diff(self.curve, axis=0), axis=1)
        self.arc = np.r_[0, np.cumsum(seg)] / seg.sum()
        self.length = float(seg.sum())
        d = self.curve[-1] - self.curve[0]
        self.direction = d / (np.linalg.norm(d) + 1e-9)

    def uv(self, s, t, mirror=False):
        # the spike's root starts a little before the highlight and its tip ends just past it
        g = -0.1 + 1.12 * np.clip(s, 0, 1)
        gc = np.clip(g, 0, 1)
        P = np.stack([np.interp(gc, self.arc, self.curve[:, i]) for i in (0, 1)], 1)
        tang = np.gradient(self.curve, self.arc, axis=0)
        T = np.stack([np.interp(gc, self.arc, tang[:, i]) for i in (0, 1)], 1)
        T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-9
        P += T * ((g - gc) * self.length)[:, None]  # carry on straight past either end
        N = np.c_[-T[:, 1], T[:, 0]]
        tt = np.clip(t, -1, 1) * (-1 if mirror else 1)
        return P + N * (tt * self.half)[:, None]


def load_highlights(path):
    return [Highlight(f) for f in json.load(open(path))]


def chain_membership(rig):
    names = [c[0] for c in rig.chains]
    chain_of = np.full(len(rig.P), -1)
    for i, name in enumerate(names):
        vs = rig.chain_verts.get(name)
        if vs is not None and len(vs):
            chain_of[vs] = i
    return names, chain_of


def face_owners(tris, chain_of):
    """Each triangle belongs to the chain most of its corners belong to (-1 = scalp)."""
    owner = np.full(len(tris), -1)
    for f, tri in enumerate(tris):
        c = [int(chain_of[v]) for v in tri]
        owner[f] = max(set(c), key=lambda x: (c.count(x), x >= 0))
    return owner


def chain_joints(rig, name):
    return np.array([b[1] for b in rig.bones if b[0].startswith(name + '_')])


def layout(rig, highlights, reuse_penalty=0.35, verbose=True):
    """New texture coordinates for every triangle corner of rig.tris (shape: faces x 3 x 2)."""
    names, chain_of = chain_membership(rig)
    owner = face_owners(rig.tris, chain_of)
    frames = {i: Chain(chain_joints(rig, n), rig.P[rig.chain_verts[n]]) for i, n in enumerate(names)}
    longest = max(f.length for f in frames.values())
    hl_longest = max(h.length for h in highlights)
    uses = np.zeros(len(highlights))
    pick = {}
    # long spikes choose first: they show the most
    for i in sorted(frames, key=lambda i: -frames[i].length):
        d, shows = frames[i].front_direction()
        rel = frames[i].length / longest
        score = []
        for k, h in enumerate(highlights):
            sc = shows * float(d @ h.direction)
            sc -= 0.4 * abs(np.log(max(rel, 0.05) / max(h.length / hl_longest, 0.05)))
            sc -= reuse_penalty * uses[k]
            score.append(sc)
        k = int(np.argmax(score))
        pick[i] = (k, uses[k] % 2 == 1)  # every second use of a highlight is mirrored
        uses[k] += 1
    uv = np.zeros((len(rig.tris), 3, 2))
    for f in range(len(rig.tris)):
        X = rig.P[rig.tris[f]]
        cap = cap_uv(X)
        i = owner[f]
        if i < 0:
            uv[f] = cap
            continue
        s, t = frames[i].coords(X)
        k, mirror = pick[i]
        spot = highlights[k].uv(s, t, mirror)
        fade = smoothstep(-0.35, -0.05, s)[:, None]  # below the spike's root: blend into the scalp
        uv[f] = cap + (spot - cap) * fade
    uv = np.clip(uv, 0.002, 0.998)
    if verbose:
        print('%s: %d chains textured from %d drawn highlights (%d used, most %d times), %d scalp triangles' % (
            rig.name, len(names), len(highlights), int((uses > 0).sum()), int(uses.max()), int((owner < 0).sum())))
    return uv
