"""v3.5.2 Kurt Adam: procedural werewolf-wolf (big, muscular, quadruped) with its own armature and
animations (idle, run gallop, attack, jump, howl). Skin-modifier body -> subdivided mesh -> automatic weights.
Faces +Y in Blender (= -Z, forward, in Godot). run: python3.13 tools/wolf_model.py"""
import bpy, bmesh, math
from mathutils import Vector

OUT = '/home/claude/sokak/assets/models/wolf.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30

# ------------------------------------------------------------------ skeleton points
P = {
    'hip': (0, -0.55, 1.08), 'spine': (0, -0.08, 1.16), 'chest': (0, 0.38, 1.26), 'neck': (0, 0.66, 1.32),
    'head': (0, 0.92, 1.58), 'snout': (0, 1.28, 1.5), 'nose': (0, 1.42, 1.47),
    'tail1': (0, -0.95, 1.08), 'tail2': (0, -1.38, 0.95), 'tail3': (0, -1.75, 0.8),
}
for s, x in (('L', 0.21), ('R', -0.21)):
    P['sh' + s] = (x * 1.25, 0.5, 1.18); P['elb' + s] = (x * 1.08, 0.6, 0.66); P['wri' + s] = (x * 1.08, 0.56, 0.16); P['fpaw' + s] = (x * 1.08, 0.74, 0.05)
    P['hp' + s] = (x * 1.1, -0.48, 1.02); P['kn' + s] = (x * 1.15, -0.24, 0.62); P['hk' + s] = (x * 1.15, -0.6, 0.3); P['rpaw' + s] = (x * 1.15, -0.5, 0.05); P['rtoe' + s] = (x * 1.15, -0.36, 0.04)
    P['ear' + s] = (x * 0.55, 0.86, 1.82)
R = {'hip': 0.33, 'spine': 0.37, 'chest': 0.47, 'neck': 0.33, 'head': 0.215, 'snout': 0.11, 'nose': 0.06, 'tail1': 0.14, 'tail2': 0.15, 'tail3': 0.06}
for s in 'LR':
    R.update({'sh' + s: 0.23, 'elb' + s: 0.135, 'wri' + s: 0.085, 'fpaw' + s: 0.095, 'hp' + s: 0.25, 'kn' + s: 0.155, 'hk' + s: 0.085, 'rpaw' + s: 0.08, 'rtoe' + s: 0.075, 'ear' + s: 0.045})
E = [('hip', 'spine'), ('spine', 'chest'), ('chest', 'neck'), ('neck', 'head'), ('head', 'snout'), ('snout', 'nose'),
     ('hip', 'tail1'), ('tail1', 'tail2'), ('tail2', 'tail3')]
for s in 'LR':
    E += [('chest', 'sh' + s), ('sh' + s, 'elb' + s), ('elb' + s, 'wri' + s), ('wri' + s, 'fpaw' + s),
          ('hip', 'hp' + s), ('hp' + s, 'kn' + s), ('kn' + s, 'hk' + s), ('hk' + s, 'rpaw' + s), ('rpaw' + s, 'rtoe' + s), ('head', 'ear' + s)]

# ------------------------------------------------------------------ body mesh from the skin modifier
names = list(P.keys())
me = bpy.data.meshes.new('wolf_body')
me.from_pydata([P[n] for n in names], [(names.index(a), names.index(b)) for a, b in E], [])
body = bpy.data.objects.new('wolf_body', me)
sc.collection.objects.link(body)
bpy.context.view_layer.objects.active = body
body.select_set(True)
sk = body.modifiers.new('skin', 'SKIN')
sk.use_smooth_shade = True
for i, n in enumerate(names):
    r = R[n]
    sv = me.skin_vertices[0].data[i]
    # wider than tall for the torso, flat ears
    if n in ('hip', 'spine', 'chest'):
        sv.radius = (r * 0.92, r * 1.02)
    elif n.startswith('ear'):
        sv.radius = (r * 1.8, r * 0.6)
    else:
        sv.radius = (r, r)
me.skin_vertices[0].data[names.index('hip')].use_root = True
sub = body.modifiers.new('sub', 'SUBSURF'); sub.levels = 2; sub.render_levels = 2
bpy.ops.object.convert(target='MESH')
# mane / back bulk: push the upper chest & neck outward a little
for v in body.data.vertices:
    co = v.co
    if 0.3 < co.y < 0.95 and co.z > 1.25:
        co.z += 0.05 * math.exp(-((co.y - 0.6) ** 2) / 0.05)
