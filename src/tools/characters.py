"""Realistic character generator: MakeHuman (MPFB2, CC0 assets) body + procedural clothing shells,
mixamo-compatible rig, animations retargeted from soldier.glb. -> assets/models/char_<id>.glb
Material naming (resolved by Godot MatLib): skin|RRGGBB, lips|RRGGBB, cloth|<tex>|RRGGBB|rough, hair|RRGGBB, eye|brown, gear|RRGGBB
"""
import sys, os, math, importlib, random
import bpy, bmesh, addon_utils
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MH = '/home/claude/makehumancommunity/makehuman/makehuman/data'
OUT = os.path.join(ROOT, 'assets', 'models')

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
HS = importlib.import_module("bl_ext.user_default.mpfb.services.humanservice").HumanService
TS = importlib.import_module("bl_ext.user_default.mpfb.services.targetservice").TargetService

CHARS = {
    "suit": dict(macro=dict(gender=1.0, age=0.55, muscle=0.62, weight=0.5, height=0.62, proportions=0.7, race=dict(caucasian=0.75, asian=0.05, african=0.2)),
                 skin="b88a6e", hair="1c1410", hair_style="short", beard="stubble",
                 outfit=[("shirt", "cotton", "e9e6df", 0.8), ("pants", "wool", "2a1a1e", 0.75), ("jacket", "wool", "3a2226", 0.7), ("shoes", "bootleather", "120c0a", 0.3), ("belt", "bootleather", "1a1210", 0.4)]),
    "leather": dict(macro=dict(gender=1.0, age=0.68, muscle=0.55, weight=0.52, height=0.58, proportions=0.6, race=dict(caucasian=0.8, asian=0.0, african=0.2)),
                    skin="b08066", hair="191210", hair_style="long", beard="full",
                    outfit=[("shirt", "cotton", "3a3632", 0.8), ("vest", "wool", "c9a35a", 0.75), ("pants", "denim", "ffffff", 0.85), ("jacket", "leather", "1a1716", 0.45), ("shoes", "bootleather", "5a3a22", 0.4), ("belt", "bootleather", "2a1a10", 0.4)]),
    "operator": dict(macro=dict(gender=1.0, age=0.5, muscle=0.8, weight=0.6, height=0.6, proportions=0.6, race=dict(caucasian=0.95, asian=0.0, african=0.05)),
                     skin="c79a80", hair="8a6a40", hair_style="buzz", beard="none",
                     outfit=[("tshirt", "cotton", "4a4a44", 0.85), ("pants", "camo", "ffffff", 0.85), ("hoodie", "nylon", "4d5038", 0.8), ("platecarrier", "nylon", "3e4130", 0.75), ("boots", "bootleather", "3a2a1c", 0.5), ("gloves", "leather", "2a2622", 0.6), ("belt", "nylon", "2a2a24", 0.7)]),
    "commando": dict(macro=dict(gender=1.0, age=0.6, muscle=0.85, weight=0.55, height=0.57, proportions=0.6, race=dict(caucasian=0.7, asian=0.0, african=0.3)),
                     skin="a87458", hair="2a1e14", hair_style="medium", beard="full",
                     outfit=[("tshirt", "cotton", "2b2d2a", 0.85), ("pants", "nylon", "7a6a4e", 0.85), ("platecarrier", "nylon", "2c2e28", 0.75), ("boots", "bootleather", "4a3a2a", 0.5), ("gloves", "nylon", "9a8a6a", 0.7), ("kneepads", "nylon", "1e1e1c", 0.6), ("bandana", "cotton", "a01814", 0.8), ("belt", "nylon", "2a2a24", 0.7)]),
}


def mat(name, color=(0.8, 0.8, 0.8), rough=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    return m


def hexc(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


# ------------------------------------------------------------------ soldier reference (animation source)
def load_soldier():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, 'soldier.glb'))
    objs = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in objs if o.type == 'ARMATURE'][0]
    for o in objs:
        if o.type == 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    for a in bpy.data.actions:
        if not a.name.startswith('SRC_'):
            a.name = 'SRC_' + a.name
    root = arm
    while root.parent:
        root = root.parent
    root.matrix_world = Matrix.Rotation(math.pi, 4, 'Z') @ root.matrix_world
    bpy.context.view_layer.update()
    return arm


