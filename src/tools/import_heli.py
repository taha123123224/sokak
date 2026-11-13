"""CH-47 Chinook (drcrazzie, CC-BY 4.0) usdz -> assets/models/heli_ch47.glb for the match insertion cinematic.
Front = +X (Godot +X), rotor hubs are separate nodes 'rotor_f' / 'rotor_r' with origin on the hub."""
import bpy, sys
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath='/home/claude/usdz/heli/scene.usdc')
S = 2.2
ms = [o for o in bpy.data.objects if o.type == 'MESH']
for o in bpy.data.objects:
    if o.parent is None:
        o.scale = (o.scale[0] * S, o.scale[1] * S, o.scale[2] * S)
        o.location = o.location * S
bpy.context.view_layer.update()
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in ms:
    if o.name.startswith('Cylinder_009'):
        o.name = 'rotor_f'
    elif o.name.startswith('Cylinder_004'):
        o.name = 'rotor_r'
for nm in ('rotor_f', 'rotor_r'):
    o = bpy.data.objects[nm]
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    ctr = sum(bb, Vector()) / 8
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.scene.cursor.location = ctr
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)
bpy.ops.export_scene.gltf(filepath='/home/claude/sokak/assets/models/heli_ch47.glb', export_format='GLB', export_image_format='JPEG', export_jpeg_quality=85)
print("HELI OK")
