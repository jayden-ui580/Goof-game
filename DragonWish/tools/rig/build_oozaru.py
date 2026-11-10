"""Builds the Oozaru for Roblox from GreatApe.fbx (Blender's Python module).

  * the jaw: in the original only the HEAD bone moves the mouth, so it can't open. The lower
    jaw (lower teeth, tongue, the floor of the mouth, the chin and lower lip, the beard) is
    re-weighted to the CHIN bone, whose pivot is moved back to the jaw hinge in front of the
    ears, with a soft blend toward the hinge so the cheeks stretch instead of tearing
  * the 90-odd helper bones nothing uses (AIM_, UTILITY_, ik_, roll bones ...) are removed
  * the 14 meshes are joined into 8 by colour: Fur, Skin, Face, Ink (the black linework),
    Mouth, Teeth, EarInner, Eyes. Every mesh in the original is a single flat colour (the game
    it came from tinted them with a toon shader), so each becomes one MeshPart with one Color
  * the two meshes over Roblox's 20,000-triangle limit (the fur body and the hands and feet)
    are decimated to fit
  * turned to face Roblox's front (-Z) and exported at 1 unit = 1 stud (about 10.8 tall; the
    game scales it up)
Writes models/Oozaru_Rigged.fbx + .blend, tools/rig/oozaru.json (bones, rest frames and
parents in Roblox space, for the game and the tests) and, with a third argument, an .npz of
the meshes for previews.
usage: python build_oozaru.py <GreatApe.fbx> <out folder> [preview.npz]
"""
import sys, os, json, math
import numpy as np
import bpy, bmesh
from mathutils import Matrix, Vector

SRC, OUT = sys.argv[1], sys.argv[2]
NPZ = sys.argv[3] if len(sys.argv) > 3 else None

GROUPS = {  # output mesh: original meshes (by the middle of their names)
    'Fur': ['BodyA', 'HeadF'],
    'Skin': ['BodyB'],
    'Face': ['HeadA'],
    'Ink': ['BodyC', 'BodyD', 'HeadC', 'HeadG'],
    'Mouth': ['HeadE', 'HeadD'],
    'Teeth': ['HeadH', 'HeadI'],
    'EarInner': ['HeadB'],
    'Eyes': ['Eyes'],
}
DECIMATE = {'BodyA': 0.56, 'BodyB': 0.62}  # keep this share of the triangles
KEEP_UNWEIGHTED = {'NULL', 'FACE', 'CHIN'}  # bones nothing deforms but we still need
JAW_HINGE = Vector((0.0, -0.55, 8.40))  # (Blender axes, before turning round) in front of the ears

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
scene = bpy.context.scene
arm = [o for o in scene.objects if o.type == 'ARMATURE'][0]
meshes = {o.name.split('_')[1]: o for o in scene.objects if o.type == 'MESH'}


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------------------------------
# 1. the jaw. Work in "face" coordinates: f = (x, height, forward) with forward = -Blender Y
# ------------------------------------------------------------------------------------------
def mouth_line(fwd):
    # the line between the upper and lower teeth: it rises toward the corners of the mouth
    return 8.30 - 0.2 * (max(fwd, 1.1) - 1.1)


def jaw_weight(co, soft=False):
    x, height, fwd = co.x, co.z, -co.y
    below = mouth_line(fwd) - height
    wv = smooth(-0.01, 0.05 if not soft else 0.12, below)
    wz = smooth(0.45, 1.0, fwd)  # nothing behind the hinge moves; the cheeks blend
    return wv * wz


def lower_tooth(centre):
    x, height, fwd = abs(centre.x), centre.z, -centre.y
    side_inner = x < 0.28 and fwd < 1.6  # the inner side rows (the upper rows sit outside them)
    incisors = abs(x - 0.06) < 0.025 and abs(fwd - 1.84) < 0.04  # small front teeth
    canines = abs(x - 0.15) < 0.025 and abs(fwd - 1.795) < 0.04  # small lower canines
    return side_inner or incisors or canines


def components(me):
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen, comps = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            u = stack.pop(); comp.append(u.index)
            for e in u.link_edges:
                w = e.other_vert(u)
                if w.index not in seen:
                    seen.add(w.index); stack.append(w)
        comps.append(comp)
    bm.free()
    return comps


