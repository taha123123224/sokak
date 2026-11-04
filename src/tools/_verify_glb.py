import bpy, sys, math
from mathutils import Vector
wid = sys.argv[-1]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=f'assets/models/w_{wid}.glb')
ms = [o for o in bpy.data.objects if o.type == 'MESH']
pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))); mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
print('OBJS', [(o.name, o.type) for o in bpy.data.objects if o.type == 'MESH'], 'size', tuple(round(v, 3) for v in mx - mn))
for o in bpy.data.objects:
    if o.type == 'EMPTY':
        p = o.matrix_world.translation
        print('MARK', o.name, tuple(round(v, 3) for v in p))
        if o.name in ('muzzle', 'sight', 'lhand', 'rhand', 'eject'):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=(mx - mn).y * 0.012, location=p)
            s = bpy.context.active_object
            mt = bpy.data.materials.new('m' + o.name); mt.diffuse_color = {'muzzle': (1, 0, 0, 1), 'sight': (0, 1, 0, 1), 'lhand': (0, 0.4, 1, 1), 'rhand': (1, 1, 0, 1), 'eject': (1, 0, 1, 1)}[o.name]
            s.data.materials.append(mt); s.show_in_front = True
sc = bpy.context.scene
ctr = (mn + mx) / 2; L = (mx - mn).y * 1.15
cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = L
cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam)
cam.location = ctr + Vector((L * 2, 0, 0)); cam.rotation_euler = (math.radians(90), 0, math.radians(90)); sc.camera = cam
sc.render.engine = 'BLENDER_WORKBENCH'; sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 900; sc.render.resolution_y = 450
sc.render.filepath = f'/tmp/vg_{wid}.png'; bpy.ops.render.render(write_still=True)
