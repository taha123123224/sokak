"""v4.12 dressing layers for imported maps -> assets/maps/<id>_dress.glb + <id>_dress.json
    python3 tools/dress.py fabrika

The imported model is loaded only as a BVH (ground height, clearance, line of sight); it is removed before
export, so the dress glb holds just the new geometry. Props are placed on the model's real ground; a prop
whose footprint is blocked by the model is skipped (reported). Spawn line of sight is measured against the
model + dress geometry (the json box-collider check cannot see imported meshes).
"""
import sys, os, math, json
sys.path.insert(0, os.path.dirname(__file__))
import maps as MP
from maps import *                      # noqa: F401,F403  (box, cyl, wall, container, crate, M, col, spawn, ...)
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = MP.ROOT
OUTD = os.path.join(ROOT, 'assets', 'maps')
BVH = None
SKIPPED = []


def load_model_bvh(mid):
    global BVH
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUTD, mid + '.glb'))
    objs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        me = o.evaluated_get(dg).to_mesh(); me.transform(o.matrix_world); bm.from_mesh(me)
        o.evaluated_get(dg).to_mesh_clear()
    BVH = BVHTree.FromBMesh(bm)
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
    return BVH


def ground_z(x, y, top=1.8):
    h = BVH.ray_cast(Vector((x, y, top)), Vector((0, 0, -1)), 40.0)
    return h[0].z if h[0] is not None else 0.0


def footprint_probe(x, y, w, d, rot=0.0, hgt=3.0, step=1.0, tol=0.45, top=1.8):
    """vertical probes over the footprint: returns (ok, ground_z_max). ok = nothing of the model above the
    ground inside the footprint (up to hgt) and the ground is inside the map and level within tol"""
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    nx, ny = max(2, int(w / step) + 1), max(2, int(d / step) + 1)
    zs = []
    for i in range(nx):
        for j in range(ny):
            lx = -w / 2 + w * i / (nx - 1); ly = -d / 2 + d * j / (ny - 1)
            px, py = x + lx * c - ly * s, y + lx * s + ly * c
            g = BVH.ray_cast(Vector((px, py, top)), Vector((0, 0, -1)), 40.0)
            if g[0] is None:
                return False, 0.0                  # off the model (outside the compound)
            gz = g[0].z
            h = BVH.ray_cast(Vector((px, py, gz + 0.25)), Vector((0, 0, 1)), hgt)
            if h[0] is not None:
                return False, 0.0
            zs.append(gz)
    if max(zs) - min(zs) > tol:
        return False, 0.0
    return True, max(zs)


def blocked(x, y, w, d, rot=0.0, z0=None, hgt=3.0, step=1.0):
    return not footprint_probe(x, y, w, d, rot, hgt, step)[0]


SEARCH = [(0, 0)] + [(r * math.cos(a), r * math.sin(a)) for r in (1.0, 2.0, 3.0, 3.5) for a in [i * math.pi / 4 for i in range(8)]]


def placed(fn, x, y, w, d, rot=0.0, hgt=3.0, tag='', search=True, top=1.8):
    """build a prop with footprint w x d around (x, y) where the model leaves room (spiral search up to
    3.5 m); fn(x, y) builds it at ground 0, the new objects + colliders are lifted onto the model's ground"""
    for (dx, dy) in (SEARCH if search else [(0, 0)]):
        ok, gz = footprint_probe(x + dx, y + dy, w, d, rot, hgt, top=top)
        if ok:
            break
    else:
        SKIPPED.append((tag, round(x, 1), round(y, 1)))
        return None
    before = set(bpy.data.objects); nc = len(MP.COL)
    fn(x + dx, y + dy)
    for o in bpy.data.objects:
        if o not in before and o.parent is None:
            o.location.z += gz
    for cdat in MP.COL[nc:]:
        cdat['c'][1] += gz
    return (x + dx, y + dy, gz)


