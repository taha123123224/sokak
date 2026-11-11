"""Bake per-map ambient occlusion (CS2-style baked contact shading) into a UV2 atlas with Blender/Cycles.
The chunk_* meshes get a second UV map packed into one atlas; AO is baked with every mesh (far/det too) as
occluder; the glb is re-exported with TEXCOORD_1 and the atlas is written next to it as <map>_ao.png.
In game MatLib puts the atlas into every map material's AO slot (ao_on_uv2), so it costs nothing per frame.
python3 tools/bake_ao.py <map> [atlas_size] [samples] [ao_distance]
"""
import bpy, sys, os, time
a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
MAP = a[0]
SIZE = int(a[1]) if len(a) > 1 else 2048
SAMPLES = int(a[2]) if len(a) > 2 else 24
DIST = float(a[3]) if len(a) > 3 else 2.0
M = '/home/claude/sokak/assets/maps/'
src = M + MAP + '.glb'
t0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
objs = [o for o in bpy.data.objects if o.type == 'MESH']
chunks = [o for o in objs if o.name.startswith('chunk')]
print('meshes', len(objs), 'chunks', len(chunks), 'faces', sum(len(o.data.polygons) for o in chunks))

# ---- UV2 for the chunks: smart-project each chunk into [0,1], then give every chunk its own atlas tile sized by
# the square root of its surface area (a simple shelf packer), so texel density is roughly even across the map
import math, numpy as np
areas = {}
for o in chunks:
    uv = o.data.uv_layers.new(name='UVLightmap')
    o.data.uv_layers.active = uv
    o.data.uv_layers.active_index = len(o.data.uv_layers) - 1
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    # the enormous horizon ground plane (hundreds of metres) must not be in the atlas: split it off into its
    # own object (still an occluder, keeps its material, gets no AO)
    import bmesh
    bm = bmesh.new(); bm.from_mesh(o.data)
    huge = [fc.index for fc in bm.faces if fc.calc_area() > 1500.0]
    bm.free()
    if huge:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='DESELECT')
        bpy.ops.object.mode_set(mode='OBJECT')
        for i in huge:
            o.data.polygons[i].select = True
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        for nobj in bpy.context.selected_objects:
            if nobj is not o:
                nobj.name = 'ground_far_' + o.name
                nobj.data.uv_layers.remove(nobj.data.uv_layers['UVLightmap'])
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
    # huge flat faces (ground planes, slabs) would hog the atlas as one island: cut them into <= ~25 m2 pieces
    for _ in range(5):
        bm = bmesh.new(); bm.from_mesh(o.data)
        sc3 = o.scale
        big = [fc for fc in bm.faces if fc.calc_area() * sc3.x * sc3.z > 25.0]
        if not big:
            bm.free(); break
        bmesh.ops.subdivide_edges(bm, edges=list({e for fc in big for e in fc.edges}), cuts=1, use_grid_fill=True)
        bm.to_mesh(o.data); bm.free(); o.data.update()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003, area_weight=0.0, correct_aspect=True, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    areas[o.name] = sum(pg.area for pg in o.data.polygons) * (o.scale.x * o.scale.y * o.scale.z) ** (2.0 / 3.0)
tot = sum(math.sqrt(v) for v in areas.values())
order = sorted(chunks, key=lambda o: -areas[o.name])
# shelf packing of squares with side = sqrt(area)/tot * k; find the largest k that fits in the unit square
def shelf(k):
    x = y = row_h = 0.0
    pos = {}
    for o in order:
        sz = math.sqrt(areas[o.name]) / tot * k
        if x + sz > 1.0:
            x = 0.0; y += row_h; row_h = 0.0
        if y + sz > 1.0:
            return None
        pos[o.name] = (x, y, sz)
        x += sz; row_h = max(row_h, sz)
    return pos
lo, hi = 0.5, 6.0
best = shelf(lo)
for _ in range(40):
    mid = (lo + hi) / 2
    r = shelf(mid)
    if r: lo, best = mid, r
    else: hi = mid
pad = 1.5 / SIZE
for o in chunks:
    x0, y0, sz = best[o.name]
    layer = o.data.uv_layers['UVLightmap']
    d = np.zeros(len(layer.data) * 2); layer.data.foreach_get('uv', d); d = d.reshape(-1, 2)
    d = np.clip(d, 0.0, 1.0) * (sz - 2 * pad) + np.array([x0 + pad, y0 + pad])
    layer.data.foreach_set('uv', d.ravel())
print('tiles', {k: (round(v[0], 3), round(v[1], 3), round(v[2], 3)) for k, v in best.items()})
print('uv2 done', round(time.time() - t0), 's')

# ---- bake target image in every chunk material
img = bpy.data.images.new('ao', SIZE, SIZE, alpha=False)
img.colorspace_settings.name = 'Non-Color'
mats = set()
for o in chunks:
    for m in o.data.materials:
        if m:
            mats.add(m)
for m in mats:
    m.use_nodes = True
    nt = m.node_tree
    n = nt.nodes.new('ShaderNodeTexImage')
    n.image = img
    n.name = 'AO_BAKE'
    for nn in nt.nodes:
        nn.select = False
    n.select = True
    nt.nodes.active = n
    uvn = nt.nodes.new('ShaderNodeUVMap')
    uvn.uv_map = 'UVLightmap'
    nt.links.new(uvn.outputs['UV'], n.inputs['Vector'])

sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = False
if sc.world is None:
    sc.world = bpy.data.worlds.new('W')
sc.world.light_settings.distance = DIST
sc.render.bake.use_selected_to_active = False
sc.render.bake.margin = 6
sc.render.bake.use_clear = True
sc.cycles.bake_type = 'AO'
bpy.ops.object.select_all(action='DESELECT')
for o in chunks:
    o.select_set(True)
bpy.context.view_layer.objects.active = chunks[0]
# the bake reads the active UV map of each object: make UVLightmap active
for o in chunks:
    lay = o.data.uv_layers['UVLightmap']
    o.data.uv_layers.active = lay
    lay.active_render = True
print('bake start', round(time.time() - t0), 's')
bpy.ops.object.bake(type='AO', margin=6, use_clear=True)
img.filepath_raw = M + MAP + '_ao.png'
img.file_format = 'PNG'
img.save()
# denoise + soften (the raw Cycles bake at low sample counts is speckled)
from PIL import Image as PI, ImageFilter
import numpy as _np
_im = PI.open(M + MAP + '_ao.png').convert('L').filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.GaussianBlur(1.6))
_a = _np.clip(1.0 - (1.0 - _np.asarray(_im).astype(_np.float32) / 255.0) * 0.78, 0.18, 1.0)
PI.fromarray((_a * 255).astype(_np.uint8)).save(M + MAP + '_ao.png')
print('bake done', round(time.time() - t0), 's')

# ---- restore: first UV map must stay the render/active one, drop the bake nodes, export glb with both UVs
for o in chunks:
    o.data.uv_layers.active_index = 0
    o.data.uv_layers[0].active_render = True
for m in mats:
    nt = m.node_tree
    for nn in list(nt.nodes):
        if nn.name == 'AO_BAKE' or nn.type == 'UVMAP':
            nt.nodes.remove(nn)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=src, export_format='GLB', export_yup=True, export_apply=False,
                          export_texcoords=True, export_normals=True, export_tangents=False,
                          export_materials='EXPORT', export_image_format='AUTO', export_animations=False)
print('WROTE', src, round(time.time() - t0), 's')
