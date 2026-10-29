"""Shouldered-rifle / two-hand-pistol aim poses for the Rocketbox avatars (third-person bots).

Solved in Blender with real IK + pole targets on the actual skeleton, so in game the hands sit exactly on the
weapon (no runtime IK, no stretching). Adds actions 'AimRifle' and 'AimPistol' and writes a JSON with the
weapon grip transform (Godot / glTF Y-up space of the exported character root).
"""
import math, json, os
import bpy
from mathutils import Vector, Matrix, Quaternion


def _w(arm, b):
    return (arm.matrix_world @ arm.pose.bones[b].matrix).translation.copy()


def _wm(arm, b):
    return arm.matrix_world @ arm.pose.bones[b].matrix


def _set_world(arm, b, M):
    arm.pose.bones[b].matrix = arm.matrix_world.inverted() @ M
    bpy.context.view_layer.update()


def _rotate_world(arm, b, q, pivot=None):
    M = _wm(arm, b)
    p = M.translation.copy() if pivot is None else pivot
    _set_world(arm, b, Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p) @ M)


def _empty(name, loc):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    return e


def _ik(arm, side, target, pole):
    # effector = head of the hand bone (Bip01 bone tails are arbitrary after FBX import)
    pb = arm.pose.bones[f'Bip01 {side} Hand']
    c = pb.constraints.new('IK')
    c.target = target
    c.pole_target = pole
    c.chain_count = 3
    c.use_tail = False
    # Bip01 forearm points toward the hand; pole angle chosen so the elbow plane faces the pole
    c.pole_angle = math.radians(-90)
    return c


def _two_bone(arm, side, T, P):
    """analytic two-bone IK: wrist (hand head) to T, elbow bent toward the pole point P"""
    ua, fa, hd = f'Bip01 {side} UpperArm', f'Bip01 {side} Forearm', f'Bip01 {side} Hand'
    for _ in range(2):
        S = _w(arm, ua); E = _w(arm, fa); W = _w(arm, hd)
        a = (E - S).length; b = (W - E).length
        d = T - S
        dist = min(d.length, (a + b) * 0.999)
        dn = d.normalized()
        # elbow position in the plane (S, T, P)
        pv = (P - S); pv = (pv - pv.dot(dn) * dn).normalized()
        cos_a = max(-1.0, min(1.0, (a * a + dist * dist - b * b) / (2 * a * dist)))
        ang = math.acos(cos_a)
        E2 = S + dn * (math.cos(ang) * a) + pv * (math.sin(ang) * a)
        _rotate_world(arm, ua, (E - S).normalized().rotation_difference((E2 - S).normalized()), pivot=S)
        E = _w(arm, fa); W = _w(arm, hd)
        T2 = S + dn * dist
        _rotate_world(arm, fa, (W - E).normalized().rotation_difference((T2 - E).normalized()), pivot=E)


def _palm_point(arm, side, along=0.5, depth=0.02):
    h = _w(arm, f'Bip01 {side} Hand')
    mid = _w(arm, f'Bip01 {side} Finger2')
    fd, ac = _hand_dir(arm, side)
    return h + (mid - h) * along + _palm(side, fd, ac) * depth


def _grip_point(arm, R):
    h = _w(arm, 'Bip01 R Hand')
    mid = _w(arm, 'Bip01 R Finger2')
    fd, ac = _hand_dir(arm, 'R')
    palm_n = _palm('R', fd, ac)
    return h + (mid - h) * 0.55 + palm_n * 0.025


def _hand_dir(arm, side):
    h = _w(arm, f'Bip01 {side} Hand')
    mid = _w(arm, f'Bip01 {side} Finger2')
    idx = _w(arm, f'Bip01 {side} Finger1')
    pky = _w(arm, f'Bip01 {side} Finger4') if f'Bip01 {side} Finger4' in arm.pose.bones else _w(arm, f'Bip01 {side} Finger3')
    fd = (mid - h).normalized()
    across = (idx - pky).normalized()
    return fd, across


def _palm(side, fd, ac):
    # right hand: palm = fd x across ; left hand (mirrored): palm = across x fd
    return (fd.cross(ac) if side == 'R' else ac.cross(fd)).normalized()


def _orient_hand(arm, side, fd_t, palm_t):
    """rotate the hand so the knuckles point along fd_t and the palm faces palm_t"""
    fd_t = fd_t.normalized()
    palm_t = (palm_t - palm_t.dot(fd_t) * fd_t).normalized()
    across_t = (palm_t.cross(fd_t) if side == 'R' else fd_t.cross(palm_t)).normalized()
    for _ in range(3):
        fd, ac = _hand_dir(arm, side)
        q1 = fd.rotation_difference(fd_t)
        _rotate_world(arm, f'Bip01 {side} Hand', q1)
        fd, ac = _hand_dir(arm, side)
        a2 = (ac - ac.dot(fd_t) * fd_t).normalized()
        b2 = (across_t - across_t.dot(fd_t) * fd_t).normalized()
        q2 = a2.rotation_difference(b2)
        _rotate_world(arm, f'Bip01 {side} Hand', q2)


