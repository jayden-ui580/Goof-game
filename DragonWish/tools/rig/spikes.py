"""Splits spiky hair into spikes: every vertex climbs to the farthest-out neighbour (from the head
centre) until it reaches a tip; vertices that reach the same tip form one spike."""
import numpy as np
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rigcore import *

def spike_segments(P, adj, r, min_len, r_core):
    n = len(P)
    up = np.arange(n)
    for v in range(n):
        best, br = v, r[v]
        for u in adj[v]:
            if r[u] > br: best, br = u, r[u]
        up[v] = best
    tip = np.arange(n)
    for v in range(n):
        x = v
        seen = 0
        while up[x] != x and seen < 10000:
            x = up[x]; seen += 1
        tip[v] = x
    labels = {}
    for v in range(n):
        labels.setdefault(tip[v], []).append(v)
    spikes = []
    for t, vs in labels.items():
        vs = np.array(vs)
        length = r[t] - max(r_core, r[vs].min())
        if length >= min_len and len(vs) >= 6:
            spikes.append((t, vs))
    return spikes, tip

if __name__ == '__main__':
    import sys, matplotlib
    matplotlib.use('Agg'); import matplotlib.pyplot as plt
    name, H, out, r_core, min_len = sys.argv[1], [float(x) for x in sys.argv[2].split(',')], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
    V, VT, VN, F = load_obj(name, H)
    P, inv = weld(V)
    tris = np.array([[inv[c[0]] for c in f] for f in F])
    adj = adjacency(len(P), tris, P)
    # head is roughly a 1.2 box: measure "how far out" with a slightly squashed distance
    r = np.linalg.norm(P * np.array([1, 0.9, 1]), axis=1)
    spikes, tip = spike_segments(P, adj, r, min_len, r_core)
    print('spikes', len(spikes))
    for t, vs in sorted(spikes, key=lambda s: -len(s[1])):
        print('  tip %s r=%.2f verts %d base r %.2f' % (np.round(P[t], 2), r[t], len(vs), r[vs].min()))
    fig, axs = plt.subplots(1, 3, figsize=(21, 7))
    col = np.zeros(len(P)) - 1
    for n_, (t, vs) in enumerate(spikes): col[vs] = n_
    for ax, (i, j, nm) in zip(axs, ((0, 1, 'front'), (2, 1, 'side'), (0, 2, 'top'))):
        for f in tris:
            c = col[f[0]]
            ax.fill(P[f][:, i], P[f][:, j], color=(0.8, 0.8, 0.8) if c < 0 else plt.cm.tab20(int(c) % 20), alpha=0.5, lw=0)
        for t, vs in spikes: ax.plot(P[t][i], P[t][j], 'k.')
        ax.set_aspect('equal'); ax.set_title(nm)
    plt.tight_layout(); plt.savefig(out, dpi=50)
