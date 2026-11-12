"""v3.6.1 Kurt Adam: rig + animate the CC-BY werewolf "Howling" by Daniele De Filippis (Sketchfab) for the game.
Input: the user's Howling.usdz (static mesh). Output: assets/models/wolf_hd.glb with a fitted armature and
idle / run / attack / jump / howl animations. Faces +Y in Blender (= -Z, forward, in Godot); feet at z=0.
run: python3.13 tools/wolf_hd.py /path/Howling.usdz"""
import bpy, bmesh, math, sys
import numpy as np
from mathutils import Vector, Quaternion, Matrix

SRC = sys.argv[-1] if sys.argv[-1].endswith('.usdz') else '/tmp/wolfusd/w.usdz'
OUT = '/home/claude/sokak/assets/models/wolf_hd.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
bpy.ops.wm.usd_import(filepath=SRC)
meshes = [o for o in sc.objects if o.type == 'MESH']
# bake world transforms, turn to face +Y, feet on the floor
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation((0, 0, 0.9985)) @ mw)
    o.matrix_world = Matrix.Identity(4)
for o in list(sc.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o)
body = next(o for o in meshes if 'Wolf_MAT' in o.name)
fur = next(o for o in meshes if 'fur_MAT' in o.name)
eyes = [o for o in meshes if 'eye' in o.name]

def decimate(o, ratio):
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new('dec', 'DECIMATE'); m.ratio = ratio; m.use_collapse_triangulate = False
    bpy.ops.object.modifier_apply(modifier='dec')
decimate(body, 0.55)
decimate(fur, 0.5)

# ------------------------------------------------------------------ armature fitted to the model
def f(x, y, z):      # landmark from the source's frame (front -Y, origin at mid height) to ours
    return Vector((-x, -y, z + 0.9985))
J = {
    'hips': f(0, 0.02, -0.05), 'spine': f(0, 0.12, 0.25), 'chest': f(0, 0.18, 0.55), 'neck': f(0, 0.16, 0.8),
    'head': f(0, -0.06, 0.8), 'snout': f(0, -0.5, 0.66), 'jaw0': f(0, -0.12, 0.66), 'jaw1': f(0, -0.45, 0.6),
}
for s, k in (('L', 1), ('R', -1)):   # L = the wolf's left side (+X after the turn... named by our x sign)
    J['clav' + s] = f(-k * 0.1, 0.2, 0.78); J['sh' + s] = f(-k * 0.38, 0.25, 0.85); J['elb' + s] = f(-k * 0.75, 0.33, 0.62)
    J['wri' + s] = f(-k * 0.97, 0.42, 0.33); J['hand' + s] = f(-k * 1.04, 0.46, 0.14)
    J['hip' + s] = f(-k * 0.2, 0.05, -0.1); J['kn' + s] = f(-k * 0.26, -0.22, -0.38); J['hk' + s] = f(-k * 0.27, 0.38, -0.62)
    J['ball' + s] = f(-k * 0.31, 0.05, -0.93); J['toe' + s] = f(-k * 0.32, -0.14, -0.97)
arm_d = bpy.data.armatures.new('wolf_rig')
arm = bpy.data.objects.new('wolf_rig', arm_d)
sc.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
B = {}
def bone(n, h, t, parent=None, conn=False):
    b = arm_d.edit_bones.new(n); b.head = J[h] if isinstance(h, str) else Vector(h); b.tail = J[t] if isinstance(t, str) else Vector(t)
    b.roll = 0
    if parent: b.parent = B[parent]; b.use_connect = conn
    B[n] = b