def _curl(arm, side, amount, thumb=0.5):
    """curl fingers around the grip: each joint bends toward the palm (segment directions from joint positions,
    because Bip01 bone axes are arbitrary after the FBX import)"""
    fd, ac = _hand_dir(arm, side)
    palm_n = _palm(side, fd, ac)
    for fi in range(5):
        names = [f'Bip01 {side} Finger{fi}{suf}' for suf in ('', '1', '2')]
        names = [n for n in names if n in arm.pose.bones]
        for k, bn in enumerate(names):
            p0 = _w(arm, bn)
            if k + 1 < len(names):
                seg = (_w(arm, names[k + 1]) - p0).normalized()
            else:
                seg = (p0 - _w(arm, names[k - 1])).normalized() if k > 0 else fd
            axis = seg.cross(palm_n).normalized()
            ang = (amount * (0.75 if k == 0 else 1.0)) if fi > 0 else thumb * (0.5 if k == 0 else 0.7)
            # rotating by +ang around (seg x palm) turns seg toward palm_n
            _rotate_world(arm, bn, Quaternion(axis, ang))


def build_aim(arm, cid, out_json):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    # NLA strips (Idle/Walk/Run) would overwrite every pose edit on update: mute them while solving
    tracks = list(arm.animation_data.nla_tracks) if arm.animation_data else []
    for t in tracks:
        t.mute = True
    data = {}
    new_acts = []
    for kind in ('rifle', 'pistol'):
        # neutral standing pose (rest) as base
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        F = Vector((0, -1, 0)); U = Vector((0, 0, 1)); R = F.cross(U).normalized()   # character right
        rs = _w(arm, 'Bip01 R UpperArm'); ls = _w(arm, 'Bip01 L UpperArm')
        if (rs - ls).dot(R) < 0:
            R = -R
        pel = _w(arm, 'Bip01 Pelvis')
        if kind == 'rifle':
            # bladed stance: torso yawed ~18 deg (right shoulder back), slight forward lean, head down to the sight
            for b, ang in (('Bip01 Spine1', 9), ('Bip01 Spine2', 9)):
                _rotate_world(arm, b, Quaternion(U, math.radians(-ang) if R.x < 0 else math.radians(ang)))
            for b, ang in (('Bip01 Spine1', 3), ('Bip01 Spine2', 3)):
                _rotate_world(arm, b, Quaternion(R, math.radians(-ang)))
        else:
            for b, ang in (('Bip01 Spine1', 2), ('Bip01 Spine2', 2)):
                _rotate_world(arm, b, Quaternion(R, math.radians(-ang)))
        if kind == 'rifle':
            # chin down to the sights; the clavicles hang off Bip01 Neck, so do it before solving the arms
            _rotate_world(arm, 'Bip01 Neck', Quaternion(R, math.radians(-14)))
        rs = _w(arm, 'Bip01 R UpperArm'); ls = _w(arm, 'Bip01 L UpperArm')
        head = _w(arm, 'Bip01 Head')
        chest_c = (rs + ls) * 0.5
        sh_w = (rs - ls).length
        if kind == 'rifle':
            # stock in the right shoulder pocket, sight line under the right eye
            pocket = rs - R * 0.10 + F * 0.04 - U * 0.03
            grip = pocket + F * 0.27 + U * 0.07
            gun_fwd = F.copy()
            fore = grip + gun_fwd * 0.26 + U * 0.02 - R * 0.005
        else:
            grip = chest_c + F * 0.46 + U * 0.06 + R * 0.02
            gun_fwd = F.copy()
            fore = grip - R * 0.035 - U * 0.01 + F * 0.005
        gun_up = (U - U.dot(gun_fwd) * gun_fwd).normalized()
        # IK targets for both arms (wrist positions are a bit behind the grip points)
        rt = _empty('ik_r', grip - gun_fwd * 0.03 + R * 0.03 + U * 0.02)
        lt = _empty('ik_l', fore - U * 0.022 - R * 0.015 if kind == 'rifle' else fore - gun_fwd * 0.03 - R * 0.035)
        rp = _empty('pole_r', rs + R * 0.6 - U * (0.25 if kind == 'rifle' else 0.6) + F * 0.0)
        lp = _empty('pole_l', ls - R * 0.25 - U * 0.7 + F * 0.2)
        bpy.context.view_layer.update()
        tgt_r = rt.location.copy()
        for it in range(3):
            _two_bone(arm, 'R', tgt_r, rp.location.copy())
            # back of the hand on the right of the grip, knuckles forward-down, knuckle line running down the grip
            if kind == 'rifle':
                _orient_hand(arm, 'R', gun_fwd * 0.75 - U * 0.6 - R * 0.1, -R)
            else:
                _orient_hand(arm, 'R', gun_fwd * 0.85 - U * 0.45 - R * 0.1, -R)
            gr = _grip_point(arm, R)
            tgt_r = tgt_r + (grip - gr)
        # support hand: iterate so the palm centre presses against the underside of the handguard
        contact = (fore - U * 0.03) if kind == 'rifle' else (grip - R * 0.035 + gun_fwd * 0.005 - U * 0.01)
        tgt_l = lt.location.copy()
        for it in range(4):
            _two_bone(arm, 'L', tgt_l, lp.location.copy())
            if kind == 'rifle':
                _orient_hand(arm, 'L', gun_fwd * 0.8 + R * 0.35 + U * 0.25, U)
            else:
                _orient_hand(arm, 'L', gun_fwd * 0.55 + R * 0.65 - U * 0.4, R * 0.85 - gun_fwd * 0.2)
            tgt_l = tgt_l + (contact - _palm_point(arm, 'L', 0.5, 0.022))
        for e in (rt, lt, rp, lp):
            bpy.data.objects.remove(e, do_unlink=True)
        bpy.context.view_layer.update()
        pass
        # hands: right wraps the pistol grip (fingers point across, to the left and down), left cups the handguard
        if kind == 'rifle':
            _orient_hand(arm, 'R', gun_fwd * 0.75 - U * 0.6 - R * 0.1, -R)
            _curl(arm, 'R', math.radians(78), 0.7)
            _curl(arm, 'L', math.radians(70), 0.6)
        else:
            _orient_hand(arm, 'R', gun_fwd * 0.85 - U * 0.45 - R * 0.1, -R)
            _curl(arm, 'R', math.radians(80), 0.7)
            _curl(arm, 'L', math.radians(72), 0.6)
        # head: chin down + tilt toward the stock
        if kind == 'rifle':
            _rotate_world(arm, 'Bip01 Head', Quaternion(F, math.radians(10) if R.x < 0 else math.radians(-10)))
            _rotate_world(arm, 'Bip01 Head', Quaternion(R, math.radians(-6)))
        else:
            _rotate_world(arm, 'Bip01 Head', Quaternion(R, math.radians(-4)))
        bpy.context.view_layer.update()
        # actual grip point from the solved right hand (palm centre), so the weapon sits in the fist
        grip_real = _grip_point(arm, R)
        if os.environ.get('AIMPREVIEW'):
            _preview(arm, cid, kind, grip_real, R)
        # key the pose
        act = bpy.data.actions.new('Aim' + kind.capitalize())
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = act
        for fr in (1, 2):
            for pb in arm.pose.bones:
                pb.keyframe_insert('rotation_quaternion', frame=fr)
                if pb.name == 'Bip01 Pelvis':
                    pb.keyframe_insert('location', frame=fr)
        arm.animation_data.action = None
        new_acts.append(act)
        # Blender Z-up (-Y forward) -> glTF/Godot Y-up: (x, y, z) -> (x, z, -y)
        cv = lambda v: [round(v.x, 5), round(v.z, 5), round(-v.y, 5)]
        data[kind] = {'grip': cv(grip_real), 'fwd': cv(gun_fwd), 'up': cv(gun_up)}
        print('AIM', cid, kind, data[kind])
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    for t in tracks:
        t.mute = False
    for act in new_acts:
        tr = arm.animation_data.nla_tracks.new(); tr.name = act.name
        st = tr.strips.new(act.name, 1, act)
        try:
            st.action_slot = act.slots[0]
        except Exception:
            pass
    with open(out_json, 'w') as f:
        json.dump(data, f)


def _preview(arm, cid, kind, grip, R):
    sc = bpy.context.scene
    before = set(bpy.data.objects)
    w = 'ak47' if kind == 'rifle' else 'glock'
    bpy.ops.import_scene.gltf(filepath=os.path.join(os.path.dirname(__file__), '..', 'assets', 'models', f'w_{w}.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for r in roots:
        r.location = grip
        r.rotation_mode = 'XYZ'
        r.rotation_euler = (0, 0, math.pi)
    cam = bpy.data.objects.new('pcam', bpy.data.cameras.new('pcam'))
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 560; sc.render.resolution_y = 560
    tgt = grip + Vector((0, 0.1, 0.05))
    views = [R * 1.6 + Vector((0, -0.3, 0.2)), Vector((0, -1.7, 0.15)) - R * 0.6, -R * 1.5 + Vector((0, -0.6, 0.1)), R * 0.5 + Vector((0, -0.35, 0.12)), -R * 0.55 + Vector((0, -0.45, -0.1))]
    for vi, off in enumerate(views):
        cam.location = tgt + off
        cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.angle = math.radians(45)
        sc.render.filepath = f'/tmp/aim_{cid}_{kind}_{vi}.png'
        bpy.ops.render.render(write_still=True)
    for o in new + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)
