"""Animated first-person arms (skinned Rocketbox arms + keyframed actions solved with IK).

For every weapon exports assets/models/fp_<id>.glb containing the armature, the skinned arm mesh and actions:
  idle, reload (mag out / new mag in), shell + pump (shotgun), bolt (snipers), slash + stab (knives), throw (grenade)
plus assets/models/fp_<id>.json with timing metadata (lengths, magazine attach window, sound cues).
Usage: python3.13 tools/fp_anim.py [ids...]   PREVIEW=1 renders /tmp/fpa_<id>_<action>_<t>.png
"""
import sys, os, math, json
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
sys.path.insert(0, os.path.dirname(__file__))
import characters as C
import fp_hands as F
import fp_rb as RB

FPS = 30
OUT = C.OUT
X = Vector((1, 0, 0)); Y = Vector((0, 1, 0)); Z = Vector((0, 0, 1))


def n(v):
    return Vector(v).normalized()


# ---------------------------------------------------------------- weapon geometry probes
def weapon_parts(wid):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f'w_{wid}.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    parts = {}
    for o in new:
        base = o.name.split('.')[0]
        if o.type == 'MESH':
            cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
            mn = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
            mx = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
            parts[base] = (mn, mx)
        else:
            parts.setdefault('@' + base, (o.matrix_world.translation.copy(),) * 2)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    return parts


def center(parts, key, default):
    if key in parts:
        mn, mx = parts[key]
        return (mn + mx) / 2, mn, mx
    return Vector(default), Vector(default), Vector(default)


# ---------------------------------------------------------------- rig helpers
def arm_bones(rig):
    return [pb for pb in rig.pose.bones if any(k in pb.name for k in ('Shoulder', 'Arm', 'Hand'))]


def snapshot(rig):
    return {pb.name: pb.matrix_basis.copy() for pb in rig.pose.bones}


def restore(rig, snap):
    for k, m in snap.items():
        rig.pose.bones[k].matrix_basis = m
    bpy.context.view_layer.update()


def hand_state(rig, side):
    M = F.bw(rig, side + 'Hand')
    m3 = M.to_3x3()
    return M.translation.copy(), (m3 @ Y).normalized(), (m3 @ Vector(rig['pa_' + side + 'Hand'])).normalized()


def catmull(p0, p1, p2, p3, u):
    u2, u3 = u * u, u * u * u
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)


def sample(path, t):
    """path: [(t, pos, fwd, palm)] -> smooth interpolated state"""
    if t <= path[0][0]:
        return path[0][1:]
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        if a[0] <= t <= b[0]:
            u = (t - a[0]) / max(b[0] - a[0], 1e-6)
            p0 = path[max(i - 1, 0)][1]; p3 = path[min(i + 2, len(path) - 1)][1]
            pos = catmull(p0, a[1], b[1], p3, u)
            e = u * u * (3 - 2 * u)
            fwd = a[2].lerp(b[2], e).normalized()
            palm = a[3].lerp(b[3], e).normalized()
            return pos, fwd, palm
    return path[-1][1:]


def rot_state(st, q, off=Vector()):
    p, f, pa = st
    return (p + off, (q @ f).normalized(), (q @ pa).normalized())


