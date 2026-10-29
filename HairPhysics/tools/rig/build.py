"""Builds the rigged hair in Blender (bpy) and exports FBX + a JSON of the rig layout."""
import sys, json, numpy as np, bpy
sys.path.insert(0, sys.argv[1]); import hairs
DATA, OUT = sys.argv[2], sys.argv[3]

def to_bl(v):   # Roblox (x, y up, z back) -> Blender (x, y back->-z... ) same mapping Blender's OBJ importer uses
    return (float(v[0]), float(-v[2]), float(v[1]))

def build(rig, fname):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
    # ---- mesh
    me = bpy.data.meshes.new(rig.name)
    me.from_pydata([to_bl(p) for p in rig.P], [], [tuple(int(i) for i in t) for t in rig.tris])
    me.update()
    uv = me.uv_layers.new(name='UVMap')
    loop_normals = []
    for poly, face in zip(me.polygons, rig.corner):
        for li, (vi, ti, ni) in zip(poly.loop_indices, face):
            uv.data[li].uv = tuple(rig.VT[ti]) if ti >= 0 else (0, 0)
            loop_normals.append(to_bl(rig.VN[ni]) if ni >= 0 else (0, 0, 1))
    me.normals_split_custom_set(loop_normals)
    mat = bpy.data.materials.new(rig.name + 'Mat'); me.materials.append(mat)
    mo = bpy.data.objects.new(rig.name, me); sc.collection.objects.link(mo)
    # ---- armature
    arm = bpy.data.armatures.new(rig.name + 'Rig')
    ao = bpy.data.objects.new(rig.name + 'Rig', arm); sc.collection.objects.link(ao)
    ao.show_in_front = True
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent in rig.bones:
        eb = arm.edit_bones.new(name)
        eb.head = to_bl(head); eb.tail = to_bl(tail)
        eb.use_deform = True; eb.use_connect = False
        if parent: eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    # ---- skin
    for j, bn in enumerate(rig.bone_names):
        vg = mo.vertex_groups.new(name=bn)
        col = rig.Wmat[:, j]
        for i in np.nonzero(col > 0)[0]:
            vg.add([int(i)], float(col[i]), 'REPLACE')
    mo.parent = ao
    mod = mo.modifiers.new('Armature', 'ARMATURE'); mod.object = ao
    # ---- save + export
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
        'name': rig.name,
        'bones': {b[0]: [round(float(c), 4) for c in b[1]] for b in rig.bones},
        'chains': [{'name': c[0], 'bones': c[1], 'radii': c[2]} for c in rig.chains],
        'size': [round(float(c), 4) for c in (rig.P.max(0) - rig.P.min(0))],
        'center': [round(float(c), 4) for c in (rig.P.max(0) + rig.P.min(0)) / 2],
    }

info = [build(hairs.build_pigtails(DATA + '/Pigtails.obj'), 'Pigtails_Rigged'),
        build(hairs.build_hair1(DATA + '/hair1.obj'), 'LadyHair_Rigged')]
json.dump(info, open(OUT + '/riginfo.json', 'w'), indent=1)
print('built', [i['name'] for i in info])