def set_jaw(obj, weight_of):
    """move weight w(v) of each vertex onto CHIN, scaling its other influences by (1 - w)"""
    vg_chin = obj.vertex_groups.get('CHIN') or obj.vertex_groups.new(name='CHIN')
    moved = 0
    for v in obj.data.vertices:
        w = weight_of(v)
        if w <= 1e-3:
            continue
        for g in v.groups:
            if g.group != vg_chin.index:
                g.weight *= (1 - w)
        vg_chin.add([v.index], w, 'ADD')
        moved += 1
    return moved


for key in ('HeadA', 'HeadC', 'HeadE'):
    print('jaw', key, set_jaw(meshes[key], lambda v: jaw_weight(v.co)))
print('jaw HeadF', set_jaw(meshes['HeadF'], lambda v: jaw_weight(v.co, soft=True)))
print('jaw HeadD', set_jaw(meshes['HeadD'], lambda v: 1.0))  # tongue and lower gums
teeth = meshes['HeadH']
lower = set()
for comp in components(teeth.data):
    c = sum((teeth.data.vertices[i].co for i in comp), Vector()) / len(comp)
    if lower_tooth(c):
        lower.update(comp)
print('jaw HeadH (lower teeth)', set_jaw(teeth, lambda v: 1.0 if v.index in lower else 0.0))

# ------------------------------------------------------------------------------------------
# 2. bones: move the jaw pivot to the hinge, remove helpers nothing uses
# ------------------------------------------------------------------------------------------
weighted = set()
for o in meshes.values():
    names = {g.index: g.name for g in o.vertex_groups}
    for v in o.data.vertices:
        for g in v.groups:
            if g.weight > 1e-4:
                weighted.add(names[g.group])
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
chin = eb['CHIN']
length = (chin.tail - chin.head).length
chin.head = JAW_HINGE
chin.tail = JAW_HINGE + Vector((0, -length, 0))  # pointing forward along the jaw
removed = []
changed = True
while changed:  # leaves first, so whole unused branches go
    changed = False
    for b in list(eb):
        if b.name in weighted or b.name in KEEP_UNWEIGHTED or b.children:
            continue
        removed.append(b.name)
        eb.remove(b)
        changed = True
bpy.ops.object.mode_set(mode='OBJECT')
print('removed %d unused bones, %d left' % (len(removed), len(arm.data.bones)))

# ------------------------------------------------------------------------------------------
# 3. decimate the two big meshes (in the rest pose, before skinning), then join by colour
# ------------------------------------------------------------------------------------------
for key, ratio in DECIMATE.items():
    o = meshes[key]
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active = o
    mod = o.modifiers.new('Decimate', 'DECIMATE')
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_move_to_index(modifier='Decimate', index=0)
    bpy.ops.object.modifier_apply(modifier='Decimate')
    print('decimated', key, 'to', len(o.data.polygons), 'faces')

out_meshes = {}
for name, parts in GROUPS.items():
    objs = [meshes[p] for p in parts]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(bpy.data.materials.new(name))
    # vertex groups that weight nothing after joining
    used = set()
    for v in o.data.vertices:
        for g in v.groups:
            if g.weight > 1e-4:
                used.add(g.group)
    for g in list(o.vertex_groups):
        if g.index not in used:
            o.vertex_groups.remove(g)
    # at most 4 influences per vertex, normalised (Roblox's limit)
    names = {g.index: g.name for g in o.vertex_groups}
    for v in o.data.vertices:
        gs = sorted(((g.weight, g.group) for g in v.groups), reverse=True)
        keep = gs[:4]
        tot = sum(w for w, _ in keep) or 1.0
        for w, gi in gs[4:]:
            o.vertex_groups[names[gi]].remove([v.index])
        for w, gi in keep:
            o.vertex_groups[names[gi]].add([v.index], w / tot, 'REPLACE')
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print('mesh %-9s %6d triangles  %3d bones' % (name, tris, len(o.vertex_groups)))
    assert tris < 20000, name + ' is over the triangle limit'
    out_meshes[name] = o

