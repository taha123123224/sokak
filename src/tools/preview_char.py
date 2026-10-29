import sys, math, bpy
from mathutils import Vector
out = sys.argv[1]; f = sys.argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
print('ACTIONS', [a.name for a in bpy.data.actions]); print('NLA', [(t.name, t.mute) for t in (arm.animation_data.nla_tracks if arm.animation_data else [])])
act = bpy.data.actions.get(sys.argv[3]) if len(sys.argv) > 3 else None
if arm.animation_data:
    [setattr(t, 'mute', True) for t in arm.animation_data.nla_tracks]
if act:
    arm.animation_data_create(); arm.animation_data.action = act
    try: arm.animation_data.action_slot = act.slots[0]
    except Exception: pass
    bpy.context.scene.frame_set(int(sys.argv[4]) if len(sys.argv) > 4 else 10)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True; sc.display.shading.show_shadows = True
from PIL import Image
tiles = []
for i, (loc, tgt, lens) in enumerate([((1.6, -3.6, 1.2), (0, 0, 0.95), 50), ((-1.8, 2.6, 1.3), (0, 0, 0.95), 50), ((0.25, -0.7, 1.68), (0, 0, 1.62), 85)]):
    cam = bpy.data.objects.new('c%d' % i, bpy.data.cameras.new('c%d' % i)); sc.collection.objects.link(cam)
    cam.location = loc; cam.data.lens = lens
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.resolution_x = 500; sc.render.resolution_y = 700
    sc.render.filepath = '/tmp/pc_%d.png' % i
    bpy.ops.render.render(write_still=True); tiles.append(Image.open(sc.render.filepath))
sheet = Image.new('RGB', (1500, 700)); [sheet.paste(t, (i * 500, 0)) for i, t in enumerate(tiles)]
sheet.save(out); print('saved', out)