bone('root', (0, 0, 0), (0, 0.3, 0))
bone('hips', 'hips', 'spine', 'root')
bone('spine', 'spine', 'chest', 'hips', True)
bone('chest', 'chest', 'neck', 'spine', True)
bone('neck', 'neck', 'head', 'chest', True)
bone('head', 'head', 'snout', 'neck', True)
bone('jaw', 'jaw0', 'jaw1', 'head')
for s in 'LR':
    bone('clav' + s, 'clav' + s, 'sh' + s, 'chest')
    bone('upperarm' + s, 'sh' + s, 'elb' + s, 'clav' + s, True)
    bone('forearm' + s, 'elb' + s, 'wri' + s, 'upperarm' + s, True)
    bone('hand' + s, 'wri' + s, 'hand' + s, 'forearm' + s, True)
    bone('thigh' + s, 'hip' + s, 'kn' + s, 'hips')
    bone('shin' + s, 'kn' + s, 'hk' + s, 'thigh' + s, True)
    bone('foot' + s, 'hk' + s, 'ball' + s, 'shin' + s, True)
    bone('toe' + s, 'ball' + s, 'toe' + s, 'foot' + s, True)
bpy.ops.object.mode_set(mode='OBJECT')
DEFORM = [b.name for b in arm_d.bones if b.name != 'root']
arm_d.bones['root'].use_deform = False

# ------------------------------------------------------------------ skin weights
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