# ---------------------------------------------------------------- per-weapon choreography
def choreograph(wid, rig, meta):
    kind = F.KIND[wid]
    parts = weapon_parts(wid)
    L0 = hand_state(rig, 'Left'); R0 = hand_state(rig, 'Right')
    lsh = F.bw(rig, 'LeftArm').translation.copy(); rsh = F.bw(rig, 'RightArm').translation.copy()
    lpole = lsh + Vector((-0.6, 0.0, -0.7)); rpole = rsh + Vector((0.6, 0.0, -0.7))
    rh = F.weapon_points(wid).get('rhand', Vector())
    acts = {}
    acts['idle'] = make_action(rig, 'idle', 1.0, {})
    if kind in ('rifle', 'sniper', 'pistol'):
        mc, mmn, mmx = center(parts, 'mag', rh + Vector((0, 0.12, -0.08)))
        if kind == 'pistol':
            grab = Vector((mc.x - 0.012, mc.y + 0.005, mmn.z - 0.045))
            g_fwd = n((0.35, 0.85, 0.25)); g_palm = n((0.15, -0.05, 1.0))
            drop = Vector((0, 0.0, -0.13)); away = Vector((-0.16, -0.06, -0.42))
        else:
            grab = Vector((mc.x - 0.055, mc.y - 0.01, mc.z - 0.035))
            g_fwd = n((0.25, 0.7, 0.65)); g_palm = n((1.0, 0.05, -0.15))
            drop = Vector((0, 0.05, -0.16)); away = Vector((-0.22, -0.12, -0.45))
        G = (grab, g_fwd, g_palm)
        def at(o, st=G):
            return (st[0] + o, st[1], st[2])
        slap = at(Vector((0, 0, 0.03)))
        path = [(0.0, *L0), (0.13, *G), (0.22, *G), (0.33, *at(drop)), (0.46, *at(away)), (0.57, *at(away)),
                (0.69, *at(drop * 0.8)), (0.79, *G), (0.84, *slap), (0.88, *G), (1.0, *L0)]
        if kind == 'pistol':
            # left hand comes from its support grip under the right hand
            path[0] = (0.0, *L0); path[-1] = (1.0, *L0)
        acts['reload'] = make_action(rig, 'reload', 2.0, {'Left': (path, lpole)})
        meta['reload'] = {'len': acts['reload'], 'attach': [0.22, 0.79], 'mag_out': 0.24, 'mag_in': 0.79,
                          'bolt': 0.9 if kind != 'pistol' else 0.92}
    if wid == 'spas':
        port = rh + Vector((-0.035, 0.11, -0.085))
        P = (port, n((0.3, 0.9, 0.3)), n((0.3, 0.0, 1.0)))
        down = (L0[0] + Vector((-0.06, -0.1, -0.32)), L0[1], L0[2])
        path = [(0.0, *L0), (0.28, *down), (0.55, *P), (0.68, P[0] + Vector((0, 0.03, 0.03)), P[1], P[2]), (1.0, *L0)]
        acts['shell'] = make_action(rig, 'shell', 0.55, {'Left': (path, lpole)})
        back = (L0[0] + Vector((0, -0.085, -0.005)), L0[1], L0[2])
        acts['pump'] = make_action(rig, 'pump', 0.45, {'Left': ([(0.0, *L0), (0.35, *back), (0.45, *back), (0.8, *L0), (1.0, *L0)], lpole)})
        meta['shell'] = {'len': acts['shell'], 'insert': 0.66}
        meta['pump'] = {'len': acts['pump']}
    if kind == 'sniper':
        bc, bmn, bmx = center(parts, 'bolt', rh + Vector((0.04, 0.08, 0.075)))
        B = (Vector((bmx.x + 0.035, bc.y + 0.01, bc.z - 0.01)), n((-0.6, 0.6, -0.5)), n((-1.0, 0.0, 0.2)))
        lift = (B[0] + Vector((0, 0, 0.035)), B[1], B[2])
        back = (lift[0] + Vector((0, -0.09, 0)), lift[1], lift[2])
        path = [(0.0, *R0), (0.22, *B), (0.34, *lift), (0.5, *back), (0.64, *lift), (0.74, *B), (1.0, *R0)]
        acts['bolt'] = make_action(rig, 'bolt', 1.05, {'Right': (path, rpole)})
        meta['bolt'] = {'len': acts['bolt'], 'curve': [[0.0, 0, 0], [0.34, 0, 1], [0.5, 1, 1], [0.64, 0, 1], [0.74, 0, 0], [1.0, 0, 0]]}
    if kind == 'knife':
        def yaw(deg):
            return Quaternion(Z, math.radians(deg))
        def roll(deg):
            return Quaternion(Y, math.radians(deg))
        wind = rot_state(R0, yaw(28) @ roll(-15), Vector((0.11, -0.06, 0.09)))
        end = rot_state(R0, yaw(-62) @ roll(45), Vector((-0.3, 0.2, -0.12)))
        follow = rot_state(R0, yaw(-70) @ roll(55), Vector((-0.34, 0.12, -0.2)))
        acts['slash'] = make_action(rig, 'slash', 0.5, {'Right': ([(0.0, *R0), (0.22, *wind), (0.45, *end), (0.6, *follow), (1.0, *R0)], rpole)})
        pull = rot_state(R0, Quaternion(X, math.radians(-12)), Vector((0.02, -0.1, 0.02)))
        thrust = rot_state(R0, Quaternion(X, math.radians(8)), Vector((-0.04, 0.32, 0.04)))
        acts['stab'] = make_action(rig, 'stab', 0.8, {'Right': ([(0.0, *R0), (0.32, *pull), (0.5, *thrust), (0.62, *thrust), (1.0, *R0)], rpole)})
        meta['slash'] = {'len': acts['slash'], 'hit': 0.38}
        meta['stab'] = {'len': acts['stab'], 'hit': 0.5}
    if kind == 'frag':
        back = rot_state(R0, Quaternion(X, math.radians(-30)), Vector((0.09, -0.07, 0.13)))
        rel = rot_state(R0, Quaternion(X, math.radians(30)), Vector((-0.03, 0.38, 0.14)))
        thru = rot_state(R0, Quaternion(X, math.radians(55)), Vector((-0.12, 0.26, -0.3)))
        low = (R0[0] + Vector((0.05, -0.05, -0.35)), R0[1], R0[2])
        acts['throw'] = make_action(rig, 'throw', 1.0, {'Right': ([(0.0, *R0), (0.3, *back), (0.36, *back), (0.5, *rel), (0.62, *thru), (0.78, *low), (1.0, *R0)], rpole)})
        meta['throw'] = {'len': acts['throw'], 'hold': 0.33, 'release': 0.5, 'reappear': 0.8}
    meta['acts'] = {k: v for k, v in acts.items()}
    return acts