mat = bpy.data.materials.new('wolf_fur')
mat.use_nodes = True
bs = mat.node_tree.nodes['Principled BSDF']
bs.inputs['Base Color'].default_value = (0.11, 0.09, 0.08, 1)
bs.inputs['Roughness'].default_value = 0.92
body.data.materials.append(mat)

# eyes, fangs, claws
def ball(name, loc, r, m):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=r)
    mm = bpy.data.meshes.new(name); bm.to_mesh(mm); bm.free()
    o = bpy.data.objects.new(name, mm); sc.collection.objects.link(o); o.location = loc; mm.materials.append(m)
    return o
eye_m = bpy.data.materials.new('wolf_eye'); eye_m.use_nodes = True
eb = eye_m.node_tree.nodes['Principled BSDF']; eb.inputs['Base Color'].default_value = (1, 0.25, 0.05, 1)
eb.inputs['Emission Color'].default_value = (1, 0.25, 0.05, 1); eb.inputs['Emission Strength'].default_value = 6.0
claw_m = bpy.data.materials.new('wolf_claw'); claw_m.use_nodes = True
claw_m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.85, 0.82, 0.74, 1)
extras = [ball('eyeL', (0.075, 1.06, 1.63), 0.03, eye_m), ball('eyeR', (-0.075, 1.06, 1.63), 0.03, eye_m)]
for s, x in (('L', 1), ('R', -1)):
    for k in range(3):
        o = ball('claw', (P['fpaw' + s][0] + (k - 1) * 0.035, P['fpaw' + s][1] + 0.07, 0.03), 0.022, claw_m)
        o.scale = (0.6, 1.8, 0.6); extras.append(o)
    o = ball('fang', (x * 0.035, 1.33, 1.43), 0.014, claw_m); o.scale = (1, 1, 2.6); extras.append(o)
for o in extras:
    o.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = 'wolf_body'

# ------------------------------------------------------------------ armature
arm_d = bpy.data.armatures.new('wolf_rig')
arm = bpy.data.objects.new('wolf_rig', arm_d)
sc.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
B = {}
def bone(n, h, t, parent=None, conn=False):
    b = arm_d.edit_bones.new(n); b.head = Vector(h); b.tail = Vector(t); b.roll = 0
    if parent: b.parent = B[parent]; b.use_connect = conn
    B[n] = b; return b
bone('root', (0, -0.3, 0.0), (0, 0.0, 0.0))
bone('hips', P['hip'], P['spine'], 'root')
bone('spine', P['spine'], P['chest'], 'hips', True)
bone('chest', P['chest'], P['neck'], 'spine', True)
bone('neck', P['neck'], P['head'], 'chest', True)
bone('head', P['head'], P['snout'], 'neck', True)
bone('jaw', (0, 0.98, 1.47), (0, 1.36, 1.4), 'head')
bone('tail1', P['hip'], P['tail1'], 'hips'); bone('tail2', P['tail1'], P['tail2'], 'tail1', True); bone('tail3', P['tail2'], P['tail3'], 'tail2', True)
for s in 'LR':
    bone('upperarm' + s, P['sh' + s], P['elb' + s], 'chest'); bone('forearm' + s, P['elb' + s], P['wri' + s], 'upperarm' + s, True)
    bone('fpaw' + s, P['wri' + s], P['fpaw' + s], 'forearm' + s, True)
    bone('thigh' + s, P['hp' + s], P['kn' + s], 'hips'); bone('shin' + s, P['kn' + s], P['hk' + s], 'thigh' + s, True)
    bone('hock' + s, P['hk' + s], P['rpaw' + s], 'shin' + s, True); bone('rpaw' + s, P['rpaw' + s], P['rtoe' + s], 'hock' + s, True)
    bone('ear' + s, P['head'], P['ear' + s], 'head')
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# ------------------------------------------------------------------ animations
pb = arm.pose.bones
for b in pb:
    b.rotation_mode = 'XYZ'
def key(action_name, frames, fn):
    act = bpy.data.actions.new(action_name)
    arm.animation_data_create(); arm.animation_data.action = act
    for f in range(frames[0], frames[1] + 1):
        t = (f - frames[0]) / max(frames[1] - frames[0], 1)
        for b in pb:
            b.rotation_euler = (0, 0, 0); b.location = (0, 0, 0)
        fn(t)
        for b in pb:
            b.keyframe_insert('rotation_euler', frame=f)
            if b.name in ('root', 'hips'):
                b.keyframe_insert('location', frame=f)
    tr = arm.animation_data.nla_tracks.new(); tr.name = action_name
    tr.strips.new(action_name, frames[0], act)
    arm.animation_data.action = None