segs = [(n, np.array(arm_d.bones[n].head_local), np.array(arm_d.bones[n].tail_local)) for n in DEFORM]
def seg_weights(P, k=2, pw=6.0):
    """fallback: inverse-distance weights to the nearest bone segments"""
    D = []
    for n, a, b in segs:
        ab = b - a; t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
        D.append(np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    D = np.stack(D, 1) + 1e-4
    idx = np.argsort(D, 1)[:, :k]
    w = 1.0 / np.take_along_axis(D, idx, 1) ** pw
    return idx, w / w.sum(1, keepdims=True)
def fill_unweighted(o):
    for n in DEFORM:
        if n not in o.vertex_groups: o.vertex_groups.new(name=n)
    P = np.array([tuple(v.co) for v in o.data.vertices])
    miss = [v.index for v in o.data.vertices if sum(g.weight for g in v.groups) < 1e-3]
    if miss:
        idx, w = seg_weights(P[miss])
        for j, vi in enumerate(miss):
            for c in range(idx.shape[1]):
                o.vertex_groups[DEFORM[idx[j, c]]].add([vi], float(w[j, c]), 'REPLACE')
    print(o.name, 'unweighted filled', len(miss), '/', len(P))
fill_unweighted(body)

# fur cards and eyes: copy the weights from the nearest body surface
for o in [fur] + eyes:
    for n in DEFORM:
        o.vertex_groups.new(name=n)
    bpy.context.view_layer.objects.active = o
    dt = o.modifiers.new('dt', 'DATA_TRANSFER')
    dt.object = body; dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'; dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
    bpy.ops.object.modifier_apply(modifier='dt')
    fill_unweighted(o)
for o in eyes:   # eyes stay locked to the skull
    for v in o.data.vertices:
        for g in list(v.groups):
            g.weight = 0.0
    o.vertex_groups['head'].add([v.index for v in o.data.vertices], 1.0, 'REPLACE')
for o in [fur] + eyes:
    o.parent = arm
    m = o.modifiers.new('arm', 'ARMATURE'); m.object = arm

# ------------------------------------------------------------------ animations (world-axis FK helpers)
pb = arm.pose.bones
for b in pb:
    b.rotation_mode = 'QUATERNION'
REST = {b.name: arm_d.bones[b.name].matrix_local.to_3x3() for b in pb}
Q = {}
def rot(n, axis, ang):
    """rotate bone n about a world axis (in its rest orientation) — accumulates for this frame"""
    la = (REST[n].inverted() @ Vector(axis)).normalized()
    Q[n] = Quaternion(la, ang) @ Q.get(n, Quaternion())
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
S = math.sin; C = math.cos; TAU = math.tau
def key(name, n_frames, fn, loop=True):
    act = bpy.data.actions.new(name)
    arm.animation_data_create(); arm.animation_data.action = act
    for fr in range(n_frames + (1 if loop else 0)):
        t = fr / n_frames
        Q.clear()
        for b in pb:
            b.location = (0, 0, 0)
        fn(t)
        for b in pb:
            b.rotation_quaternion = Q.get(b.name, Quaternion())
            b.keyframe_insert('rotation_quaternion', frame=fr + 1)
            if b.name == 'hips':
                b.keyframe_insert('location', frame=fr + 1)
    tr = arm.animation_data.nla_tracks.new(); tr.name = name
    tr.strips.new(name, 1, act)
    arm.animation_data.action = None
def hips_up(dz, dy=0.0):
    # hips location is in bone-local space: convert a world offset
    pb['hips'].location = REST['hips'].inverted() @ Vector((0, dy, dz))

# ---- pose-key authoring: each pose is {(bone, axis): angle} (+ 'dz'/'dy' hip offsets); poses are eased
def posed(keys, t):
    """keys: [(time, pose_dict, ease)], returns the interpolated pose at t"""
    for i in range(len(keys) - 1):
        t0, p0, _ = keys[i]; t1, p1, e = keys[i + 1]
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            if e == 'fast': u = 1 - (1 - u) ** 4          # snap (strikes)
            elif e == 'in': u = u * u * u                 # wind-up
            else: u = u * u * (3 - 2 * u)                 # smooth
            out = {}
            for k in set(p0) | set(p1):
                out[k] = p0.get(k, 0.0) + (p1.get(k, 0.0) - p0.get(k, 0.0)) * u
            return out
    return dict(keys[-1][1])
AX = {'X': X, 'Y': Y, 'Z': Z}
def apply(pose):
    dz = pose.pop('dz', 0.0); dy = pose.pop('dy', 0.0)
    for (bn, ax), v in pose.items():
        rot(bn, AX[ax], v)
    hips_up(dz, dy)

def idle(t):
    # heavy breathing, shoulders rolling, head scanning, claws flexing
    w = TAU * t
    br = S(w); br2 = S(w * 2 + 0.4)
    rot('spine', X, 0.035 * br); rot('chest', X, 0.05 * br); rot('chest', Z, 0.04 * S(w + 1.0))
    rot('neck', X, -0.05 * br); rot('head', Z, 0.3 * S(w + 0.7)); rot('head', X, 0.08 * br2 + 0.04)
    rot('jaw', X, -0.1 - 0.08 * max(0.0, S(w * 2)))
    for s, k in (('L', 1), ('R', -1)):
        ph = 0.0 if k > 0 else 1.7
        rot('clav' + s, X, 0.05 * br); rot('clav' + s, Z, -0.04 * k * br)
        rot('upperarm' + s, X, 0.08 * S(w + ph)); rot('upperarm' + s, Y, -0.05 * k * br)
        rot('forearm' + s, X, 0.1 + 0.08 * S(w + ph + 0.6))
        rot('hand' + s, X, 0.18 * S(w * 2 + ph)); rot('hand' + s, Y, 0.12 * k * S(w * 2 + ph))
        rot('thigh' + s, X, 0.03 * br); rot('shin' + s, X, -0.04 * br)
    hips_up(-0.025 * (0.5 + 0.5 * br))
key('idle', 90, idle)

def walk(t):
    # prowling walk: low, heavy steps, shoulders rolling against the hips, head low and steady
    w = TAU * t
    for s, ph, k in (('L', 0.0, 1), ('R', math.pi, -1)):
        a = w + ph
        rot('thigh' + s, X, 0.45 * S(a) + 0.12)
        rot('shin' + s, X, -0.55 * max(0.0, C(a + 0.3)) - 0.12)
        rot('foot' + s, X, 0.3 * max(0.0, -S(a + 0.5)) + 0.1 * max(0.0, C(a)))
        rot('toe' + s, X, 0.3 * max(0.0, S(a - 1.0)))
        b = a + math.pi
        rot('upperarm' + s, X, 0.32 + 0.38 * S(b)); rot('upperarm' + s, Y, 0.06 * k)
        rot('forearm' + s, X, 0.3 + 0.25 * max(0.0, S(b + 0.8)))
        rot('hand' + s, X, 0.2 * S(b + 0.5))
    rot('hips', Z, 0.1 * S(w)); rot('hips', Y, 0.05 * S(w))
    rot('spine', X, -0.14); rot('spine', Z, -0.05 * S(w)); rot('chest', Z, -0.14 * S(w)); rot('chest', X, -0.08)
    rot('neck', X, 0.18); rot('head', Z, 0.1 * S(w)); rot('head', X, 0.06 + 0.03 * S(w * 2 + 1.0)); rot('jaw', X, -0.12)
    hips_up(-0.06 + 0.04 * abs(C(w)))
key('walk', 36, walk)

def run(t):
    # werewolf sprint: deep forward lean, long bounding strides with airtime, arms clawing forward,
    # head stays level (counter-rotated), strong shoulder roll and hip drop at each contact
    w = TAU * t
    for s, ph, k in (('L', 0.0, 1), ('R', math.pi, -1)):
        a = w + ph
        rot('thigh' + s, X, 1.05 * S(a) + 0.32)
        rot('shin' + s, X, -1.15 * max(0.0, C(a + 0.2)) - 0.06)
        rot('foot' + s, X, 0.65 * max(0.0, -S(a + 0.7)) + 0.25 * max(0.0, C(a)))
        rot('toe' + s, X, 0.5 * max(0.0, S(a - 0.9)))
        b = a + math.pi
        rot('upperarm' + s, X, 0.75 + 0.7 * S(b)); rot('upperarm' + s, Y, 0.12 * k * S(b))
        rot('forearm' + s, X, 0.55 + 0.45 * max(0.0, S(b + 0.9)))
        rot('hand' + s, X, 0.35 * S(b + 0.6) + 0.15)
        rot('clav' + s, X, 0.08 * S(b))
    rot('hips', X, -0.42); rot('hips', Z, 0.14 * S(w)); rot('hips', Y, 0.06 * S(w))
    rot('spine', X, -0.3 + 0.06 * S(w * 2)); rot('chest', X, -0.12 + 0.05 * S(w * 2 + 0.5)); rot('chest', Z, -0.22 * S(w))
    rot('neck', X, 0.55); rot('head', X, 0.32 - 0.07 * S(w * 2 + 0.8)); rot('jaw', X, -0.28)
    hips_up(0.0 + 0.12 * max(0.0, S(w * 2 - 0.6)), 0.05)
key('run', 20, run)

def strike(side):
    k = 1 if side == 'L' else -1   # L = the +X arm
    o = 'R' if side == 'L' else 'L'
    rest = {}
    wind = {('chest', 'Z'): -0.42 * k, ('spine', 'Z'): -0.2 * k, ('hips', 'Z'): -0.1 * k, ('spine', 'X'): 0.06,
            ('upperarm' + side, 'X'): -0.5, ('upperarm' + side, 'Y'): -1.25 * k, ('forearm' + side, 'X'): 1.1, ('hand' + side, 'X'): -0.45,
            ('upperarm' + o, 'X'): 0.35, ('forearm' + o, 'X'): 0.5, ('head', 'Z'): 0.15 * k, ('jaw', 'X'): -0.35,
            ('thigh' + side, 'X'): -0.12, ('thigh' + o, 'X'): 0.25, ('shin' + o, 'X'): -0.25, 'dz': -0.05}
    hit = {('chest', 'Z'): 0.55 * k, ('spine', 'Z'): 0.25 * k, ('hips', 'Z'): 0.12 * k, ('spine', 'X'): -0.28, ('chest', 'X'): -0.12,
           ('upperarm' + side, 'X'): 1.15, ('upperarm' + side, 'Y'): 0.1 * k, ('upperarm' + side, 'Z'): 1.05 * k, ('forearm' + side, 'X'): 0.25,
           ('hand' + side, 'X'): 0.55, ('upperarm' + o, 'X'): -0.25, ('upperarm' + o, 'Y'): -0.35 * -k, ('forearm' + o, 'X'): 0.35,
           ('head', 'Z'): -0.12 * k, ('neck', 'X'): 0.12, ('jaw', 'X'): -0.5,
           ('thigh' + side, 'X'): 0.45, ('shin' + side, 'X'): -0.35, ('thigh' + o, 'X'): -0.22, 'dz': -0.1, 'dy': 0.18}
    follow = {kk: v * 0.75 for kk, v in hit.items()}
    follow[('upperarm' + side, 'X')] = 0.95; follow[('upperarm' + side, 'Z')] = 1.25 * k; follow[('forearm' + side, 'X')] = 0.4
    return [(0.0, rest, 's'), (0.28, wind, 'in'), (0.4, hit, 'fast'), (0.56, follow, 's'), (1.0, rest, 's')]
for nm, sd in (('attack', 'L'), ('attack2', 'R')):
    kk = strike(sd)
    key(nm, 18, lambda t, kk=kk: apply(posed(kk, t)), loop=False)

def slam_keys():
    rest = {}
    up = {('spine', 'X'): 0.32, ('chest', 'X'): 0.22, ('neck', 'X'): 0.2, ('head', 'X'): 0.25, ('jaw', 'X'): -0.6, 'dz': 0.04}
    for s, k in (('L', 1), ('R', -1)):
        up[('upperarm' + s, 'X')] = 2.1; up[('upperarm' + s, 'Y')] = -0.55 * k; up[('forearm' + s, 'X')] = 0.75; up[('hand' + s, 'X')] = -0.5
        up[('thigh' + s, 'X')] = 0.05
    down = {('spine', 'X'): -0.55, ('chest', 'X'): -0.3, ('neck', 'X'): 0.35, ('head', 'X'): 0.15, ('jaw', 'X'): -0.55, 'dz': -0.2, 'dy': 0.22}
    for s, k in (('L', 1), ('R', -1)):
        down[('upperarm' + s, 'X')] = 0.95; down[('upperarm' + s, 'Y')] = 0.15 * k; down[('forearm' + s, 'X')] = 0.2; down[('hand' + s, 'X')] = 0.6
        down[('thigh' + s, 'X')] = 0.55; down[('shin' + s, 'X')] = -0.6; down[('foot' + s, 'X')] = 0.15
    hold = {kk: v * 0.9 for kk, v in down.items()}
    return [(0.0, rest, 's'), (0.36, up, 'in'), (0.48, down, 'fast'), (0.66, hold, 's'), (1.0, rest, 's')]
sk = slam_keys()
key('attack3', 24, lambda t: apply(posed(sk, t)), loop=False)

def jump(t):
    # take-off stretch -> tuck at the apex -> reach for the landing
    tk = [(0.0, {}, 's'),
          (0.15, {('spine', 'X'): 0.15, ('thigh' + 'L', 'X'): -0.3, ('thighR', 'X'): -0.3, ('upperarmL', 'X'): -0.5, ('upperarmR', 'X'): -0.5, ('head', 'X'): 0.25}, 's'),
          (0.5, {('spine', 'X'): -0.3, ('thighL', 'X'): 1.15, ('thighR', 'X'): 1.0, ('shinL', 'X'): -1.3, ('shinR', 'X'): -1.2, ('footL', 'X'): 0.5, ('footR', 'X'): 0.5,
                 ('upperarmL', 'X'): 0.9, ('upperarmR', 'X'): 0.9, ('forearmL', 'X'): 0.9, ('forearmR', 'X'): 0.9, ('neck', 'X'): 0.3, ('jaw', 'X'): -0.3}, 's'),
          (1.0, {('spine', 'X'): -0.1, ('thighL', 'X'): 0.5, ('thighR', 'X'): 0.35, ('shinL', 'X'): -0.4, ('shinR', 'X'): -0.35,
                 ('upperarmL', 'X'): 1.0, ('upperarmR', 'X'): 1.0, ('upperarmL', 'Y'): -0.5, ('upperarmR', 'Y'): 0.5, ('jaw', 'X'): -0.25}, 's')]
    apply(posed(tk, t))
key('jump', 24, jump, loop=False)

def tuck(t):
    # flip: compact ball, held (the body itself spins in-game)
    p = {('spine', 'X'): -0.55, ('chest', 'X'): -0.3, ('neck', 'X'): -0.2, ('head', 'X'): -0.2,
         ('thighL', 'X'): 1.6, ('thighR', 'X'): 1.6, ('shinL', 'X'): -1.9, ('shinR', 'X'): -1.9, ('footL', 'X'): 0.6, ('footR', 'X'): 0.6,
         ('upperarmL', 'X'): 1.4, ('upperarmR', 'X'): 1.4, ('upperarmL', 'Y'): 0.35, ('upperarmR', 'Y'): -0.35, ('forearmL', 'X'): 1.3, ('forearmR', 'X'): 1.3,
         ('jaw', 'X'): -0.2, 'dz': 0.2}
    apply(posed([(0.0, {}, 's'), (0.25, p, 's'), (0.75, p, 's'), (1.0, {}, 's')], t))
key('tuck', 18, tuck, loop=False)

def howl(t):
    # transformation roar: crouch and gather, then rise with the chest thrown open, arms flung wide and
    # back, head up, jaws wide, the whole body trembling with the roar; settle back into the stance
    w = TAU * t
    gather = {('spine', 'X'): -0.45, ('chest', 'X'): -0.2, ('neck', 'X'): -0.1, ('head', 'X'): -0.2,
              ('thighL', 'X'): 0.6, ('thighR', 'X'): 0.6, ('shinL', 'X'): -0.7, ('shinR', 'X'): -0.7, ('footL', 'X'): 0.2, ('footR', 'X'): 0.2,
              ('upperarmL', 'X'): 0.5, ('upperarmR', 'X'): 0.5, ('forearmL', 'X'): 1.0, ('forearmR', 'X'): 1.0,
              ('upperarmL', 'Y'): 0.2, ('upperarmR', 'Y'): -0.2, 'dz': -0.2}
    roar = {('spine', 'X'): 0.35, ('chest', 'X'): 0.35, ('neck', 'X'): 0.5, ('head', 'X'): 0.75, ('jaw', 'X'): -0.75,
            ('upperarmL', 'Y'): -0.95, ('upperarmR', 'Y'): 0.95, ('upperarmL', 'X'): -0.35, ('upperarmR', 'X'): -0.35,
            ('forearmL', 'X'): 0.45, ('forearmR', 'X'): 0.45, ('handL', 'X'): -0.5, ('handR', 'X'): -0.5,
            ('clavL', 'Z'): 0.15, ('clavR', 'Z'): -0.15, 'dz': 0.04}
    pk = [(0.0, {}, 's'), (0.18, gather, 's'), (0.32, roar, 'fast'), (0.78, roar, 's'), (1.0, {}, 's')]
    apply(posed(pk, t))
    tr = smoothstep01 = max(0.0, min(1.0, (t - 0.3) / 0.05)) * max(0.0, min(1.0, (0.8 - t) / 0.1))
    rot('chest', X, 0.03 * S(w * 22) * tr); rot('head', Z, 0.04 * S(w * 27 + 1.0) * tr)
    rot('upperarmL', X, 0.03 * S(w * 19) * tr); rot('upperarmR', X, 0.03 * S(w * 21 + 2.0) * tr)
key('howl', 60, howl, loop=False)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_image_format='JPEG', export_jpeg_quality=88, export_apply=False)
print('WROTE', OUT)
