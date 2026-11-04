# Render a flat white side silhouette of a weapon glb (kill-feed icon).
# usage: blender -b -P tools/kf_icons.py -- in.glb out.png
import bpy, sys, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# drop marker / helper meshes and hands
objs2 = []
for o in objs:
    n = o.name.lower()
    if any(k in n for k in ("hand", "arm", "glass", "lens", "flash")):
        o.hide_render = True
        continue
    objs2.append(o)
mn = mathutils.Vector((1e9, 1e9, 1e9)); mx = -mn
for o in objs2:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c)
        mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
ctr = (mn + mx) / 2; ext = mx - mn
mat = bpy.data.materials.new("sil"); mat.use_nodes = True
nt = mat.node_tree; nt.nodes.clear()
em = nt.nodes.new("ShaderNodeEmission"); em.inputs[0].default_value = (1, 1, 1, 1)
o_ = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0], o_.inputs[0])
for o in objs2:
    o.data.materials.clear(); o.data.materials.append(mat)
    for p in o.data.polygons: p.material_index = 0
sc = bpy.context.scene
# glTF import: Godot +Y up -> Blender +Z; weapon muzzle along an horizontal axis
long_axis = 0 if ext.x >= ext.y else 1
cam_d = bpy.data.cameras.new("c"); cam_d.type = "ORTHO"
L = max(ext[long_axis], ext.z * 3.0) * 1.08
cam_d.ortho_scale = L
cam = bpy.data.objects.new("c", cam_d); sc.collection.objects.link(cam)
if long_axis == 1:
    # muzzle along +/-Y : look from +X
    cam.location = (ctr.x + 5, ctr.y, ctr.z); cam.rotation_euler = (1.5708, 0, 1.5708)
else:
    cam.location = (ctr.x, ctr.y - 5, ctr.z); cam.rotation_euler = (1.5708, 0, 0)
sc.camera = cam
sc.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
sc.render.film_transparent = True
sc.render.resolution_x = 384; sc.render.resolution_y = 128
sc.view_settings.view_transform = "Standard"
sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("KF OK", out, long_axis, tuple(round(v, 2) for v in ext))
