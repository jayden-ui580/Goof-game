"""Builds the Dragon Wish rigs in Blender (bpy): .blend + riginfo json, and
   - the hairs as .glb (glTF with the texture packed inside, so it comes in with the import)
   - the belt and fingers as .fbx (untextured: the game colours them)."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, bpy
import hairs, dbz, fingers, texmap
DATA, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))

_finish = hairs.Rig.finish
hairs.Rig.finish = lambda self, smooth_iters=6: _finish(self, smooth_iters)

def to_bl(v):
    return (float(v[0]), float(-v[2]), float(v[1]))

def textured_material(name, texture):
    """A plain material whose colour is the texture (no shine): glTF exports it as baseColor."""
    mat = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True  # (always on from Blender 5)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    img = bpy.data.images.load(texture)
    img.name = os.path.splitext(os.path.basename(texture))[0]
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Roughness'].default_value = 1.0
    mat.use_backface_culling = True  # one-sided, like the original Roblox hair (glTF doubleSided off)
    return mat

def build(rig, fname, attach, texture=None, uvs=None):
    """uvs: texture coordinates per triangle corner (faces x 3 x 2); default = the .obj's own."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    # Blender can't hold a triangle whose corners were welded together, or two triangles on the
    # same three corners (the SSJ2/SSJ3 meshes have both: double-sided spots are a front and a back
    # triangle). Collapsed triangles are dropped; a second triangle on the same corners gets its
    # own copies of them (same place, same skin weights), so it still shows from behind.
    verts = [to_bl(p) for p in rig.P]
    copies = []  # (new vertex, the vertex it copies)
    faces, kept, seen = [], [], set()
    for f, t in enumerate(rig.tris):
        t = [int(i) for i in t]
        if len(set(t)) < 3:
            continue
        key = tuple(sorted(t))
        if key in seen:
            fresh = []
            for i in t:
                verts.append(verts[i])
                copies.append((len(verts) - 1, i))
                fresh.append(len(verts) - 1)
            t = fresh
        seen.add(tuple(sorted(t)))
        faces.append(t)
        kept.append(f)
    if len(kept) < len(rig.tris) or copies:
        print('%s: dropped %d collapsed triangles, %d corners copied for double-sided spots' % (
            rig.name, len(rig.tris) - len(kept), len(copies)))
    me = bpy.data.meshes.new(rig.name)
    me.from_pydata(verts, [], faces)
    me.update()
    uv = me.uv_layers.new(name='UVMap')
    normals = []
    for poly, f in zip(me.polygons, kept):
        face = rig.corner[f]
        for c, (li, (vi, ti, ni)) in enumerate(zip(poly.loop_indices, face)):
            if uvs is not None:
                uv.data[li].uv = tuple(float(x) for x in uvs[f][c])
            else:
                uv.data[li].uv = tuple(rig.VT[ti]) if ti >= 0 else (0, 0)
            normals.append(to_bl(rig.VN[ni]) if ni >= 0 else (0, 0, 1))
    me.normals_split_custom_set(normals)
    if texture:
        me.materials.append(textured_material(rig.name + 'Mat', texture))
    else:
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
        for new_i, old_i in copies:
            if col[old_i] > 0:
                vg.add([new_i], float(col[old_i]), 'REPLACE')
    mo.parent = ao
    mod = mo.modifiers.new('Armature', 'ARMATURE'); mod.object = ao
    bpy.ops.object.select_all(action='DESELECT')
    mo.select_set(True); ao.select_set(True); bpy.context.view_layer.objects.active = ao
    if texture:
        bpy.ops.file.pack_all()  # keep the texture inside the .blend too
    bpy.ops.wm.save_as_mainfile(filepath=OUT + '/' + fname + '.blend')
    if texture:
        # glTF binary: mesh, bones, skin weights and the texture in one file. The armature stays
        # as an empty node above the hair's root bone (at 0, 0, 0): the same layout as the .fbx
        # hairs that already import fine.
        bpy.ops.export_scene.gltf(
            filepath=OUT + '/' + fname + '.glb', export_format='GLB', use_selection=True,
            export_yup=True, export_apply=False, export_texcoords=True, export_normals=True,
            export_tangents=False, export_materials='EXPORT', export_image_format='AUTO',
            export_vertex_color='NONE', export_skins=True, export_def_bones=False,
            export_armature_object_remove=False, export_leaf_bone=False,
            export_animations=False, export_extras=False)
    else:
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

def painted(rig):
    """New texture coordinates that lay the drawn highlights along this hair's spikes."""
    return texmap.layout(rig, texmap.load_highlights(HERE + '/hair_strokes.json'))

# usage: build_dbz.py <folder with the .obj and .png files> <output folder> [piece names to rebuild]
# With piece names, only those are rebuilt and their entries replaced in <output>/riginfo.json.
GOLD, BLACK = DATA + '/HairGold.png', DATA + '/HairBlack.png'

def base_hair():
    rig = dbz.build_base_hair(DATA + '/BaseHair.obj')
    return build(rig, 'BaseHair_Rigged', 'Head', texture=BLACK, uvs=painted(rig))

def ssj_hair():
    rig = dbz.build_ssj_hair(DATA + '/SSJHair.obj')
    return build(rig, 'SSJHair_Rigged', 'Head', texture=GOLD, uvs=painted(rig))

PIECES = {
    'BaseHair': base_hair,
    'SSJHair': ssj_hair,
    # SSJ2 / SSJ3 came with their own texture coordinates for the gold texture
    'SSJ2Hair': lambda: build(dbz.build_ssj2_hair(DATA + '/SSJ2Hair.obj'), 'SSJ2Hair_Rigged', 'Head', texture=GOLD),
    'SSJ3Hair': lambda: build(dbz.build_ssj3_hair(DATA + '/SSJ3Hair.obj'), 'SSJ3Hair_Rigged', 'Head', texture=GOLD),
    'Belt': lambda: build(dbz.build_belt(DATA + '/Belt.obj'), 'Belt_Rigged', 'LowerTorso'),
    'LeftFingers': lambda: build(fingers.build_fingers('L', DATA + '/TakeTheFingers.obj', DATA + '/R15_body.obj'), 'LeftFingers_Rigged', 'LeftHand'),
    'RightFingers': lambda: build(fingers.build_fingers('R', DATA + '/TakeTheFingers.obj', DATA + '/R15_body.obj'), 'RightFingers_Rigged', 'RightHand'),
}
ORDER = ('BaseHair', 'SSJHair', 'SSJ2Hair', 'SSJ3Hair', 'Belt', 'LeftFingers', 'RightFingers')
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
    info.sort(key=lambda h: ORDER.index(h['name']) if h['name'] in ORDER else 99)
else:
    info = [PIECES[name]() for name in ORDER]
json.dump(info, open(OUT + '/riginfo.json', 'w'), indent=1)
print('built', [(i['name'], len(i['bones'])) for i in info])
print('bones with < 1 weighted vertex:', [n for i in info for n, c in i['weights_per_bone'].items() if c < 1])