# ------------------------------------------------------------------------------------------
# 4. turn round to face Roblox's front: Blender +Y here becomes Roblox -Z in the export
# ------------------------------------------------------------------------------------------
turn = Matrix.Rotation(math.pi, 4, 'Z')
for o in out_meshes.values():
    o.data.transform(turn)
    o.data.update()
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones:
    b.use_connect = False  # (a connected bone's head is its parent's tail: it would turn twice)
for b in arm.data.edit_bones:
    b.transform(turn)
bpy.ops.object.mode_set(mode='OBJECT')
arm.name = 'OozaruRig'
arm.data.name = 'OozaruRig'

# ------------------------------------------------------------------------------------------
# 5. export
# ------------------------------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
for o in out_meshes.values():
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'Oozaru_Rigged.blend'))
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, 'Oozaru_Rigged.fbx'), use_selection=True, object_types={'ARMATURE', 'MESH'},
    apply_scale_options='FBX_SCALE_UNITS', global_scale=1.0, axis_forward='-Z', axis_up='Y',
    use_mesh_modifiers=False, mesh_smooth_type='OFF', use_armature_deform_only=False,
    add_leaf_bones=False, primary_bone_axis='Y', secondary_bone_axis='X',
    armature_nodetype='NULL', bake_anim=False, path_mode='AUTO')

# rig info in Roblox axes: Blender (x, y, z) -> Roblox (x, z, -y)
R = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)
def rb(v):
    return [round(float(c), 5) for c in R @ np.array(v)]
bones = []
for b in arm.data.bones:
    M = np.array(arm.matrix_world @ b.matrix_local)
    rot = R @ M[:3, :3] @ R.T
    bones.append({'name': b.name, 'parent': b.parent.name if b.parent else None, 'head': rb(M[:3, 3]),
                  'tail': rb(arm.matrix_world @ b.tail_local), 'rot': [[round(float(c), 6) for c in row] for row in rot]})
lo = np.min([np.min(np.array([R @ np.array(v.co) for v in o.data.vertices]), 0) for o in out_meshes.values()], 0)
hi = np.max([np.max(np.array([R @ np.array(v.co) for v in o.data.vertices]), 0) for o in out_meshes.values()], 0)
info = {'bones': bones, 'meshes': {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in out_meshes.items()},
        'bounds': [lo.round(4).tolist(), hi.round(4).tolist()]}
json.dump(info, open(os.path.join(OUT, 'oozaru.json'), 'w'), indent=1)
print('bounds (Roblox axes)', info['bounds'])

if NPZ:
    bidx = {b.name: i for i, b in enumerate(arm.data.bones)}
    rest = []
    for b in arm.data.bones:
        M = np.array(arm.matrix_world @ b.matrix_local)
        M2 = np.eye(4); M2[:3, :3] = R @ M[:3, :3] @ R.T; M2[:3, 3] = R @ M[:3, 3]
        rest.append(M2)
    out = {'bones': np.array([b.name for b in arm.data.bones]),
           'parents': np.array([bidx[b.parent.name] if b.parent else -1 for b in arm.data.bones]),
           'rest': np.array(rest), 'meshes': np.array(list(out_meshes))}
    for name, o in out_meshes.items():
        me = o.data
        co = np.array([R @ np.array(v.co) for v in me.vertices])
        tris = []
        for p in me.polygons:
            vs = list(p.vertices)
            for k in range(1, len(vs) - 1):
                tris.append((vs[0], vs[k], vs[k + 1]))
        W = np.zeros((len(me.vertices), 4)); I = np.zeros((len(me.vertices), 4), int)
        gname = {g.index: g.name for g in o.vertex_groups}
        for v in me.vertices:
            gs = sorted([(g.weight, bidx[gname[g.group]]) for g in v.groups if gname[g.group] in bidx], reverse=True)[:4]
            for k, (w, bi) in enumerate(gs):
                W[v.index, k] = w; I[v.index, k] = bi
        out[name + '_V'] = co; out[name + '_T'] = np.array(tris); out[name + '_W'] = W; out[name + '_I'] = I
        out[name + '_C'] = np.array([1.0, 1.0, 1.0])
    np.savez_compressed(NPZ, **out)
    print('preview data', NPZ)
