"""First-person arms from a real MakeHuman body, posed per weapon (two-bone IK + finger curl),
baked to static meshes in WEAPON SPACE -> assets/models/fp_<weapon>.glb
"""
import sys, os, math, json, struct, importlib
import bpy, bmesh, addon_utils
from mathutils import Vector, Matrix, Quaternion

sys.path.insert(0, os.path.dirname(__file__))
import characters as C

ROOT = C.ROOT
OUT = C.OUT
HIP = {"rifle": (0.14, -0.165, -0.36), "pistol": (0.13, -0.14, -0.40), "knife": (0.17, -0.18, -0.36), "frag": (0.16, -0.17, -0.34), "sniper": (0.14, -0.17, -0.33)}
GRIP = {"aug": 10, "vector": 12, "m249": 16, "scar": 20, "ump45": 14, "revolver": 24, "ak47": 20, "m4a1": 22, "mp5": 15, "p90": 0, "spas": 20, "awp": 10, "kar98": 10, "glock": 22, "deagle": 18, "knife": 0, "karambit": 0, "frag": 0}
KIND = {"aug": "rifle", "vector": "rifle", "m249": "rifle", "scar": "rifle", "ump45": "rifle", "revolver": "pistol", "ak47": "rifle", "m4a1": "rifle", "mp5": "rifle", "p90": "rifle", "spas": "rifle", "awp": "sniper", "kar98": "sniper", "glock": "pistol", "deagle": "pistol", "knife": "knife", "karambit": "knife", "frag": "frag"}


