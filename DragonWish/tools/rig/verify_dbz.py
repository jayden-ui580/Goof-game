import sys, json, bpy, numpy as np
info = {i['name']: i for i in json.load(open(sys.argv[2]))}
# usage: verify_dbz.py <folder with the .fbx files> <riginfo.json> [piece names]
names = sys.argv[3:] or ['BaseHair', 'SSJHair', 'Belt', 'LeftFingers', 'RightFingers']
for fname, name in ((n + '_Rigged', n) for n in names):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=sys.argv[1] + '/' + fname + '.fbx')
    a = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
    m = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    err = 0
    for b in a.data.bones:
        w = a.matrix_world @ b.head_local
        err = max(err, np.abs(np.array([w.x, w.z, -w.y]) - np.array(info[name]['bones'][b.name])).max())
    inf = [len(v.groups) for v in m.data.vertices]
    vs = np.array([m.matrix_world @ v.co for v in m.data.vertices]); vs = vs[:, [0, 2, 1]]
    print(fname, 'bones', len(a.data.bones), 'bone error %.5f' % err, 'verts', len(m.data.vertices), 'max infl', max(inf), 'unweighted', inf.count(0), 'size', np.round(vs.max(0) - vs.min(0), 3), 'expected', info[name]['size'])
