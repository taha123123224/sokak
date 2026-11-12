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

def idle(t):
    w = TAU * t
    br = S(w)
    rot('spine', X, 0.03 * br); rot('chest', X, 0.04 * br)
    rot('neck', X, -0.04 * br); rot('head', Z, 0.22 * S(w + 0.7)); rot('head', X, 0.06 * S(w * 2))
    rot('jaw', X, -0.08 - 0.06 * max(0.0, S(w * 2)))
    for s, k in (('L', 1), ('R', -1)):
        rot('upperarm' + s, X, 0.06 * S(w + (0 if k > 0 else 1.5))); rot('forearm' + s, X, 0.05 * br)
        rot('hand' + s, Y, 0.1 * S(w * 2) * k)
    hips_up(0.012 * br)
key('idle', 72, idle)

def run(t):
    # hunched sprint: big leg strides, arms pumping opposite, body rocking, head forward
    w = TAU * t
    for s, ph in (('L', 0.0), ('R', math.pi)):
        a = w + ph
        rot('thigh' + s, X, 0.85 * S(a) + 0.15)
        rot('shin' + s, X, -0.75 * max(0.0, C(a)) - 0.1)
        rot('foot' + s, X, 0.55 * max(0.0, -S(a + 0.6)) - 0.15 * max(0.0, C(a)))
        rot('toe' + s, X, 0.4 * max(0.0, S(a - 0.8)))
        b = w + ph + math.pi
        rot('upperarm' + s, X, 0.42 + 0.5 * S(b))
        rot('forearm' + s, X, 0.35 + 0.3 * S(b + 0.6))
        rot('hand' + s, X, 0.25 * S(b))
    rot('hips', Z, 0.12 * S(w)); rot('hips', X, -0.15); rot('spine', X, -0.22); rot('chest', Z, -0.18 * S(w)); rot('chest', X, -0.12 + 0.05 * S(w * 2))
    rot('neck', X, 0.3); rot('head', X, 0.2 - 0.05 * S(w * 2)); rot('jaw', X, -0.22)
    hips_up(0.07 * abs(C(w)) - 0.05)
key('run', 18, run)

def attack(t):
    # two-handed overhead rake: wind up (0-0.35), slash down and across (0.35-0.6), recover
    up = math.sin(min(t / 0.35, 1.0) * math.pi * 0.5) * (1.0 - max(0.0, (t - 0.65) / 0.35))
    sl = math.sin(min(max((t - 0.32) / 0.3, 0.0), 1.0) * math.pi * 0.5) * (1.0 - max(0.0, (t - 0.7) / 0.3))
    for s, k in (('L', 1), ('R', -1)):
        rot('upperarm' + s, X, 2.0 * up - 1.6 * sl)
        rot('upperarm' + s, Y, -0.5 * k * up + 0.6 * k * sl)
        rot('forearm' + s, X, 0.6 * up - 0.2 * sl)
        rot('hand' + s, X, -0.4 * up + 0.5 * sl)
        rot('thigh' + s, X, 0.2 * sl if k > 0 else -0.1 * sl)
    rot('spine', X, 0.18 * up - 0.4 * sl); rot('chest', X, 0.15 * up - 0.3 * sl)
    rot('neck', X, 0.2 * up - 0.1 * sl); rot('head', X, 0.1 * up); rot('jaw', X, -0.45 * up - 0.2 * sl)
    hips_up(-0.06 * sl, 0.1 * sl)
key('attack', 18, attack, loop=False)

def jump(t):
    k = S(t * math.pi)
    for s in 'LR':
        rot('thigh' + s, X, 1.0 * k); rot('shin' + s, X, -1.1 * k); rot('foot' + s, X, 0.6 * k)
        rot('upperarm' + s, X, -0.6 * k); rot('forearm' + s, X, 0.5 * k)
    rot('spine', X, -0.2 * k); rot('head', X, 0.15 * k)
key('jump', 20, jump, loop=False)

def howl(t):
    k = S(min(t / 0.25, 1.0) * math.pi * 0.5) * (1.0 - max(0.0, (t - 0.82) / 0.18))
    rot('spine', X, 0.25 * k); rot('chest', X, 0.3 * k); rot('neck', X, 0.45 * k); rot('head', X, 0.6 * k)
    rot('jaw', X, -0.5 * k)
    for s, kk in (('L', 1), ('R', -1)):
        rot('upperarm' + s, Y, 0.35 * kk * k); rot('upperarm' + s, X, 0.3 * k); rot('forearm' + s, X, 0.4 * k)
    hips_up(0.03 * k)
key('howl', 48, howl, loop=False)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_image_format='JPEG', export_jpeg_quality=88, export_apply=False)
print('WROTE', OUT)