# ------------------------------------------------------------------------- industrial props
def tank(x, y, r, h, mm, color=(0.78, 0.78, 0.74)):
    """vertical storage tank: shell, roof cone, ring stiffeners, caged ladder, top platform rail"""
    sh = M('mixer_white', color, 0.45, 0.3)
    cyl('tank_shell', r, h, (x, y, h / 2), m=sh, axis='Z', verts=32)
    lathe('tank_roof', [(r + 0.05, h), (r * 0.15, h + r * 0.28)], (x, y, 0), m=sh, seg=32)
    for k in range(1, int(h / 2.4)):
        torus('tank_ring', r + 0.03, 0.04, (x, y, k * 2.4), m=mm['steel'], seg=32, mseg=4)
    cyl('tank_base', r + 0.3, 0.3, (x, y, 0.15), m=mm['concrete'], axis='Z', verts=32)
    lx = x + r + 0.35
    for sx in (-0.22, 0.22):
        box('ladder_rail', (0.05, 0.05, h + 1.0), (lx, y + sx, (h + 1.0) / 2), m=mm['steel'])
    for i in range(int(h / 0.3)):
        box('ladder_rung', (0.04, 0.44, 0.03), (lx, y, 0.3 + i * 0.3), m=mm['steel'])
    for i in range(int(h / 0.9)):
        torus('cage', 0.4, 0.015, (lx + 0.25, y, 2.4 + i * 0.9), (0, 0, 0), m=mm['steel'], seg=10, mseg=3, arc=200)
    for i in range(16):
        a = i / 16 * math.tau
        cyl('roof_post', 0.025, 1.0, (x + math.cos(a) * (r - 0.1), y + math.sin(a) * (r - 0.1), h + 0.5), m=mm['steel'], axis='Z', verts=5)
    torus('roof_rail', r - 0.1, 0.03, (x, y, h + 1.0), m=mm['steel'], seg=32, mseg=4)
    col((x, y, h / 2), (r * 1.85, r * 1.85, h))


def coil(x, y, z, r, w, mm, rot=0):
    """hot-rolled steel coil lying on its side: crisp outer drum, darker wound end faces, open eye"""
    rm = M('metal_steel', (0.46, 0.46, 0.48), 0.5, 0.85)
    dk = M('metal_dark', (0.16, 0.16, 0.17), 0.55, 0.8)
    root = empty('coil', (x, y, z)); root.rotation_euler = (0, 0, math.radians(rot))
    cyl('coil_drum', r, w, (0, 0, r), m=rm, parent=root, axis='X', verts=32, bevel=0.025, segs=2)
    for sx in (-1, 1):
        cyl('coil_face', r * 0.97, 0.01, (sx * (w / 2 + 0.004), 0, r), m=dk, parent=root, axis='X', verts=32)
        cyl('coil_eye', r * 0.36, 0.02, (sx * (w / 2 + 0.012), 0, r), m=mm['black'], parent=root, axis='X', verts=20)
    for sx in (-0.25, 0.25):
        torus('coil_band', r + 0.01, 0.012, (sx * w, 0, r), (0, 90, 0), m=mm['black'], parent=root, seg=32, mseg=3)


def coil_row(x, y, n, rot, mm, r=0.8, w=1.4):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for i in range(n):
        coil(x + c * i * (w + 0.25), y + s * i * (w + 0.25), 0.18, r, w, mm, rot=rot)
        box('coil_saddle', (w * 0.9, r * 1.6, 0.18), (x + c * i * (w + 0.25), y + s * i * (w + 0.25), 0.09), (0, 0, rot), m=mm['planks'])
    L = n * (w + 0.25)
    col((x + c * (L / 2 - w / 2), y + s * (L / 2 - w / 2), r + 0.1), (L, r * 2, r * 2 + 0.2), rotz=rot)


