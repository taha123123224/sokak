"""Render quick previews of glb files with Workbench (side view). usage: preview.py out.png a.glb b.glb ..."""
import sys, os, math
import bpy
from mathutils import Vector

out = sys.argv[1]
files = sys.argv[2:]
view = os.environ.get('VIEW', 'side')
size = int(os.environ.get('SIZE', '640'))
tiles = []
for f in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    ctr = (mn + mx) / 2; ext = mx - mn
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    if view == 'side':
        cam.location = ctr + Vector((ext.length * 2, 0, 0))
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
        cam.data.ortho_scale = max(ext.y, ext.z * 2.6) * 1.1
    elif view == 'persp':
        cam.data.type = 'PERSP'; cam.data.lens = 50
        d = ext.length * 1.6
        cam.location = ctr + Vector((d * 0.7, -d * 0.5, d * 0.45))
        direction = ctr - cam.location
        cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    else:  # top
        cam.location = ctr + Vector((0, 0, ext.length * 2))
        cam.rotation_euler = (0, 0, 0)
        cam.data.ortho_scale = max(ext.x, ext.y) * 1.05
    cam.data.clip_end = 10000
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = view != 'side'
    sc.render.resolution_x = size; sc.render.resolution_y = int(size * (0.375 if view == 'side' else 0.66))
    sc.render.filepath = f'/tmp/pv_{len(tiles)}.png'
    bpy.ops.render.render(write_still=True)
    tiles.append(sc.render.filepath)

from PIL import Image
ims = [Image.open(t) for t in tiles]
cols = 2 if len(ims) > 1 else 1
w, h = ims[0].size
rows = math.ceil(len(ims) / cols)
sheet = Image.new('RGB', (w * cols, h * rows), (40, 40, 40))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
sheet.save(out)
print('saved', out)
