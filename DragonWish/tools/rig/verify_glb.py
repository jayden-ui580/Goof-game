"""Reads the .glb hairs back (no Blender needed) and checks what Roblox will import: one skinned
mesh with texture coordinates, the texture packed inside, every bone where riginfo.json says it is,
at most 4 bones per vertex with weights adding up to 1.
usage: python verify_glb.py <folder with the .glb files> <riginfo.json> [piece names] [--render out.png]"""
import sys, json, struct, io, numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
SIZE = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    data = open(path, 'rb').read()
    magic, version, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67 and version == 2, 'not a glTF 2 binary'
    off, doc, binary = 12, None, b''
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(chunk)
        elif ctype == 0x004E4942:
            binary = chunk
        off += 8 + clen
    return doc, binary


def accessor(doc, binary, i):
    a = doc['accessors'][i]
    bv = doc['bufferViews'][a['bufferView']]
    dt = np.dtype(COMP[a['componentType']])
    n, k = a['count'], SIZE[a['type']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', dt.itemsize * k)
    raw = np.frombuffer(binary, np.uint8, count=stride * (n - 1) + dt.itemsize * k, offset=start)
    out = np.lib.stride_tricks.as_strided(raw, (n, dt.itemsize * k), (stride, 1)).copy().view(dt).reshape(n, k)
    if a.get('normalized'):
        out = out.astype(float) / np.iinfo(dt).max
    return out


def node_matrix(nd):
    if 'matrix' in nd:
        return np.array(nd['matrix'], float).reshape(4, 4).T
    t = np.array(nd.get('translation', [0, 0, 0]), float)
    x, y, z, w = nd.get('rotation', [0, 0, 0, 1])
    s = np.array(nd.get('scale', [1, 1, 1]), float)
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * s
    M[:3, 3] = t
    return M


def world_matrices(doc):
    parent = {}
    for i, nd in enumerate(doc['nodes']):
        for c in nd.get('children', []):
            parent[c] = i
    cache = {}
    def world(i):
        if i not in cache:
            M = node_matrix(doc['nodes'][i])
            cache[i] = world(parent[i]) @ M if i in parent else M
        return cache[i]
    return [world(i) for i in range(len(doc['nodes']))], parent


def check(path, info):
    doc, binary = read_glb(path)
    problems = []
    meshes = doc.get('meshes', [])
    prims = [p for m in meshes for p in m['primitives']]
    if len(meshes) != 1 or len(prims) != 1:
        problems.append('expected 1 mesh with 1 part, got %d meshes / %d parts' % (len(meshes), len(prims)))
    prim = prims[0]
    for attr in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'):
        if attr not in prim['attributes']:
            problems.append('mesh has no ' + attr)
    P = accessor(doc, binary, prim['attributes']['POSITION'])
    UV = accessor(doc, binary, prim['attributes']['TEXCOORD_0'])
    J = accessor(doc, binary, prim['attributes']['JOINTS_0']).astype(int)
    W = accessor(doc, binary, prim['attributes']['WEIGHTS_0']).astype(float)
    idx = accessor(doc, binary, prim['indices']).ravel()
    wsum = W.sum(1)
    if np.abs(wsum - 1).max() > 0.01:
        problems.append('weights off 1 by up to %.3f' % np.abs(wsum - 1).max())
    # material -> texture -> embedded image
    mat = doc['materials'][prim['material']]
    pbr = mat.get('pbrMetallicRoughness', {})
    img_info = None
    if 'baseColorTexture' not in pbr:
        problems.append('material has no colour texture')
    else:
        tex = doc['textures'][pbr['baseColorTexture']['index']]
        img = doc['images'][tex['source']]
        if 'bufferView' not in img:
            problems.append('texture is not packed inside the file')
        else:
            bv = doc['bufferViews'][img['bufferView']]
            raw = binary[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
            from PIL import Image
            im = Image.open(io.BytesIO(raw))
            img_info = (img.get('name'), img.get('mimeType'), im.size, len(raw), im)
    # skeleton
    skin = doc['skins'][0]
    joints = skin['joints']
    names = [doc['nodes'][j].get('name') for j in joints]
    worlds, parent = world_matrices(doc)
    expected = info['bones']
    missing = [b for b in expected if b not in names]
    extra = [n for n in names if n not in expected]
    if missing:
        problems.append('missing bones: %s' % missing[:5])
    err = 0
    for j, nm in zip(joints, names):
        if nm in expected:
            err = max(err, np.abs(worlds[j][:3, 3] - np.array(expected[nm])).max())
    if err > 2e-3:
        problems.append('bones off by up to %.4f studs' % err)
    # top of the skeleton: the hair's root bone, no extra empty node
    tops = [j for j in joints if j not in parent or parent[j] not in joints]
    top_names = [doc['nodes'][j].get('name') for j in tops]
    if top_names != [info['root']]:
        problems.append('skeleton top is %s, expected %s' % (top_names, info['root']))
    mesh_node = [i for i, nd in enumerate(doc['nodes']) if 'mesh' in nd]
    used = np.zeros(len(joints), bool)
    used[np.unique(J[W > 0])] = True
    unused = [names[i] for i in np.where(~used)[0]]
    if unused:
        problems.append('bones moving nothing (Roblox would drop them): %s' % unused[:6])
    # same vertices as the rig (positions)?
    size = P.max(0) - P.min(0)
    if np.abs(size - np.array(info['size'])).max() > 0.01:
        problems.append('size %s, expected %s' % (np.round(size, 3), info['size']))
    report = dict(verts=len(P), tris=len(idx) // 3, bones=len(joints), extra_nodes=len(doc['nodes']) - len(joints) - len(mesh_node),
                  max_influences=int((W > 0).sum(1).max()), bone_err=err, uv_range=(UV.min(0).round(3).tolist(), UV.max(0).round(3).tolist()),
                  texture=img_info[:4] if img_info else None, skeleton_top=top_names)
    return problems, report, (P, UV, idx, img_info[4] if img_info else None)


if __name__ == '__main__':
    args = sys.argv[1:]
    render_out = None
    if '--render' in args:
        k = args.index('--render'); render_out = args[k + 1]; del args[k:k + 2]
    folder, riginfo = args[0], args[1]
    info = {h['name']: h for h in json.load(open(riginfo))}
    names = args[2:] or ['BaseHair', 'SSJHair', 'SSJ2Hair', 'SSJ3Hair']
    tiles = []
    bad = 0
    for name in names:
        problems, rep, mesh = check('%s/%s_Rigged.glb' % (folder, name), info[name])
        print('%s_Rigged.glb: %s' % (name, 'OK' if not problems else 'PROBLEMS'))
        for k, v in rep.items():
            print('   %s: %s' % (k, v))
        for p in problems:
            print('   !! ' + p)
        bad += bool(problems)
        if render_out:
            sys.path.insert(0, __file__.rsplit('/', 1)[0])
            from texrender_lite import render
            P, UV, idx, im = mesh
            tex = np.asarray(im.convert('RGB')).astype(float) / 255
            tri_p = P[idx.reshape(-1, 3)]
            tri_uv = UV[idx.reshape(-1, 3)].copy()
            tri_uv[..., 1] = 1 - tri_uv[..., 1]  # glTF texture v runs down
            c = (P.min(0) + P.max(0)) / 2
            ext = np.abs(P - c).max() * 1.05
            tiles.append(np.concatenate([render(tri_p, tri_uv, tex, yw, size=300, center=c, extent=ext) for yw in (0, 90, 180)], 1))
    if render_out:
        from PIL import Image
        Image.fromarray(np.concatenate(tiles, 0)).save(render_out)
    sys.exit(1 if bad else 0)