def actions_for(arm):
    out = {}
    for a in bpy.data.actions:
        nm = a.name.split('_')[0] if '_' in a.name else a.name
        for k in ['Idle', 'Run', 'Walk', 'TPose']:
            if a.name.startswith('SRC_' + k):
                out[k] = a
    return out


def set_action(arm, action):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    try:
        if action.slots:
            arm.animation_data.action_slot = action.slots[0]
    except Exception:
        pass


def world_pose(arm):
    """bone name -> world matrix (posed)"""
    mw = arm.matrix_world
    return {pb.name: mw @ pb.matrix for pb in arm.pose.bones}


def child_dir(arm, mats, name):
    pb = arm.pose.bones[name]
    kids = [c for c in pb.children]
    head = mats[name].translation
    if kids:
        # prefer the main chain child
        pref = [c for c in kids if any(k in c.name for k in ['Spine', 'Neck', 'Head'])] or [c for c in kids if not any(k in c.name for k in ['Thumb', 'Index', 'Pinky', 'Ring', 'Shoulder'])] or kids
        tail = mats[pref[0].name].translation
        if 'Hand' in name and not name.endswith('End'):
            mid = [c for c in kids if 'Middle1' in c.name]
            if mid:
                tail = mats[mid[0].name].translation
    else:
        tail = head + (mats[name].to_quaternion() @ Vector((0, 1, 0))) * 0.05
    return (tail - head)


# ------------------------------------------------------------------ build body
def build_body(cfg):
    m = TS.get_default_macro_info_dict()
    for k, v in cfg['macro'].items():
        if k != 'race':
            m[k] = v
    m['race'] = cfg['macro']['race']
    h = HS.create_human(macro_detail_dict=m, detailed_helpers=True)
    rig = HS.add_builtin_rig(h, 'mixamo')
    eyes = HS.add_mhclo_asset(os.path.join(MH, 'eyes', 'high-poly', 'high-poly.mhclo'), h, asset_type='Eyes', subdiv_levels=0)
    TS.bake_targets(h)
    # apply helper mask
    bpy.context.view_layer.objects.active = h
    for md in list(h.modifiers):
        if md.type == 'MASK':
            with bpy.context.temp_override(object=h, active_object=h):
                bpy.ops.object.modifier_apply(modifier=md.name)
    if eyes and eyes.data.shape_keys:
        with bpy.context.temp_override(object=eyes, active_object=eyes):
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    return h, rig, eyes


