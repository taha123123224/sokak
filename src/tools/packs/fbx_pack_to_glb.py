# v4.17: FP animation packs shipped as FBX sources (Sketchfab "source" downloads): import, keep the listed meshes,
# wire the pack's texture set into the materials, freeze the pack camera, clean the action names, export one glb.
import bpy, sys, os, re
from mathutils import Matrix, Vector
a = sys.argv[sys.argv.index('--') + 1:]
src, tex, out, keep = a[0], a[1], a[2], a[3].split(',')
texmap = dict(x.split('=') for x in a[4].split(';')) if len(a) > 4 and a[4] else {}
ref_act = a[5] if len(a) > 5 else ''
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
cams = [o for o in bpy.data.objects if o.type == 'CAMERA']
if ref_act and rig.animation_data:
    rig.animation_data.action = [x for x in bpy.data.actions if x.name.endswith(ref_act) and x.name.startswith(rig.name)][0]
bpy.context.scene.frame_set(1); bpy.context.view_layer.update()
for cam in cams:
    mw = cam.matrix_world.copy(); cam.animation_data_clear(); cam.parent = None
    loc, rot, _ = mw.decompose(); cam.matrix_world = Matrix.LocRotScale(loc, rot, Vector((1, 1, 1)))
    print('CAMERA', loc, cam.data.lens, cam.data.sensor_width)
for o in list(bpy.data.objects):
    if o is rig or o.type == 'CAMERA': continue
    if o.name not in keep: bpy.data.objects.remove(o)
for act in list(bpy.data.actions):
    if not act.name.startswith(rig.name + '|'):
        bpy.data.actions.remove(act); continue
    act.name = act.name.split('|')[-1]; act.use_fake_user = True
def img(p, cs):
    if not p or not os.path.exists(p): return None
    im = bpy.data.images.load(p); im.colorspace_settings.name = cs; return im
def find(prefix, kind):
    c = [f for f in os.listdir(tex) if f.startswith(prefix) and kind.lower() in f.lower()]
    return os.path.join(tex, min(c, key=len)) if c else ''
done = set()
for o in bpy.data.objects:
    if o.type != 'MESH': continue
    for m in o.data.materials:
        if not m or m.name not in texmap or m.name in done: continue
        done.add(m.name); pre = texmap[m.name]
        m.use_nodes = True; nt = m.node_tree
        for n in list(nt.nodes): nt.nodes.remove(n)
        bs = nt.nodes.new('ShaderNodeBsdfPrincipled'); on = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(bs.outputs[0], on.inputs[0])
        for kind, sock, cs in (('Base', 'Base Color', 'sRGB'), ('Metal', 'Metallic', 'Non-Color'), ('Rough', 'Roughness', 'Non-Color')):
            im = img(find(pre, kind), cs)
            if im:
                t = nt.nodes.new('ShaderNodeTexImage'); t.image = im; nt.links.new(t.outputs[0], bs.inputs[sock])
            elif kind == 'Rough':
                bs.inputs['Roughness'].default_value = 0.6
            elif kind == 'Metal':
                bs.inputs['Metallic'].default_value = 0.0
        im = img(find(pre, 'Normal'), 'Non-Color')
        if im:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = im
            nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(t.outputs[0], nm.inputs['Color']); nt.links.new(nm.outputs[0], bs.inputs['Normal'])
        print('MAT', m.name, [n.image.name for n in nt.nodes if n.type == 'TEX_IMAGE'])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_cameras=True, export_yup=True, export_apply=False)
print('WROTE', out, [x.name for x in bpy.data.actions])
