"""Microsoft Rocketbox (MIT) avatars -> game-ready GLB with retargeted Idle/Walk/Run (from soldier.glb mixamo clips).
Output: assets/models/rb_<name>.glb
"""
import sys, os, math
import bpy
from mathutils import Vector, Matrix, Quaternion
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import characters as C

RB = '/home/claude/ext/Microsoft-Rocketbox/Assets/Avatars'
OUT = C.OUT
TEXOUT = '/tmp/rbtex'
os.makedirs(TEXOUT, exist_ok=True)

CHARS = {
    'takim': 'Professions/Business_Male_01', 'patron': 'Professions/Business_Male_05',
    'deri': 'Adults/Male_Adult_04', 'kot': 'Adults/Male_Adult_12', 'kapson': 'Adults/Male_Adult_18',
    'asker1': 'Professions/Military_Male_01', 'asker2': 'Professions/Military_Male_03', 'asker3': 'Professions/Military_Male_05',
}

M2B = {'Hips': 'Pelvis', 'Spine': 'Spine', 'Spine1': 'Spine1', 'Spine2': 'Spine2', 'Neck': 'Neck', 'Head': 'Head'}
for s, b in (('Left', 'L'), ('Right', 'R')):
    M2B.update({f'{s}Shoulder': f'{b} Clavicle', f'{s}Arm': f'{b} UpperArm', f'{s}ForeArm': f'{b} Forearm', f'{s}Hand': f'{b} Hand',
                f'{s}UpLeg': f'{b} Thigh', f'{s}Leg': f'{b} Calf', f'{s}Foot': f'{b} Foot', f'{s}ToeBase': f'{b} Toe0'})
    for fi, fn in enumerate(['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']):
        for k in range(3):
            M2B[f'{s}Hand{fn}{k + 1}'] = f'{b} Finger{fi}' + ('' if k == 0 else str(k))
# chain children for direction alignment (mixamo name -> child mixamo name)
CHILD = {}
for s in ('Left', 'Right'):
    CHILD.update({f'{s}Shoulder': f'{s}Arm', f'{s}Arm': f'{s}ForeArm', f'{s}ForeArm': f'{s}Hand', f'{s}Hand': f'{s}HandMiddle1',
                  f'{s}UpLeg': f'{s}Leg', f'{s}Leg': f'{s}Foot', f'{s}Foot': f'{s}ToeBase'})
    for fn in ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']:
        CHILD[f'{s}Hand{fn}1'] = f'{s}Hand{fn}2'
        CHILD[f'{s}Hand{fn}2'] = f'{s}Hand{fn}3'


def B(n):
    return 'Bip01 ' + M2B[n]


def wpos(arm, bone):
    return (arm.matrix_world @ arm.pose.bones[bone].matrix).translation


def convert_tex(path, size, mode='RGB'):
    name = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(TEXOUT, name + ('.png' if mode == 'RGBA' else '.jpg'))
    if not os.path.exists(out):
        im = Image.open(path).convert(mode)
        if im.size[0] > size:
            im = im.resize((size, size), Image.LANCZOS)
        if mode == 'RGBA':
            im.save(out, optimize=True)
        else:
            im.save(out, quality=90)
    return out


def setup_materials(mesh, folder):
    texdir = os.path.join(RB, folder, 'Textures')
    files = os.listdir(texdir)
    for slot in mesh.material_slots:
        m = slot.material
        if m is None:
            continue
        key = m.name.split('.')[0]          # e.g. sm002_body
        base = key
        def find(suffix):
            for f in files:
                if f.startswith(base) and suffix in f:
                    return os.path.join(texdir, f)
            return None
        colp = find('_color'); nrmp = find('_normal')
        is_opacity = 'opacity' in key
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        bs = nt.nodes.new('ShaderNodeBsdfPrincipled')
        nt.links.new(bs.outputs[0], out.inputs[0])
        rough = 0.5 if 'head' in key else (0.35 if 'knife' in key or 'helmet' in key else 0.72)
        bs.inputs['Roughness'].default_value = rough
        if colp:
            if is_opacity:
                ci = nt.nodes.new('ShaderNodeTexImage'); ci.image = bpy.data.images.load(convert_tex(colp, 1024, 'RGBA'))
                nt.links.new(ci.outputs['Color'], bs.inputs['Base Color'])
                nt.links.new(ci.outputs['Alpha'], bs.inputs['Alpha'])
                m.blend_method = 'CLIP' if hasattr(m, 'blend_method') else None
            else:
                ci = nt.nodes.new('ShaderNodeTexImage'); ci.image = bpy.data.images.load(convert_tex(colp, 2048))
                nt.links.new(ci.outputs['Color'], bs.inputs['Base Color'])
        if nrmp:
            ni = nt.nodes.new('ShaderNodeTexImage'); ni.image = bpy.data.images.load(convert_tex(nrmp, 1024))
            ni.image.colorspace_settings.name = 'Non-Color'
            nm = nt.nodes.new('ShaderNodeNormalMap')
            nt.links.new(ni.outputs['Color'], nm.inputs['Color'])
            nt.links.new(nm.outputs['Normal'], bs.inputs['Normal'])
        m.name = 'rb_' + key


