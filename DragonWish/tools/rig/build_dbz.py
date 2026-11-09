"""Builds the Dragon Wish rigs in Blender (bpy): FBX + .blend + riginfo json."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, bpy
import hairs, dbz, fingers
DATA, OUT = sys.argv[1], sys.argv[2]

_finish = hairs.Rig.finish
hairs.Rig.finish = lambda self, smooth_iters=6: _finish(self, smooth_iters)

def to_bl(v):
    return (float(v[0]), float(-v[2]), float(v[1]))

def build(rig, fname, attach):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    me = bpy.data.meshes.new(rig.name)
    me.from_pydata([to_bl(p) for p in rig.P], [], [tuple(int(i) for i in t) for t in rig.tris])
    me.update()
    uv = me.uv_layers.new(name='UVMap')
    normals = []
    for poly, face in zip(me.polygons, rig.corner):
        for li, (vi, ti, ni) in zip(poly.loop_indices, face):
            uv.data[li].uv = tuple(rig.VT[ti]) if ti >= 0 else (0, 0)
            normals.append(to_bl(rig.VN[ni]) if ni >= 0 else (0, 0, 1))
    me.normals_split_custom_set(normals)
    me.materials.append(bpy.data.materials.new(rig.name + 'Mat'))
    mo = bpy.data.objects.new(rig.name, me); sc.collection.objects.link(mo)
    arm = bpy.data.armatures.new(rig.name + 'Rig')
    ao = bpy.data.objects.new(rig.name + 'Rig', arm); sc.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent in rig.bones:
        eb = arm.edit_bones.new(name)
        eb.head = to_bl(head); eb.tail = to_bl(tail)
        if np.linalg.norm(np.array(eb.tail) - np.array(eb.head)) < 1e-4:
            eb.tail = to_bl(head + np.array([0, 0.1, 0]))
        eb.use_deform = True; eb.use_connect = False
        if parent: eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for j, bn in enumerate(rig.bone_names):
        vg = mo.vertex_groups.new(name=bn)
        col = rig.Wmat[:, j]
        for i in np.nonzero(col > 0)[0]:
            vg.add([int(i)], float(col[i]), 'REPLACE')
    mo.parent = ao
    mod = mo.modifiers.new('Armature', 'ARMATURE'); mod.object = ao
    bpy.ops.object.select_all(action='DESELECT')
    mo.select_set(True); ao.select_set(True); bpy.context.view_layer.objects.active = ao
    bpy.ops.wm.save_as_mainfile(filepath=OUT + '/' + fname + '.blend')
    bpy.ops.export_scene.fbx(
        filepath=OUT + '/' + fname + '.fbx', use_selection=True, object_types={'ARMATURE', 'MESH'},
        apply_scale_options='FBX_SCALE_UNITS', global_scale=1.0, axis_forward='-Z', axis_up='Y',
        use_mesh_modifiers=False, mesh_smooth_type='OFF', use_armature_deform_only=True,
        add_leaf_bones=False, primary_bone_axis='Y', secondary_bone_axis='X',
        armature_nodetype='NULL', bake_anim=False, path_mode='AUTO')
    return {
        'name': rig.name, 'attach': attach, 'root': rig.root,
        'bones': {b[0]: [round(float(c), 4) for c in b[1]] for b in rig.bones},
        'chains': [{'name': c[0], 'bones': c[1], 'radii': c[2]} for c in rig.chains],
        'size': [round(float(c), 4) for c in (rig.P.max(0) - rig.P.min(0))],
        'weights_per_bone': {n: int((rig.Wmat[:, j] > 0.05).sum()) for j, n in enumerate(rig.bone_names)},
    }

# usage: build_dbz.py <folder with the .obj files> <output folder> [piece names to rebuild]
# With piece names, only those are rebuilt and their entries replaced in <output>/riginfo.json.
PIECES = {
    'BaseHair': lambda: build(dbz.build_base_hair(DATA + '/BaseHair.obj'), 'BaseHair_Rigged', 'Head'),
    'SSJHair': lambda: build(dbz.build_ssj_hair(DATA + '/SSJHair.obj'), 'SSJHair_Rigged', 'Head'),
    'Belt': lambda: build(dbz.build_belt(DATA + '/Belt.obj'), 'Belt_Rigged', 'LowerTorso'),
    'LeftFingers': lambda: build(fingers.build_fingers('L', DATA + '/TakeTheFingers.obj', DATA + '/R15_body.obj'), 'LeftFingers_Rigged', 'LeftHand'),
    'RightFingers': lambda: build(fingers.build_fingers('R', DATA + '/TakeTheFingers.obj', DATA + '/R15_body.obj'), 'RightFingers_Rigged', 'RightHand'),
}
only = sys.argv[3:]
if only:
    old = json.load(open(OUT + '/riginfo.json'))
    fresh = {name: PIECES[name]() for name in only}
    for h in fresh.values():
        prev = next((o for o in old if o['name'] == h['name']), None)
        if prev and 'ring' in prev:
            h['ring'] = prev['ring']  # measured separately by belt_ring.py
    info = [fresh.get(o['name'], o) for o in old]
    info += [h for name, h in fresh.items() if not any(o['name'] == name for o in old)]
else:
    info = [PIECES[name]() for name in ('BaseHair', 'SSJHair', 'Belt', 'LeftFingers', 'RightFingers')]
json.dump(info, open(OUT + '/riginfo.json', 'w'), indent=1)
print('built', [(i['name'], len(i['bones'])) for i in info])
print('bones with < 1 weighted vertex:', [n for i in info for n, c in i['weights_per_bone'].items() if c < 1])
