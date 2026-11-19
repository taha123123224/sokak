# v4.17: Matzh FP packs from their original .blend (the Sketchfab glb/usdz conversions put the meshes outside their skin's
# bind space). Keeps only what the first-person camera sees (gloves, sleeves, watch, the gun), wires the pack's own 4K
# texture set into the materials and exports every action, sampled from the Rigify deform bones, to one glb.
import bpy, sys, os
from mathutils import Matrix, Vector
a = sys.argv[sys.argv.index('--') + 1:]
blend, tex, out = a[0], a[1], a[2]
keep_mats = a[3].split(',')          # materials of the arms mesh to keep
gun = a[4]                           # gun object
texmap = dict(x.split('=') for x in a[5].split(';'))   # material=texture prefix
bpy.ops.wm.open_mainfile(filepath=blend)
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
# the pack camera rides the head control (Child Of a widget object): freeze it where it is in the idle pose
for cam in [o for o in bpy.data.objects if o.type == 'CAMERA']:
    rig.animation_data.action = bpy.data.actions.get('Idle') or rig.animation_data.action
    bpy.context.scene.frame_set(1); bpy.context.view_layer.update()
    mw = cam.matrix_world.copy()
    for c in list(cam.constraints): cam.constraints.remove(c)
    cam.parent = None
    loc, rot, _ = mw.decompose()
    cam.matrix_world = Matrix.LocRotScale(loc, rot, Vector((1, 1, 1)))
    print('CAMERA', loc, cam.data.lens, cam.data.sensor_width)
arms = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is rig and any(m and m.name in keep_mats for m in o.data.materials)][0]
for o in list(bpy.data.objects):
    if o not in (rig, arms, bpy.data.objects[gun]) and o.type != 'CAMERA':
        bpy.data.objects.remove(o)
# drop the arms mesh faces of the rest of the body (head, armor, backpack ... are behind the camera)
import bmesh
bm = bmesh.new(); bm.from_mesh(arms.data)
keep_idx = {i for i, m in enumerate(arms.data.materials) if m and m.name in keep_mats}
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in keep_idx], context='FACES')
bm.to_mesh(arms.data); bm.free()
def img(p, cs):
    if not os.path.exists(p): return None
    im = bpy.data.images.load(p); im.colorspace_settings.name = cs; return im
def find(prefix, kind):
    c = [f for f in os.listdir(tex) if f.startswith(prefix) and kind.lower() in f.lower()]
    return os.path.join(tex, min(c, key=len)) if c else ''
for o in (arms, bpy.data.objects[gun]):
    for m in o.data.materials:
        if not m or m.name not in texmap: continue
        pre = texmap[m.name]
        m.use_nodes = True; nt = m.node_tree
        for n in list(nt.nodes): nt.nodes.remove(n)
        bs = nt.nodes.new('ShaderNodeBsdfPrincipled'); outn = nt.nodes.new('ShaderNodeOutputMaterial')
        nt.links.new(bs.outputs[0], outn.inputs[0])
        for kind, sock, cs in (('Base', 'Base Color', 'sRGB'), ('Metal', 'Metallic', 'Non-Color'), ('Rough', 'Roughness', 'Non-Color')):
            im = img(find(pre, kind), cs)
            if im:
                t = nt.nodes.new('ShaderNodeTexImage'); t.image = im; nt.links.new(t.outputs[0], bs.inputs[sock])
        im = img(find(pre, 'Normal'), 'Non-Color')
        if im:
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = im
            nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(t.outputs[0], nm.inputs['Color']); nt.links.new(nm.outputs[0], bs.inputs['Normal'])
        print('MAT', m.name, pre, [n.image.name for n in nt.nodes if n.type == 'TEX_IMAGE'])
rig.animation_data_create()
for act in bpy.data.actions:
    act.use_fake_user = True
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_def_bones=True, export_cameras=True, export_yup=True, export_apply=False, export_image_format='AUTO')
print('WROTE', out)