S = math.sin; C = math.cos; TAU = math.tau
def rx(n, a): pb[n].rotation_euler.x += a
def rz(n, a): pb[n].rotation_euler.z += a

def idle(t):
    w = TAU * t
    rx('chest', 0.03 * S(w)); rx('neck', -0.05 + 0.04 * S(w + 1)); rx('head', 0.05 * S(w * 2 + 0.5)); rz('head', 0.12 * S(w))
    rz('tail1', 0.25 * S(w * 2)); rz('tail2', 0.3 * S(w * 2 - 0.6)); rx('tail1', -0.15)
    rx('jaw', 0.06 + 0.04 * S(w * 2))
    pb['hips'].location.y = 0.015 * S(w * 2)
key('idle', (1, 60), idle)

def run(t):
    w = TAU * t
    # rotary gallop: fore pair and hind pair half a cycle apart, each pair slightly split
    for s, o in (('L', 0.0), ('R', 0.35)):
        a = w + o
        rx('upperarm' + s, 0.75 * S(a)); rx('forearm' + s, -0.55 * max(0.0, S(a + 1.2)) - 0.1); rx('fpaw' + s, 0.6 * max(0.0, -S(a + 0.4)))
        b = w + math.pi + o
        rx('thigh' + s, -0.7 * S(b)); rx('shin' + s, 0.7 * max(0.0, S(b + 1.0)) + 0.1); rx('hock' + s, -0.5 * max(0.0, S(b - 0.8)))
    rx('spine', 0.14 * S(w + 0.5)); rx('chest', -0.1 * S(w)); rx('hips', -0.08 * S(w + 0.5))
    rx('neck', 0.12 * S(w + 1.0) - 0.15); rx('head', -0.1 * S(w + 1.0) + 0.1)
    rx('tail1', -0.35 + 0.15 * S(w)); rz('tail2', 0.1 * S(w * 2))
    pb['hips'].location.y = 0.09 * abs(S(w))
    rx('earL', -0.35); rx('earR', -0.35); rx('jaw', 0.18)
key('run', (1, 18), run)

def attack(t):
    # rear up, both fore paws rake down, jaws snap
    up = S(min(t / 0.45, 1.0) * math.pi * 0.5) * (1 - max(0, (t - 0.6) / 0.4))
    rx('hips', 0.45 * up); rx('spine', 0.2 * up); rx('chest', 0.25 * up)
    sw = S(min(max((t - 0.3) / 0.35, 0), 1) * math.pi)
    for s in 'LR':
        rx('upperarm' + s, -1.4 * up + 1.6 * sw); rx('forearm' + s, -0.6 * up + 0.4 * sw); rx('fpaw' + s, 0.5 * up)
        rx('thigh' + s, 0.35 * up); rx('shin' + s, -0.3 * up)
    rx('neck', 0.3 * sw - 0.2 * up); rx('head', -0.2 * up); rx('jaw', 0.55 * up * (1 - sw) + 0.05)
    rx('tail1', -0.5 * up)
key('attack', (1, 16), attack)

def jump(t):
    k = S(t * math.pi)
    for s in 'LR':
        rx('upperarm' + s, -0.9 * k); rx('forearm' + s, 0.6 * k); rx('thigh' + s, 0.9 * k); rx('shin' + s, -0.7 * k)
    rx('spine', -0.15 * k); rx('neck', -0.2 * k); rx('tail1', -0.6 * k)
key('jump', (1, 20), jump)

def howl(t):
    k = S(min(t / 0.3, 1.0) * math.pi * 0.5) * (1 - max(0, (t - 0.8) / 0.2))
    rx('hips', -0.25 * k); rx('chest', -0.3 * k); rx('neck', -0.7 * k); rx('head', -0.5 * k); rx('jaw', 0.5 * k)
    for s in 'LR':
        rx('upperarm' + s, -0.3 * k); rx('thigh' + s, 0.25 * k)
key('howl', (1, 45), howl)

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_animations=True,
                          export_animation_mode='NLA_TRACKS', export_apply=False)
print('WROTE', OUT)
