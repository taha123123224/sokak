"""Top-down height raster of a map glb (no renderer): python3 tools/topdown.py <id> out.png [px_per_m]
Shows building heights (colour), spawns (blue A / red B) and the playable bounds; also prints the model
bounds and a few stats. Works for imported maps (mesh collision) where map_check.py cannot see walls.
"""
import bpy, sys, os, json, math
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
mid, out = sys.argv[1], sys.argv[2]
ppm = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, 'assets', 'maps', mid + '.glb'))
paths = [os.path.join(ROOT, 'assets', 'maps', mid + '_dress.glb')]
if os.path.exists(paths[0]):
    bpy.ops.import_scene.gltf(filepath=paths[0])
d = json.load(open(os.path.join(ROOT, 'assets', 'maps', mid + '.json')))
dp = os.path.join(ROOT, 'assets', 'maps', mid + '_dress.json')
if os.path.exists(dp):
    dj = json.load(open(dp))
    if dj.get('spawns'):
        d['spawns'] = dj['spawns']
tris = []
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    if o.type != 'MESH':
        continue
    me = o.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    mw = np.array(o.matrix_world)
    v = np.array([vv.co[:] for vv in me.vertices], np.float32)
    if len(v) == 0:
        continue
    v = (np.c_[v, np.ones(len(v))] @ mw.T)[:, :3]
    t = np.array([lt.vertices[:] for lt in me.loop_triangles], np.int64)
    if len(t):
        tris.append(v[t])
T = np.concatenate(tris)          # blender coords: x east, y north, z up
b = d['bounds']                   # godot x0, (-y) ... stored as [x0, y0, x1, y1] in blender-ish x / y
x0, y0, x1, y1 = b[0] - 10, b[1] - 10, b[2] + 10, b[3] + 10
W, H = int((x1 - x0) * ppm), int((y1 - y0) * ppm)
zb = np.full((H, W), -50.0, np.float32)
for tri in T:
    mnx, mxx = tri[:, 0].min(), tri[:, 0].max(); mny, mxy = tri[:, 1].min(), tri[:, 1].max()
    if mxx < x0 or mnx > x1 or mxy < y0 or mny > y1:
        continue
    i0, i1 = int((mnx - x0) * ppm), int((mxx - x0) * ppm) + 1
    j0, j1 = int((y1 - mxy) * ppm), int((y1 - mny) * ppm) + 1
    i0, j0 = max(i0, 0), max(j0, 0); i1, j1 = min(i1, W), min(j1, H)
    if i1 <= i0 or j1 <= j0:
        continue
    xs = x0 + (np.arange(i0, i1) + 0.5) / ppm; ys = y1 - (np.arange(j0, j1) + 0.5) / ppm
    X, Y = np.meshgrid(xs, ys)
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9:
        continue
    l1 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / den
    l2 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / den
    l3 = 1 - l1 - l2
    m = (l1 >= -1e-4) & (l2 >= -1e-4) & (l3 >= -1e-4)
    z = l1 * az + l2 * bz + l3 * cz
    sub = zb[j0:j1, i0:i1]
    np.maximum(sub, np.where(m, z, -50.0), out=sub)
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig, ax = plt.subplots(figsize=(11, 11 * H / W))
im = ax.imshow(np.clip(zb, -2, 14), extent=[x0, x1, y0, y1], cmap='terrain', vmin=-2, vmax=14)
plt.colorbar(im, ax=ax, fraction=0.03, label='yükseklik (m)')
ax.add_patch(plt.Rectangle((b[0], b[1]), b[2] - b[0], b[3] - b[1], fill=False, ec='red', lw=1.5, ls='--'))
for s in d['spawns']:
    ax.plot(s['p'][0], -s['p'][2], 'o', c='#3d8bff' if s['team'] == 'a' else '#ff4d3d', ms=7, mec='k')
ax.grid(alpha=0.25); ax.set_title(f'{mid} — üstten yükseklik (oyun alanı kesikli kırmızı)')
plt.savefig(out, dpi=80, bbox_inches='tight')
print('bounds', b, 'tris', len(T), 'z range', round(float(T[:, :, 2].min()), 2), round(float(T[:, :, 2].max()), 2))