# ---------------------------------------------------------------- build
def cut_arms(body):
    W = C.bone_weights(body)
    bm = bmesh.new(); bm.from_mesh(body.data)
    dele = []
    for f in bm.faces:
        w = sum(C.region_w(W[v.index], C.HAND + C.FARM) for v in f.verts) / len(f.verts)
        wu = sum(C.region_w(W[v.index], C.UARM) for v in f.verts) / len(f.verts)
        if w < 0.35 and wu < 0.5:
            dele.append(f)
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(body.data); bm.free()
    for p in body.data.polygons:
        p.use_smooth = True
    sub = body.modifiers.new('sub', 'SUBSURF'); sub.levels = 1; sub.render_levels = 1
    # subdivision before the armature so the exporter keeps skinning
    while body.modifiers[0].name != 'sub':
        with bpy.context.temp_override(object=body, active_object=body):
            bpy.ops.object.modifier_move_up(modifier='sub')


def export(rig, body, wid, meta):
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True); body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = os.path.join(OUT, f'fp_{wid}.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                              export_skins=True, export_morph=False, export_yup=True, export_optimize_animation_size=False)
    with open(os.path.join(OUT, f'fp_{wid}.json'), 'w') as fh:
        json.dump(meta, fh, indent=1)
    print('EXPORTED', path, os.path.getsize(path) // 1024, 'KB', list(meta.get('acts', {}).keys()))


def preview(rig, body, wid, acts):
    sc = bpy.context.scene
    kind = F.KIND[wid]
    hip = F.HIP[kind]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f'w_{wid}.glb'))
    wobjs = [o for o in bpy.data.objects if o not in before]
    cam = bpy.data.objects.new('pcam', bpy.data.cameras.new('pcam'))
    sc.collection.objects.link(cam)
    cam.location = Vector((-hip[0], hip[2], -hip[1]))
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.sensor_fit = 'VERTICAL'; cam.data.angle = math.radians(56)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'; sc.display.shading.show_cavity = True
    sc.render.resolution_x = 640; sc.render.resolution_y = 360
    sc.render.fps = FPS
    for name in [a for a in acts if a in os.environ.get('PACTS', 'reload,slash,stab,throw,bolt,shell,pump').split(',')]:
        act = bpy.data.actions.get(name)
        rig.animation_data.action = act
        try:
            rig.animation_data.action_slot = act.slots[0]
        except Exception:
            pass
        tts = [float(x) for x in os.environ.get('PTIMES', '0,0.13,0.33,0.46,0.79,0.9').split(',')]
        for view in ('eye', 'side'):
            if view == 'eye':
                cam.location = Vector((-hip[0], hip[2], -hip[1])); cam.rotation_euler = (math.radians(90), 0, 0)
                cam.data.angle = math.radians(56)
            else:
                cam.location = Vector((-0.75, 0.15, -0.2)); cam.rotation_euler = (Vector((0, 0.15, -0.05)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
                cam.data.angle = math.radians(50)
            for tt in tts:
                sc.frame_set(int(round(tt * acts[name] * FPS)))
                sc.render.filepath = f'/tmp/fpa_{wid}_{name}_{view}_{int(tt * 100):02d}.png'
                bpy.ops.render.render(write_still=True)
    # the weapon parts stay static in preview (Godot attaches mag/knife to the hand)
    rig.animation_data.action = None
    for o in wobjs + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)


def main(wids):
    body, rig = RB.build_base_rb()
    cut_arms(body)
    if rig.animation_data is None:
        rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for wid in wids:
        for tr in list(rig.animation_data.nla_tracks):
            rig.animation_data.nla_tracks.remove(tr)
        for a in list(bpy.data.actions):
            bpy.data.actions.remove(a)
        rig.animation_data.action = None
        F.pose_for(wid, body, rig)
        _store['base'] = snapshot(rig)
        meta = {'kind': F.KIND[wid]}
        acts = choreograph(wid, rig, meta)
        export(rig, body, wid, meta)
        if os.environ.get('PREVIEW'):
            preview(rig, body, wid, acts)


_store = {}


def make_action(rig, name, length, tracks, extra=None):
    """tracks: {side: (path, pole)} ; length in seconds"""
    base = _store['base']
    act = bpy.data.actions.new(name)
    rig.animation_data.action = act
    frames = max(2, int(round(length * FPS)))
    bones = arm_bones(rig)
    for f in range(frames + 1):
        t = f / frames
        restore(rig, base)
        for side, (path, pole) in tracks.items():
            pos, fwd, palm = sample(path, t)
            F.arm_ik(rig, side, pos, pole, fwd, palm)
        if extra:
            extra(t)
        bpy.context.view_layer.update()
        for pb in bones:
            pb.keyframe_insert('rotation_quaternion', frame=f)
            pb.keyframe_insert('location', frame=f)
    tr = rig.animation_data.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, 0, act)
    try:
        st.action_slot = act.slots[0]
    except Exception:
        pass
    rig.animation_data.action = None
    restore(rig, base)
    return frames / FPS


if __name__ == '__main__':
    main([a for a in sys.argv[1:] if a in F.KIND] or list(F.KIND))
