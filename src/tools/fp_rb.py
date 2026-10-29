"""First-person arms cut from a real Rocketbox avatar (realistic textures, sleeves, gloves),
posed per weapon with the IK code from fp_hands.py and baked in weapon space.
Usage: blender-python tools/fp_rb.py [weapon ids...]   (env FP_AVATAR=Professions/Military_Male_01)
"""
import sys, os
import bpy
sys.path.insert(0, os.path.dirname(__file__))
import characters as C
import rocketbox as R
import fp_hands as F

AVATAR = os.environ.get('FP_AVATAR', 'Professions/Military_Male_01')


def build_base_rb():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = C.load_soldier()
    before = set(bpy.data.objects)
    exp = os.path.join(R.RB, AVATAR, 'Export')
    fbx = [f for f in os.listdir(exp) if f.endswith('.fbx') and 'facial' not in f][0]
    bpy.ops.import_scene.fbx(filepath=os.path.join(exp, fbx), automatic_bone_orientation=True)
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == 'ARMATURE'][0]
    mesh = [o for o in new if o.type == 'MESH'][0]
    for o in new:
        if o.type == 'EMPTY':
            bpy.data.objects.remove(o, do_unlink=True)
    for o in (arm, mesh):
        o.animation_data_clear()
    for a in list(bpy.data.actions):
        if not a.name.startswith('SRC_'):
            bpy.data.actions.remove(a)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    with bpy.context.temp_override(active_object=arm, selected_editable_objects=[arm, mesh], selected_objects=[arm, mesh]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    R.setup_materials(mesh, AVATAR)
    if mesh.data.shape_keys:
        mesh.shape_key_clear()
    R.align_tpose(arm, mesh, src)
    for o in list(bpy.data.objects):
        if o not in (arm, mesh):
            bpy.data.objects.remove(o, do_unlink=True)
    # rename Bip01 bones to mixamo names (vertex groups follow automatically)
    inv = {v: k for k, v in R.M2B.items()}
    for b in arm.data.bones:
        if b.name.startswith('Bip01 ') and b.name[6:] in inv:
            b.name = 'mixamorig:' + inv[b.name[6:]]
    arm.animation_data_clear()
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    return mesh, arm


def main(wids):
    body, rig = build_base_rb()
    for wid in wids:
        F.pose_for(wid, body, rig)
        obj = F.bake_and_cut(body, rig, wid)
        for p in obj.data.polygons:
            p.use_smooth = True
        sub = obj.modifiers.new('sub', 'SUBSURF'); sub.levels = 1; sub.render_levels = 1
        F.export([obj], wid)
        if os.environ.get('PREVIEW'):
            F.preview(obj, wid)
        bpy.data.objects.remove(obj, do_unlink=True)


if __name__ == '__main__':
    main([a for a in sys.argv[1:] if a in F.KIND] or list(F.KIND))