def weapon_points(wid):
    b = open(os.path.join(OUT, f'w_{wid}.glb'), 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    pts = {}
    for nd in j['nodes']:
        if nd.get('name') in ('rhand', 'lhand', 'muzzle', 'sight'):
            t = nd.get('translation', [0, 0, 0])
            pts[nd['name']] = Vector((t[0], -t[2], t[1]))  # glTF -> blender
    return pts


def bw(rig, name):
    return rig.matrix_world @ rig.pose.bones['mixamorig:' + name].matrix


def set_world(rig, name, M):
    pb = rig.pose.bones['mixamorig:' + name]
    pb.matrix = rig.matrix_world.inverted() @ M
    bpy.context.view_layer.update()


def aim_bone(rig, name, target_dir, roll_hint=None):
    """rotate bone so its Y axis points along target_dir (keeping head)"""
    M = bw(rig, name)
    cur = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(target_dir.normalized())
    head = M.translation.copy()
    R = q.to_matrix().to_4x4()
    NM = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ M
    set_world(rig, name, NM)


def arm_ik(rig, side, wrist_target, pole, hand_fwd, hand_palm):
    up, lo = side + 'Arm', side + 'ForeArm'
    A = bw(rig, up).translation.copy()
    L1 = (bw(rig, lo).translation - A).length
    L2 = (bw(rig, side + 'Hand').translation - bw(rig, lo).translation).length
    T = Vector(wrist_target)
    d = T - A
    dist = min(d.length, (L1 + L2) * 0.995)
    dn = d.normalized()
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    pdir = (Vector(pole) - A)
    pdir = (pdir - dn * pdir.dot(dn)).normalized()
    E = A + dn * a + pdir * h
    down = Vector((0, 0, -1))
    up_palm = (down * 0.6 + hand_palm.normalized() * 0.4)
    orient(rig, up, E - A, up_palm)
    E2 = bw(rig, lo).translation.copy()
    fa_palm = (hand_palm.normalized() * 0.75 + up_palm.normalized() * 0.25)
    orient(rig, lo, T - E2, fa_palm)
    Tw = bw(rig, side + 'Hand').translation.copy()
    orient(rig, side + 'Hand', hand_fwd, hand_palm, Tw)


def two_bone_ik(rig, side, wrist_target, pole):
    up, lo, hand = side + 'Arm', side + 'ForeArm', side + 'Hand'
    A = bw(rig, up).translation
    L1 = (bw(rig, lo).translation - A).length
    L2 = (bw(rig, hand).translation - bw(rig, lo).translation).length
    T = Vector(wrist_target)
    d = T - A
    dist = min(d.length, (L1 + L2) * 0.999)
    dn = d.normalized()
    # elbow position via law of cosines in the plane containing pole
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    pdir = (Vector(pole) - A)
    pdir = (pdir - dn * pdir.dot(dn)).normalized()
    E = A + dn * a + pdir * h
    aim_bone(rig, up, E - A)
    aim_bone(rig, lo, T - bw(rig, lo).translation)


def set_hand(rig, side, fwd, palm, wrist_pos=None):
    """fwd: wrist->knuckles direction, palm: palm normal (world)"""
    M = bw(rig, side + 'Hand')
    # determine local axes: Y = along bone; palm local axis computed at rest
    pa = rig['palm_axis_' + side]
    fwd = fwd.normalized()
    palm = (palm - fwd * palm.dot(fwd)).normalized()
    # build basis: local Y -> fwd, local 'pa' -> palm
    pa = Vector(pa)
    other = Vector((0, 1, 0)).cross(pa).normalized()  # third local axis
    # world third axis
    w_other = fwd.cross(palm).normalized()
    # local frame matrix columns (Y, pa, other) -> world (fwd, palm, w_other)
    Lm = Matrix((Vector((0, 1, 0)), pa, other)).transposed()
    Wm = Matrix((fwd, palm, w_other)).transposed()
    R = Wm @ Lm.inverted()
    head = M.translation.copy() if wrist_pos is None else Vector(wrist_pos)
    NM = Matrix.Translation(head) @ R.to_4x4()
    set_world(rig, side + 'Hand', NM)


def curl(rig, side, finger, angles, palm_world, spread=0.0):
    for i, ang in enumerate(angles, start=1):
        name = f'{side}Hand{finger}{i}'
        if ('mixamorig:' + name) not in rig.pose.bones:
            continue
        M = bw(rig, name)
        d = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
        axis = d.cross(palm_world).normalized()
        q = Quaternion(axis, math.radians(ang))
        if i == 1 and spread:
            q = Quaternion(palm_world, math.radians(spread)) @ q
        head = M.translation.copy()
        NM = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ M
        set_world(rig, name, NM)


def palm_axes(rig):
    """at T-pose palms face down (-Z): store, for each arm bone, the local axis that points to world -Z"""
    for side in ('Left', 'Right'):
        for b in ('Arm', 'ForeArm', 'Hand'):
            M = bw(rig, side + b).to_3x3()
            loc = M.inverted() @ Vector((0, 0, -1))
            loc.y = 0
            rig['pa_' + side + b] = list(loc.normalized())
        rig['palm_axis_' + side] = rig['pa_' + side + 'Hand']


def orient(rig, name, fwd, palm, head=None):
    M = bw(rig, name)
    pa = Vector(rig['pa_' + name])
    fwd = fwd.normalized()
    palm = (palm - fwd * palm.dot(fwd)).normalized()
    other = Vector((0, 1, 0)).cross(pa).normalized()
    Lm = Matrix((Vector((0, 1, 0)), pa, other)).transposed()
    Wm = Matrix((fwd, palm, fwd.cross(palm).normalized())).transposed()
    R = Wm @ Lm.inverted()
    h = M.translation.copy() if head is None else Vector(head)
    set_world(rig, name, Matrix.Translation(h) @ R.to_4x4())


def build_base():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = C.load_soldier()
    sacts = C.actions_for(src)
    cfg = dict(C.CHARS['operator'])
    cfg['macro'] = dict(gender=1.0, age=0.45, muscle=0.75, weight=0.5, height=0.6, proportions=0.7, race=dict(caucasian=0.7, asian=0.1, african=0.2))
    body, rig, eyes = C.build_body(cfg)
    C.to_tpose(rig, [o for o in (body, eyes) if o], src, sacts)
    for o in list(bpy.data.objects):
        if o == src or o.parent == src or o == eyes:
            bpy.data.objects.remove(o, do_unlink=True)
    return body, rig


def pose_for(wid, body, rig):
    kind = KIND[wid]
    pts = weapon_points(wid)
    hip = HIP[kind]
    cam = Vector((-hip[0], hip[2] * -1 * -1, 0)) if False else Vector((-hip[0], hip[2], -hip[1]))  # godot (x,y,z) -> blender (x,-z,y) of -hip
    # place body: face +Y, eyes at cam
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    rig.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    head = (rig.matrix_world @ rig.data.bones['mixamorig:Head'].head_local)
    eye = head + Vector((0, -0.11, 0.1))  # approx eye offset from head joint (front is -Y before rotation)
    rot = Matrix.Rotation(math.pi, 4, 'Z')
    eye_r = rot @ eye
    rig.matrix_world = Matrix.Translation(cam - eye_r + Vector((0.02, 0.3, -0.06))) @ rot
    bpy.context.view_layer.update()
    palm_axes_done = 'palm_axis_Left' in rig.keys()
    if not palm_axes_done:
        palm_axes(rig)
    # bring shoulders forward/inward like a shooter's stance (clavicles protract)
    for side, ang in (('Left', 38.0), ('Right', -22.0)):
        M = bw(rig, side + 'Shoulder')
        hd = M.translation.copy()
        R = Matrix.Rotation(math.radians(ang), 4, 'Z') @ Matrix.Rotation(math.radians(-12), 4, 'X')
        set_world(rig, side + 'Shoulder', Matrix.Translation(hd) @ R @ Matrix.Translation(-hd) @ M)
    g = math.radians(GRIP.get(wid, 18))
    grip_axis = Vector((0, math.sin(g), math.cos(g)))  # up along grip (bottom tilts back)
    rh = pts.get('rhand', Vector())
    lh = pts.get('lhand', Vector((0, 0.3, 0.03)))
    X = Vector((1, 0, 0)); Y = Vector((0, 1, 0)); Z = Vector((0, 0, 1))
    fwd_grip = Vector((0, math.cos(g), -math.sin(g)))
    if kind in ('rifle', 'sniper', 'pistol'):
        r_fwd = (fwd_grip + Z * 0.15).normalized()
        r_palm = (-X).normalized()
        r_wrist = rh + Vector((0.03, -0.085, -0.035)) - grip_axis * 0.01
        shoulder = bw(rig, 'RightArm').translation
        arm_ik(rig, 'Right', r_wrist, shoulder + Vector((0.6, 0.0, -0.7)), r_fwd, r_palm)
        for f, c in [('Index', [18, 25, 15]), ('Middle', [70, 80, 45]), ('Ring', [74, 82, 45]), ('Pinky', [78, 80, 40])]:
            curl(rig, 'Right', f, c, r_palm)
        curl(rig, 'Right', 'Thumb', [15, 25, 15], r_palm)
    if kind in ('rifle', 'sniper'):
        l_fwd = (X * 0.85 + Y * 0.35 + Z * 0.2).normalized()
        l_palm = (Z * 0.95 - X * 0.1).normalized()
        l_wrist = lh + Vector((-0.06, -0.035, -0.045))
        shoulder = bw(rig, 'LeftArm').translation
        arm_ik(rig, 'Left', l_wrist, shoulder + Vector((-0.6, 0.0, -0.7)), l_fwd, l_palm)
        for f, c in [('Index', [55, 60, 35]), ('Middle', [60, 65, 35]), ('Ring', [64, 65, 35]), ('Pinky', [68, 62, 30])]:
            curl(rig, 'Left', f, c, l_palm)
        curl(rig, 'Left', 'Thumb', [10, 15, 5], l_palm)
    elif kind == 'pistol':
        l_fwd = (X * 0.6 + fwd_grip * 0.6 + Z * 0.3).normalized()
        l_palm = (X * 0.85 + Z * 0.3).normalized()
        l_wrist = rh + Vector((-0.06, -0.06, -0.08))
        shoulder = bw(rig, 'LeftArm').translation
        arm_ik(rig, 'Left', l_wrist, shoulder + Vector((-0.6, 0.0, -0.7)), l_fwd, l_palm)
        for f, c in [('Index', [50, 55, 30]), ('Middle', [55, 60, 30]), ('Ring', [60, 60, 30]), ('Pinky', [62, 58, 28])]:
            curl(rig, 'Left', f, c, l_palm)
    elif kind in ('knife', 'frag'):
        r_fwd = (Z * 0.25 + Y * 0.9).normalized()
        r_palm = (-X).normalized()
        r_wrist = rh + Vector((0.035, -0.09, -0.02))
        shoulder = bw(rig, 'RightArm').translation
        arm_ik(rig, 'Right', r_wrist, shoulder + Vector((0.6, 0.0, -0.7)), r_fwd, r_palm)
        cv = 78 if kind == 'knife' else 50
        for f in ('Index', 'Middle', 'Ring', 'Pinky'):
            curl(rig, 'Right', f, [cv, cv * 0.95, cv * 0.5], r_palm)
        curl(rig, 'Right', 'Thumb', [30, 35, 20], r_palm)
        shoulder = bw(rig, 'LeftArm').translation
        arm_ik(rig, 'Left', shoulder + Vector((0.0, 0.1, -0.5)), shoulder + Vector((-0.6, 0.0, -0.3)), Vector((0, 0.3, -1)), Vector((1, 0, 0)))


def bake_and_cut(body, rig, wid):
    """duplicate the posed body, apply armature, keep forearms+hands, add glove & sleeve"""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    me.transform(body.matrix_world)
    W = C.bone_weights(body)
    keep_bones = C.HAND + C.FARM
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    kind = KIND[wid]
    dele = []
    for f in bm.faces:
        w = sum(C.region_w(W[v.index], keep_bones) for v in f.verts) / len(f.verts)
        wu = sum(C.region_w(W[v.index], C.UARM) for v in f.verts) / len(f.verts)
        if w < 0.35 and wu < 0.5:
            dele.append(f)
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    out = bpy.data.meshes.new('arms_' + wid)
    bm.to_mesh(out); bm.free()
    for m in me.materials:
        out.materials.append(m)
    # keep weights of remaining verts for region tests: rebuild W map by nearest index (bmesh keeps order of survivors)
    obj = bpy.data.objects.new('fp_arms', out)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def region_split(obj, rig, wid):
    """assign materials: glove on hands, sleeve on forearm/upper arm, skin at wrist gap"""
    glove = C.mat('cloth|leather|2b2a27|0.55', (0.17, 0.16, 0.15), 0.55)
    sleeve = C.mat('cloth|camo|ffffff|0.85', (0.5, 0.5, 0.4), 0.85)
    cuff = C.mat('cloth|nylon|3a3a34|0.7', (0.2, 0.2, 0.2), 0.7)
    me = obj.data
    me.materials.clear()
    for m in (glove, sleeve, cuff):
        me.materials.append(m)
    wr = {s: (rig.matrix_world @ rig.pose.bones['mixamorig:' + s + 'Hand'].matrix).translation for s in ('Left', 'Right')}
    el = {s: (rig.matrix_world @ rig.pose.bones['mixamorig:' + s + 'ForeArm'].matrix).translation for s in ('Left', 'Right')}
    bm = bmesh.new(); bm.from_mesh(me)
    for f in bm.faces:
        c = f.calc_center_median()
        side = 'Left' if (c - wr['Left']).length + (c - el['Left']).length < (c - wr['Right']).length + (c - el['Right']).length else 'Right'
        fa = (wr[side] - el[side])
        t = (c - el[side]).dot(fa.normalized()) / fa.length  # 0 at elbow, 1 at wrist
        if t > 1.02:
            f.material_index = 0
        elif t > 0.9:
            f.material_index = 2
        else:
            f.material_index = 1
        f.smooth = True
    bm.to_mesh(me); bm.free()
    # push sleeve/cuff outward along normals (fabric volume), glove slightly
    bm = bmesh.new(); bm.from_mesh(me); bm.normal_update()
    for v in bm.verts:
        mats = {f.material_index for f in v.link_faces}
        off = 0.0
        if 1 in mats: off = 0.012
        if 2 in mats: off = 0.016
        if mats == {0}: off = 0.0015
        v.co += v.normal * off
    # smooth only sleeve region to remove muscle detail
    sv = [v for v in bm.verts if all(f.material_index in (1, 2) for f in v.link_faces)]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=sv, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(me); bm.free()
    sub = obj.modifiers.new('sub', 'SUBSURF'); sub.levels = 1


def export(objs, wid):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, f'fp_{wid}.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_animations=False, export_skins=False, export_yup=True)
    print('EXPORTED', path)


def main(wids):
    body, rig = build_base()
    for wid in wids:
        pose_for(wid, body, rig)
        obj = bake_and_cut(body, rig, wid)
        region_split(obj, rig, wid)
        export([obj], wid)
        if os.environ.get('PREVIEW'):
            preview(obj, wid)
        bpy.data.objects.remove(obj, do_unlink=True)


def preview(obj, wid):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f'w_{wid}.glb'))
    wobjs = [o for o in bpy.data.objects if o not in before]
    kind = KIND[wid]
    hip = HIP[kind]
    cam_pos = Vector((-hip[0], hip[2], -hip[1]))
    cam = bpy.data.objects.new('pcam', bpy.data.cameras.new('pcam'))
    bpy.context.scene.collection.objects.link(cam)
    cam.location = cam_pos
    cam.rotation_euler = (math.radians(90), 0, 0)  # look +Y
    cam.data.angle = math.radians(56 * 16 / 9)
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.angle = math.radians(56)
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'; sc.display.shading.show_cavity = True
    sc.render.resolution_x = 960; sc.render.resolution_y = 540
    hidden = [o for o in bpy.data.objects if o.type == 'MESH' and o not in wobjs and o != obj]
    for o in hidden:
        o.hide_render = True
    sc.render.filepath = f'/tmp/fp_{wid}.png'
    bpy.ops.render.render(write_still=True)
    # side view
    cam.location = cam_pos + Vector((0.9, 0.25, 0.0))
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    sc.render.filepath = f'/tmp/fp_{wid}_side.png'
    bpy.ops.render.render(write_still=True)
    cam.location = cam_pos + Vector((-0.6, 0.45, -0.35))
    cam.rotation_euler = (Vector((0, 0.25, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f'/tmp/fp_{wid}_low.png'
    bpy.ops.render.render(write_still=True)
    for o in hidden:
        o.hide_render = False
    for o in wobjs + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)


if __name__ == '__main__':
    ws = [a for a in sys.argv[1:] if a in KIND] or list(KIND)
    main(ws)
