import bpy, sys, math, json
from mathutils import Vector
sys.path.insert(0, 'tools')
exec(open('tools/_inspect_ext.py').read().split("for k,f in")[0])   # reuse 'files'
k = sys.argv[-1]
f = files[k]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
if f.endswith('.blend'):
    bpy.ops.wm.open_mainfile(filepath=f, load_ui=False, use_scripts=False)
else:
    bpy.ops.import_scene.fbx(filepath=f)
ms = [o for o in bpy.data.objects if o.type == 'MESH']
for o in bpy.data.objects:
    if o.type not in ('MESH',): o.hide_render = True
pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
ctr = (mn + mx) / 2
size = mx - mn
long_axis = 'X' if size.x > size.y else 'Y'
sc = bpy.context.scene
cam_d = bpy.data.cameras.new('c'); cam_d.type = 'ORTHO'
L = max(size.x, size.y) * 1.1
cam_d.ortho_scale = L
cam = bpy.data.objects.new('cam', cam_d); sc.collection.objects.link(cam)
if long_axis == 'Y':   # look from +X toward -X; image right = +Y? camera right axis
    cam.location = ctr + Vector((L * 2, 0, 0)); cam.rotation_euler = (math.radians(90), 0, math.radians(90))
else:                  # look from -Y toward +Y; image right = +X
    cam.location = ctr + Vector((0, -L * 2, 0)); cam.rotation_euler = (math.radians(90), 0, 0)
sc.camera = cam
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 1400; sc.render.resolution_y = int(1400 * max(size.z * 1.25, L * 0.3) / L)
sc.render.filepath = f'/tmp/ext_{k}.png'
bpy.ops.render.render(write_still=True)
r = cam.matrix_world.to_3x3()
print('MAP', json.dumps({'k': k, 'long': long_axis, 'ctr': list(ctr), 'L': L, 'w': sc.render.resolution_x, 'h': sc.render.resolution_y,
      'right': list(r @ Vector((1, 0, 0))), 'up': list(r @ Vector((0, 1, 0))), 'min': list(mn), 'max': list(mx)}))