def beam_stack(x, y, rot, mm, n=4, L=8.0):
    """I-beam (HEB) stack on timber bearers"""
    rs = M('rust_metal', (0.4, 0.25, 0.15), 0.8, 0.6)
    root = empty('beams', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for b in (-L * 0.35, 0, L * 0.35):
        box('bearer', (1.9, 0.14, 0.14), (0, b, 0.07), m=mm['planks'], parent=root)
    for layer in range(n):
        for i in range(4):
            prof('ibeam', [(-0.15, 0), (0.15, 0), (0.15, 0.03), (0.02, 0.03), (0.02, 0.27), (0.15, 0.27), (0.15, 0.3), (-0.15, 0.3), (-0.15, 0.27), (-0.02, 0.27), (-0.02, 0.03), (-0.15, 0.03)],
                 L, (-0.6 + i * 0.4, 0, 0.14 + layer * 0.3), m=rs, parent=root, plane='XZ', bevel=0.0)
    col((x, y, (0.14 + n * 0.3) / 2), (1.9, L, 0.14 + n * 0.3), rotz=rot)


def pipe_rack(x, y, rot, L, mm, h=4.2):
    """steel pipe bridge: portal frames every 6 m carrying 4 insulated pipes (overhead, walk under)"""
    root = empty('piperack', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    n = max(2, int(L / 6) + 1)
    pm = [M('pipe_grey', (0.6, 0.62, 0.62), 0.45, 0.6), M('pipe_yellow', (0.82, 0.66, 0.12), 0.45, 0.4), M('pipe_alu', (0.78, 0.8, 0.82), 0.3, 0.9)]
    for i in range(n):
        yy = -L / 2 + L * i / (n - 1)
        for sx in (-1, 1):
            box('pr_col', (0.25, 0.25, h), (sx * 1.4, yy, h / 2), m=mm['steel'], parent=root)
            col((x + (sx * 1.4) * math.cos(math.radians(rot)) - yy * math.sin(math.radians(rot)),
                 y + (sx * 1.4) * math.sin(math.radians(rot)) + yy * math.cos(math.radians(rot)), h / 2), (0.3, 0.3, h), rotz=rot)
        box('pr_beam', (3.1, 0.25, 0.3), (0, yy, h), m=mm['steel'], parent=root)
    for k, px in enumerate((-1.0, -0.35, 0.35, 1.0)):
        cyl('pr_pipe', 0.22 if k % 2 == 0 else 0.16, L + 1.0, (px, 0, h + 0.38), m=pm[k % 3], parent=root, axis='Y', verts=14)
    col((x, y, h + 0.3), (3.1 if abs(math.sin(math.radians(rot))) < 0.5 else L, L if abs(math.sin(math.radians(rot))) < 0.5 else 3.1, 0.7), rotz=0)


def guard_hut(x, y, rot, mm):
    root = empty('hut', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    w = M('hut_white', (0.86, 0.86, 0.84), 0.6)
    box('hut_body', (2.4, 2.4, 2.5), (0, 0, 1.25), m=w, parent=root, bevel=0.03)
    box('hut_roof', (2.8, 2.8, 0.15), (0, 0, 2.58), m=mm['steel'], parent=root)
    for (px, py, rx) in [(0, -1.21, 0), (1.21, 0, 90)]:
        box('hut_win', (1.4, 0.03, 0.9), (px, py, 1.6), (0, 0, rx), m=mm['glass'], parent=root)
    col((x, y, 1.3), (2.4, 2.4, 2.6), rotz=rot)


def spawn_los(spawns_a, spawns_b, extra_objs):
    """count open eye-height sight lines between the two spawn sets through model + dress geometry"""
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in extra_objs:
        if o.type != 'MESH':
            continue
        me = o.evaluated_get(dg).to_mesh(); me.transform(o.matrix_world); bm.from_mesh(me)
        o.evaluated_get(dg).to_mesh_clear()
    dress = BVHTree.FromBMesh(bm)
    opn = []
    for a in spawns_a:
        for b in spawns_b:
            pa = Vector((a[0], a[1], a[2] + 1.65)); pb = Vector((b[0], b[1], b[2] + 1.65))
            d = pb - pa; L = d.length; d.normalize()
            if BVH.ray_cast(pa, d, L)[0] is None and dress.ray_cast(pa, d, L)[0] is None:
                opn.append((a, b))
    return opn


def finalize_dress(mid, spawns_a, spawns_b, extra=None):
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    opn = spawn_los(spawns_a, spawns_b, objs)
    MP.SPAWNS.clear()
    for (x, y, z, yaw) in spawns_a:
        MP.spawn(x, y, z + 0.1, yaw, 'a')
    for (x, y, z, yaw) in spawns_b:
        MP.spawn(x, y, z + 0.1, yaw, 'b')
    import numpy as np
    dmin = min(math.dist(a[:2], b[:2]) for a in spawns_a for b in spawns_b)
    print(f'{mid} dress: open spawn sight-lines {len(opn)} / {len(spawns_a) * len(spawns_b)}, closest enemy spawns {dmin:.1f} m')
    for a, b in opn[:8]:
        print('   OPEN', a[:2], '->', b[:2])
    if SKIPPED:
        print('   skipped (no room in the model):', SKIPPED)
    ex = dict(extra or {})
    MP.finalize(mid + '_dress', ex.pop('env', {}), json.load(open(os.path.join(OUTD, mid + '.json')))['bounds'], extra=ex)


# ======================================================================== FABRİKA (Rust compound, 33.7° rotated)
def dress_fabrika():
    mm = MP.begin()
    load_model_bvh('fabrika')
    ANG = 33.7                                # compound axes (long edge W corner -> N corner)
    ca, sa = math.cos(math.radians(ANG)), math.sin(math.radians(ANG))
    def P(u, v, ox, oy):
        return ox + u * ca - v * sa, oy + u * sa + v * ca
    conc = M('site_floor', (0.62, 0.62, 0.6), 0.6)
    def yard(ox, oy, mirror, tank_col):
        sg = 1 if not mirror else -1
        for (u, v, r_, h_) in [(-6.5, 5.5, 2.8, 9.0), (-0.5, 6.5, 2.8, 9.0)]:
            x, y = P(sg * u, sg * v, ox, oy)
            placed(lambda x, y, r_=r_, h_=h_: tank(x, y, r_, h_, mm, tank_col), x, y, 6.0, 6.0, 0, 10.0, 'tank')
        for (u, v, rot, n) in [(-7.5, -1.5, ANG, 4), (-7.5, -4.2, ANG, 3), (2.5, -1.0, ANG + 90, 3)]:
            x, y = P(sg * u, sg * v, ox, oy)
            placed(lambda x, y, rot=rot, n=n: coil_row(x - math.cos(math.radians(rot)) * n * 0.82, y - math.sin(math.radians(rot)) * n * 0.82, n, rot, mm), x, y, 1.65 * n + 0.4, 1.9, rot, 2.0, 'coils')
        for (u, v) in [(5.0, 4.0), (7.6, 4.0)]:
            x, y = P(sg * u, sg * v, ox, oy)
            placed(lambda x, y: beam_stack(x, y, ANG + 90, mm), x, y, 8.2, 2.0, ANG, 1.6, 'beams')
        # container screen towards the compound: one 2-high stack + one single
        for (u, v, two, cm) in [(9.5, -3.2, False, mm['c_red']), (9.5, 3.0, True, mm['c_blue'])]:
            x, y = P(sg * u, sg * v, ox, oy)
            r = placed(lambda x, y, cm=cm: container(x, y, 0, ANG, cm, mm), x, y, 2.5, 6.1, ANG, 5.4 if two else 2.7, 'cont')
            if r and two:
                container(r[0], r[1], r[2] + 2.59, ANG, mm['c_grey'], mm)
        x, y = P(sg * -10.0, sg * -6.0, ox, oy)
        placed(lambda x, y: guard_hut(x, y, ANG + (180 if mirror else 0), mm), x, y, 2.6, 2.6, ANG, 2.8, 'hut')
    yard(-49.5, 17.5, False, (0.78, 0.78, 0.74))
    yard(33.0, -31.5, True, (0.72, 0.6, 0.42))
    def spawn_set(ox, oy, pts, yaw, sg):
        out = []
        for (u, v) in pts:
            x, y = P(sg * u, sg * v, ox, oy)
            ok, gz = footprint_probe(x, y, 0.9, 0.9, 0, 2.2, 0.45, 0.3)
            if ok:
                out.append((round(x, 2), round(y, 2), round(gz, 2), yaw))
        return out
    pts = [(-9, 0), (-6, 0.5), (-3, 0), (0, 0.5), (3, 0), (-7.5, 3.0), (-1.5, 3.2), (4.5, 2.8), (-4.5, -3.5), (1.5, -3.8), (-10.5, 2.0), (5.5, -2.0)]
    sa_ = spawn_set(-49.5, 17.5, pts, ANG - 90, 1)[:8]
    sb_ = spawn_set(33.0, -31.5, pts, ANG + 90, -1)[:8]
    print('spawns', len(sa_), len(sb_))
    finalize_dress('fabrika', sa_, sb_)


# ======================================================================== HURDA (small scrapyard arena)
def wreck(x, y, z, rot, mm, seed=0):
    """flattened scrap car body (crusher output): rusty shell with dark window slots, crushed roof"""
    import random as _r
    rr = _r.Random(seed)
    paint = M(rr.choice(['car_paint_red', 'car_paint_white', 'car_paint_blue', 'car_paint_grey', 'car_paint_yellow']), (0.5, 0.5, 0.5), 0.6, 0.4)
    rust = M('rust_metal', (0.4, 0.25, 0.15), 0.8, 0.6)
    root = empty('wreck', (x, y, z)); root.rotation_euler = (0, 0, math.radians(rot))
    box('wr_body', (1.85, 4.3, 0.62), (0, 0, 0.31), (rr.uniform(-2, 2), rr.uniform(-2, 2), 0), m=paint, parent=root, bevel=0.06)
    box('wr_rust', (1.87, 4.32, 0.2), (0, 0, 0.1), m=rust, parent=root, bevel=0.03)
    box('wr_roof', (1.5, 2.0, 0.28), (rr.uniform(-0.1, 0.1), rr.uniform(-0.3, 0.2), 0.74), (rr.uniform(-6, 6), 0, 0), m=paint, parent=root, bevel=0.05)
    for sy in (-0.55, 0.55):
        box('wr_glass', (1.88, 0.75, 0.16), (0, sy, 0.48), m=mm['black'], parent=root)
    box('wr_light', (1.6, 0.04, 0.12), (0, 2.16, 0.4), m=mm['taillight'], parent=root)
    return root


def wreck_stack(x, y, rot, n, mm, seed=0):
    for i in range(n):
        wreck(x + (i % 2) * 0.12, y + (i % 2) * 0.18, i * 0.86, rot + (i % 2) * 6 - 3, mm, seed + i)
    col((x, y, n * 0.43), (2.0, 4.5, n * 0.86), rotz=rot)


def tire_stack(x, y, n, mm, r=0.38):
    for i in range(n):
        torus('tire', r, 0.13, (x + (i % 2) * 0.04, y, 0.13 + i * 0.26), m=mm['tire'], seg=20, mseg=8)
    col((x, y, n * 0.13), (1.0, 1.0, n * 0.26))


def scrap_heap(x, y, r, h, mm, seed=0):
    import random as _r
    rr = _r.Random(seed)
    rust = M('rust_metal', (0.4, 0.25, 0.15), 0.8, 0.6)
    lathe('heap', [(r, 0.0), (r * 0.75, h * 0.4), (r * 0.4, h * 0.82), (0.05, h)], (x, y, 0), m=M('rust_sheet', (0.4, 0.3, 0.2), 0.85, 0.5), seg=18)
    for k in range(int(r * 9)):
        a = rr.uniform(0, math.tau); d = rr.uniform(0.2, r * 0.9)
        zz = h * (1 - d / r) * rr.uniform(0.6, 1.0)
        if rr.random() < 0.5:
            box('scrap_sheet', (rr.uniform(0.4, 1.4), rr.uniform(0.3, 1.0), 0.02), (x + math.cos(a) * d, y + math.sin(a) * d, zz), (rr.uniform(-50, 50), rr.uniform(-50, 50), rr.uniform(0, 180)), m=rust)
        else:
            cyl('scrap_bar', rr.uniform(0.02, 0.06), rr.uniform(0.8, 2.2), (x + math.cos(a) * d, y + math.sin(a) * d, zz), (rr.uniform(-70, 70), rr.uniform(-70, 70), rr.uniform(0, 180)), m=rust, axis='Z', verts=6)
    col((x, y, h * 0.35), (r * 1.3, r * 1.3, h * 0.7))


def baler(x, y, rot, mm):
    """scrap baler / car press: low ribbed steel chamber with an open hopper, vertical lid rams, cabin"""
    root = empty('baler', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    y_ = M('crane_yellow', (0.95, 0.68, 0.05), 0.5, 0.3)
    dk = mm['metal']
    grime = M('rust_metal', (0.4, 0.25, 0.15), 0.8, 0.6)
    box('bl_base', (3.0, 6.4, 0.35), (0, 0, 0.175), m=dk, parent=root)
    for sx in (-1, 1):
        box('bl_side', (0.22, 5.2, 1.35), (sx * 1.35, -0.4, 1.0), m=y_, parent=root, bevel=0.03)
        box('bl_grime', (0.24, 5.22, 0.35), (sx * 1.35, -0.4, 0.5), m=grime, parent=root)
        for k in range(6):
            box('bl_rib', (0.12, 0.14, 1.35), (sx * 1.5, -2.8 + k * 0.95, 1.0), m=y_, parent=root)
        for ky in (-2.0, 1.2):
            cyl('bl_ram_v', 0.13, 1.6, (sx * 1.6, ky, 2.2), m=mm['chrome'], parent=root, axis='Z', verts=12)
            cyl('bl_ram_body', 0.19, 1.0, (sx * 1.6, ky, 1.2), m=dk, parent=root, axis='Z', verts=12)
    box('bl_floor', (2.5, 5.2, 0.2), (0, -0.4, 0.45), m=grime, parent=root)
    box('bl_lid', (2.9, 1.6, 0.18), (0, -2.4, 3.05), (0, 0, 0), m=y_, parent=root, bevel=0.02)
    box('bl_end', (2.9, 0.3, 1.9), (0, -3.05, 1.3), m=y_, parent=root, bevel=0.03)
    box('bl_motor', (2.4, 1.4, 1.5), (0, 2.6, 1.1), m=y_, parent=root, bevel=0.05)
    cyl('bl_ram', 0.32, 1.6, (0, 1.6, 1.1), m=mm['chrome'], parent=root, axis='Y', verts=16)
    box('bl_cab', (1.3, 1.3, 2.1), (2.2, 2.6, 1.05), m=y_, parent=root, bevel=0.04)
    box('bl_cab_glass', (0.04, 1.0, 0.8), (2.86, 2.6, 1.55), m=mm['carglass'], parent=root)
    box('bl_bale', (1.1, 1.1, 1.0), (0, -0.6, 1.05), m=M('car_paint_blue', (0.1, 0.2, 0.5), 0.5, 0.5), parent=root, bevel=0.08)
    col((x, y, 1.0), (3.2, 6.6, 2.0), rotz=rot)


def dress_hurda():
    mm = MP.begin()
    load_model_bvh('hurda')
    # props in the open ground lanes (north / south) and round the central deck — symmetric about x = -1.5
    CX = -1.5
    items = [
        (lambda x, y: wreck_stack(x, y, 90, 3, mm, 1), CX - 6.5, 11.0, 4.6, 2.1, 90, 2.7, 'wrecksN'),
        (lambda x, y: wreck_stack(x, y, 90, 3, mm, 5), CX + 6.5, -11.5, 4.6, 2.1, 90, 2.7, 'wrecksS'),
        (lambda x, y: wreck_stack(x, y, 90, 2, mm, 9), CX + 5.0, 11.2, 4.6, 2.1, 90, 1.8, 'wrecksN2'),
        (lambda x, y: wreck_stack(x, y, 90, 2, mm, 13), CX - 5.0, -11.7, 4.6, 2.1, 90, 1.8, 'wrecksS2'),
        (lambda x, y: scrap_heap(x, y, 2.2, 2.0, mm, 3), CX - 11.5, 8.0, 3.0, 3.0, 0, 2.2, 'heapNW'),
        (lambda x, y: wreck_stack(x, y, 0, 4, mm, 21), CX - 9.0, 8.3, 2.1, 4.6, 0, 3.5, 'wrecksNW4'),
        (lambda x, y: wreck_stack(x, y, 0, 4, mm, 25), CX + 9.0, -8.8, 2.1, 4.6, 0, 3.5, 'wrecksSE4'),
        (lambda x, y: scrap_heap(x, y, 2.2, 2.0, mm, 4), CX + 11.5, -8.5, 3.0, 3.0, 0, 2.2, 'heapSE'),
        (lambda x, y: baler(x, y, 0, mm), CX - 11.5, -8.0, 3.2, 7.0, 0, 2.6, 'balerSW'),
        (lambda x, y: baler(x, y, 180, mm), CX + 11.5, 7.5, 3.2, 7.0, 0, 2.6, 'balerNE'),
    ]
    for (fn, x, y, w, d, rot, h, tag) in items:
        placed(fn, x, y, w, d, rot, h, tag)
    for (x, y, n) in [(CX - 1.0, 12.4, 5), (CX + 0.2, 12.6, 4), (CX + 1.0, -12.9, 5), (CX - 0.2, -13.1, 4), (CX - 9.0, 12.0, 6), (CX + 9.0, -12.5, 6)]:
        placed(lambda x, y, n=n: tire_stack(x, y, n, mm), x, y, 1.0, 1.0, 0, n * 0.26, 'tires')
    # spawns at the two short ends (west walkway side, east tower side)
    def sset(cands, yaw):
        out = []
        for (x, y) in cands:
            ok, gz = footprint_probe(x, y, 0.9, 0.9, 0, 2.2, 0.45, 0.3, top=4.6)
            if ok:
                out.append((x, y, round(gz, 2), yaw))
        return out
    ca = [(-19.5, -10.0), (-19.5, -6.5), (-19.5, -3.0), (-19.5, 0.5), (-19.5, 4.0), (-19.5, 7.5), (-17.0, -11.5), (-17.0, 11.0), (-16.5, -1.5), (-16.5, 5.5)]
    cb = [(18.0, 10.5), (18.0, -9.5), (15.5, -11.5), (15.5, 11.0), (14.0, 8.0), (14.0, -7.0), (15.0, 4.0), (15.0, -3.5), (16.5, 1.0), (13.0, 0.5),
          (17.0, 6.5), (17.0, -6.0), (12.5, -11.0), (12.5, 11.2), (19.5, 6.0), (19.5, -6.5), (13.5, 3.0), (13.5, -2.5)]
    sa_ = sset(ca, -90)[:8]; sb_ = sset(cb, 90)[:8]
    print('spawns', len(sa_), len(sb_))
    finalize_dress('hurda', sa_, sb_)


# ======================================================================== ÇEKİRDEK (one open lane on the east terrace)
def dress_cekirdek():
    mm = MP.begin()
    load_model_bvh('cekirdek')
    d = json.load(open(os.path.join(OUTD, 'cekirdek.json')))
    sa_ = [(s['p'][0], -s['p'][2], s['p'][1] - 0.1, math.degrees(s.get('yaw', 0))) for s in d['spawns'] if s['team'] == 'a']
    sb_ = [(s['p'][0], -s['p'][2], s['p'][1] - 0.1, math.degrees(s.get('yaw', 0))) for s in d['spawns'] if s['team'] == 'b']
    def stack(x, y):
        # two-crate stack on the narrow east terrace: blocks the long lane, a body-width gap stays beside it
        z = 0.0
        crate(x, y, z, 1.25, mm)
        crate(x + 0.05, y - 0.05, z + 1.25, 1.1, mm, rot=12)
        MP.col((x, y, z + 1.17), (1.25, 1.25, 2.35))
    placed(stack, 42.6, -11.3, 1.3, 1.3, 0, 2.4, 'eastTerraceCrates', search=False, top=11.0)
    finalize_dress('cekirdek', sa_, sb_)


DRESS = dict(fabrika=dress_fabrika, hurda=dress_hurda, cekirdek=dress_cekirdek)
if __name__ == '__main__':
    for n in sys.argv[1:]:
        DRESS[n]()
