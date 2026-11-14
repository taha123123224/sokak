"""Walkability / reachability analysis of an imported mesh map (v4.8).
Loads assets/maps/<id>.glb + .json, samples every walkable floor layer on a fine grid, floods from the spawns
using the player's real limits (step 0.42 m on foot, ~0.75 m with a jump, 48 deg slopes, 1.8 m head room)
and reports walkable regions you can see but not reach, plus the ledge height that blocks each one.
run: python3.13 tools/reach_map.py -- kereste [out.png]
"""
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from collections import Counter, deque

args = sys.argv[sys.argv.index('--') + 1:]
mid = args[0]
MAPID = mid
import os
STEPH = float(os.environ.get("STEPH", "0.45"))
OUTP = args[1] if len(args) > 1 else '/tmp/reach_%s.png' % mid
R = '/home/claude/sokak/assets/maps/'
meta = json.load(open(R + mid + '.json'))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=R + mid + '.glb')
bm = bmesh.new()
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    if o.type != 'MESH':
        continue
    if any(n in o.name for n in meta.get('nocol', [])):
        continue
    e = o.evaluated_get(dg); me = e.to_mesh(); me.transform(o.matrix_world); bm.from_mesh(me); e.to_mesh_clear()
bvh = BVHTree.FromBMesh(bm)
b = meta['bounds']
G = float(args[2]) if len(args) > 2 else 0.3
xs = np.arange(b[0] + 0.2, b[2] - 0.2, G)
ys = np.arange(b[1] + 0.2, b[3] - 0.2, G)
TOP = 60.0
COSM = math.cos(math.radians(48))
layers = {}   # (i,j) -> list of z
for i, x in enumerate(xs):
    for j, y in enumerate(ys):
        z = TOP; L = []
        for _ in range(12):
            h = bvh.ray_cast(Vector((x, y, z)), Vector((0, 0, -1)), 200.0)
            if h[0] is None:
                break
            p, n = h[0], h[1]
            z = p.z - 0.03
            if n.z < COSM:
                continue
            up = bvh.ray_cast(p + Vector((0, 0, 0.05)), Vector((0, 0, 1)), 1.75)
            if up[0] is not None:
                continue
            L.append(p.z)
        if L:
            layers[(i, j)] = L
nodes = [(i, j, k) for (i, j), L in layers.items() for k in range(len(L))]
idx = {nd: n for n, nd in enumerate(nodes)}
Z = np.array([layers[(i, j)][k] for (i, j, k) in nodes])
print("NODES", len(nodes))

def clear(a, bb, zh):
    pa = Vector((xs[a[0]], ys[a[1]], zh)); pb = Vector((xs[bb[0]], ys[bb[1]], zh))
    d = pb - pa
    return bvh.ray_cast(pa, d.normalized(), d.length)[0] is None

# edges: walk (<=0.45) and jump (<=0.8); store the needed rise for unreachable diagnosis
walk = [[] for _ in nodes]; jump = [[] for _ in nodes]
for n, (i, j, k) in enumerate(nodes):
    z = Z[n]
    for di, dj in ((1, 0), (0, 1), (-1, 0), (0, -1)):
        L2 = layers.get((i + di, j + dj))
        if not L2:
            continue
        for k2, z2 in enumerate(L2):
            dz = z2 - z
            if dz > 1.75 or dz < -6:
                continue
            if not clear((i, j), (i + di, j + dj), max(z, z2) + 0.5) or not clear((i, j), (i + di, j + dj), max(z, z2) + 1.5):
                continue
            m = idx[(i + di, j + dj, k2)]
            # headroom above the start for a climb
            if dz > 0.45:
                hu = bvh.ray_cast(Vector((xs[i], ys[j], z + 1.7)), Vector((0, 0, 1)), dz + 0.2)
                if hu[0] is not None:
                    continue
            (walk if dz <= STEPH else jump)[n].append(m)
# flood from spawns (game coords -> blender: x, y=-z, z=y)
seed = []
for s in meta['spawns']:
    px, py, pz = s['p'][0], -s['p'][2], s['p'][1] - 0.1
    i = int(round((px - xs[0]) / G)); j = int(round((py - ys[0]) / G))
    best = None
    for (di, dj) in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)):
        L = layers.get((i + di, j + dj), [])
        for k, z in enumerate(L):
            if abs(z - pz) < 0.6:
                best = idx[(i + di, j + dj, k)]
    if best is None:
        print("SPAWN NOT ON FLOOR", s)
    else:
        seed.append(best)
reach = np.zeros(len(nodes), np.int8)   # 1 = walk, 2 = needs jump
dq = deque(seed)
for s_ in seed:
    reach[s_] = 1
while dq:
    n = dq.popleft()
    for m in walk[n]:
        if reach[m] == 0 or reach[m] > reach[n]:
            if reach[m] == 0:
                reach[m] = reach[n]; dq.append(m)
    for m in jump[n]:
        if reach[m] == 0:
            reach[m] = 2; dq.append(m)
print("REACH walk", int((reach == 1).sum()), "jump-only", int((reach == 2).sum()), "unreached", int((reach == 0).sum()))
# unreached regions (connected through walk/jump edges, undirected)
par = list(range(len(nodes)))
def f(a):
    while par[a] != a:
        par[a] = par[par[a]]; a = par[a]
    return a
for n in range(len(nodes)):
    if reach[n]:
        continue
    for m in walk[n] + jump[n]:
        if not reach[m]:
            ra, rb = f(n), f(m)
            if ra != rb: par[ra] = rb