def align_tpose(arm, mesh, src):
    C.set_action(src, C.actions_for(src)['TPose'])
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    order = [b.name for b in arm.data.bones]
    inv = {v: k for k, v in M2B.items()}
    for bname in order:
        mx = inv.get(bname[6:]) if bname.startswith('Bip01 ') else None
        if mx is None or mx not in CHILD:
            continue
        if ('mixamorig:' + CHILD[mx]) not in src.pose.bones or ('mixamorig:' + mx) not in src.pose.bones or B(CHILD[mx]) not in arm.pose.bones:
            continue
        bpy.context.view_layer.update()
        d_t = wpos(arm, B(CHILD[mx])) - wpos(arm, bname)
        d_s = wpos(src, 'mixamorig:' + CHILD[mx]) - wpos(src, 'mixamorig:' + mx)
        if d_t.length < 1e-5 or d_s.length < 1e-5:
            continue
        q = d_t.normalized().rotation_difference(d_s.normalized())
        if q.angle < math.radians(1.0):
            continue
        pb = arm.pose.bones[bname]
        wm = arm.matrix_world @ pb.matrix
        loc = wm.translation.copy()
        nw = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ wm
        pb.matrix = arm.matrix_world.inverted() @ nw
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = mesh
    for md in list(mesh.modifiers):
        if md.type == 'ARMATURE':
            with bpy.context.temp_override(object=mesh, active_object=mesh):
                bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    with bpy.context.temp_override(active_object=arm, object=arm):
        bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    md = mesh.modifiers.new('Armature', 'ARMATURE')
    md.object = arm


def retarget(arm, src):
    acts = C.actions_for(src)
    C.set_action(src, acts['TPose'])
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    s_rest = {n: (src.matrix_world @ src.pose.bones['mixamorig:' + n].matrix) for n in M2B if ('mixamorig:' + n) in src.pose.bones}
    t_rest = {n: arm.matrix_world @ arm.data.bones[B(n)].matrix_local for n in M2B if B(n) in arm.data.bones and n in s_rest}
    off = {n: s_rest[n].to_quaternion().inverted() @ t_rest[n].to_quaternion() for n in t_rest}
    hips0_s = (src.matrix_world @ src.data.bones['mixamorig:Hips'].matrix_local).translation.copy()
    hips0_t = t_rest['Hips'].translation.copy()
    ratio = hips0_t.z / max(hips0_s.z, 0.01)
    inv = arm.matrix_world.inverted()
    tb2m = {B(n): n for n in t_rest}
    if arm.animation_data is None:
        arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for key in ['Idle', 'Walk', 'Run']:
        sa = acts[key]
        C.set_action(src, sa)
        f0, f1 = int(sa.frame_range[0]), int(sa.frame_range[1])
        act = bpy.data.actions.new(key)
        C.set_action(arm, act)
        for fr in range(f0, f1 + 1):
            bpy.context.scene.frame_set(fr)
            sm = {n: src.matrix_world @ src.pose.bones['mixamorig:' + n].matrix for n in t_rest}
            mats = {}
            for b in arm.data.bones:
                pb = arm.pose.bones[b.name]
                rest = b.matrix_local
                base = mats[b.parent.name] @ (b.parent.matrix_local.inverted() @ rest) if b.parent else rest.copy()
                mx = tb2m.get(b.name)
                if mx:
                    R = inv.to_quaternion() @ sm[mx].to_quaternion() @ off[mx]
                    loc = base.translation
                    if mx == 'Hips':
                        d = (sm['Hips'].translation - hips0_s) * ratio
                        d.x = 0.0; d.y = 0.0
                        loc = inv @ (hips0_t + d)
                    M = Matrix.LocRotScale(loc, R, Vector((1, 1, 1)))
                else:
                    M = base
                mats[b.name] = M
                pb.matrix_basis = base.inverted() @ M
                pb.keyframe_insert('rotation_quaternion', frame=fr)
                if mx == 'Hips':
                    pb.keyframe_insert('location', frame=fr)
        tr = arm.animation_data.nla_tracks.new(); tr.name = key
        st = tr.strips.new(key, f0, act)
        try:
            st.action_slot = act.slots[0]
        except Exception:
            pass
    arm.animation_data.action = None


def build(cid):
    folder = CHARS[cid]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = C.load_soldier()
    before = set(bpy.data.objects)
    fbx = [f for f in os.listdir(os.path.join(RB, folder, 'Export')) if f.endswith('.fbx') and 'facial' not in f][0]
    bpy.ops.import_scene.fbx(filepath=os.path.join(RB, folder, 'Export', fbx))
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
    # apply the 0.01 scale on armature + mesh
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    with bpy.context.temp_override(active_object=arm, selected_editable_objects=[arm, mesh], selected_objects=[arm, mesh]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # rocketbox faces -Y like makehuman? soldier was rotated to face -Y as well by load_soldier
    setup_materials(mesh, folder)
    if mesh.data.shape_keys:
        mesh.shape_key_clear()
    align_tpose(arm, mesh, src)
    retarget(arm, src)
    import rb_aim
    rb_aim.build_aim(arm, cid, os.path.join(OUT, f'rb_{cid}_aim.json'))
    for o in list(bpy.data.objects):
        if o == src or o.parent == src:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a.name.startswith('SRC_'):
            bpy.data.actions.remove(a)
    for o in list(bpy.data.objects):
        if o not in (arm, mesh):
            bpy.data.objects.remove(o, do_unlink=True)
    arm.name = 'Character'
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); mesh.select_set(True)
    path = os.path.join(OUT, f'rb_{cid}.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_force_sampling=True, export_optimize_animation_size=False,
                              export_skins=True, export_morph=False, export_yup=True, export_image_format='AUTO')
    print('EXPORTED', path, os.path.getsize(path) // 1024, 'KB')


if __name__ == '__main__':
    for c in [a for a in sys.argv[1:] if a in CHARS] or list(CHARS):
        try:
            build(c)
        except Exception:
            import traceback; traceback.print_exc(); print('FAILED', c)
