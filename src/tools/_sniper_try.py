import bpy, sys, math
from mathutils import Vector
exec(open('tools/_inspect_ext.py').read().split("for k,f in")[0])
B='/home/claude/ext3d/3dexport_sniper_1722149628/3dexport_sniper_1722149628/bakes/'
swap = sys.argv[-1] == 'swap'
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.fbx(filepath=files['sniper'])
def setimg(mat, pre):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE': nt.nodes.remove(n)
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(B + pre + '_basecolor.png')
    nt.nodes.active = t
bm = {'Material.001': '1st', 'Material.002': '2nd'}
if swap: bm = {'Material.001': '2nd', 'Material.002': '1st'}
for m, pre in bm.items(): setimg(bpy.data.materials[m], pre)
sc = bpy.context.scene
cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = 4.2
cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam)
cam.location = (8, -0.6, 0.1); cam.rotation_euler = (math.radians(90), 0, math.radians(90)); sc.camera = cam
sc.render.engine = 'BLENDER_WORKBENCH'; sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 1000; sc.render.resolution_y = 600
sc.render.filepath = '/tmp/sn_%s.png' % ('swap' if swap else 'a'); bpy.ops.render.render(write_still=True)