reg = Counter(f(n) for n in range(len(nodes)) if not reach[n])
res = []
for r, cnt in reg.most_common(40):
    mem = [n for n in range(len(nodes)) if not reach[n] and f(n) == r]
    area = cnt * G * G
    if area < 1.5:
        continue
    zz = Z[mem]
    cx = float(np.mean([xs[nodes[n][0]] for n in mem])); cy = float(np.mean([ys[nodes[n][1]] for n in mem]))
    # lowest ledge from any reached neighbour node
    best = 99.0; bp = None
    S_ = set(mem)
    for n in mem:
        i, j, k = nodes[n]
        for di, dj in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            for k2, z2 in enumerate(layers.get((i + di, j + dj), [])):
                m = idx[(i + di, j + dj, k2)]
                if reach[m] and Z[n] - z2 > 0 and Z[n] - z2 < best and Z[n] - z2 < 4:
                    if clear((i, j), (i + di, j + dj), Z[n] + 0.5):
                        best = Z[n] - z2; bp = (xs[i], ys[j], z2)
    res.append(dict(area=round(area, 1), z=[round(float(zz.min()), 2), round(float(zz.max()), 2)],
                    c_game=[round(cx, 1), round(float(np.median(zz)), 1), round(-cy, 1)],
                    ledge=round(best, 2) if bp else None, ledge_at_game=[round(bp[0], 1), round(bp[2], 2), round(-bp[1], 1)] if bp else None))
for r_ in res:
    print("UNREACHED", r_)
json.dump(res, open('/tmp/reach_%s.json' % mid, 'w'), indent=1)
# picture: top layer per cell coloured
try:
    from PIL import Image
    W, H = len(xs), len(ys)
    img = np.zeros((H, W, 3), np.uint8) + 20
    zmin, zmax = Z.min(), Z.max()
    for n, (i, j, k) in enumerate(nodes):
        if k != 0:
            continue
        t = (Z[n] - zmin) / max(zmax - zmin, 1e-3)
        base = 80 + int(150 * t)
        col = (40, base, 40) if reach[n] == 1 else ((base, base, 40) if reach[n] == 2 else (base, 30, 30))
        img[H - 1 - j, i] = col
    Image.fromarray(img).resize((W * 3, H * 3), Image.NEAREST).save(OUTP)
    print("IMG", OUTP)
except Exception as ex:
    print("noimg", ex)

# ---- v4.8: re-pick spawns on the walkable main level (reachable on foot, open around, not in the pit / on props)
if '--spawns' in args:
    main_z = float(args[args.index('--spawns') + 1])
    cand = []
    for n, (i, j, k) in enumerate(nodes):
        if reach[n] != 1 or abs(Z[n] - main_z) > 0.35:
            continue
        x, y, z = xs[i], ys[j], Z[n]
        p = Vector((x, y, z + 1.0))
        # elbow room: nothing within 1.4 m, and a decent view (>= 5 of 8 directions open for 4 m)
        near = 0; opn = 0
        for a in range(8):
            d = Vector((math.cos(a * math.pi / 4), math.sin(a * math.pi / 4), 0))
            r1 = bvh.ray_cast(p, d, 1.4)
            if r1[0] is not None:
                near += 1
            if bvh.ray_cast(p, d, 4.0)[0] is None:
                opn += 1
        # open sky or at least 3.5 m of ceiling
        up = bvh.ray_cast(Vector((x, y, z + 0.1)), Vector((0, 0, 1)), 3.5)
        if near == 0 and opn >= 5 and up[0] is None:
            cand.append((x, y, z))
    cand = np.array(cand)
    print("SPAWN CANDIDATES", len(cand))
    cx = float(np.median(cand[:, 0])); cy = float(np.median(cand[:, 1]))
    ext = cand.max(0) - cand.min(0)
    ax = 0 if ext[0] >= ext[1] else 1
    midv = float(np.median(cand[:, ax]))
    out = []
    for team, sel in (('a', cand[:, ax] < midv - ext[ax] * 0.15), ('b', cand[:, ax] > midv + ext[ax] * 0.15)):
        cs = cand[sel]
        chosen = [cs[np.argmin(cs[:, ax])] if team == 'a' else cs[np.argmax(cs[:, ax])]]
        for _ in range(7):
            d = np.min(np.linalg.norm(cs[:, None, :2] - np.array(chosen)[None, :, :2], axis=2), axis=1)
            chosen.append(cs[np.argmax(d)])
        for p in chosen:
            best, bd = None, -1.0
            for a in range(24):
                d = Vector((math.cos(a * math.pi / 12), math.sin(a * math.pi / 12), 0))
                o = Vector((p[0], p[1], p[2] + 1.6))
                h = bvh.ray_cast(o, d, 40.0)
                L = 40.0 if h[0] is None else (h[0] - o).length
                L += 6.0 * d.dot(Vector((cx - p[0], cy - p[1], 0)).normalized())
                if L > bd:
                    bd, best = L, d
            to = Vector((best.x, 0, -best.y))
            yaw = math.atan2(-to.x, -to.z)
            out.append({"p": [round(float(p[0]), 2), round(float(p[2]) + 0.1, 2), round(float(-p[1]), 2)], "yaw": round(yaw, 3), "team": team})
    meta['spawns'] = out
    json.dump(meta, open(R + MAPID + '.json', 'w'), indent=1)
    for o_ in out:
        print("SPAWN", o_)