def to_tpose(rig, meshes, src_arm, src_actions):
    """re-pose MPFB rig bones to match soldier T-pose directions, bake into meshes, apply as rest"""
    set_action(src_arm, src_actions['TPose'])
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    smats = world_pose(src_arm)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    order = [b.name for b in rig.data.bones]  # parents before children
    for name in order:
        if name not in src_arm.pose.bones or name.endswith('_End') or 'HeadTop' in name:
            continue
        if not any(k in name for k in ['Shoulder', 'Arm', 'Hand', 'UpLeg', 'Leg', 'Foot', 'Toe']) or any(k in name for k in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky')):
            continue
        bpy.context.view_layer.update()
        tm = world_pose(rig)
        if not rig.pose.bones[name].children:
            continue
        d_t = child_dir(rig, tm, name)
        d_s = child_dir(src_arm, smats, name)
        if d_t.length < 1e-5 or d_s.length < 1e-5:
            continue
        q = d_t.normalized().rotation_difference(d_s.normalized())
        if q.angle < math.radians(2.0):
            continue
        pb = rig.pose.bones[name]
        wm = rig.matrix_world @ pb.matrix
        loc = wm.translation.copy()
        nw = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ wm
        pb.matrix = rig.matrix_world.inverted() @ nw
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    for me in meshes:
        bpy.context.view_layer.objects.active = me
        for md in list(me.modifiers):
            if md.type == 'ARMATURE':
                with bpy.context.temp_override(object=me, active_object=me):
                    bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    with bpy.context.temp_override(active_object=rig, object=rig):
        bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for me in meshes:
        md = me.modifiers.new('Armature', 'ARMATURE')
        md.object = rig
        me.parent = rig


# ------------------------------------------------------------------ geometry helpers
def bone_weights(obj):
    names = {g.index: g.name for g in obj.vertex_groups}
    W = []
    for v in obj.data.vertices:
        d = {}
        for g in v.groups:
            n = names.get(g.group, '')
            if n.startswith('mixamorig:'):
                d[n[10:]] = g.weight
        W.append(d)
    return W


def region_w(wd, bones):
    return sum(wd.get(b, 0.0) for b in bones)


TORSO = ['Hips', 'Spine', 'Spine1', 'Spine2', 'LeftShoulder', 'RightShoulder']
UARM = ['LeftArm', 'RightArm']
FARM = ['LeftForeArm', 'RightForeArm']
HAND = ['LeftHand', 'RightHand'] + [f'{s}Hand{f}{i}' for s in ('Left', 'Right') for f in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky') for i in (1, 2, 3, 4)]
ULEG = ['LeftUpLeg', 'RightUpLeg']
LLEG = ['LeftLeg', 'RightLeg']
FOOT = ['LeftFoot', 'RightFoot', 'LeftToeBase', 'RightToeBase']
HEAD = ['Head', 'HeadTop_End']
NECK = ['Neck']


def make_shell(body, name, face_pred, offset, thick, material, smooth=6, smooth_fac=0.5, offset_fn=None, keep_groups=True):
    """duplicate selected body faces into a new skinned mesh, push out along normals"""
    me = body.data.copy()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = body.parent
    obj.matrix_world = body.matrix_world.copy()
    W = bone_weights(body)
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    dele = [f for f in bm.faces if not face_pred(f, W)]
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.normal_update()
    orig = {v.index: v.co.copy() for v in bm.verts}
    nrm0 = {v.index: v.normal.copy() for v in bm.verts}
    for v in bm.verts:
        off = offset if offset_fn is None else offset_fn(v)
        v.co += v.normal * off
    boundary = [v for v in bm.verts if v.is_boundary]
    inner = [v for v in bm.verts if not v.is_boundary]
    for it in range(smooth):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=smooth_fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        if boundary:
            bmesh.ops.smooth_vert(bm, verts=boundary, factor=smooth_fac * 0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for v in bm.verts:
        o = orig[v.index]
        lim = (offset if offset_fn is None else offset_fn(v)) * 2.5 + 0.004
        dv = v.co - o
        if dv.length > lim:
            v.co = o + nrm0[v.index] * (offset if offset_fn is None else offset_fn(v))
    # never let smoothing sink the cloth under the skin: enforce minimum offset along original normal
    for v in bm.verts:
        o = orig[v.index]; n = nrm0[v.index]
        minoff = (offset if offset_fn is None else offset_fn(v)) * 0.75
        d = (v.co - o).dot(n)
        if d < minoff:
            v.co += n * (minoff - d)
    bm.to_mesh(me); bm.free()
    me.materials.clear()
    me.materials.append(material)
    for p in me.polygons:
        p.material_index = 0
        p.use_smooth = True
    if me.shape_keys:
        obj.shape_key_clear()
    sub = obj.modifiers.new('sub', 'SUBSURF')
    sub.levels = 1; sub.render_levels = 1
    if thick > 0:
        s = obj.modifiers.new('solid', 'SOLIDIFY')
        s.thickness = thick
        s.offset = -1
        s.use_even_offset = True
    a = obj.modifiers.new('Armature', 'ARMATURE')
    a.object = body.parent
    print('SHELL', name, len(me.polygons))
    return obj


def face_avg(f):
    c = Vector()
    for v in f.verts:
        c += v.co
    return c / len(f.verts)


def fw(f, W, bones):
    return sum(region_w(W[v.index], bones) for v in f.verts) / len(f.verts)


def rigid_box(name, size, loc, bone, material, rig, bevel=0.004, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    me.materials.append(material)
    if bevel:
        b = o.modifiers.new('bev', 'BEVEL'); b.width = bevel; b.segments = 2
    vg = o.vertex_groups.new(name='mixamorig:' + bone)
    vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    o.parent = rig
    o.matrix_parent_inverse = rig.matrix_world.inverted()
    a = o.modifiers.new('Armature', 'ARMATURE'); a.object = rig
    return o


# ------------------------------------------------------------------ outfit
def landmarks(body, eyes):
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    zmax = max(v.z for v in vs)
    lips_g = body.vertex_groups.get('lips')
    lips = [body.matrix_world @ v.co for v in body.data.vertices if lips_g and any(g.group == lips_g.index for g in v.groups)]
    ev = [eyes.matrix_world @ v.co for v in eyes.data.vertices] if eyes else []
    L = dict(top=zmax)
    if lips:
        L['mouth'] = sum(lips, Vector()) / len(lips)
        L['mouth_w'] = max(p.x for p in lips) - min(p.x for p in lips)
    if ev:
        left = [p for p in ev if p.x > 0]; right = [p for p in ev if p.x <= 0]
        L['eyeL'] = sum(left, Vector()) / max(len(left), 1)
        L['eyeR'] = sum(right, Vector()) / max(len(right), 1)
    return L


def build_outfit(body, rig, eyes, cfg, cid):
    W = bone_weights(body)
    L = landmarks(body, eyes)
    rig_w = {b.name[10:]: (rig.matrix_world @ b.head_local) for b in rig.data.bones}
    hip_z = rig_w['Hips'].z
    neck_z = rig_w['Neck'].z
    head_z = rig_w['Head'].z
    knee_z = rig_w['LeftLeg'].z
    ankle_z = rig_w['LeftFoot'].z
    wrist_x = abs(rig_w['LeftHand'].x)
    elbow_x = abs(rig_w['LeftForeArm'].x)
    chest_z = rig_w['Spine2'].z
    objs = []
    M = {}
    for (piece, tex, color, rough) in cfg['outfit']:
        M[piece] = mat(f'cloth|{tex}|{color}|{rough}', hexc(color), rough)
    torso_arm = TORSO + UARM + FARM + NECK

    def P(piece):
        return M[piece]

    for (piece, tex, color, rough) in cfg['outfit']:
        if piece in ('shirt', 'tshirt'):
            sleeve_x = wrist_x - 0.03 if piece == 'shirt' else (elbow_x + abs(rig_w['LeftArm'].x)) / 2
            def pred(f, W, sx=sleeve_x):
                c = face_avg(f)
                return fw(f, W, HEAD) < 0.4 and fw(f, W, HAND) < 0.3 and abs(c.x) < sx and c.z > hip_z - 0.12 and (c.z < neck_z + 0.03 or abs(c.x) > 0.11)
            objs.append(make_shell(body, piece, pred, 0.004, 0.002, P(piece), smooth=3))
            # collar
            if piece == 'shirt':
                def cp(f, W):
                    c = face_avg(f)
                    return fw(f, W, NECK + ['Spine2']) > 0.4 and neck_z - 0.02 < c.z < neck_z + 0.05
                objs.append(make_shell(body, 'collar', cp, 0.012, 0.003, P(piece), smooth=2))
        elif piece in ('jacket', 'hoodie'):
            hem = hip_z - (0.2 if piece == 'jacket' else 0.08)
            def pred(f, W, hem=hem, piece=piece):
                c = face_avg(f)
                if not (fw(f, W, HEAD) < 0.4 and fw(f, W, HAND) < 0.3 and abs(c.x) < wrist_x - 0.05 and c.z > hem and (c.z < neck_z + 0.04 or abs(c.x) > 0.11)):
                    return False
                # open front for suit / leather jackets
                if piece == 'jacket' and c.y < -0.04 and abs(c.x) < 0.075 - (0.035 if c.z > chest_z else 0.0) * (c.z - chest_z) * 4 and c.z > hip_z - 0.25 and abs(c.x) < 0.11:
                    if abs(c.x) < 0.06 + max(0.0, (c.z - chest_z)) * 0.6:
                        return False
                return True
            objs.append(make_shell(body, piece, pred, 0.012, 0.005, P(piece), smooth=5, offset_fn=lambda v, pc=piece: (0.007 if abs(v.co.x) > 0.2 else (0.014 if pc == 'jacket' else 0.018))))
            if piece == 'jacket':
                # lapels: thin band along the opening
                def lp(f, W):
                    c = face_avg(f)
                    edge = 0.06 + max(0.0, (c.z - chest_z)) * 0.6
                    return fw(f, W, TORSO + NECK) > 0.5 and c.y < -0.03 and edge < abs(c.x) < edge + 0.035 and chest_z - 0.05 < c.z < neck_z + 0.02
                objs.append(make_shell(body, 'lapel', lp, 0.024, 0.004, P(piece), smooth=4))
            if piece == 'hoodie':
                def hp(f, W):
                    c = face_avg(f)
                    return fw(f, W, NECK + ['Spine2']) > 0.3 and c.y > 0.0 and neck_z - 0.04 < c.z < neck_z + 0.08
                objs.append(make_shell(body, 'hood', hp, 0.045, 0.01, P(piece), smooth=8))
        elif piece == 'vest':
            def pred(f, W):
                c = face_avg(f)
                if not (fw(f, W, TORSO) > 0.6 and hip_z - 0.08 < c.z < neck_z - 0.04):
                    return False
                if c.y < -0.04 and abs(c.x) < 0.035:
                    return False
                return abs(c.x) < 0.2
            objs.append(make_shell(body, 'vest', pred, 0.01, 0.004, P(piece), smooth=6))
        elif piece == 'pants':
            def pred(f, W):
                c = face_avg(f)
                return fw(f, W, HAND + FARM + UARM) < 0.3 and c.z < hip_z + 0.06 and c.z > 0.1
            objs.append(make_shell(body, 'pants', pred, 0.008 if cfg['outfit'][0][0] != 'tshirt' else 0.014, 0.003, P(piece), smooth=6))
        elif piece in ('shoes', 'boots'):
            top = 0.13 if piece == 'shoes' else 0.27
            def pred(f, W, top=top):
                c = face_avg(f)
                return c.z < top and fw(f, W, HAND) < 0.1
            def offf(v, top=top):
                return 0.01 if v.co.z > 0.06 else 0.014
            objs.append(make_shell(body, piece, pred, 0.012, 0.0, P(piece), smooth=3, offset_fn=offf))
        elif piece == 'gloves':
            def pred(f, W):
                c = face_avg(f)
                return fw(f, W, HAND + FARM) > 0.5 and abs(c.x) > wrist_x - 0.04
            objs.append(make_shell(body, 'gloves', pred, 0.003, 0.0015, P(piece), smooth=1))
        elif piece == 'belt':
            def pred(f, W):
                c = face_avg(f)
                return fw(f, W, ['Hips', 'Spine'] + ULEG) > 0.5 and hip_z + 0.04 < c.z < hip_z + 0.085
            objs.append(make_shell(body, 'belt', pred, 0.02, 0.004, P(piece), smooth=4))
            buckle = mat('gear|9a9a9a|0.3', (0.6, 0.6, 0.6), 0.3)
            objs.append(rigid_box('buckle', (0.06, 0.012, 0.04), (0, rig_w['Hips'].y - 0.135, hip_z + 0.062), 'Hips', buckle, rig))
        elif piece == 'platecarrier':
            def pred(f, W):
                c = face_avg(f)
                return fw(f, W, TORSO) > 0.7 and hip_z + 0.02 < c.z < chest_z + 0.12 and abs(c.x) < 0.17
            objs.append(make_shell(body, 'platecarrier', pred, 0.045, 0.02, P(piece), smooth=10, smooth_fac=0.6))
            # straps over shoulders
            def sp(f, W):
                c = face_avg(f)
                return fw(f, W, TORSO + NECK) > 0.5 and chest_z < c.z < neck_z + 0.05 and 0.06 < abs(c.x) < 0.12
            objs.append(make_shell(body, 'straps', sp, 0.03, 0.01, P(piece), smooth=5))
            pm = P(piece)
            fy = rig_w['Spine1'].y - 0.16
            for i, x in enumerate((-0.09, -0.03, 0.03, 0.09)):
                objs.append(rigid_box(f'mag{i}', (0.05, 0.035, 0.13), (x, fy, hip_z + 0.17), 'Spine1', pm, rig, 0.006))
            objs.append(rigid_box('radio', (0.06, 0.04, 0.12), (0.15, fy + 0.04, chest_z + 0.0), 'Spine2', mat('gear|1a1a1a|0.5', (0.1, 0.1, 0.1), 0.5), rig, 0.006))
            objs.append(rigid_box('admin', (0.2, 0.03, 0.08), (0, fy + 0.005, chest_z + 0.05), 'Spine2', pm, rig, 0.006))
            objs.append(rigid_box('backpanel', (0.28, 0.05, 0.3), (0, rig_w['Spine1'].y + 0.17, chest_z - 0.02), 'Spine2', pm, rig, 0.01))
        elif piece == 'kneepads':
            def pred(f, W):
                c = face_avg(f)
                return fw(f, W, ULEG + LLEG) > 0.5 and abs(c.z - knee_z) < 0.07 and c.y < rig_w['LeftLeg'].y - 0.01
            objs.append(make_shell(body, 'kneepads', pred, 0.03, 0.012, P(piece), smooth=5))
        elif piece == 'bandana':
            fz = (L.get('eyeL', Vector((0, 0, head_z + 0.1))).z + 0.045)
            def pred(f, W, fz=fz):
                c = face_avg(f)
                return fw(f, W, HEAD) > 0.6 and fz - 0.02 < c.z < fz + 0.025
            objs.append(make_shell(body, 'bandana', pred, 0.012, 0.003, P(piece), smooth=3))
    # ---- hair / beard / brows
    hm = mat('hair|' + cfg['hair'], hexc(cfg['hair']), 0.6)
    scalp_g = body.vertex_groups.get('scalp')
    eyez = L['eyeL'].z if 'eyeL' in L else head_z + 0.08
    style = cfg['hair_style']
    def hair_pred(f, W):
        c = face_avg(f)
        if fw(f, W, HEAD + NECK) < 0.4:
            return False
        if style == 'long':
            if c.y > -0.02 and c.z > neck_z - 0.1:
                return True
            return c.z > eyez + 0.035 or (c.z > eyez - 0.04 and c.y > 0.01 and abs(c.x) > 0.06)
        lim = {'short': 0.03, 'buzz': 0.05, 'medium': 0.025}[style]
        if c.y > 0.02:
            return c.z > eyez - (0.03 if style != 'buzz' else 0.0)
        return c.z > eyez + lim + (0.02 if abs(c.x) < 0.05 else 0.0)
    th = {'short': 0.014, 'buzz': 0.004, 'medium': 0.02, 'long': 0.022}[style]
    def hair_off(v):
        return th * (1.0 if v.co.z > eyez + 0.03 else 0.6)
    objs.append(make_shell(body, 'hair', hair_pred, th, 0.0, hm, smooth=4, offset_fn=hair_off))
    if 'mouth' in L:
        mo = L['mouth']
        bmat = mat('hair|' + cfg['hair'] + '|beard', hexc(cfg['hair']), 0.7)
        beard = cfg['beard']
        if beard != 'none':
            def bp(f, W):
                c = face_avg(f)
                if fw(f, W, HEAD + NECK) < 0.5 or c.y > mo.y + 0.06:
                    return False
                if abs(c.z - mo.z) < 0.012 and abs(c.x - mo.x) < L['mouth_w'] * 0.55:
                    return False  # lips
                if beard == 'stubble':
                    return c.z < mo.z + 0.01 and c.z > mo.z - 0.075 and abs(c.x) < 0.065
                return (c.z < mo.z + 0.03 and c.z > mo.z - 0.09 and abs(c.x) < 0.075) or (abs(c.x) > 0.055 and mo.z - 0.02 < c.z < eyez - 0.025 and c.y > mo.y + 0.02)
            objs.append(make_shell(body, 'beard', bp, 0.0025 if beard == 'stubble' else 0.008, 0.0, bmat, smooth=2))
    if 'eyeL' in L:
        brow = mat('hair|' + cfg['hair'] + '|brow', hexc(cfg['hair']), 0.7)
        for e in (L['eyeL'], L['eyeR']):
            def brp(f, W, e=e):
                c = face_avg(f)
                return fw(f, W, HEAD) > 0.6 and e.z + 0.014 < c.z < e.z + 0.028 and abs(c.x - e.x) < 0.026 and c.y < e.y + 0.015
            objs.append(make_shell(body, 'brow', brp, 0.003, 0.0, brow, smooth=1))
    return objs


def skin_materials(body, eyes, cfg):
    sk = mat('skin|' + cfg['skin'], hexc(cfg['skin']), 0.5)
    lips = mat('lips|' + cfg['skin'], hexc(cfg['skin']), 0.4)
    body.data.materials.clear()
    body.data.materials.append(sk)
    body.data.materials.append(lips)
    lg = body.vertex_groups.get('lips')
    lset = set()
    if lg:
        for v in body.data.vertices:
            for g in v.groups:
                if g.group == lg.index and g.weight > 0.5:
                    lset.add(v.index)
    for p in body.data.polygons:
        p.material_index = 1 if all(i in lset for i in p.vertices) else 0
        p.use_smooth = True
    if eyes:
        eyes.data.materials.clear()
        eyes.data.materials.append(mat('eye|brown', (0.3, 0.2, 0.1), 0.1))


# ------------------------------------------------------------------ retarget
HIPS_DZ = {}


def retarget(rig, src, src_actions, height_ratio):
    set_action(src, src_actions['TPose'])
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    s_rest = world_pose(src)
    t_rest = {b.name: rig.matrix_world @ b.matrix_local for b in rig.data.bones}
    off = {}
    names = [b.name for b in rig.data.bones if b.name in src.pose.bones and not any(k in b.name for k in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky'))]
    for n in names:
        off[n] = s_rest[n].to_quaternion().inverted() @ t_rest[n].to_quaternion()
    hips0_s = (src.matrix_world @ src.data.bones['mixamorig:Hips'].matrix_local).translation.copy()
    hips0_t = t_rest['mixamorig:Hips'].translation.copy()
    rig_inv = rig.matrix_world.inverted()
    if rig.animation_data is None:
        rig.animation_data_create()
    out = []
    for key in ['Idle', 'Walk', 'Run']:
        sa = src_actions[key]
        set_action(src, sa)
        f0, f1 = int(sa.frame_range[0]), int(sa.frame_range[1])
        act = bpy.data.actions.new(key)
        set_action(rig, act)
        for pb in rig.pose.bones:
            pb.rotation_mode = 'QUATERNION'
        dz_acc = []
        for fr in range(f0, f1 + 1):
            bpy.context.scene.frame_set(fr)
            sm = world_pose(src)
            arm_mats = {}
            for b in rig.data.bones:
                pb = rig.pose.bones[b.name]
                rest_local = b.matrix_local
                if b.parent:
                    pm = arm_mats[b.parent.name]
                    base = pm @ (b.parent.matrix_local.inverted() @ rest_local)
                else:
                    base = rest_local.copy()
                if b.name in off:
                    R = (rig_inv.to_quaternion() @ sm[b.name].to_quaternion() @ off[b.name])
                    loc = base.translation
                    if b.parent is None:
                        d = (sm[b.name].translation - hips0_s) * height_ratio
                        d.x = 0.0; d.y = 0.0
                        dz_acc.append(d.z)
                        loc = (rig_inv @ (hips0_t + d))
                    M = Matrix.LocRotScale(loc, R, Vector((1, 1, 1)))
                else:
                    M = base
                arm_mats[b.name] = M
                basis = base.inverted() @ M
                pb.matrix_basis = basis
                pb.keyframe_insert('rotation_quaternion', frame=fr)
                if b.parent is None:
                    pb.keyframe_insert('location', frame=fr)
        HIPS_DZ[key] = sum(dz_acc) / max(len(dz_acc), 1)
        tr = rig.animation_data.nla_tracks.new()
        tr.name = key
        st = tr.strips.new(key, f0, act)
        try:
            if act.slots:
                st.action_slot = act.slots[0]
        except Exception as e:
            print('slot err', e)
        out.append(act)
    rig.animation_data.action = None
    return out


def build(cid):
    cfg = CHARS[cid]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = load_soldier()
    sacts = actions_for(src)
    body, rig, eyes = build_body(cfg)
    to_tpose(rig, [o for o in (body, eyes) if o], src, sacts)
    objs = build_outfit(body, rig, eyes, cfg, cid)
    skin_materials(body, eyes, cfg)
    src_h = (world_pose(src)['mixamorig:Head'].translation.z)
    tgt_h = (rig.matrix_world @ rig.data.bones['mixamorig:Head'].head_local).z
    retarget(rig, src, sacts, tgt_h / max(src_h, 0.01))
    # remove source + unused
    for o in list(bpy.data.objects):
        if o == src or (o.parent == src):
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a.name.startswith('SRC_'):
            bpy.data.actions.remove(a)
    rig.name = 'Character'
    # export selected rig + children
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for o in rig.children_recursive:
        o.select_set(True)
    path = os.path.join(OUT, f'char_{cid}.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_optimize_animation_size=False, export_force_sampling=True, export_skins=True, export_morph=False, export_yup=True)
    print('EXPORTED', path, os.path.getsize(path) // 1024, 'KB')
    import json
    jp = os.path.join(OUT, 'char_offsets.json')
    data = json.load(open(jp)) if os.path.exists(jp) else {}
    data[cid] = HIPS_DZ.copy()
    json.dump(data, open(jp, 'w'))
    print('HIPS_DZ', HIPS_DZ)


if __name__ == '__main__':
    for c in [a for a in sys.argv[1:] if a in CHARS] or list(CHARS):
        try:
            build(c)
        except Exception:
            import traceback; traceback.print_exc(); print('FAILED', c)
