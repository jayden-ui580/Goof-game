"""Shared mesh/skinning helpers for the hair rigs. All coordinates are Roblox
space (Y up, front = -Z) relative to the estimated head centre, in studs."""
import heapq, numpy as np

def load_obj(path, head):
    V, VT, VN, faces = [], [], [], []
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == 'v': V.append([float(x) for x in p[1:4]])
        elif p[0] == 'vt': VT.append([float(x) for x in p[1:3]])
        elif p[0] == 'vn': VN.append([float(x) for x in p[1:4]])
        elif p[0] == 'f':
            faces.append([tuple(int(i) - 1 if i else -1 for i in (t.split('/') + ['', ''])[:3]) for t in p[1:]])
    V = np.array(V) - np.array(head)
    return V, np.array(VT), np.array(VN), faces

def weld(V, tol=1e-4):
    q = np.round(V / tol).astype(np.int64)
    _, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    return V[first], inv.ravel()

def components(n, tris):
    par = np.arange(n)
    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]; a = par[a]
        return a
    for t in tris:
        a = find(t[0])
        for b in t[1:]:
            b = find(b)
            if a != b: par[b] = a
    roots = np.array([find(i) for i in range(n)])
    _, cid = np.unique(roots, return_inverse=True)
    return cid

def adjacency(n, tris, P):
    adj = [dict() for _ in range(n)]
    for t in tris:
        for i in range(3):
            a, b = t[i], t[(i + 1) % 3]
            d = float(np.linalg.norm(P[a] - P[b]))
            adj[a][b] = d; adj[b][a] = d
    return adj

def geodesic(adj, sources):
    dist = {s: 0.0 for s in sources}
    h = [(0.0, s) for s in sources]
    while h:
        d, a = heapq.heappop(h)
        if d > dist.get(a, 1e9): continue
        for b, w in adj[a].items():
            nd = d + w
            if nd < dist.get(b, 1e9):
                dist[b] = nd; heapq.heappush(h, (nd, b))
    return dist

def strand_centerline(P, adj, cid, comp_ids, root_pt, nbins=24):
    """Average the strands of a lock into one centre curve, ordered from root_pt to the tips."""
    pts = [[] for _ in range(nbins)]
    for c in comp_ids:
        idx = np.where(cid == c)[0]
        start = idx[np.argsort(np.linalg.norm(P[idx] - root_pt, axis=1))[:3]]
        g = geodesic(adj, list(start))
        gm = max(g[i] for i in idx)
        for i in idx:
            b = min(nbins - 1, int(g[i] / gm * nbins))
            pts[b].append(P[i])
    return np.array([np.mean(p, axis=0) for p in pts if p])

def resample(poly, n_seg, start=None):
    """Points at equal arc length along a polyline (n_seg segments -> n_seg+1 points)."""
    if start is not None: poly = np.vstack([start, poly])
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.r_[0, np.cumsum(seg)]
    out = []
    for k in range(n_seg + 1):
        t = s[-1] * k / n_seg
        j = min(np.searchsorted(s, t, side='right') - 1, len(seg) - 1)
        f = (t - s[j]) / seg[j] if seg[j] > 0 else 0
        out.append(poly[j] + (poly[j + 1] - poly[j]) * f)
    return np.array(out)

def project(points, joints):
    """Closest point on the joint polyline. Returns (u, distance) where u is measured in
    segments (1.5 = halfway along the 2nd segment). u < 0 before the root, > n past the tip."""
    n = len(joints) - 1
    best_d = np.full(len(points), np.inf); best_u = np.zeros(len(points))
    for k in range(n):
        a, b = joints[k], joints[k + 1]
        ab = b - a
        t = ((points - a) @ ab) / (ab @ ab)
        ts = np.clip(t, 0, 1)
        d = np.linalg.norm(points - (a + ts[:, None] * ab), axis=1)
        tu = ts.copy()
        if k == 0: tu = np.where(t < 0, t, tu)
        if k == n - 1: tu = np.where(t > 1, t, tu)
        m = d < best_d
        best_d[m] = d[m]; best_u[m] = k + tu[m]
    return best_u, best_d

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def chain_weights(u, n_seg):
    """Linear-blend weights along a chain of n_seg bones from the segment parameter u.
    Returns (n_points, n_seg) array. Each bone's weight peaks at the middle of its segment."""
    c = np.clip(u - 0.5, 0, n_seg - 1)
    lo = np.floor(c).astype(int); hi = np.minimum(lo + 1, n_seg - 1); f = c - lo
    W = np.zeros((len(u), n_seg))
    W[np.arange(len(u)), lo] += 1 - f
    W[np.arange(len(u)), hi] += f
    return W

def limit_influences(W, k=4, min_w=0.01):
    W = W.copy()
    for i in range(len(W)):
        row = W[i]
        if np.count_nonzero(row > 0) > k:
            row[np.argsort(row)[:-k]] = 0
        row[row < min_w] = 0
        s = row.sum()
        W[i] = row / s if s > 0 else row
    return W

def project_strands(P, adj, cid, comp_ids, joints, root_pt, window=0.35):
    """Like project(), but for curly strands: each vertex may only snap to the part of the
    chain whose arc length is close to the vertex's distance along its own strand (measured
    over the mesh from the end nearest root_pt). Stops the inside of a C-shaped curl from
    grabbing a bone from the other side of the curl."""
    seg = np.linalg.norm(np.diff(joints, axis=0), axis=1)
    s0 = np.r_[0, np.cumsum(seg)]
    n = len(joints) - 1
    verts = np.where(np.isin(cid, comp_ids))[0]
    sgeo = np.zeros(len(P))
    for c in comp_ids:
        idx = np.where(cid == c)[0]
        start = idx[np.argsort(np.linalg.norm(P[idx] - root_pt, axis=1))[:3]]
        start_s = project(P[start], joints)[0].clip(0, n)
        base = float(np.interp(start_s.mean(), np.arange(n + 1), s0))
        g = geodesic(adj, list(start))
        for i in idx: sgeo[i] = base + g[i]
    U = np.zeros(len(verts)); Dd = np.full(len(verts), np.inf)
    pts = P[verts]; sg = sgeo[verts]
    for k in range(n):
        a, b = joints[k], joints[k + 1]; ab = b - a
        t = ((pts - a) @ ab) / (ab @ ab); ts = np.clip(t, 0, 1)
        d = np.linalg.norm(pts - (a + ts[:, None] * ab), axis=1)
        tu = ts.copy()
        if k == 0: tu = np.where(t < 0, t, tu)
        if k == n - 1: tu = np.where(t > 1, t, tu)
        ok = (sg + window >= s0[k]) & (sg - window <= s0[k + 1])
        if k == n - 1: ok |= sg > s0[-1]
        d = np.where(ok, d, np.inf)
        m = d < Dd
        Dd[m] = d[m]; U[m] = k + tu[m]
    return verts, U, Dd
