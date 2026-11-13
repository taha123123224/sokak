"""v3.4 user-supplied Sketchfab USDZ maps (CC-BY 4.0, frostychaos144) -> assets/maps/<id>.glb + <id>.json
The model is real-sized (scale S), centred, its floor put at 0; collision is the map's own meshes
(json "mesh_collision": the game builds trimesh bodies), spawns are found by ray-casting the floor
on a grid (head room + elbow room), spread out by farthest-point sampling and split into two team halves.
run: python3.13 tools/import_usdmap.py -- kum
"""
import bpy, bmesh, sys, os, json, math, random
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

U = '/home/claude/usdz/'
OUT = '/home/claude/sokak/assets/maps/'
SPECS = {
    # v4.3 user-supplied Sketchfab maps
    'kum': dict(usd=U + 'desert/scene.usdc', S=220.0, env={"preset": "golden", "fog": 0.003, "sky": "day"},
                credit="Desert City — Mikey x pc (CC-BY 4.0)", floor_obj='Ground_EXT', nocol=['Alpha', 'additiveunlit'],
                prune=40.0, dedupe=True, ground={'tex': 'dryground', 'y': -4.6, 'tint': [1.0, 0.9, 0.75]}, area=52.0, max_h=2.2, prune_sep=False, drop_mats=['SkyDome', 'UnitPortrait', 'GridMat', 'No_Name']),
    'ayvadisi': dict(usd=U + 'abandoned/scene.usdc', S=4.2, env={"preset": "overcast", "fog": 0.014, "sky": "day"},
                     credit="Abandoned City Street — dasy444 (Sketchfab Standard)", floor_obj='Material_007', nocol=[], prune=None, max_h=2.5, ground={'tex': 'asphalt', 'y': 0.0, 'tint': [0.55, 0.55, 0.55]}),

    'kum_old': dict(usd=U + '731dc94a-Dust2-short/scene.usdc', S=33.0, env={"preset": "golden", "fog": 0.004, "sky": "day"},
                credit="Dust2-short — frostychaos144 (CC-BY 4.0)", floor_obj='ShortDust2', nocol=[], prune=15.0, ground={'tex': 'dryground', 'y': -0.03, 'tint': [1.0, 0.93, 0.8]}),
    'hurda': dict(usd=U + '65f9ca94-Maps/scene.usdc', S=10.5, env={"preset": "day", "fog": 0.006, "sky": "day"},
                  credit="Maps — frostychaos144 (CC-BY 4.0)", floor_obj='Floor_Concrete', nocol=['Decals', 'Clothes', 'Wood', 'plane1']),
    'fabrika': dict(usd=U + 'd89bc40a-Rust/scene.usdc', S=6.0, env={"preset": "overcast", "fog": 0.005, "sky": "day"},
                    credit="Rust — frostychaos144 (CC-BY 4.0)", floor_obj=None, nocol=['WaterPool'], ground={'tex': 'dirt', 'y': -0.03, 'tint': [0.85, 0.85, 0.8]}),
}

def meshes():
    return [o for o in bpy.data.objects if o.type == 'MESH']

def world_bounds(objs):
    P = []
    for o in objs:
        for c in o.bound_box:
            P.append(tuple(o.matrix_world @ Vector(c)))
    P = np.array(P)
    return P.min(0), P.max(0)

def build_bvh(objs):
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        e.to_mesh_clear()
    bm.verts.ensure_lookup_table()
    return BVHTree.FromBMesh(bm)

