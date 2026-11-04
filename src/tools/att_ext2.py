"""User-supplied optics (no textures came with them -> game PBR materials by name):
  att_optik  <- EOTECH HWS EXPS2 holographic sight (+ 68 MOA ring/dot reticle)
  att_durbun <- compact tactical scope with flip-up caps (+ crosshair reticle)
Blender +Y forward (muzzle), +Z up, origin = bottom centre of the mount."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector
from bkit import ROOT, export_glb
OUT = os.path.join(ROOT, 'assets', 'models')
NEW = '/home/claude/ext3d/new'


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def join_all():
    ms = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in list(bpy.data.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o)
    for o in ms:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def remap(o, table):
    # rename / merge materials to the game material library names
    new = {}
    for i, sl in enumerate(o.material_slots):
        nm = sl.material.name if sl.material else ''
        key = next((v for k, v in table if nm.startswith(k)), 'gun_metal_dark')
        if key not in new:
            new[key] = bpy.data.materials.get(key) or bpy.data.materials.new(key)
        sl.material = new[key]


def add_mesh_mat(obj, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    obj.data.materials.clear(); obj.data.materials.append(m)


def finish(parts, name, marker, mpos):
    bpy.ops.object.select_all(action='DESELECT')
    for x in parts:
        x.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    for p in o.data.polygons:
        p.use_smooth = True
    o.data.shade_auto_smooth if hasattr(o.data, 'shade_auto_smooth') else None
    root = bpy.data.objects.new('ATT_' + name, None); bpy.context.scene.collection.objects.link(root)
    o.parent = root
    e = bpy.data.objects.new(marker, None); bpy.context.scene.collection.objects.link(e); e.parent = root; e.location = mpos
    export_glb(os.path.join(OUT, 'att_%s.glb' % name))
    print('ATT', name, tuple(round(v, 4) for v in o.dimensions))


def eotech():
    clean()
    bpy.ops.import_scene.fbx(filepath=NEW + '/eotech.fbx')
    o = join_all()
    remap(o, [('holo_glass', 'gun_holo_glass'), ('main_color_metalic_litt', 'gun_metal'), ('main_color_metalic', 'gun_metal_dark'),
              ('main_color', 'gun_paint_eotech'), ('screws', 'gun_metal'), ('cable', 'gun_rubber'), ('plastic_2', 'gun_polymer'), ('plastic', 'gun_rubber')])
    # model: long axis X with the battery cap (front) at +X, base at z=0.  -> +Y forward, 0.098 m long
    xs = [v.co.x for v in o.data.vertices]; mnx, mxx = min(xs), max(xs)
    s = 0.098 / (mxx - mnx)
    cx = (mnx + mxx) / 2
    for v in o.data.vertices:
        p = v.co.copy()
        v.co = Vector((-p.y * s, (p.x - cx) * s, p.z * s))
    # window: glass plane at model x=-0.077, z 0.172..0.248 -> reticle a hair behind the glass
    gy = (-0.077 - cx) * s
    zc = 0.212 * s
    d = bpy.data.materials.get('gun_dot') or bpy.data.materials.new('gun_dot')
    bpy.ops.mesh.primitive_torus_add(major_radius=0.0046, minor_radius=0.00026, location=(0, gy - 0.0006, zc), rotation=(math.radians(90), 0, 0), major_segments=48, minor_segments=4)
    ring = bpy.context.active_object; ring.data.materials.append(d)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.00048, location=(0, gy - 0.0006, zc), segments=10, ring_count=5)
    dot = bpy.context.active_object; dot.data.materials.append(d)
    # 4 short ticks on the ring (EOTech style)
    ticks = []
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * 0.0052, gy - 0.0006, zc + math.sin(a) * 0.0052))
        t = bpy.context.active_object
        t.scale = (0.0011 if ang in (0, 180) else 0.00028, 0.0002, 0.00028 if ang in (0, 180) else 0.0011)
        bpy.ops.object.transform_apply(scale=True)
        t.data.materials.append(d); ticks.append(t)
    finish([o, ring, dot] + ticks, 'optik', 'sight', (0, gy, zc))


def scope():
    clean()
    bpy.ops.import_scene.fbx(filepath=NEW + '/scope.fbx')
    o = join_all()
    remap(o, [('SCOPE_VIEW', 'gun_holo_glass'), ('SCOPE_MAT', 'gun_metal_dark'), ('PLASTIC', 'gun_polymer')])
    # model: tube along X, objective (bigger lens) at -X, mount base bottom at z=-2.118 -> +Y forward, 0.13 m long
    zs = [v.co.z for v in o.data.vertices]; mnz = min(zs)
    s = 0.13 / 4.915
    for v in o.data.vertices:
        p = v.co.copy()
        v.co = Vector((p.y * s, -p.x * s, (p.z - mnz) * s))
    zc = (0.0 - mnz) * s
    # fine crosshair + red centre dot inside the tube (middle), eyepiece at model x=+2.37 -> y = -2.37*s
    d = bpy.data.materials.get('gun_dot') or bpy.data.materials.new('gun_dot')
    k = bpy.data.materials.get('gun_reticle') or bpy.data.materials.new('gun_reticle')
    parts = [o]
    for horiz in (True, False):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.0, zc))
        c = bpy.context.active_object
        c.scale = (0.036 if horiz else 0.00022, 0.0002, 0.00022 if horiz else 0.036)
        bpy.ops.object.transform_apply(scale=True)
        c.data.materials.append(k); parts.append(c)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.0006, location=(0, -0.0004, zc), segments=10, ring_count=5)
    dot = bpy.context.active_object; dot.data.materials.append(d); parts.append(dot)
    finish(parts, 'durbun', 'sight', (0, -2.37 * s, zc))


if __name__ == '__main__':
    eotech()
    scope()
