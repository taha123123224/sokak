"""Attachments taken from the user's high-detail models (PBR textures kept):
  att_sus   <- M1911 silencer (Silencer_lowTris), rescaled to a rifle can
  att_optik <- RPK-16 holographic sight (Holo_*)
Blender +Y forward, +Z up, origin = mounting point (bottom centre / rear of the can)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector, Matrix
from bkit import ROOT, export_glb
OUT = os.path.join(ROOT, 'assets', 'models')
NEW = '/home/claude/ext3d/new'
M19 = NEW + '/m1911/tex2k/m1911_'


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def isolate(prefix):
    keep = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(prefix)]
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o)
    for o in keep:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(keep) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def bbox(o):
    xs = [v.co for v in o.data.vertices]
    mn = Vector((min(p.x for p in xs), min(p.y for p in xs), min(p.z for p in xs)))
    mx = Vector((max(p.x for p in xs), max(p.y for p in xs), max(p.z for p in xs)))
    return mn, mx


def tex_mat(name, files):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes.get('Principled BSDF')
    bc, nrm, rgh, met = files
    def img(p, color=True):
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(p)
        if not color: t.image.colorspace_settings.name = 'Non-Color'
        return t
    nt.links.new(img(bc).outputs['Color'], b.inputs['Base Color'])
    nt.links.new(img(rgh, False).outputs['Color'], b.inputs['Roughness'])
    nt.links.new(img(met, False).outputs['Color'], b.inputs['Metallic'])
    nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(img(nrm, False).outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    return m


def finish(o, name, marker, mpos):
    root = bpy.data.objects.new('ATT_' + name, None); bpy.context.scene.collection.objects.link(root)
    o.parent = root
    e = bpy.data.objects.new(marker, None); bpy.context.scene.collection.objects.link(e); e.parent = root; e.location = mpos
    for p in o.data.polygons:
        p.use_smooth = True
    export_glb(os.path.join(OUT, 'att_%s.glb' % name))
    print('ATT', name, tuple(round(v, 4) for v in o.dimensions))


def suppressor():
    clean()
    bpy.ops.import_scene.fbx(filepath=NEW + '/m1911/source/1911 Sketchfab/m1911.fbx')
    o = isolate('Silencer')
    mn, mx = bbox(o)
    L = mx.y - mn.y; R = (mx.x - mn.x) / 2
    sl, sr = 0.165 / L, 0.0172 / R
    cx, cz = (mn.x + mx.x) / 2, (mn.z + mx.z) / 2
    for v in o.data.vertices:
        v.co = Vector(((v.co.x - cx) * sr, (v.co.y - mn.y) * sl, (v.co.z - cz) * sr))
    o.data.materials.clear()
    o.data.materials.append(tex_mat('ext_att_sus', (M19 + 'silencer_albedo.png', M19 + 'silencer_normal.png', M19 + 'silencer_roughness.png', M19 + 'silencer_metallic.png')))
    finish(o, 'sus', 'muzzle', (0, 0.167, 0))


def holo():
    clean()
    bpy.ops.wm.usd_import(filepath=NEW + '/b9d78480-RPK-16/scene.usdc')
    o = isolate('Holo')
    mn, mx = bbox(o)
    # RPK file: long axis X (muzzle +X). Re-orient to +Y forward, scale to a 0.09 m long optic.
    s = 0.092 / (mx.x - mn.x)
    cy = (mn.y + mx.y) / 2
    for v in o.data.vertices:
        p = v.co.copy()
        v.co = Vector((-(p.y - cy) * s, (p.x - (mn.x + mx.x) / 2) * s, (p.z - mn.z) * s))
    for sl in o.material_slots:
        if sl.material:
            sl.material.name = 'ext_att_optik'
    h = (mx.z - mn.z) * s
    zc = h * 0.716
    # holographic glass + red ring/dot reticle (game materials gun_holo_glass / gun_dot)
    g = bpy.data.materials.new('gun_holo_glass'); d = bpy.data.materials.new('gun_dot')
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.0, zc), rotation=(math.radians(90), 0, 0))
    gl = bpy.context.active_object; gl.scale = (0.0224, 0.0178, 1); gl.data.materials.append(g)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.0042, minor_radius=0.00028, location=(0, -0.0005, zc), rotation=(math.radians(90), 0, 0), major_segments=40, minor_segments=4)
    ring = bpy.context.active_object; ring.data.materials.append(d)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.0005, location=(0, -0.0005, zc), segments=10, ring_count=5)
    dot = bpy.context.active_object; dot.data.materials.append(d)
    bpy.ops.object.select_all(action='DESELECT')
    for x in (o, gl, ring, dot):
        x.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    finish(o, 'optik', 'sight', (0, 0.0, zc))


if __name__ == '__main__':
    suppressor()
    holo()
