"""Tiny textured z-buffer renderer for checking hair texture layouts (verify_glb.py --render uses
it). Roblox axes: Y up, front = -Z; yaw 0 looks at the face.
usage: python texrender_lite.py out.png texture.png obj1[,obj2...] [yaw list]"""
import sys, numpy as np
from PIL import Image

def load_obj(path):
    V, VT, VN, F = [], [], [], []
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == 'v': V.append([float(x) for x in p[1:4]])
        elif p[0] == 'vt': VT.append([float(x) for x in p[1:3]])
        elif p[0] == 'f':
            F.append([tuple(int(i) - 1 if i else -1 for i in (t.split('/') + ['', ''])[:3]) for t in p[1:]])
    V = np.array(V); VT = np.array(VT) if VT else np.zeros((1, 2))
    tri_p = np.array([[V[c[0]] for c in f[:3]] for f in F])
    tri_uv = np.array([[VT[c[1]] if c[1] >= 0 else (0, 0) for c in f[:3]] for f in F])
    return tri_p, tri_uv

def render(tri_p, tri_uv, tex, yaw_deg, size=420, center=None, extent=None, light=(-0.4, 0.6, -0.7), flat=False, tri_col=None, pitch_deg=0):
    th = np.radians(yaw_deg)
    R = np.array([[np.cos(th), 0, np.sin(th)], [0, 1, 0], [-np.sin(th), 0, np.cos(th)]])
    ph = np.radians(pitch_deg)
    R = np.array([[1, 0, 0], [0, np.cos(ph), -np.sin(ph)], [0, np.sin(ph), np.cos(ph)]]) @ R
    if center is None: center = tri_p.reshape(-1, 3).mean(0)
    P = (tri_p - center) @ R.T
    if extent is None: extent = np.abs(P[..., :2]).max() * 1.05
    s = size / (2 * extent)
    X = P[..., 0] * -s + size / 2   # camera in front (-Z) looking at +Z: the wearer's right (+X) appears on the left
    Y = -P[..., 1] * s + size / 2
    Z = P[..., 2]
    img = np.ones((size, size, 3)) * 0.93
    zb = np.full((size, size), np.inf)
    th_, tw_ = tex.shape[:2]
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    L = np.array(light); L = L / np.linalg.norm(L)
    shade = 0.55 + 0.45 * np.abs(n @ L)
    for k in range(len(P)):
        x, y, z = X[k], Y[k], Z[k]
        x0, x1 = int(max(0, np.floor(x.min()))), int(min(size - 1, np.ceil(x.max())))
        y0, y1 = int(max(0, np.floor(y.min()))), int(min(size - 1, np.ceil(y.max())))
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(d) < 1e-9: continue
        a = ((y[1] - y[2]) * (gx - x[2]) + (x[2] - x[1]) * (gy - y[2])) / d
        b = ((y[2] - y[0]) * (gx - x[2]) + (x[0] - x[2]) * (gy - y[2])) / d
        c = 1 - a - b
        m = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6)
        if not m.any(): continue
        zz = a * z[0] + b * z[1] + c * z[2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= zz < sub
        if not m.any(): continue
        sub[m] = zz[m]
        uv = a[..., None] * tri_uv[k, 0] + b[..., None] * tri_uv[k, 1] + c[..., None] * tri_uv[k, 2]
        tu = np.clip((uv[..., 0] % 1.0) * tw_, 0, tw_ - 1).astype(int)
        tv = np.clip((1 - uv[..., 1] % 1.0) * th_, 0, th_ - 1).astype(int)
        if tri_col is not None and not np.isnan(tri_col[k, 0]):
            col = np.broadcast_to(tri_col[k] * shade[k], tu.shape + (3,))
        else:
            col = tex[tv, tu] * (1.0 if flat else shade[k])
        img[y0:y1 + 1, x0:x1 + 1][m] = col[m]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)

if __name__ == '__main__':
    out, texpath = sys.argv[1], sys.argv[2]
    objs = sys.argv[3].split(',')
    yaws = [float(a) for a in sys.argv[4].split(',')] if len(sys.argv) > 4 else [0, 90, 180, 270]
    tex = np.asarray(Image.open(texpath).convert('RGB')).astype(float) / 255
    parts = [load_obj(o) for o in objs]
    tri_p = np.concatenate([p for p, _ in parts]); tri_uv = np.concatenate([u for _, u in parts])
    center = (tri_p.reshape(-1, 3).min(0) + tri_p.reshape(-1, 3).max(0)) / 2
    ext = np.abs(tri_p.reshape(-1, 3) - center).max() * 1.05
    tiles = [render(tri_p, tri_uv, tex, yw, center=center, extent=ext) for yw in yaws]
    Image.fromarray(np.concatenate(tiles, axis=1)).save(out)