def run(mid):
    sp = SPECS[mid]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=sp['usd'])
    for o in list(bpy.data.objects):
        if o.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(o)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and any(any(k in (m.name if m else '') for k in sp.get('drop_mats', [])) for m in o.data.materials):
            bpy.data.objects.remove(o)
    if sp.get('dedupe'):
        # the model ships every prop twice (same mesh, two materials): keep one copy
        seen = set(); gone = 0
        for o in list(meshes()):
            bb = [tuple(o.matrix_world @ Vector(c)) for c in o.bound_box]
            key = (len(o.data.polygons), tuple(round(v, 4) for v in np.mean(bb, 0)), tuple(round(v, 4) for v in np.ptp(np.array(bb), 0)))
            if key in seen:
                bpy.data.objects.remove(o); gone += 1
            else:
                seen.add(key)
        print("DEDUPED", gone)
    S = sp['S']
    roots = [o for o in bpy.data.objects if o.parent is None]
    piv = bpy.data.objects.new('maproot', None)
    bpy.context.scene.collection.objects.link(piv)
    for o in roots:
        o.parent = piv
        o.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    ms = meshes()
    fo = [o for o in ms if sp['floor_obj'] and o.data.materials and sp['floor_obj'] in o.data.materials[0].name] or ms
    lo, hi = world_bounds(fo)
    c = (lo + hi) / 2
    piv.matrix_world = Matrix.Scale(S, 4) @ Matrix.Translation(Vector((-c[0], -c[1], -lo[2])))
    bpy.context.view_layer.update()
    lo, hi = world_bounds(fo)
    alo, ahi = world_bounds(ms)
    if sp.get('area'):
        a_ = sp['area']; lo = np.array([-a_, -a_, lo[2]]); hi = np.array([a_, a_, hi[2]])
    print("FLOOR AREA", lo.round(1), hi.round(1), "ALL", alo.round(1), ahi.round(1))
    # walkable sample points
    bvh = build_bvh(ms)
    pts = []
    REJ = {'up': 0, 'side': 0, 'norm': 0, 'high': 0}
    step = 1.5
    xs = np.arange(lo[0] + 1.0, hi[0] - 1.0, step)
    ys = np.arange(lo[1] + 1.0, hi[1] - 1.0, step)
    top = ahi[2] + 5.0
    for x in xs:
        for y in ys:
            orig = Vector((x, y, top))
            z = top
            # walk down through stacked floors: keep the lowest walkable hit with head room
            hits = []
            for _ in range(14):
                h = bvh.ray_cast(Vector((x, y, z)), Vector((0, 0, -1)), 500.0)
                if h[0] is None:
                    break
                hits.append(h)
                z = h[0].z - 0.05
            for h in hits[::-1]:
                p, n = h[0], h[1]
                if abs(n.z) < 0.85 or p.z > lo[2] + sp.get('max_h', 8.0):
                    REJ['norm' if abs(n.z) < 0.85 else 'high'] += 1
                    continue
                up = bvh.ray_cast(p + Vector((0, 0, 0.05)), Vector((0, 0, 1)), 2.3)
                if up[0] is not None:
                    REJ['up'] += 1
                    continue
                ok = True
                for a in range(8):
                    d = Vector((math.cos(a * math.pi / 4), math.sin(a * math.pi / 4), 0))
                    r = bvh.ray_cast(p + Vector((0, 0, 1.0)), d, 0.8)
                    if r[0] is not None:
                        ok = False; REJ['side'] += 1; break
                if ok:
                    # how open is it around (spawns want elbow room, not a rock crevice)
                    op = 0
                    for a in range(8):
                        d = Vector((math.cos(a * math.pi / 4), math.sin(a * math.pi / 4), 0))
                        if bvh.ray_cast(p + Vector((0, 0, 1.0)), d, 3.0)[0] is None:
                            op += 1
                    pts.append((p.x, p.y, p.z, op))
                break
    pts = np.array(pts)
    print("WALKABLE", len(pts), REJ)
    opn = pts[:, 3]
    pts = pts[:, :3]
    # keep the biggest connected-ish region: drop points far from the median cluster
    med = np.median(pts, 0)
    dist = np.linalg.norm(pts[:, :2] - med[:2], axis=1)
    keep = dist < np.percentile(dist, 97) + 1e-3
    pts = pts[keep]; opn = opn[keep]
    cen = np.median(pts, 0)
    # team halves along the long axis
    ext = pts.max(0) - pts.min(0)
    ax = 0 if ext[0] >= ext[1] else 1
    mid_v = np.median(pts[:, ax])
    spawns = []
    for team, sel in (('a', pts[:, ax] < mid_v - ext[ax] * 0.12), ('b', pts[:, ax] > mid_v + ext[ax] * 0.12)):
        cand = pts[sel & (opn >= 6)] if np.sum(sel & (opn >= 6)) >= 8 else pts[sel]
        if len(cand) == 0:
            continue
        # farthest point sampling inside the half
        chosen = [cand[np.argmin(cand[:, ax]) if team == 'a' else np.argmax(cand[:, ax])]]
        for _ in range(7):
            d = np.min(np.linalg.norm(cand[:, None, :2] - np.array(chosen)[None, :, :2], axis=2), axis=1)
            chosen.append(cand[np.argmax(d)])
        for p in chosen:
            yaw = math.atan2(-(0 - p[0]), -(0 - (-p[1])))  # face the map centre
            # world: x = bx, y = bz, z = -by ; yaw so -Z basis looks at the centre
            to = Vector((cen[0] - p[0], 0, -(cen[1] - p[1])))
            yaw = math.atan2(-to.x, -to.z)
            spawns.append({"p": [round(float(p[0]), 2), round(float(p[2]) + 0.1, 2), round(float(-p[1]), 2)], "yaw": round(yaw, 3), "team": team})
    # bounds of the playable area (+ margin) and invisible walls on them
    plo = pts.min(0) - 2.0
    phi = pts.max(0) + 2.0
    b = [math.floor(plo[0]), math.floor(plo[1]), math.ceil(phi[0]), math.ceil(phi[1])]
    H = 40.0
    cols = []
    cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
    w, h = b[2] - b[0], b[3] - b[1]
    for (px, py, sx, sy) in ((b[0] - 0.5, cy, 1, h + 2), (b[2] + 0.5, cy, 1, h + 2), (cx, b[1] - 0.5, w + 2, 1), (cx, b[3] + 0.5, w + 2, 1)):
        cols.append({"c": [px, H / 2 - 1, -py], "s": [sx, H, sy], "r": [0, 0, 0]})
    if sp.get('prune'):
        # drop the far backdrop pieces (floating city blocks) that sit outside the playable area
        for o in (list(meshes()) if sp.get('prune_sep', True) else []):
            bpy.ops.object.select_all(action='DESELECT')
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.separate(type='LOOSE')
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.context.view_layer.update()
        pr = sp['prune']; gone = 0
        for o in list(meshes()):
            olo, ohi = world_bounds([o])
            cxo, cyo = (olo[0] + ohi[0]) / 2, (olo[1] + ohi[1]) / 2
            outside = cxo < b[0] - pr or cxo > b[2] + pr or cyo < b[1] - pr or cyo > b[3] + pr
            floating = olo[2] > 2.5 and (cxo < b[0] - 2 or cxo > b[2] + 2 or cyo < b[1] - 2 or cyo > b[3] + 2)
            if outside or floating:
                bpy.data.objects.remove(o); gone += 1
        print("PRUNED", gone)
    meta = {"bounds": b, "spawns": spawns, "colliders": cols, "env": sp['env'], "mesh_collision": True,
            "nocol": sp['nocol'], "credit": sp['credit']}
    if sp.get('ground'):
        meta["ground"] = sp['ground']
    json.dump(meta, open(OUT + mid + '.json', 'w'), indent=1)
    bpy.ops.export_scene.gltf(filepath=OUT + mid + '.glb', export_format='GLB', export_yup=True, export_apply=True,
                              export_image_format='AUTO')
    print("WROTE", mid, "spawns", len(spawns), "bounds", b)

run(sys.argv[sys.argv.index('--') + 1])
