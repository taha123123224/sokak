"""Procedural weapon models -> assets/models/w_<id>.glb
Material names are mapped to real PBR materials inside Godot (MatLib.gd).
Any material starting with 'gun_paint' receives the weapon skin.
Blender: +Y = muzzle direction, +Z up. Origin = right hand grip point.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector
from bkit import *

OUT = os.path.join(ROOT, 'assets', 'models')


AO_DIR = os.path.join(ROOT, 'assets', 'tex', 'ao')
os.makedirs(AO_DIR, exist_ok=True)


def bake_ao(wid):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = int(os.environ.get('AO_SAMPLES', '48'))
    sc.render.bake.margin = 6
    meshes = [o for o in sc.objects if o.type == 'MESH']
    for o in meshes:
        me = o.data
        if not me.uv_layers:
            me.uv_layers.new(name='UV')
        uv = me.uv_layers.new(name='UVAO')
        me.uv_layers.active = uv
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        with bpy.context.temp_override(active_object=o, object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.015)
            bpy.ops.object.mode_set(mode='OBJECT')
        res = 1024 if o.name == 'body' else 512
        img = bpy.data.images.new(f'ao_{wid}_{o.name}', res, res)
        img.generated_color = (1, 1, 1, 1)
        tmp_nodes = []
        for slot in o.material_slots:
            m = slot.material
            if m is None:
                continue
            m = m.copy() if m.users > 1 and False else m
            n = m.node_tree.nodes.new('ShaderNodeTexImage')
            n.image = img
            uvn = m.node_tree.nodes.new('ShaderNodeUVMap'); uvn.uv_map = 'UVAO'
            m.node_tree.links.new(uvn.outputs[0], n.inputs[0])
            m.node_tree.nodes.active = n
            tmp_nodes.append((m, n, uvn))
        with bpy.context.temp_override(active_object=o, object=o, selected_objects=[o], selected_editable_objects=[o]):
            try:
                bpy.ops.object.bake(type='AO', use_selected_to_active=False)
            except Exception as e:
                print('bake failed', o.name, e)
        img.filepath_raw = os.path.join(AO_DIR, f'{wid}_{o.name}.png')
        img.file_format = 'PNG'
        img.save()
        for (m, n, uvn) in tmp_nodes:
            m.node_tree.nodes.remove(n); m.node_tree.nodes.remove(uvn)
        me.uv_layers.active = me.uv_layers['UV']
        me.uv_layers['UV'].active_render = True
    sc.render.engine = 'BLENDER_WORKBENCH'


# real-world overall lengths (m) -> every model is scaled to true size
REAL_LEN = {'ak47': 0.88, 'm4a1': 0.84, 'mp5': 0.70, 'p90': 0.50, 'spas': 1.04, 'awp': 1.18, 'kar98': 1.11, 'glock': 0.186,
            'deagle': 0.27, 'revolver': 0.29, 'scar': 0.97, 'ump45': 0.69, 'aug': 0.79, 'vector': 0.62, 'm249': 1.04, 'knife': 0.30, 'karambit': 0.20}


def true_scale(wid):
    if wid not in REAL_LEN:
        return
    root = bpy.data.objects.get('W_' + wid)
    if root is None:
        return
    bpy.context.view_layer.update()
    ys = []
    for o in bpy.context.scene.objects:
        if o.type == 'MESH' and not o.name.startswith('pin'):
            for c in o.bound_box:
                ys.append((o.matrix_world @ Vector(c)).y)
    if not ys:
        return
    L = max(ys) - min(ys)
    f = REAL_LEN[wid] / L
    if abs(f - 1.0) < 0.03:
        return
    for o in list(root.children):
        o.location = o.location * f
        o.scale = o.scale * f
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for o in root.children:
        if o.type == 'EMPTY':
            o.scale = (1, 1, 1)
    print('true scale', wid, round(L, 3), '->', REAL_LEN[wid], 'f=%.3f' % f)


def finish_export(wid):
    true_scale(wid)
    if os.environ.get('AO'):
        bake_ao(wid)
    export_glb(os.path.join(OUT, f'w_{wid}.glb'))


def M():
    return dict(
        metal=mat('gun_metal', (0.16, 0.16, 0.17), 0.9, 0.38),
        dark=mat('gun_metal_dark', (0.06, 0.06, 0.065), 0.8, 0.45),
        paint=mat('gun_paint', (0.05, 0.05, 0.05), 0.0, 0.65),
        wood=mat('gun_paint_wood', (0.45, 0.22, 0.09), 0.0, 0.45),
        olive=mat('gun_paint_olive', (0.22, 0.26, 0.17), 0.0, 0.6),
        tan=mat('gun_paint_tan', (0.55, 0.45, 0.32), 0.0, 0.6),
        poly=mat('gun_polymer', (0.04, 0.04, 0.042), 0.0, 0.75),
        glass=mat('gun_glass', (0.1, 0.2, 0.25), 0.2, 0.05, alpha=0.4),
        dot=mat('gun_dot', (1, 0.1, 0.05), 0, 0.3, emission=(1, 0.05, 0.02), emit_strength=8),
        brass=mat('gun_brass', (0.8, 0.6, 0.25), 1.0, 0.3),
        blade=mat('gun_blade', (0.75, 0.76, 0.78), 1.0, 0.18),
        green=mat('gun_paint_green', (0.18, 0.24, 0.12), 0.1, 0.7),
        rubber=mat('gun_rubber', (0.03, 0.03, 0.03), 0.0, 0.9),
    )


def start(wid):
    reset()
    root = empty('W_' + wid)
    body = empty('body_grp', parent=root)
    return root, body


def points(root, muzzle, sight, lhand, eject=(0.03, 0.1, 0.05), extra=None):
    empty('muzzle', muzzle, root)
    empty('sight', sight, root)
    empty('lhand', lhand, root)
    empty('rhand', (0, 0, 0), root)
    empty('eject', eject, root)
    for k, v in (extra or {}).items():
        empty(k, v, root)


def finish(wid, root, body, keep_parts=()):
    apply_all_modifiers()
    box_uv_all(4.0)
    j = join_children(body, 'body')
    if j:
        j.parent = root
        # body_grp empty now has the mesh child; reparent keep transform
    export_glb(os.path.join(OUT, f'w_{wid}.glb'))


# ---------------------------------------------------------------- shared parts
def rail(parent, m, length, loc, name='rail'):
    x, y, z = loc
    box(name, (0.021, length, 0.006), (x, y, z), m=m, parent=parent, bevel=0.0015)
    n = int(length / 0.01)
    for i in range(n):
        box(f'{name}_t{i}', (0.023, 0.0052, 0.004), (x, y - length / 2 + 0.005 + i * 0.01, z + 0.004), m=m, parent=parent, bevel=0.0008, segs=1)


def reddot(parent, m, loc):
    x, y, z = loc
    box('rd_base', (0.026, 0.05, 0.012), (x, y, z), m=m['dark'], parent=parent, bevel=0.003)
    tube('rd_tube', 0.019, 0.016, 0.045, (x, y, z + 0.028), m=m['dark'], parent=parent, verts=32)
    cyl('rd_lens', 0.0162, 0.002, (x, y + 0.015, z + 0.028), m=m['glass'], parent=parent, verts=32)
    sphere('rd_dot', 0.0012, (x, y + 0.016, z + 0.028), m=m['dot'], parent=parent, seg=8, rings=4)
    cyl('rd_knob', 0.006, 0.01, (x + 0.022, y - 0.005, z + 0.028), m=m['metal'], parent=parent, axis='X', verts=16)
    box('rd_hood', (0.03, 0.04, 0.004), (x, y, z + 0.049), m=m['dark'], parent=parent, bevel=0.0015)


def holo(parent, m, loc):
    """EOTech style holographic sight"""
    x, y, z = loc
    box('ho_base', (0.03, 0.09, 0.015), (x, y, z), m=m['dark'], parent=parent, bevel=0.004)
    box('ho_l', (0.004, 0.05, 0.04), (x - 0.017, y + 0.01, z + 0.026), m=m['dark'], parent=parent, bevel=0.0015)
    box('ho_r', (0.004, 0.05, 0.04), (x + 0.017, y + 0.01, z + 0.026), m=m['dark'], parent=parent, bevel=0.0015)
    box('ho_top', (0.038, 0.05, 0.005), (x, y + 0.01, z + 0.048), m=m['dark'], parent=parent, bevel=0.002)
    box('ho_glass', (0.03, 0.002, 0.028), (x, y + 0.03, z + 0.03), m=m['glass'], parent=parent)
    sphere('ho_dot', 0.0013, (x, y + 0.031, z + 0.031), m=m['dot'], parent=parent, seg=8, rings=4)
    box('ho_btn', (0.008, 0.012, 0.006), (x, y - 0.035, z + 0.01), m=m['rubber'], parent=parent, bevel=0.002)


def scope(parent, m, loc, length=0.32, r=0.0165, obj_r=0.025, mount_dy=(-0.06, 0.06)):
    x, y, z = loc
    cyl('sc_tube', r, length * 0.55, (x, y, z), m=m['dark'], parent=parent, verts=32)
    lathe('sc_obj', [(r, 0), (r, 0.02), (obj_r, 0.06), (obj_r, 0.10), (obj_r - 0.002, 0.102), (obj_r - 0.004, 0.1)], (x, y + length * 0.27, z), (0, 0, 0), m=m['dark'], parent=parent, axis='Y', seg=32)
    lathe('sc_eye', [(r, 0), (r, -0.02), (0.021, -0.045), (0.021, -0.075), (0.019, -0.077)], (x, y - length * 0.27, z), (0, 0, 0), m=m['dark'], parent=parent, axis='Y', seg=32)
    cyl('sc_lens_f', obj_r - 0.003, 0.002, (x, y + length * 0.27 + 0.098, z), m=m['glass'], parent=parent, verts=32)
    cyl('sc_lens_b', 0.018, 0.002, (x, y - length * 0.27 - 0.074, z), m=m['glass'], parent=parent, verts=32)
    cyl('sc_tur_t', 0.011, 0.02, (x, y, z + r + 0.008), m=m['metal'], parent=parent, axis='Z', verts=20, bevel=0.001)
    cyl('sc_tur_s', 0.011, 0.02, (x + r + 0.008, y, z), m=m['metal'], parent=parent, axis='X', verts=20, bevel=0.001)
    cyl('sc_saddle', r + 0.004, 0.05, (x, y, z), m=m['dark'], parent=parent, verts=24)
    for i, dy in enumerate(mount_dy):
        torus(f'sc_ring{i}', r + 0.002, 0.004, (x, y + dy, z), (90, 0, 0), m=m['metal'], parent=parent, seg=24, mseg=8)
        box(f'sc_mnt{i}', (0.012, 0.016, 0.03), (x, y + dy, z - r - 0.012), m=m['metal'], parent=parent, bevel=0.002)


def curved_mag(name, parent, m, c, r_rear, r_front, a0, a1, width, n=10, lip=0.0):
    rear = arc_pts(c, r_rear, a0, a1, n)
    front = arc_pts(c, r_front, a1, a0, n)
    pts = rear + front
    return prof(name, pts, width, m=m, parent=parent, bevel=0.003)


def grip(parent, m, loc, angle=18, h=0.105, w=0.03, d=0.042, name='grip'):
    pts = [(-d / 2, 0), (d / 2, 0), (d / 2 - 0.004, -h * 0.5), (d / 2 + 0.002, -h * 0.75), (d / 2 - 0.006, -h), (-d / 2 - 0.004, -h), (-d / 2 - 0.006, -h * 0.4)]
    o = prof(name, pts, w, loc, (-angle, 0, 0), m=m, parent=parent, bevel=0.006, segs=3)
    return o


def trigger_guard(parent, m, y0, y1, z, depth=0.03, t=0.004, w=0.012):
    pts = [(y0, z), (y1, z), (y1, z - depth), (y0 + 0.01, z - depth), (y0, z - depth + 0.01)]
    inner = [(y0 + t, z), (y1 - t, z), (y1 - t, z - depth + t), (y0 + t + 0.008, z - depth + t), (y0 + t, z - depth + 0.012)]
    g = prof('tg', pts, w, m=m, parent=parent, bevel=0.0015)
    cut = prof('tg_cut', inner, w * 3, m=m, parent=parent, bevel=0)
    boolean_diff(g, cut)
    # trigger blade
    prof('trigger', [(y1 - 0.012, z), (y1 - 0.006, z), (y1 - 0.01, z - depth * 0.6), (y1 - 0.016, z - depth * 0.7), (y1 - 0.016, z - depth * 0.4)], 0.006, m=m, parent=parent, bevel=0.001)


def mag_curved_ak(parent, m, y_top=0.05):
    return curved_mag('mag', parent, m, (0.40, 0.0), 0.355, 0.268, 180, 213, 0.026, n=12)


# ---------------------------------------------------------------- weapons
def ak47():
    root, b = start('ak47'); m = M()
    metal, wood = m['metal'], m['wood']
    prof('receiver', [(-0.14, 0.0), (0.18, 0.0), (0.18, 0.058), (0.16, 0.074), (-0.11, 0.074), (-0.14, 0.05)], 0.044, m=metal, parent=b, bevel=0.003)
    box('dustcover', (0.041, 0.27, 0.022), (0, 0.02, 0.075), m=metal, parent=b, bevel=0.01, segs=3)
    for i in range(6):
        box(f'rib{i}', (0.042, 0.004, 0.012), (0, -0.09 + i * 0.006, 0.084), m=metal, parent=b, bevel=0.001)
    box('rsight', (0.03, 0.045, 0.022), (0, 0.175, 0.083), m=metal, parent=b, bevel=0.003)
    box('rsight_leaf', (0.018, 0.06, 0.006), (0, 0.18, 0.097), m=metal, parent=b, bevel=0.0015)
    box('trunnion', (0.046, 0.04, 0.062), (0, 0.19, 0.035), m=metal, parent=b, bevel=0.004)
    prof('lowerhg', [(0.205, 0.008), (0.39, 0.012), (0.395, 0.03), (0.39, 0.062), (0.205, 0.062)], 0.054, m=wood, parent=b, bevel=0.009, segs=3)
    for i in range(3):
        box(f'hg_groove{i}', (0.056, 0.12, 0.003), (0, 0.30, 0.028 + i * 0.01), m=m['dark'], parent=b, bevel=0.001)
    box('upperhg', (0.042, 0.16, 0.026), (0, 0.29, 0.088), m=wood, parent=b, bevel=0.012, segs=3)
    cyl('gastube', 0.011, 0.12, (0, 0.43, 0.088), m=metal, parent=b, verts=20)
    box('gasblock', (0.03, 0.035, 0.05), (0, 0.495, 0.07), m=metal, parent=b, bevel=0.004)
    cyl('barrel', 0.0105, 0.45, (0, 0.42, 0.045), m=m['dark'], parent=b, verts=24)
    prof('fsight', [(0.585, 0.045), (0.62, 0.045), (0.612, 0.11), (0.598, 0.11)], 0.016, m=metal, parent=b, bevel=0.002)
    torus('fsight_hood', 0.011, 0.002, (0, 0.603, 0.105), (0, 90, 0), m=metal, parent=b, seg=16, mseg=6, arc=180)
    cyl('fsight_post', 0.0015, 0.016, (0, 0.603, 0.108), m=metal, parent=b, axis='Z', verts=8)
    cyl('brake', 0.0145, 0.05, (0, 0.65, 0.045), m=metal, parent=b, verts=24, bevel=0.002)
    box('brake_cut', (0.012, 0.03, 0.01), (0, 0.655, 0.058), m=m['dark'], parent=b)
    grip(b, wood, (0, -0.02, 0.0), 20)
    trigger_guard(b, metal, -0.005, 0.085, 0.0)
    # selector
    prof('selector', [(-0.05, 0.05), (0.13, 0.048), (0.13, 0.04), (-0.05, 0.04)], 0.004, (0.024, 0, 0), m=metal, parent=b, bevel=0.001)
    # stock
    prof('stock', [(-0.12, 0.066), (-0.12, 0.004), (-0.30, -0.042), (-0.505, -0.082), (-0.525, -0.082), (-0.53, -0.03), (-0.525, 0.045), (-0.30, 0.058)], 0.042, m=wood, parent=b, bevel=0.009, segs=3)
    prof('buttplate', [(-0.522, -0.083), (-0.535, -0.083), (-0.54, -0.03), (-0.535, 0.047), (-0.522, 0.047)], 0.044, m=metal, parent=b, bevel=0.003)
    # moving parts
    mg = mag_curved_ak(root, m['paint'])
    mg.name = 'mag'
    bolt = box('bolt', (0.012, 0.03, 0.012), (0.03, 0.10, 0.06), m=metal, parent=root, bevel=0.003)
    cyl('bolt_knob', 0.006, 0.02, (0.04, 0.115, 0.06), m=metal, parent=root, axis='X', verts=12)
    points(root, (0, 0.68, 0.045), (0, 0.18, 0.1035), (0, 0.30, 0.025), (0.03, 0.10, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    bk = join_children_named(root, ['bolt', 'bolt_knob'], 'bolt')
    finish_export('ak47')


def join_children_named(root, names, newname):
    objs = [o for o in bpy.context.scene.objects if o.name in names]
    if len(objs) < 2:
        return objs[0] if objs else None
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = newname
    return objs[0]


def m4a1():
    root, b = start('m4a1'); m = M()
    metal, dark, paint = m['metal'], m['dark'], m['paint']
    # lower receiver
    prof('lower', [(-0.10, 0.0), (0.11, 0.0), (0.12, 0.02), (0.11, 0.045), (-0.08, 0.045), (-0.10, 0.03)], 0.034, m=paint, parent=b, bevel=0.004)
    prof('magwell', [(0.04, 0.0), (0.12, 0.0), (0.118, -0.045), (0.042, -0.045)], 0.036, m=paint, parent=b, bevel=0.004)
    # upper receiver
    prof('upper', [(-0.11, 0.045), (0.15, 0.045), (0.15, 0.085), (-0.11, 0.085)], 0.036, m=paint, parent=b, bevel=0.004)
    rail(b, dark, 0.20, (0, 0.03, 0.09), 'urail')
    cyl('fassist', 0.008, 0.03, (0.022, -0.05, 0.075), (0, 0, 0), m=dark, parent=b, verts=16)
    box('ejport', (0.004, 0.06, 0.018), (0.019, 0.03, 0.062), m=dark, parent=b, bevel=0.001)
    box('chandle', (0.025, 0.03, 0.012), (0, -0.12, 0.08), m=dark, parent=b, bevel=0.003)
    # handguard (quad rail)
    box('handguard', (0.044, 0.26, 0.046), (0, 0.29, 0.065), m=paint, parent=b, bevel=0.008, segs=3)
    rail(b, dark, 0.25, (0, 0.29, 0.091), 'hrail_t')
    rail(b, dark, 0.20, (0, 0.30, 0.039), 'hrail_b')
    for side in (-1, 1):
        for i in range(8):
            box(f'vent{side}{i}', (0.003, 0.018, 0.01), (side * 0.0225, 0.2 + i * 0.025, 0.065), m=dark, parent=b, bevel=0.001)
    cyl('barrel', 0.0095, 0.26, (0, 0.53, 0.068), m=dark, parent=b, verts=24)
    prof('fsb', [(0.47, 0.06), (0.50, 0.06), (0.495, 0.125), (0.478, 0.125)], 0.014, m=dark, parent=b, bevel=0.002)
    box('fsb_base', (0.03, 0.035, 0.03), (0, 0.488, 0.068), m=dark, parent=b, bevel=0.003)
    lathe('flash', [(0.0, 0), (0.011, 0), (0.011, 0.04), (0.012, 0.045), (0.0095, 0.05), (0.0, 0.05)], (0, 0.655, 0.068), m=dark, parent=b, axis='Y', seg=24)
    for i in range(6):
        box(f'fh{i}', (0.003, 0.025, 0.003), (math.cos(i / 6 * math.tau) * 0.011, 0.68, 0.068 + math.sin(i / 6 * math.tau) * 0.011), m=dark, parent=b)
    # buffer tube & stock
    cyl('buffer', 0.0145, 0.20, (0, -0.20, 0.06), m=dark, parent=b, verts=24)
    prof('stock', [(-0.17, 0.085), (-0.32, 0.09), (-0.33, 0.07), (-0.33, -0.035), (-0.30, -0.035), (-0.20, 0.03), (-0.17, 0.035)], 0.04, m=paint, parent=b, bevel=0.007, segs=3)
    box('stock_pad', (0.042, 0.015, 0.128), (0, -0.335, 0.028), m=m['rubber'], parent=b, bevel=0.005)
    grip(b, paint, (0, -0.035, 0.0), 22)
    trigger_guard(b, paint, -0.01, 0.07, 0.0)
    holo(b, m, (0, 0.03, 0.1))
    mg = curved_mag('mag', root, metal, (1.2, 0.0), 1.12, 1.04, 180, 189.5, 0.024, n=8)
    box('mag_base', (0.028, 0.085, 0.012), (0, 0.135, -0.19), m=paint, parent=root, bevel=0.004).name = 'magbase'
    box('bolt', (0.01, 0.03, 0.01), (0.02, -0.11, 0.08), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.69, 0.068), (0, 0.04, 0.131), (0, 0.32, 0.035), (0.02, 0.03, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['mag', 'magbase'], 'mag')
    finish_export('m4a1')


def mp5():
    root, b = start('mp5'); m = M()
    metal, dark, paint = m['metal'], m['dark'], m['paint']
    box('receiver', (0.042, 0.30, 0.05), (0, 0.06, 0.05), m=dark, parent=b, bevel=0.012, segs=3)
    cyl('cocktube', 0.012, 0.22, (0, 0.24, 0.08), m=dark, parent=b, verts=20)
    prof('handguard', [(0.20, 0.0), (0.37, 0.005), (0.37, 0.065), (0.20, 0.065)], 0.05, m=paint, parent=b, bevel=0.014, segs=3)
    for i in range(5):
        box(f'hgr{i}', (0.052, 0.006, 0.04), (0, 0.23 + i * 0.03, 0.025), m=m['poly'], parent=b, bevel=0.002)
    cyl('barrel', 0.009, 0.10, (0, 0.40, 0.05), m=dark, parent=b, verts=20)
    tube('fhood', 0.014, 0.011, 0.02, (0, 0.36, 0.1), m=dark, parent=b, verts=20)
    box('fhood_base', (0.02, 0.02, 0.025), (0, 0.36, 0.085), m=dark, parent=b, bevel=0.002)
    cyl('drum', 0.013, 0.012, (0, -0.07, 0.093), m=dark, parent=b, axis='X', verts=16)
    box('drum_base', (0.02, 0.025, 0.012), (0, -0.07, 0.078), m=dark, parent=b, bevel=0.002)
    prof('triggergroup', [(-0.05, 0.03), (0.08, 0.03), (0.08, -0.005), (0.03, -0.035), (-0.05, -0.005)], 0.034, m=paint, parent=b, bevel=0.005)
    grip(b, paint, (0, -0.03, -0.0), 15, h=0.10)
    trigger_guard(b, paint, 0.0, 0.07, -0.005)
    # retractable stock
    for s in (-1, 1):
        cyl(f'srod{s}', 0.004, 0.22, (s * 0.016, -0.20, 0.05), m=dark, parent=b, verts=10)
    prof('butt', [(-0.31, 0.075), (-0.33, 0.075), (-0.335, -0.02), (-0.31, -0.02)], 0.045, m=m['rubber'], parent=b, bevel=0.006)
    mg = curved_mag('mag', root, dark, (0.28, 0.02), 0.25, 0.225, 180, 214, 0.02, n=12)
    box('bolt', (0.006, 0.02, 0.008), (0.012, 0.26, 0.095), m=dark, parent=root, bevel=0.001)
    points(root, (0, 0.455, 0.05), (0, -0.07, 0.106), (0, 0.29, 0.02), (0.022, 0.08, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('mp5')


def p90():
    root, b = start('p90'); m = M()
    paint, dark = m['paint'], m['dark']
    body = prof('shell', [(-0.27, -0.02), (-0.27, 0.07), (-0.2, 0.09), (0.15, 0.09), (0.21, 0.07), (0.23, 0.02), (0.20, -0.075), (0.10, -0.085), (0.05, -0.04), (-0.05, -0.04), (-0.12, -0.075), (-0.25, -0.08)], 0.056, m=paint, parent=b, bevel=0.014, segs=3)
    cut = prof('thumbhole', [(-0.02, -0.045), (0.04, -0.045), (0.05, -0.01), (0.02, 0.005), (-0.03, 0.0)], 0.2, m=paint, parent=b, bevel=0)
    boolean_diff(body, cut)
    cut2 = prof('triggerhole', [(0.08, -0.08), (0.17, -0.07), (0.17, -0.03), (0.09, -0.03)], 0.2, m=paint, parent=b, bevel=0)
    boolean_diff(body, cut2)
    prof('trigger', [(0.115, -0.03), (0.125, -0.03), (0.12, -0.06), (0.112, -0.06)], 0.008, m=dark, parent=b, bevel=0.001)
    cyl('barrel', 0.009, 0.08, (0, 0.25, 0.03), m=dark, parent=b, verts=20)
    lathe('flash', [(0, 0), (0.013, 0), (0.013, 0.04), (0.01, 0.045), (0, 0.045)], (0, 0.27, 0.03), m=dark, parent=b, axis='Y', seg=20)
    # optic (ring sight)
    box('optic_base', (0.04, 0.16, 0.02), (0, 0.04, 0.1), m=dark, parent=b, bevel=0.006)
    tube('optic', 0.022, 0.018, 0.05, (0, 0.02, 0.125), m=dark, parent=b, verts=32)
    cyl('optic_glass', 0.018, 0.002, (0, 0.03, 0.125), m=m['glass'], parent=b, verts=24)
    sphere('optic_dot', 0.0012, (0, 0.031, 0.125), m=m['dot'], parent=b, seg=8, rings=4)
    # translucent top magazine with rounds
    mg = box('mag', (0.05, 0.32, 0.024), (0, -0.05, 0.09 + 0.015), m=mat('gun_magclear', (0.35, 0.3, 0.2), 0.0, 0.1, alpha=0.55), parent=root, bevel=0.006)
    for i in range(20):
        cyl(f'round{i}', 0.0028, 0.035, (-0.014 + (i % 2) * 0.028, -0.18 + i * 0.013, 0.104), (0, 0, 90), m=m['brass'], parent=root, axis='Y', verts=8)
    box('bolt', (0.006, 0.02, 0.008), (0.03, 0.10, 0.05), m=dark, parent=root, bevel=0.001)
    points(root, (0, 0.30, 0.03), (0, 0.0, 0.125), (0, 0.17, -0.06), (0.0, -0.05, -0.05))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['mag'] + [f'round{i}' for i in range(20)], 'mag')
    finish_export('p90')


def spas():
    root, b = start('spas'); m = M()
    paint, dark, metal = m['paint'], m['dark'], m['metal']
    prof('receiver', [(-0.10, 0.0), (0.16, 0.0), (0.16, 0.085), (-0.08, 0.085), (-0.10, 0.06)], 0.05, m=dark, parent=b, bevel=0.006)
    cyl('barrel', 0.014, 0.45, (0, 0.38, 0.07), m=dark, parent=b, verts=24)
    cyl('tubemag', 0.016, 0.40, (0, 0.36, 0.035), m=dark, parent=b, verts=24)
    cyl('heatshield', 0.02, 0.2, (0, 0.44, 0.072), m=metal, parent=b, verts=24, r2=0.019)
    for i in range(7):
        cyl(f'hole{i}', 0.006, 0.05, (0, 0.36 + i * 0.026, 0.072), m=m['poly'], parent=b, axis='X', verts=10)
    cyl('pump', 0.026, 0.13, (0, 0.27, 0.035), m=paint, parent=b, verts=24, bevel=0.003)
    for i in range(9):
        torus(f'pr{i}', 0.026, 0.0032, (0, 0.215 + i * 0.013, 0.035), (90, 0, 0), m=paint, parent=b, seg=24, mseg=6)
    cyl('cap', 0.017, 0.02, (0, 0.565, 0.035), m=metal, parent=b, verts=20)
    box('band', (0.034, 0.012, 0.06), (0, 0.565, 0.055), m=metal, parent=b, bevel=0.003)
    prof('fsight', [(0.585, 0.08), (0.6, 0.08), (0.597, 0.1), (0.588, 0.1)], 0.006, m=metal, parent=b, bevel=0.0015)
    grip(b, paint, (0, -0.03, 0.0), 20)
    trigger_guard(b, dark, -0.005, 0.075, 0.0)
    # folding wire stock (folded on top) -> show extended
    for s in (-1, 1):
        prof(f'wire{s}', [(-0.10, 0.06), (-0.36, 0.03), (-0.36, 0.022), (-0.10, 0.052)], 0.006, (s * 0.02, 0, 0), m=metal, parent=b, bevel=0.002)
        prof(f'wireb{s}', [(-0.10, 0.0), (-0.36, -0.06), (-0.36, -0.068), (-0.10, -0.008)], 0.006, (s * 0.02, 0, 0), m=metal, parent=b, bevel=0.002)
    prof('buttplate', [(-0.35, 0.035), (-0.37, 0.035), (-0.37, -0.075), (-0.35, -0.075)], 0.05, m=m['rubber'], parent=b, bevel=0.006)
    torus('hook', 0.03, 0.004, (0, -0.30, -0.02), (0, 90, 0), m=metal, parent=b, arc=200)
    box('mag', (0.001, 0.001, 0.001), (0, 0.1, 0.0), m=dark, parent=root)
    shell = cyl('shell', 0.0095, 0.065, (0.0, 0.12, -0.03), m=mat('gun_shell', (0.7, 0.05, 0.05), 0, 0.4), parent=root, verts=16)
    shell.name = 'magshell'
    points(root, (0, 0.61, 0.07), (0, 0.15, 0.1), (0, 0.27, 0.01), (0.03, 0.08, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['mag', 'magshell'], 'mag')
    finish_export('spas')


def awp():
    root, b = start('awp'); m = M()
    olive, dark, metal = m['olive'], m['dark'], m['metal']
    chassis = prof('chassis', [(-0.62, 0.02), (-0.62, -0.10), (-0.58, -0.115), (-0.40, -0.06), (-0.25, -0.03), (-0.12, -0.12), (-0.05, -0.12), (-0.02, -0.03),
                               (0.08, -0.03), (0.10, 0.0), (0.42, 0.005), (0.43, 0.06), (0.10, 0.06), (-0.05, 0.075), (-0.15, 0.075), (-0.25, 0.07), (-0.52, 0.075), (-0.6, 0.075)],
                   0.052, m=olive, parent=b, bevel=0.012, segs=3)
    th = prof('thumbhole', [(-0.22, -0.02), (-0.12, -0.02), (-0.08, -0.085), (-0.12, -0.10), (-0.17, -0.05)], 0.2, m=olive, parent=b, bevel=0)
    boolean_diff(chassis, th)
    box('cheek', (0.05, 0.22, 0.035), (0, -0.42, 0.095), m=olive, parent=b, bevel=0.012, segs=3)
    prof('butt', [(-0.62, -0.12), (-0.64, -0.12), (-0.64, 0.09), (-0.62, 0.09)], 0.054, m=m['rubber'], parent=b, bevel=0.008)
    cyl('receiver', 0.022, 0.26, (0, 0.02, 0.075), m=dark, parent=b, verts=32, bevel=0.002)
    cyl('barrel', 0.0145, 0.60, (0, 0.62, 0.075), m=dark, parent=b, verts=24, r2=0.012)
    for i in range(6):
        box(f'flute{i}', (0.002, 0.3, 0.004), (math.cos(i / 6 * math.tau) * 0.014, 0.56, 0.075 + math.sin(i / 6 * math.tau) * 0.014), m=metal, parent=b)
    lathe('brake', [(0, 0), (0.02, 0), (0.02, 0.07), (0.016, 0.075), (0, 0.075)], (0, 0.91, 0.075), m=dark, parent=b, axis='Y', seg=24)
    for i in range(3):
        box(f'port{i}', (0.045, 0.01, 0.012), (0, 0.925 + i * 0.018, 0.075), m=m['poly'], parent=b)
    scope(b, m, (0, 0.03, 0.135), 0.36, 0.017, 0.028)
    box('mount', (0.024, 0.2, 0.012), (0, 0.03, 0.1), m=dark, parent=b, bevel=0.002)
    grip_area = prof('trigger', [(-0.04, -0.03), (-0.032, -0.03), (-0.036, -0.06), (-0.044, -0.065)], 0.006, m=metal, parent=b, bevel=0.001)
    # bipod folded
    for s in (-1, 1):
        cyl(f'bipod{s}', 0.006, 0.2, (s * 0.018, 0.30, -0.005), m=dark, parent=b, verts=10)
    box('bipod_base', (0.05, 0.03, 0.02), (0, 0.4, 0.0), m=dark, parent=b, bevel=0.004)
    box('mag', (0.04, 0.09, 0.07), (0, 0.03, -0.05), m=dark, parent=root, bevel=0.006)
    blt = cyl('bolt', 0.004, 0.06, (0.04, -0.08, 0.075), m=metal, parent=root, axis='X', verts=12)
    sphere('boltball', 0.011, (0.07, -0.08, 0.075), m=metal, parent=root)
    points(root, (0, 0.99, 0.075), (0, -0.08, 0.135), (0, 0.24, 0.0), (0.03, 0.02, 0.08))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['bolt', 'boltball'], 'bolt')
    finish_export('awp')


def kar98():
    root, b = start('kar98'); m = M()
    wood, dark, metal = m['wood'], m['dark'], m['metal']
    prof('stock', [(-0.60, 0.03), (-0.60, -0.10), (-0.56, -0.105), (-0.25, -0.045), (-0.12, -0.065), (-0.06, -0.06), (-0.03, -0.02), (0.55, -0.0), (0.56, 0.03), (0.55, 0.055),
                   (0.0, 0.06), (-0.15, 0.06), (-0.25, 0.05), (-0.58, 0.045)], 0.046, m=wood, parent=b, bevel=0.01, segs=3)
    prof('butt', [(-0.6, -0.1), (-0.61, -0.1), (-0.61, 0.045), (-0.6, 0.045)], 0.048, m=metal, parent=b, bevel=0.004)
    cyl('receiver', 0.017, 0.24, (0, 0.03, 0.07), m=metal, parent=b, verts=24)
    cyl('barrel', 0.011, 0.66, (0, 0.55, 0.06), m=dark, parent=b, verts=20, r2=0.0095)
    prof('upperwood', [(0.12, 0.05), (0.45, 0.05), (0.45, 0.075), (0.12, 0.075)], 0.03, m=wood, parent=b, bevel=0.01, segs=3)
    for i, y in enumerate((0.33, 0.5)):
        torus(f'band{i}', 0.026, 0.004, (0, y, 0.04), (90, 0, 0), m=metal, parent=b, seg=24, mseg=6)
    prof('fsight', [(0.85, 0.07), (0.875, 0.07), (0.87, 0.095), (0.857, 0.095)], 0.012, m=metal, parent=b, bevel=0.0015)
    trigger_guard(b, metal, -0.03, 0.06, -0.01, depth=0.035)
    scope(b, m, (0, 0.05, 0.125), 0.30, 0.015, 0.022)
    box('mag', (0.001, 0.001, 0.001), (0, 0.03, 0.0), m=dark, parent=root)
    cyl('bolt', 0.004, 0.065, (0.04, -0.07, 0.07), (0, 0, 0), m=metal, parent=root, axis='X', verts=12)
    sphere('boltball', 0.01, (0.075, -0.07, 0.065), m=metal, parent=root)
    points(root, (0, 0.89, 0.06), (0, -0.06, 0.125), (0, 0.25, 0.015), (0.03, 0.03, 0.08))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['bolt', 'boltball'], 'bolt')
    finish_export('kar98')


def glock():
    root, b = start('glock'); m = M()
    paint, dark, metal = m['paint'], m['dark'], m['metal']
    prof('frame', [(-0.055, 0.0), (0.11, 0.0), (0.11, 0.022), (-0.055, 0.022)], 0.028, m=paint, parent=b, bevel=0.004)
    rail(b, m['poly'], 0.03, (0, 0.085, -0.002), 'frail')
    grip(b, paint, (0, -0.03, 0.0), 22, h=0.10, w=0.03, d=0.046)
    trigger_guard(b, paint, 0.0, 0.06, 0.0, depth=0.03, w=0.014)
    box('magbase', (0.032, 0.05, 0.01), (0, -0.068, -0.097), (-22, 0, 0), m=paint, parent=root, bevel=0.003).name = 'mag'
    # slide (moves)
    sl = prof('slide', [(-0.065, 0.02), (0.125, 0.02), (0.125, 0.048), (0.12, 0.053), (-0.06, 0.053), (-0.065, 0.048)], 0.026, m=dark, parent=root, bevel=0.003)
    sl.name = 'slide'
    for i in range(7):
        box(f'serr{i}', (0.027, 0.002, 0.024), (0, -0.055 + i * 0.006, 0.037), m=metal, parent=root).name = f'slserr{i}'
    box('rsight', (0.016, 0.008, 0.008), (0, -0.05, 0.057), m=metal, parent=root, bevel=0.001).name = 'slrs'
    box('fsight', (0.004, 0.006, 0.008), (0, 0.115, 0.057), m=metal, parent=root, bevel=0.001).name = 'slfs'
    box('port', (0.018, 0.04, 0.002), (0, 0.04, 0.054), m=metal, parent=root).name = 'slport'
    cyl('barrel', 0.007, 0.005, (0, 0.126, 0.035), m=m['poly'], parent=b, verts=16)
    points(root, (0, 0.13, 0.035), (0, -0.05, 0.062), (0, -0.02, -0.04), (0.02, 0.04, 0.05))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['slide', 'slrs', 'slfs', 'slport'] + [f'slserr{i}' for i in range(7)], 'slide')
    finish_export('glock')


def deagle():
    root, b = start('deagle'); m = M()
    paint, dark, metal = m['paint'], m['dark'], m['metal']
    mt = mat('gun_paint_steel', (0.55, 0.56, 0.58), 1.0, 0.25)
    prof('frame', [(-0.06, 0.0), (0.16, 0.0), (0.16, 0.03), (-0.06, 0.03)], 0.032, m=mt, parent=b, bevel=0.004)
    grip(b, m['rubber'], (0, -0.035, 0.0), 18, h=0.11, w=0.034, d=0.05)
    trigger_guard(b, mt, 0.005, 0.07, 0.0, depth=0.032, w=0.014)
    box('magbase', (0.034, 0.055, 0.01), (0, -0.07, -0.108), (-18, 0, 0), m=mt, parent=root, bevel=0.003).name = 'mag'
    sl = prof('slide', [(-0.07, 0.03), (0.10, 0.03), (0.10, 0.07), (-0.065, 0.07), (-0.07, 0.065)], 0.03, m=mt, parent=root, bevel=0.003)
    sl.name = 'slide'
    for i in range(6):
        box(f'serr{i}', (0.031, 0.003, 0.03), (0, -0.06 + i * 0.008, 0.05), m=dark, parent=root).name = f'slserr{i}'
    # triangular barrel
    prof('barrel', [(-0.0, 0.03), (0.21, 0.03), (0.21, 0.065), (0.0, 0.075)], 0.024, m=mt, parent=b, bevel=0.003)
    box('topr', (0.012, 0.21, 0.005), (0, 0.105, 0.078), m=dark, parent=b, bevel=0.001)
    cyl('bore', 0.007, 0.005, (0, 0.212, 0.048), m=m['poly'], parent=b, verts=16)
    box('rsight', (0.018, 0.01, 0.01), (0, -0.06, 0.075), m=dark, parent=root, bevel=0.001).name = 'slrs'
    cyl('hammer', 0.006, 0.012, (0, -0.075, 0.06), m=dark, parent=b, axis='X', verts=12)
    points(root, (0, 0.215, 0.048), (0, -0.06, 0.081), (0, -0.02, -0.04), (0.02, 0.0, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['slide', 'slrs'] + [f'slserr{i}' for i in range(6)], 'slide')
    finish_export('deagle')


def _sharpen(obj, edge_z, spine_z, y_min=0.03):
    """taper a flat blade toward its cutting edge (z below edge_z) so it reads as a real ground blade"""
    me = obj.data
    for v in me.vertices:
        if v.co.y > y_min:
            t = max(0.0, min(1.0, (v.co.z - edge_z) / max(spine_z - edge_z, 1e-4)))
            v.co.x *= 0.12 + 0.88 * t
    me.update()


def scar():
    root, b = start('scar'); m = M()
    tan, dark, metal = m['tan'], m['dark'], m['metal']
    poly = m['poly']
    prof('upper', [(-0.12, 0.045), (0.30, 0.045), (0.30, 0.095), (-0.12, 0.095)], 0.044, m=tan, parent=b, bevel=0.005)
    prof('lower', [(-0.08, 0.0), (0.10, 0.0), (0.11, 0.02), (0.10, 0.046), (-0.08, 0.046)], 0.038, m=tan, parent=b, bevel=0.005)
    prof('magwell', [(0.03, 0.0), (0.11, 0.0), (0.108, -0.04), (0.032, -0.04)], 0.038, m=tan, parent=b, bevel=0.004)
    rail(b, dark, 0.40, (0, 0.09, 0.1), 'trail')
    for side in (-1, 1):
        rail_side = box(f'srail{side}', (0.006, 0.10, 0.02), (side * 0.025, 0.25, 0.07), m=dark, parent=b, bevel=0.002)
    box('chandle', (0.05, 0.02, 0.012), (-0.03, 0.16, 0.07), m=dark, parent=b, bevel=0.003)
    cyl('barrel', 0.0105, 0.22, (0, 0.40, 0.07), m=dark, parent=b, verts=24)
    box('gasblock', (0.026, 0.03, 0.035), (0, 0.36, 0.07), m=dark, parent=b, bevel=0.004)
    lathe('brake', [(0.0, 0), (0.013, 0), (0.013, 0.05), (0.011, 0.055), (0.0, 0.055)], (0, 0.50, 0.07), m=dark, parent=b, axis='Y', seg=24)
    for i in range(3):
        box(f'bport{i}', (0.028, 0.006, 0.004), (0, 0.515 + i * 0.012, 0.082), m=poly, parent=b)
    # folding stock
    prof('stock', [(-0.12, 0.09), (-0.33, 0.085), (-0.345, 0.07), (-0.345, -0.03), (-0.32, -0.03), (-0.29, 0.03), (-0.16, 0.045), (-0.12, 0.05)], 0.04, m=tan, parent=b, bevel=0.007, segs=3)
    box('cheek', (0.042, 0.12, 0.015), (0, -0.26, 0.095), m=poly, parent=b, bevel=0.005)
    box('pad', (0.044, 0.012, 0.12), (0, -0.35, 0.03), m=m['rubber'], parent=b, bevel=0.004)
    grip(b, poly, (0, -0.035, 0.0), 20)
    trigger_guard(b, tan, -0.01, 0.07, 0.0)
    holo(b, m, (0, 0.05, 0.106))
    prof('mag', [(0.04, 0.0), (0.105, 0.0), (0.118, -0.16), (0.055, -0.165)], 0.03, m=poly, parent=root, bevel=0.004)
    box('bolt', (0.01, 0.03, 0.01), (0.026, 0.0, 0.08), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.56, 0.07), (0, 0.06, 0.137), (0, 0.27, 0.04), (0.025, 0.04, 0.07))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('scar')


def ump45():
    root, b = start('ump45'); m = M()
    poly, dark = m['poly'], m['dark']
    prof('body', [(-0.06, 0.0), (0.30, 0.0), (0.32, 0.03), (0.32, 0.085), (-0.06, 0.085), (-0.08, 0.06)], 0.046, m=poly, parent=b, bevel=0.008, segs=3)
    for i in range(6):
        box(f'vent{i}', (0.048, 0.016, 0.008), (0, 0.18 + i * 0.022, 0.03), m=dark, parent=b, bevel=0.002)
    rail(b, dark, 0.22, (0, 0.06, 0.09), 'trail')
    cyl('barrel', 0.010, 0.06, (0, 0.35, 0.06), m=dark, parent=b, verts=20)
    tube('muzzle_r', 0.014, 0.010, 0.02, (0, 0.38, 0.06), m=dark, parent=b, verts=20)
    grip(b, poly, (0, -0.02, 0.0), 14, h=0.10)
    trigger_guard(b, poly, 0.0, 0.08, 0.0)
    # side-folding skeleton stock
    for z in (0.02, 0.075):
        box(f'stk{z}', (0.012, 0.24, 0.014), (0.0, -0.19, z), m=poly, parent=b, bevel=0.004)
    box('stk_butt', (0.03, 0.02, 0.1), (0, -0.31, 0.05), m=m['rubber'], parent=b, bevel=0.006)
    reddot(b, m, (0, 0.02, 0.102))
    prof('mag', [(0.11, 0.0), (0.16, 0.0), (0.162, -0.15), (0.112, -0.15)], 0.03, m=poly, parent=root, bevel=0.004)
    box('bolt', (0.008, 0.02, 0.012), (0.026, 0.24, 0.07), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.395, 0.06), (0, 0.02, 0.131), (0, 0.24, 0.02), (0.025, 0.05, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('ump45')


def revolver():
    root, b = start('revolver'); m = M()
    st = mat('gun_paint_steel', (0.55, 0.56, 0.58), 1.0, 0.22)
    dark = m['dark']
    prof('frame', [(-0.05, 0.0), (0.06, 0.0), (0.07, 0.06), (-0.04, 0.065), (-0.06, 0.04)], 0.03, m=st, parent=b, bevel=0.004)
    cyl('cylinder', 0.022, 0.045, (0, 0.025, 0.035), m=st, parent=b, verts=6, bevel=0.004)
    for i in range(6):
        a = i / 6 * math.tau
        cyl(f'flute{i}', 0.004, 0.046, (math.cos(a) * 0.021, 0.025, 0.035 + math.sin(a) * 0.021), m=dark, parent=b, verts=8)
    cyl('barrel', 0.0095, 0.16, (0, 0.13, 0.05), m=st, parent=b, verts=20)
    box('rib', (0.012, 0.16, 0.01), (0, 0.13, 0.062), m=st, parent=b, bevel=0.002)
    box('ejrod', (0.008, 0.11, 0.012), (0, 0.11, 0.032), m=st, parent=b, bevel=0.002)
    box('fsight', (0.004, 0.012, 0.012), (0, 0.205, 0.07), m=dark, parent=b)
    box('hammer', (0.008, 0.02, 0.025), (0, -0.05, 0.07), (25, 0, 0), m=dark, parent=b, bevel=0.002)
    grip(b, mat('gun_paint_wood', (0.45, 0.22, 0.09), 0.0, 0.45), (0, -0.04, 0.0), 24, h=0.1, w=0.032, d=0.045)
    trigger_guard(b, st, -0.005, 0.045, 0.0, depth=0.03, w=0.012)
    box('mag', (0.004, 0.004, 0.004), (0, -0.05, -0.08), m=dark, parent=root)
    points(root, (0, 0.215, 0.05), (0, -0.04, 0.072), (0, -0.02, -0.04), (0.02, 0.025, 0.05))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('revolver')


def knife():
    root, b = start('knife'); m = M()
    blade = m['blade']
    # clip-point blade
    pts = [(0.03, -0.006), (0.20, -0.006), (0.235, 0.004), (0.255, 0.018), (0.20, 0.02), (0.16, 0.026), (0.03, 0.026)]
    bl = prof('blade', pts, 0.0065, m=blade, parent=b, bevel=0.0012, segs=2)
    _sharpen(bl, edge_z=0.004, spine_z=0.02)
    box('fuller', (0.0062, 0.09, 0.004), (0, 0.10, 0.017), m=m['dark'], parent=b)
    for i in range(6):
        prof(f'serr{i}', [(0.05 + i * 0.012, 0.026), (0.056 + i * 0.012, 0.031), (0.062 + i * 0.012, 0.026)], 0.005, m=blade, parent=b, bevel=0)
    box('guard', (0.02, 0.008, 0.055), (0, 0.025, 0.01), m=m['dark'], parent=b, bevel=0.003)
    prof('handle', [(-0.10, -0.012), (0.02, -0.01), (0.02, 0.03), (-0.10, 0.028), (-0.11, 0.008)], 0.024, m=m['paint'], parent=b, bevel=0.007, segs=3)
    for i in range(5):
        box(f'grv{i}', (0.026, 0.004, 0.044), (0, -0.08 + i * 0.02, 0.009), m=m['rubber'], parent=b, bevel=0.0015)
    cyl('pommel', 0.012, 0.01, (0, -0.112, 0.009), m=m['dark'], parent=b, verts=16, bevel=0.002)
    points(root, (0, 0.25, 0.01), (0, 0, 0.05), (0, 0, 0), (0, 0, 0))
    apply_all_modifiers(); box_uv_all(8.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('knife')


def karambit():
    root, b = start('karambit'); m = M()
    blade = m['blade']
    outer = arc_pts((0.02, -0.06), 0.13, 95, 30, 14)
    inner = arc_pts((0.035, -0.07), 0.105, 32, 98, 14)
    prof('blade', [(0.0, 0.055)] + outer + [(0.15, 0.0)] + inner, 0.006, m=blade, parent=b, bevel=0.002)
    prof('handle', [(-0.11, -0.015), (0.0, 0.035), (0.01, 0.065), (-0.01, 0.07), (-0.12, 0.012)], 0.022, m=m['paint'], parent=b, bevel=0.006, segs=3)
    torus('ring', 0.022, 0.006, (0, -0.135, -0.005), (0, 90, 0), m=m['dark'], parent=b, seg=32, mseg=10)
    for i in range(3):
        cyl(f'pin{i}', 0.003, 0.025, (0, -0.08 + i * 0.035, 0.012 + i * 0.016), m=m['blade'], parent=b, axis='X', verts=10)
    points(root, (0, 0.15, 0.0), (0, 0, 0.05), (0, 0, 0), (0, 0, 0))
    apply_all_modifiers(); box_uv_all(8.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('karambit')


def frag():
    root, b = start('frag'); m = M()
    g = m['green']
    lathe('body', [(0, -0.045), (0.02, -0.043), (0.03, -0.035), (0.033, -0.015), (0.032, 0.01), (0.027, 0.03), (0.016, 0.042), (0.0, 0.044)], m=g, parent=b, seg=32)
    cyl('fuze', 0.011, 0.025, (0, 0, 0.055), m=m['metal'], parent=b, axis='Z', verts=20)
    prof('spoon', [(-0.012, 0.065), (0.0, 0.068), (0.035, 0.04), (0.04, -0.02), (0.034, -0.02), (0.03, 0.035), (-0.012, 0.06)], 0.012, m=m['metal'], parent=b, bevel=0.0015, plane='XZ')
    torus('pinring', 0.012, 0.0018, (-0.018, 0.0, 0.06), (90, 0, 0), m=m['metal'], parent=root, seg=20, mseg=6).name = 'pin'
    points(root, (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0))
    apply_all_modifiers(); box_uv_all(8.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('frag')



def aug():
    # Steyr AUG bullpup: magazine behind the pistol grip, integrated optic, vertical foregrip
    root, b = start('aug'); m = M()
    olive, poly, dark = m['green'], m['poly'], m['dark']
    prof('stockbody', [(-0.46, 0.0), (-0.44, -0.07), (-0.36, -0.075), (-0.12, -0.03), (0.06, -0.025), (0.16, 0.0), (0.18, 0.06), (0.12, 0.085), (-0.44, 0.085), (-0.47, 0.06)], 0.058, m=olive, parent=b, bevel=0.012, segs=3)
    box('pad', (0.06, 0.014, 0.15), (0, -0.468, 0.005), m=m['rubber'], parent=b, bevel=0.005)
    tube('optic', 0.02, 0.016, 0.20, (0, -0.02, 0.135), m=dark, parent=b, verts=28)
    box('optic_mount', (0.02, 0.16, 0.035), (0, -0.02, 0.1), m=dark, parent=b, bevel=0.004)
    cyl('optic_lens', 0.0165, 0.002, (0, 0.078, 0.135), m=m['glass'], parent=b, verts=28)
    cyl('barrel', 0.011, 0.30, (0, 0.32, 0.045), m=dark, parent=b, verts=24)
    lathe('flash', [(0.0, 0), (0.014, 0), (0.014, 0.05), (0.0, 0.05)], (0, 0.45, 0.045), m=dark, parent=b, axis='Y', seg=20)
    grip(b, olive, (0, 0.0, -0.01), 10, h=0.1)
    # wide trigger guard enclosing the hand
    prof('guard', [(-0.02, -0.02), (0.15, -0.02), (0.15, -0.11), (0.13, -0.11), (0.13, -0.035), (-0.02, -0.035)], 0.012, m=olive, parent=b, bevel=0.003)
    grip(b, olive, (0, 0.16, -0.02), -8, h=0.1, name='foregrip')
    prof('mag', [(-0.17, -0.03), (-0.1, -0.03), (-0.1, -0.2), (-0.165, -0.19)], 0.03, m=m['glass'], parent=root, bevel=0.004)
    box('bolt', (0.01, 0.03, 0.012), (0.03, -0.1, 0.06), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.5, 0.045), (0, -0.02, 0.135), (0, 0.16, -0.05), (0.035, -0.12, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('aug')


def vector():
    # Kriss Vector .45: angular upper, slanted lower with the magazine in front of the grip
    root, b = start('vector'); m = M()
    poly, dark, tan = m['poly'], m['dark'], m['tan']
    prof('upper', [(-0.07, 0.035), (0.25, 0.035), (0.27, 0.06), (0.25, 0.095), (-0.07, 0.095)], 0.045, m=poly, parent=b, bevel=0.006, segs=3)
    prof('lower', [(-0.05, 0.035), (0.21, 0.035), (0.19, -0.045), (0.12, -0.075), (0.05, -0.075), (0.0, -0.02)], 0.05, m=tan, parent=b, bevel=0.008, segs=3)
    rail(b, dark, 0.30, (0, 0.09, 0.1), 'trail')
    cyl('barrel', 0.012, 0.09, (0, 0.30, 0.07), m=dark, parent=b, verts=20)
    tube('shroud', 0.017, 0.012, 0.05, (0, 0.31, 0.07), m=dark, parent=b, verts=20)
    grip(b, poly, (0, -0.01, 0.0), 12, h=0.1)
    trigger_guard(b, poly, 0.0, 0.07, -0.005)
    for z in (0.045, 0.085):
        box(f'stk{z}', (0.012, 0.22, 0.014), (0.0, -0.18, z), m=poly, parent=b, bevel=0.004)
    box('stk_butt', (0.035, 0.02, 0.11), (0, -0.29, 0.06), m=m['rubber'], parent=b, bevel=0.006)
    reddot(b, m, (0, 0.03, 0.112))
    prof('mag', [(0.07, -0.06), (0.11, -0.06), (0.115, -0.2), (0.075, -0.2)], 0.028, m=poly, parent=root, bevel=0.004)
    box('bolt', (0.008, 0.02, 0.012), (0.026, 0.18, 0.08), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.34, 0.07), (0, 0.03, 0.141), (0, 0.2, 0.02), (0.025, 0.05, 0.07))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('vector')


def m249():
    # M249 light machine gun: big receiver, 100-round box under the left side, carry handle, bipod
    root, b = start('m249'); m = M()
    paint, dark, poly = m['paint'], m['dark'], m['poly']
    prof('receiver', [(-0.06, 0.0), (0.24, 0.0), (0.26, 0.03), (0.26, 0.11), (-0.06, 0.11)], 0.07, m=paint, parent=b, bevel=0.006, segs=3)
    box('feedcover', (0.074, 0.2, 0.02), (0, 0.1, 0.12), m=dark, parent=b, bevel=0.004)
    prof('stock', [(-0.06, 0.1), (-0.40, 0.085), (-0.42, 0.07), (-0.42, -0.06), (-0.38, -0.06), (-0.2, 0.02), (-0.06, 0.03)], 0.05, m=poly, parent=b, bevel=0.01, segs=3)
    prof('handguard', [(0.26, 0.02), (0.44, 0.03), (0.44, 0.1), (0.26, 0.105)], 0.066, m=poly, parent=b, bevel=0.008, segs=3)
    cyl('barrel', 0.013, 0.42, (0, 0.62, 0.065), m=dark, parent=b, verts=24)
    tube('heat', 0.02, 0.014, 0.16, (0, 0.52, 0.065), m=dark, parent=b, verts=24)
    lathe('flash', [(0.0, 0), (0.016, 0), (0.016, 0.06), (0.0, 0.06)], (0, 0.8, 0.065), m=dark, parent=b, axis='Y', seg=20)
    box('handle', (0.02, 0.12, 0.02), (0, 0.5, 0.135), m=dark, parent=b, bevel=0.005)
    for yy in (0.45, 0.55):
        box(f'handle_p{yy}', (0.014, 0.014, 0.05), (0, yy, 0.11), m=dark, parent=b)
    for side in (-1, 1):
        box(f'bipod{side}', (0.012, 0.3, 0.012), (side * 0.018, 0.6, 0.03), (0, 0, side * 4), m=dark, parent=b, bevel=0.003)
    grip(b, poly, (0, 0.0, 0.0), 16, h=0.105)
    trigger_guard(b, dark, 0.0, 0.08, 0.0)
    rail(b, dark, 0.16, (0, 0.03, 0.135), 'trail')
    reddot(b, m, (0, 0.03, 0.146))
    box('mag', (0.09, 0.12, 0.13), (-0.035, 0.12, -0.065), m=m['olive'], parent=root, bevel=0.01)
    box('bolt', (0.012, 0.04, 0.014), (0.04, 0.12, 0.06), m=dark, parent=root, bevel=0.002)
    points(root, (0, 0.86, 0.065), (0, 0.03, 0.175), (0, 0.36, 0.02), (0.04, 0.12, 0.06))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export('m249')

ALL = dict(aug=aug, vector=vector, m249=m249, scar=scar, ump45=ump45, revolver=revolver, ak47=ak47, m4a1=m4a1, mp5=mp5, p90=p90, spas=spas, awp=awp, kar98=kar98, glock=glock, deagle=deagle, knife=knife, karambit=karambit, frag=frag)

if __name__ == '__main__':
    names = [a for a in sys.argv[1:] if a in ALL] or list(ALL)
    for n in names:
        try:
            ALL[n]()
        except Exception as e:
            import traceback; traceback.print_exc()
            print('FAILED', n)
