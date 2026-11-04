import bpy, sys
exec(open('tools/_inspect_ext.py').read().split("for k,f in")[0])
k=sys.argv[-1]; f=files[k]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
if f.endswith('.blend'): bpy.ops.wm.open_mainfile(filepath=f, load_ui=False, use_scripts=False)
else: bpy.ops.import_scene.fbx(filepath=f)
for i in bpy.data.images: print('IMG', i.name, i.filepath, 'packed' if i.packed_file else '-', i.size[:])
for o in bpy.data.objects:
    if o.type=='MESH': print('OBJ', o.name, [s.material.name if s.material else None for s in o.material_slots], len(o.data.uv_layers))
