"""Procedural map builder -> assets/maps/<id>.glb + <id>.json (colliders, spawns, env)
Blender coords: X east, Y north, Z up.  Godot: X, Y(up)=Bz, Z=-By.
"""
import sys, os, math, json, random
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector, Matrix, Euler
from bkit import *
from bkit import _finish

OUTD = os.path.join(ROOT, 'assets', 'maps')
os.makedirs(OUTD, exist_ok=True)

COL = []      # colliders: dict(c=[x,y,z], s=[sx,sy,sz], r=[rx,ry,rz]) godot space
SPAWNS = []   # dict(p=[x,y,z], yaw=, team=)
TREES = []    # v4.11 in-map impostor trees: [x, y, z, height, row, yaw] in godot space
WRND = random.Random(77)
RND = random.Random(1)


def g(p):
    """blender -> godot position"""
    return [p[0], p[2], -p[1]]


def col(center, size, rotz=0.0, rotx=0.0, roty=0.0):
    COL.append(dict(c=g(center), s=[size[0], size[2], size[1]], r=[math.radians(rotx), math.radians(rotz), -math.radians(roty)]))


def spawn(x, y, z=0.0, yaw=0.0, team=None):
    # yaw in degrees, 0 = facing blender +Y (north) -> godot -Z
    SPAWNS.append(dict(p=g((x, y, z)), yaw=math.radians(yaw), team=team))


# impostor atlas rows (assets/tex/trees_imp.json): 0-1 olive, 2 broadleaf, 3 slender broadleaf, 4-6 fir
IMP_ROWS = dict(olive=(0, 1), broad=(2,), slender=(3,), fir=(4, 5, 6))


def imp_tree(x, y, h, kind='olive', z=0.0, row=None):
    r = row if row is not None else WRND.choice(IMP_ROWS[kind])
    TREES.append([round(x, 2), round(z, 2), round(-y, 2), round(h, 2), r, round(WRND.uniform(0, 6.283), 3)])


def M(name, color, rough=0.8, metal=0.0, **kw):
    return mat(name, color, metal, rough, **kw)


def mats():
    return dict(
        cobble=M('cobble', (0.55, 0.52, 0.48)), paver=M('paver', (0.62, 0.6, 0.57)), asphalt=M('asphalt', (0.22, 0.22, 0.23)),
        curb=M('curb', (0.6, 0.6, 0.58)), concrete=M('concrete', (0.55, 0.54, 0.52)),
        p_white=M('plaster_white', (0.9, 0.88, 0.84)), p_cream=M('plaster_cream', (0.9, 0.82, 0.66)), p_ochre=M('plaster_ochre', (0.82, 0.6, 0.35)),
        p_rose=M('plaster_rose', (0.85, 0.62, 0.58)), p_blue=M('plaster_blue', (0.55, 0.68, 0.78)), p_green=M('plaster_green', (0.62, 0.72, 0.58)),
        p_grey=M('plaster_grey', (0.6, 0.6, 0.6)), brick=M('brick', (0.6, 0.35, 0.25)),
        beam=M('woodbeam', (0.22, 0.14, 0.09)), planks=M('planks', (0.45, 0.32, 0.2)), roof=M('rooftiles', (0.65, 0.3, 0.18)),
        stone=M('stonewall', (0.62, 0.58, 0.5)), grass=M('grass', (0.3, 0.42, 0.2)), dirt=M('dirt', (0.4, 0.33, 0.25)),
        glass=M('glass_window', (0.15, 0.2, 0.25), 0.05, 0.6), pipe=M('drain_pipe', (0.42, 0.43, 0.45), 0.45, 0.6), solar=M('solar_panel', (0.08, 0.12, 0.22), 0.15, 0.4), antenna=M('antenna', (0.6, 0.6, 0.62), 0.4, 0.8), glass_lit=M('window_lit', (0.9, 0.75, 0.45), 0.4, emission=(1, 0.8, 0.5), emit_strength=1.5),
        frame=M('window_frame', (0.85, 0.85, 0.82), 0.6), frame_wood=M('frame_wood', (0.35, 0.2, 0.1), 0.6),
        metal=M('metal_dark', (0.12, 0.12, 0.13), 0.5, 0.8), steel=M('metal_steel', (0.55, 0.56, 0.58), 0.35, 1.0),
        rail=M('metal_rail', (0.15, 0.15, 0.16), 0.4, 0.8), shutter=M('shutter', (0.55, 0.56, 0.58), 0.5, 0.7),
        aw_red=M('awning_red', (0.7, 0.12, 0.1)), aw_green=M('awning_green', (0.1, 0.45, 0.2)), aw_blue=M('awning_blue', (0.12, 0.25, 0.6)),
        ac=M('ac_unit', (0.85, 0.85, 0.83), 0.5), dish=M('dish', (0.8, 0.8, 0.8), 0.4),
        flag_red=M('flag_red', (0.85, 0.05, 0.08), 0.8), flag_white=M('flag_white', (0.95, 0.95, 0.95), 0.8),
        lamp=M('lamp_glow', (1, 0.9, 0.7), 0.3, emission=(1, 0.85, 0.6), emit_strength=6),
        foliage=M('foliage', (0.18, 0.32, 0.1), 0.9), bark=M('bark', (0.25, 0.18, 0.12), 0.95),
        tire=M('tire', (0.03, 0.03, 0.03), 0.9), chrome=M('chrome', (0.8, 0.8, 0.8), 0.15, 1.0), carglass=M('car_glass', (0.05, 0.07, 0.08), 0.05, 0.5),
        taillight=M('taillight', (0.8, 0.05, 0.05), 0.3, emission=(1, 0, 0), emit_strength=0.5), headlight=M('headlight', (0.95, 0.95, 0.9), 0.1),
        dumpster=M('dumpster', (0.12, 0.35, 0.18), 0.6, 0.3), crate=M('planks_crate', (0.55, 0.4, 0.25)), pallet=M('pallet', (0.6, 0.48, 0.32)),
        sandbag=M('sandbag', (0.55, 0.48, 0.35)), water=M('water', (0.05, 0.15, 0.2), 0.05, 0.0),
        deck=M('deck', (0.5, 0.38, 0.25)), hull_red=M('hull_red', (0.5, 0.08, 0.06), 0.6), hull_dark=M('hull_dark', (0.08, 0.1, 0.12), 0.6),
        ship_white=M('ship_white', (0.88, 0.88, 0.86), 0.6), ship_green=M('ship_deck_green', (0.25, 0.4, 0.3), 0.7),
        ship_yellow=M('paint_yellow', (0.85, 0.65, 0.05), 0.6), ship_orange=M('paint_orange', (0.85, 0.35, 0.05), 0.6),
        c_red=M('container_red', (0.6, 0.12, 0.08), 0.6), c_blue=M('container_blue', (0.08, 0.25, 0.55), 0.6), c_orange=M('container_orange', (0.85, 0.42, 0.08), 0.6),
        c_green=M('container_green', (0.12, 0.38, 0.2), 0.6), c_grey=M('container_grey', (0.5, 0.52, 0.53), 0.6), c_yellow=M('container_yellow', (0.85, 0.7, 0.1), 0.6),
        c_white=M('container_white', (0.85, 0.86, 0.86), 0.6),
        dome=M('dome_lead', (0.45, 0.48, 0.5), 0.5, 0.6), marble=M('marble', (0.88, 0.86, 0.82), 0.3),
        rope=M('rope', (0.5, 0.42, 0.3), 0.9), bench=M('bench_wood', (0.5, 0.32, 0.18)),
        black=M('black_paint', (0.03, 0.03, 0.03), 0.6), cable=M('cable', (0.02, 0.02, 0.02), 0.6),
        fruit_r=M('fruit_red', (0.75, 0.08, 0.05), 0.5), fruit_o=M('fruit_orange', (0.95, 0.5, 0.05), 0.5), fruit_g=M('fruit_green', (0.4, 0.65, 0.1), 0.5),
        tea=M('tea_glass', (0.6, 0.15, 0.05), 0.1),
        p_yellow=M('plaster_yellow', (0.95, 0.8, 0.4)), p_terra=M('plaster_terracotta', (0.8, 0.45, 0.32)),
        p_mint=M('plaster_mint', (0.6, 0.85, 0.75)), p_lilac=M('plaster_lilac', (0.75, 0.68, 0.85)),
        leaves=M('leaves', (0.3, 0.55, 0.2)), flag_tr=M('flag_tr', (0.9, 0.05, 0.08)),
        pot=M('flower_pot', (0.7, 0.35, 0.2)), fl_red=M('flower_red', (0.9, 0.1, 0.12)), fl_pink=M('flower_pink', (0.95, 0.45, 0.7)),
        fl_white=M('flower_white', (0.95, 0.95, 0.9)), fl_purple=M('flower_purple', (0.6, 0.3, 0.85)), plant=M('plant_green', (0.2, 0.5, 0.15)),
        sh_green=M('shutter_green', (0.15, 0.45, 0.3)), sh_blue=M('shutter_blue', (0.15, 0.35, 0.65)), sh_brown=M('shutter_brown', (0.45, 0.28, 0.15)),
        **{f'laundry{i}': M(f'laundry_{i}', c) for i, c in enumerate([(0.9, 0.2, 0.2), (0.2, 0.5, 0.9), (0.95, 0.85, 0.3), (0.95, 0.95, 0.95), (0.3, 0.75, 0.4), (0.95, 0.5, 0.7), (0.95, 0.55, 0.15)])},
        **{f'aws_{c}': M(f'aw_stripe_{c}', (0.8, 0.3, 0.3)) for c in ['red', 'green', 'blue', 'orange']},
    )


def int_mat(k):
    return M('winint%d' % k, (0.5, 0.5, 0.5), 0.06)


def grime_mat(kind):
    return M('grime_' + kind, (0.2, 0.18, 0.15), 1.0)


def poster_mat(k):
    return M('poster%d' % k, (0.8, 0.8, 0.8), 0.7)


def sign_mat(key):
    return M('sign_' + key, (0.8, 0.8, 0.8), 0.5)


# ======================================================================== primitives with collision
def wall(name, x, y, z, sx, sy, sz, m, collide=True, bevel=0.0, rot=0.0, uv=1.0):
    o = box(name, (sx, sy, sz), (x, y, z + sz / 2), (0, 0, rot), m=m, bevel=bevel, uv=uv)
    if collide:
        col((x, y, z + sz / 2), (sx, sy, sz), rotz=rot)
    return o


def ground(name, x0, y0, x1, y1, z, m, thick=0.3, collide=True):
    return wall(name, (x0 + x1) / 2, (y0 + y1) / 2, z - thick, x1 - x0, y1 - y0, thick, m, collide)


def ramp(name, x, y, z0, z1, length, width, m, axis='Y', direction=1):
    """sloped slab rising from z0 to z1 over length along axis"""
    ang = math.degrees(math.atan2(z1 - z0, length))
    L = math.hypot(length, z1 - z0)
    t = 0.25
    zc = (z0 + z1) / 2 - t / 2
    if axis == 'Y':
        o = box(name, (width, L, t), (x, y, zc), (direction * ang, 0, 0), m=m)
        col((x, y, zc), (width, L, t), rotx=direction * ang)
    else:
        o = box(name, (L, width, t), (x, y, zc), (0, -direction * ang, 0), m=m)
        col((x, y, zc), (L, width, t), roty=-direction * ang)
    return o


def stairs(name, x, y, z0, z1, length, width, m, axis='Y', direction=1, collide_ramp=True):
    """visual steps + smooth invisible ramp collider"""
    n = max(2, int(abs(z1 - z0) / 0.18))
    dz = (z1 - z0) / n
    dl = length / n
    for i in range(n):
        off = (i + 0.5) * dl * direction - direction * length / 2
        h = z0 + dz * (i + 1)
        if axis == 'Y':
            box(f'{name}_s{i}', (width, dl, h - min(z0, z1) + 0.05), (x, y + off, min(z0, z1) + (h - min(z0, z1)) / 2 - 0.025), m=m, bevel=0.01)
        else:
            box(f'{name}_s{i}', (dl, width, h - min(z0, z1) + 0.05), (x + off, y, min(z0, z1) + (h - min(z0, z1)) / 2 - 0.025), m=m, bevel=0.01)
    if collide_ramp:
        ang = math.degrees(math.atan2(z1 - z0, length))
        L = math.hypot(length, z1 - z0)
        zc = (z0 + z1) / 2 - 0.12
        if axis == 'Y':
            col((x, y, zc), (width, L, 0.25), rotx=direction * ang)
        else:
            col((x, y, zc), (L, width, 0.25), roty=-direction * ang)


# ======================================================================== props
def car(x, y, rot, color, mm, name='car'):
    root = empty(name, (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    cp = M('car_paint_' + color[0], color[1], 0.25, 0.6)
    # side profile (y,z) length 4.3
    body = [(-2.15, 0.35), (2.15, 0.35), (2.2, 0.6), (2.15, 0.85), (1.1, 0.95), (-1.6, 0.95), (-2.15, 0.9), (-2.2, 0.6)]
    prof('body', body, 1.7, m=cp, parent=root, bevel=0.06, segs=3)
    cab = [(-1.35, 0.93), (0.85, 0.93), (0.3, 1.42), (-1.0, 1.42), (-1.45, 0.98)]
    prof('cabin', cab, 1.5, m=cp, parent=root, bevel=0.05, segs=3)
    prof('wind', [(-1.3, 0.97), (0.78, 0.97), (0.27, 1.39), (-0.98, 1.39), (-1.38, 1.0)], 1.52, m=mm['carglass'], parent=root, bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1.35, 1.3):
            cyl('wheel', 0.33, 0.24, (sx * 0.78, sy, 0.33), m=mm['tire'], parent=root, axis='X', verts=20, bevel=0.03)
            cyl('rim', 0.2, 0.25, (sx * 0.78, sy, 0.33), m=mm['chrome'], parent=root, axis='X', verts=16)
        box('mirror', (0.15, 0.08, 0.1), (sx * 0.9, 0.55, 1.0), m=cp, parent=root, bevel=0.02)
        box('hl', (0.35, 0.05, 0.12), (sx * 0.55, 2.19, 0.7), m=mm['headlight'], parent=root, bevel=0.02)
        box('tl', (0.35, 0.05, 0.12), (sx * 0.55, -2.19, 0.75), m=mm['taillight'], parent=root, bevel=0.02)
    box('bumper_f', (1.75, 0.12, 0.18), (0, 2.18, 0.42), m=mm['black'], parent=root, bevel=0.04)
    box('bumper_r', (1.75, 0.12, 0.18), (0, -2.18, 0.42), m=mm['black'], parent=root, bevel=0.04)
    box('grille', (0.9, 0.04, 0.16), (0, 2.21, 0.62), m=mm['chrome'], parent=root, bevel=0.01)
    box('plate', (0.52, 0.02, 0.11), (0, -2.22, 0.5), m=mm['flag_white'], parent=root)
    # collider (axis aligned if rot multiple of 90)
    col((x, y, 0.75), (1.8, 4.4, 1.5), rotz=rot)


def dumpster(x, y, rot, mm):
    root = empty('dumpster', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('d_body', (1.8, 1.1, 1.1), (0, 0, 0.75), m=mm['dumpster'], parent=root, bevel=0.03)
    box('d_lid', (1.85, 1.18, 0.08), (0, -0.03, 1.33), (-6, 0, 0), m=mm['dumpster'], parent=root, bevel=0.02)
    for sx in (-0.75, 0.75):
        for sy in (-0.4, 0.4):
            cyl('d_wh', 0.1, 0.06, (sx, sy, 0.1), m=mm['tire'], parent=root, axis='X', verts=12)
    col((x, y, 0.7), (1.85, 1.2, 1.4), rotz=rot)


def crate(x, y, z, s, mm, rot=0, collide=True):
    root = empty('crate', (x, y, z)); root.rotation_euler = (0, 0, math.radians(rot))
    box('c_body', (s, s, s), (0, 0, s / 2), m=mm['crate'], parent=root, bevel=0.015)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('c_edge', (0.09, 0.09, s + 0.01), (sx * (s / 2 - 0.04), sy * (s / 2 - 0.04), s / 2), m=mm['pallet'], parent=root, bevel=0.01)
    for sz in (0.045, s - 0.045):
        box('c_band', (s + 0.02, s + 0.02, 0.09), (0, 0, sz), m=mm['pallet'], parent=root, bevel=0.01)
    if collide:
        col((x, y, z + s / 2), (s, s, s), rotz=rot)


def barrel(x, y, mm, color='blue'):
    cm = M('barrel_' + color, {'blue': (0.1, 0.25, 0.6), 'red': (0.6, 0.1, 0.08), 'yellow': (0.8, 0.6, 0.05)}[color], 0.5, 0.4)
    cyl('barrel', 0.3, 0.9, (x, y, 0.45), m=cm, axis='Z', verts=20, bevel=0.01)
    for z in (0.2, 0.7):
        torus('b_ring', 0.302, 0.015, (x, y, z), m=cm, seg=20, mseg=6)
    col((x, y, 0.45), (0.6, 0.6, 0.9))


def sandbags(x, y, length, rows, mm, rot=0):
    root = empty('sb', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    n = int(length / 0.55)
    for r in range(rows):
        for i in range(n - (r % 2)):
            off = (r % 2) * 0.275
            box('bag', (0.58, 0.36, 0.17), (-length / 2 + 0.28 + i * 0.55 + off, 0, 0.09 + r * 0.16), (0, 0, RND.uniform(-4, 4)), m=mm['sandbag'], parent=root, bevel=0.07, segs=3)
    col((x, y, rows * 0.16 / 2 + 0.02), (length, 0.45, rows * 0.16 + 0.04), rotz=rot)


def tree(x, y, mm, h=6.0, r=2.4, seed=0, kind=None):
    """v4.11: street / garden tree = photoscan impostor (map json "trees"; shadows + trunk collider in game).
    The old procedural leaf-card tree is gone (it read as green balls)."""
    rr = random.Random(seed)
    k = kind or ('broad' if r >= 3.2 else ('slender' if rr.random() < 0.6 else 'broad'))
    imp_tree(x, y, h * (1.15 if k == 'broad' else 1.0), k)


def flower_box(parent, x, y, z, w, mm, rr):
    box('fbox', (w, 0.22, 0.18), (x, y, z), m=mm['pot'], parent=parent, bevel=0.02)
    cols = ['fl_red', 'fl_pink', 'fl_white', 'fl_purple', 'fl_red']
    for k in range(int(w / 0.12)):
        sphere('leafb', 0.07, (x - w / 2 + 0.07 + k * 0.12, y, z + 0.13), m=mm['plant'], parent=parent, seg=6, rings=4)
        if rr.random() < 0.7:
            sphere('flw', 0.045, (x - w / 2 + 0.07 + k * 0.12 + rr.uniform(-0.03, 0.03), y - 0.05, z + 0.2 + rr.uniform(0, 0.06)), m=mm[rr.choice(cols)], parent=parent, seg=6, rings=4)


def flower_pot(parent, x, y, z, mm, rr):
    lathe('pot', [(0, 0), (0.1, 0), (0.13, 0.22), (0.14, 0.24), (0, 0.24)], (x, y, z), m=mm['pot'], parent=parent, seg=10)
    for k in range(4):
        sphere('plnt', 0.09, (x + rr.uniform(-0.06, 0.06), y + rr.uniform(-0.06, 0.06), z + 0.3 + rr.uniform(0, 0.1)), m=mm['plant'], parent=parent, seg=6, rings=4)
    for k in range(3):
        sphere('flw', 0.05, (x + rr.uniform(-0.1, 0.1), y + rr.uniform(-0.1, 0.1), z + 0.4 + rr.uniform(0, 0.1)), m=mm[rr.choice(['fl_red', 'fl_pink', 'fl_white'])], parent=parent, seg=6, rings=4)


def laundry_line(parent, a, b, mm, rr, sag=0.15):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = box('lline', (d.length, 0.01, 0.01), (a + b) / 2, m=mm['cable'], parent=parent)
    o.rotation_euler = (0, 0, math.atan2(d.y, d.x))
    t = 0.05
    while t < 0.95:
        p = a.lerp(b, t)
        p.z -= math.sin(t * math.pi) * sag
        wdt = rr.uniform(0.3, 0.6); hgt = rr.uniform(0.35, 0.75)
        c = box('cloth', (wdt, 0.015, hgt), (p.x, p.y, p.z - hgt / 2), (rr.uniform(-4, 4), 0, math.degrees(math.atan2(d.y, d.x))), m=mm[f'laundry{rr.randrange(7)}'], parent=parent)
        t += (wdt + rr.uniform(0.05, 0.25)) / max(d.length, 0.1)


def street_lamp(x, y, rot, mm, ottoman=False):
    root = empty('lamp', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    cyl('pole', 0.07, 4.2, (0, 0, 2.1), m=mm['metal'], parent=root, axis='Z', verts=12, r2=0.05)
    cyl('base', 0.14, 0.4, (0, 0, 0.2), m=mm['metal'], parent=root, axis='Z', verts=12)
    if ottoman:
        box('arm', (0.06, 0.8, 0.06), (0, 0.4, 4.0), m=mm['metal'], parent=root)
        lathe('lantern', [(0.0, -0.35), (0.12, -0.3), (0.2, -0.05), (0.18, 0.15), (0.05, 0.3), (0.0, 0.35)], (0, 0.8, 3.6), m=mm['lamp'], parent=root, seg=8)
        lathe('lcap', [(0.0, 0.3), (0.24, 0.18), (0.24, 0.13), (0.0, 0.16)], (0, 0.8, 3.65), m=mm['metal'], parent=root, seg=8)
    else:
        box('arm', (0.07, 1.4, 0.07), (0, 0.7, 4.15), (8, 0, 0), m=mm['metal'], parent=root)
        box('head', (0.3, 0.6, 0.12), (0, 1.35, 4.2), m=mm['metal'], parent=root, bevel=0.03)
        box('bulb', (0.22, 0.5, 0.03), (0, 1.35, 4.13), m=mm['lamp'], parent=root)
    col((x, y, 2.1), (0.2, 0.2, 4.2))


def bench(x, y, rot, mm):
    root = empty('bench', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for i in range(3):
        box('slat', (1.8, 0.12, 0.04), (0, -0.15 + i * 0.15, 0.45), m=mm['bench'], parent=root, bevel=0.01)
    for i in range(2):
        box('back', (1.8, 0.04, 0.12), (0, 0.22, 0.6 + i * 0.16), m=mm['bench'], parent=root, bevel=0.01)
    for sx in (-0.8, 0.8):
        box('leg', (0.05, 0.5, 0.45), (sx, 0, 0.22), m=mm['metal'], parent=root)
    col((x, y, 0.4), (1.8, 0.5, 0.8), rotz=rot)


def ac_unit(x, y, z, rot, mm, parent=None):
    root = empty('ac', (x, y, z), parent); root.rotation_euler = (0, 0, math.radians(rot))
    box('ac_b', (0.8, 0.3, 0.55), (0, 0, 0), m=mm['ac'], parent=root, bevel=0.02)
    cyl('ac_fan', 0.2, 0.02, (0.12, -0.155, 0), m=mm['metal'], parent=root, verts=16)


def bunting(p0, p1, mm, sag=0.6, n=None):
    """string of triangular flags between two points"""
    L = (Vector(p1) - Vector(p0)).length
    n = n or int(L / 0.6)
    pts = []
    for i in range(n + 1):
        t = i / n
        p = Vector(p0).lerp(Vector(p1), t)
        p.z -= math.sin(t * math.pi) * sag
        pts.append(p)
    # cable as thin boxes
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        mid = (a + b) / 2; d = b - a
        o = box('cable', (0.015, d.length, 0.015), mid, m=mm['cable'])
        o.rotation_euler = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_euler()
        if i % 1 == 0:
            fl = mm['flag_red'] if i % 2 == 0 else mm['flag_white']
            bm_ = bmesh.new()
            v1 = bm_.verts.new((-0.2, 0, 0)); v2 = bm_.verts.new((0.2, 0, 0)); v3 = bm_.verts.new((0, 0, -0.45))
            bm_.faces.new((v1, v2, v3))
            me = bpy.data.meshes.new('flag'); bm_.to_mesh(me); bm_.free()
            f = bpy.data.objects.new('flag', me); me.materials.append(fl)
            bpy.context.scene.collection.objects.link(f)
            f.location = mid
            f.rotation_euler = (0, 0, math.atan2(d.y, d.x))
            f['twosided'] = True


def power_cable(p0, p1, mm, sag=0.8):
    n = 10
    pts = []
    for i in range(n + 1):
        t = i / n
        p = Vector(p0).lerp(Vector(p1), t); p.z -= math.sin(t * math.pi) * sag; pts.append(p)
    for i in range(n):
        a, b = pts[i], pts[i + 1]; d = b - a
        o = box('pcable', (0.02, d.length, 0.02), (a + b) / 2, m=mm['cable'])
        o.rotation_euler = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_euler()


def hip_roof(name, cx, cy, w, d, z, h, m, over=0.6, parent=None):
    w2, d2 = w / 2 + over, d / 2 + over
    bm_ = bmesh.new()
    c = [bm_.verts.new(v) for v in [(-w2, -d2, 0), (w2, -d2, 0), (w2, d2, 0), (-w2, d2, 0)]]
    if w >= d:
        r = [bm_.verts.new((-w2 + d2, 0, h)), bm_.verts.new((w2 - d2, 0, h))]
        bm_.faces.new((c[0], c[1], r[1], r[0])); bm_.faces.new((c[2], c[3], r[0], r[1]))
        bm_.faces.new((c[1], c[2], r[1])); bm_.faces.new((c[3], c[0], r[0]))
    else:
        r = [bm_.verts.new((0, -d2 + w2, h)), bm_.verts.new((0, d2 - w2, h))]
        bm_.faces.new((c[1], c[2], r[1], r[0])); bm_.faces.new((c[3], c[0], r[0], r[1]))
        bm_.faces.new((c[0], c[1], r[0])); bm_.faces.new((c[2], c[3], r[1]))
    bot = bm_.faces.new(list(reversed(c)))
    bmesh.ops.solidify(bm_, geom=bm_.faces[:], thickness=0.12)
    bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces)
    o = _finish(bm_, name, m, (cx, cy, z), (0, 0, 0), parent, 0, 2, 0.5, smooth=False)
    o['roofuv'] = True
    return o


def window(parent, x, z, w, h, mm, depth=0.0, frame='frame', shutters=None, lit=False, sill=True, kafes=False):
    """window on local facade plane y=depth facing -Y"""
    fm = mm[frame]
    k = WRND.choice([0, 1, 3, 4, 5, 7]) if not lit else WRND.choice([2, 6])
    gl = box('w_glass', (w, 0.02, h), (x, depth - 0.0, z), m=int_mat(k), parent=parent)
    gl['normuv'] = True
    t = 0.07
    if frame == 'frame':
        # plaster trim molding around the opening (casts real shadow)
        tw = 0.13
        box('w_trim_t', (w + 2 * t + 2 * tw, 0.06, tw), (x, depth - 0.03, z + h / 2 + t + tw / 2), m=mm['curb'], parent=parent, bevel=0.01)
        box('w_trim_l', (tw, 0.06, h + 2 * t), (x - w / 2 - t - tw / 2, depth - 0.03, z), m=mm['curb'], parent=parent)
        box('w_trim_r', (tw, 0.06, h + 2 * t), (x + w / 2 + t + tw / 2, depth - 0.03, z), m=mm['curb'], parent=parent)
        box('w_key', (0.22, 0.08, 0.2), (x, depth - 0.045, z + h / 2 + t + tw / 2), m=mm['curb'], parent=parent, bevel=0.015)
    box('w_ft', (w + t * 2, 0.1, t), (x, depth - 0.04, z + h / 2 + t / 2), m=fm, parent=parent)
    box('w_fb', (w + t * 2, 0.1, t), (x, depth - 0.04, z - h / 2 - t / 2), m=fm, parent=parent)
    box('w_fl', (t, 0.1, h), (x - w / 2 - t / 2, depth - 0.04, z), m=fm, parent=parent)
    box('w_fr', (t, 0.1, h), (x + w / 2 + t / 2, depth - 0.04, z), m=fm, parent=parent)
    box('w_mid', (0.04, 0.06, h), (x, depth - 0.03, z), m=fm, parent=parent)
    box('w_midh', (w, 0.06, 0.04), (x, depth - 0.03, z + h * 0.2), m=fm, parent=parent)
    if sill:
        box('w_sill', (w + 0.3, 0.22, 0.06), (x, depth - 0.1, z - h / 2 - 0.1), m=mm['curb'] if frame == 'frame' else fm, parent=parent, bevel=0.01)
    if kafes:
        for i in range(5):
            box('kafes', (w, 0.03, 0.02), (x, depth - 0.07, z - h / 2 + h * (0.55 + i * 0.09)), m=fm, parent=parent)
    if shutters:
        for s in (-1, 1):
            box('shutter', (w / 2, 0.04, h + 0.05), (x + s * (w * 0.75 + t), depth - 0.06, z), m=shutters, parent=parent, bevel=0.01)


def balcony(parent, x, z, w, mm, depth=1.0):
    box('b_slab', (w, depth, 0.15), (x, -depth / 2, z), m=mm['concrete'], parent=parent, bevel=0.02)
    box('b_top', (w, 0.05, 0.05), (x, -depth + 0.03, z + 1.0), m=mm['rail'], parent=parent)
    for s in (-1, 1):
        box('b_tops', (0.05, depth, 0.05), (x + s * (w / 2 - 0.03), -depth / 2, z + 1.0), m=mm['rail'], parent=parent)
    n = int(w / 0.14)
    for i in range(n):
        box('b_bar', (0.02, 0.02, 0.92), (x - w / 2 + 0.07 + i * 0.14, -depth + 0.03, z + 0.53), m=mm['rail'], parent=parent)
    for i in range(int(depth / 0.14)):
        for s in (-1, 1):
            box('b_bars', (0.02, 0.02, 0.92), (x + s * (w / 2 - 0.03), -0.07 - i * 0.14, z + 0.53), m=mm['rail'], parent=parent)


def apartment(name, x, y, rot, w, d, floors, mm, wall_m, shop=None, seed=0, roof='flat', side_windows=False, collide=True):
    """modern Istanbul apartment, front facade faces local -Y; rot in degrees around Z"""
    rr = random.Random(seed)
    root = empty(name, (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    fh = 3.1
    gh = 3.6 if shop else fh
    H = gh + (floors - 1) * fh
    box('body', (w, d, H), (0, d / 2, H / 2), m=wall_m, parent=root, uv=0.5)
    if collide:
        # collider in world: rotate center
        c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2, H / 2))
        col((x + c.x, y + c.y, H / 2), (w, d, H), rotz=rot)
    # floor bands
    for f in range(1, floors):
        box('band', (w + 0.1, 0.12, 0.18), (0, -0.04, gh + (f - 1) * fh - 0.05), m=mm['curb'], parent=root)
    # cornice/parapet
    box('parapet', (w + 0.2, 0.3, 0.6), (0, 0.1, H + 0.3), m=wall_m, parent=root)
    box('cornice', (w + 0.3, 0.4, 0.12), (0, 0.05, H), m=mm['curb'], parent=root)
    if roof == 'tiles':
        hip_roof('roof', 0, d / 2, w, d, H + 0.05, 2.2, mm['roof'], 0.5, root)
    else:
        box('roofslab', (w - 0.4, d - 0.4, 0.3), (0, d / 2, H + 0.15), m=mm['concrete'], parent=root)
        if rr.random() < 0.7:
            cyl('tank', 0.5, 1.2, (rr.uniform(-w / 3, w / 3), d * 0.6, H + 0.6), m=mm['dish'], parent=root, axis='Z', verts=16)
        if rr.random() < 0.6:
            sphere('dish', 0.4, (rr.uniform(-w / 3, w / 3), d * 0.3, H + 0.9), m=mm['dish'], parent=root, scale=(1, 0.3, 1))
    # --- realism details --------------------------------------------------
    # stone plinth, corner quoins, drain pipes, wall grime, roof clutter
    box('plinth', (w + 0.08, 0.1, 0.85), (0, -0.03, 0.425), m=mm['stone'], parent=root, uv=0.6)
    qcol = mm['curb']
    for sx in (-1, 1):
        box('quoin', (0.34, 0.08, H - 0.9), (sx * (w / 2 - 0.15), -0.03, 0.9 + (H - 0.9) / 2), m=qcol, parent=root)
        for k in range(int((H - 1.0) / 0.55)):
            if k % 2 == 0:
                box('quoin_b', (0.5, 0.1, 0.24), (sx * (w / 2 - 0.23), -0.045, 1.1 + k * 0.55), m=qcol, parent=root, bevel=0.01)
    px = (w / 2 - 0.45) * (1 if rr.random() < 0.5 else -1)
    cyl('pipe', 0.055, H + 0.2, (px, -0.12, H / 2 + 0.1), m=mm['pipe'], parent=root, axis='Z', verts=10)
    cyl('pipe_elb', 0.055, 0.35, (px, -0.2, 0.18), (60, 0, 0), m=mm['pipe'], parent=root, axis='Z', verts=10)
    for k in range(int(H / 2.2)):
        box('pipe_clip', (0.16, 0.1, 0.04), (px, -0.07, 1.0 + k * 2.2), m=mm['pipe'], parent=root)
    g = box('grime', (w - 0.1, 0.01, 2.2), (0, -0.085, 1.15), m=grime_mat('bottom'), parent=root)
    g['normuv'] = True
    # roof clutter: solar water heaters (very Turkish), antennas, chimneys
    if roof != 'tiles':
        for k in range(rr.randint(1, 3)):
            sx = rr.uniform(-w / 2 + 1.2, w / 2 - 1.2)
            sy = rr.uniform(1.5, d - 2.0)
            sh = empty('solar', (sx, sy, H + 0.3), root)
            sh.rotation_euler = (0, 0, math.radians(rr.choice([0, 180, 15, -15])))
            box('sol_panel', (1.0, 1.8, 0.06), (0, 0, 0.75), (-40, 0, 0), m=mm['solar'], parent=sh, bevel=0.01)
            cyl('sol_tank', 0.24, 1.4, (0, 0.75, 1.32), m=mm['ac'], parent=sh, axis='X', verts=16)
            for lx in (-0.45, 0.45):
                box('sol_leg', (0.04, 0.04, 1.2), (lx, 0.55, 0.6), m=mm['antenna'], parent=sh)
                box('sol_leg2', (0.04, 1.4, 0.04), (lx, 0.0, 0.12), (-30, 0, 0), m=mm['antenna'], parent=sh)
        for k in range(rr.randint(1, 3)):
            ax = rr.uniform(-w / 2 + 0.6, w / 2 - 0.6); ay = rr.uniform(0.8, d - 0.8)
            ah = rr.uniform(1.6, 2.8)
            cyl('ant', 0.02, ah, (ax, ay, H + 0.3 + ah / 2), m=mm['antenna'], parent=root, axis='Z', verts=6)
            for kk in range(rr.randint(2, 4)):
                box('ant_x', (rr.uniform(0.5, 1.0), 0.02, 0.02), (ax, ay, H + 0.6 + ah * 0.6 + kk * 0.18), m=mm['antenna'], parent=root)
        for k in range(rr.randint(1, 2)):
            box('chimney', (0.55, 0.55, 1.2), (rr.uniform(-w / 3, w / 3), rr.uniform(1, d - 1), H + 0.9), m=wall_m, parent=root)
    # --- windows per floor
    nwin = max(1, int(w / 2.6))
    sp = w / nwin
    for f in range(1, floors):
        zc = gh + (f - 1) * fh + 1.5
        has_bal = rr.random() < 0.45
        if has_bal:
            balcony(root, 0, gh + (f - 1) * fh + 0.08, w * 0.62, mm, 1.0)
        shm = mm[rr.choice(['sh_green', 'sh_blue', 'sh_brown'])] if rr.random() < 0.5 else None
        for i in range(nwin):
            wx = -w / 2 + sp * (i + 0.5)
            window(root, wx, zc, 1.1, 1.45, mm, lit=rr.random() < 0.08, shutters=shm if rr.random() < 0.8 else None)
            if rr.random() < 0.45:
                gs = box('streak', (1.3, 0.01, 1.6), (wx, -0.082, zc - 0.85 - 0.8), m=grime_mat('streak'), parent=root)
                gs['normuv'] = True
            if rr.random() < 0.2:
                ac_unit(wx + 0.9, -0.2, zc - 0.6, 0, mm, root)
            if not has_bal and rr.random() < 0.35:
                flower_box(root, wx, -0.18, zc - 0.85, 1.1, mm, rr)
        if has_bal and rr.random() < 0.6:
            for k in range(rr.randint(3, 6)):
                flower_pot(root, -w * 0.28 + k * 0.45, -0.85, gh + (f - 1) * fh + 0.16, mm, rr)
        if has_bal and rr.random() < 0.5:
            laundry_line(root, (-w * 0.3, -0.95, gh + (f - 1) * fh + 1.85), (w * 0.3, -0.95, gh + (f - 1) * fh + 1.85), mm, rr)
    if rr.random() < 0.25 and floors >= 4:
        fl = empty('flag', (rr.uniform(-w / 4, w / 4), -0.15, gh + fh * 1.6), root)
        box('flag_tr', (2.4, 0.03, 1.6), (0, 0, 0), m=mm['flag_tr'], parent=fl)
        cyl('flagpole', 0.025, 1.4, (0, -0.6, 0.85), (60, 0, 0), m=mm['chrome'], parent=fl, axis='Z', verts=8)
    # ground floor
    if shop:
        key, aw = shop
        sw = w * 0.8
        box('shopglass', (sw - 1.4, 0.04, 2.3), (-0.7, -0.01, 1.45), m=mm['glass'], parent=root)
        box('door', (1.0, 0.05, 2.3), (sw / 2 - 0.6, -0.01, 1.15), m=mm['glass'], parent=root)
        box('shopframe', (sw + 0.15, 0.12, 0.12), (0, -0.05, 2.65), m=mm['metal'], parent=root)
        for xx in (-sw / 2, sw / 2 - 1.1, sw / 2):
            box('shoppost', (0.1, 0.12, 2.6), (xx, -0.05, 1.3), m=mm['metal'], parent=root)
        box('shopbase', (sw, 0.1, 0.3), (0, -0.05, 0.15), m=mm['stone'], parent=root)
        box('sign', (sw * 0.95, 0.12, 0.75), (0, -0.08, 3.1), m=sign_mat(key), parent=root, uv=1.0)
        if aw:
            box('awning', (sw, 1.4, 0.05), (0, -0.7, 2.75), (-18, 0, 0), m=mm['aws_' + aw.split('_')[1].replace('blue', 'blue')] if ('aws_' + aw.split('_')[1]) in mm else mm[aw], parent=root)
            box('awning_v', (sw, 0.02, 0.25), (0, -1.36, 2.45), m=mm['aws_' + aw.split('_')[1]] if ('aws_' + aw.split('_')[1]) in mm else mm[aw], parent=root)
        if rr.random() < 0.5:
            box('shutterbox', (sw - 1.2, 0.25, 0.3), (-0.6, -0.12, 2.55), m=mm['shutter'], parent=root)
        if rr.random() < 0.6 and w - sw > 1.0:
            pz = box('poster', (0.6, 0.02, 0.84), ((sw / 2 + w / 2) / 2 * (1 if rr.random() < 0.5 else -1), -0.07, 1.6), m=poster_mat(rr.randrange(6)), parent=root)
            pz['normuv'] = True
    else:
        box('entry', (1.3, 0.05, 2.3), (0, -0.01, 1.15), m=mm['frame_wood'], parent=root)
        box('entry_frame', (1.6, 0.1, 2.5), (0, -0.02, 1.25), m=mm['stone'], parent=root)
        box('entry_step', (1.9, 0.6, 0.15), (0, -0.3, 0.075), m=mm['stone'], parent=root)
        box('door_no', (0.25, 0.03, 0.18), (0.95, -0.06, 2.1), m=M('door_no_blue', (0.1, 0.25, 0.6), 0.4), parent=root)
        box('entry_can', (1.8, 1.0, 0.1), (0, -0.5, 2.5), m=mm['concrete'], parent=root)
        for i in range(nwin):
            wx = -w / 2 + sp * (i + 0.5)
            if abs(wx) > 1.2:
                window(root, wx, 1.6, 1.0, 1.2, mm, sill=True)
    if side_windows:
        for side in (-1, 1):
            for f in range(1, floors):
                for k in range(max(1, int(d / 3.5))):
                    sub = empty('sidew', (side * w / 2, 1.5 + k * 3.5, 0), root)
                    sub.rotation_euler = (0, 0, math.radians(-90 * side))
                    window(sub, 0, gh + (f - 1) * fh + 1.5, 1.0, 1.4, mm, depth=-0.0)
    return root


def konak(name, x, y, rot, w, d, mm, seed=0, floors=2, collide=True, cumba=True, color='p_white'):
    """Safranbolu Ottoman house: stone ground floor, overhanging timber-framed plaster upper floors, hipped tile roof"""
    rr = random.Random(seed)
    root = empty(name, (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    gh, fh, ov = 3.0, 2.9, 0.7
    box('ground', (w, d, gh), (0, d / 2, gh / 2), m=mm['stone'], parent=root, uv=0.5)
    if collide:
        c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2, gh / 2))
        col((x + c.x, y + c.y, gh / 2), (w, d, gh), rotz=rot)
        c2 = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2 - ov / 2, gh + floors * fh / 2))
        col((x + c2.x, y + c2.y, gh + floors * fh / 2), (w + ov * 2, d + ov, floors * fh), rotz=rot)
    # door (arched-ish wooden)
    box('door', (1.3, 0.08, 2.2), (rr.uniform(-w / 4, w / 4), -0.02, 1.1), m=mm['frame_wood'], parent=root, bevel=0.02)
    for i in range(2):
        wx = (-w / 3 if i == 0 else w / 3)
        window(root, wx, 1.7, 0.7, 0.9, mm, frame='frame_wood', kafes=False, sill=True)
        for k in range(4):
            box('grate', (0.025, 0.04, 0.9), (wx - 0.3 + k * 0.2, -0.08, 1.7), m=mm['metal'], parent=root)
    W = w + ov * 2
    for f in range(floors):
        z0 = gh + f * fh
        # upper floor box overhanging front and sides
        box('upper', (W, d + ov, fh), (0, d / 2 - ov / 2, z0 + fh / 2), m=mm[color], parent=root, uv=0.5)
        # timber frame on front facade
        fy = -ov - 0.02
        box('beam_b', (W + 0.05, 0.1, 0.18), (0, fy, z0 + 0.09), m=mm['beam'], parent=root)
        box('beam_t', (W + 0.05, 0.1, 0.16), (0, fy, z0 + fh - 0.08), m=mm['beam'], parent=root)
        nwin = max(2, int(W / 1.25))
        sp = W / nwin
        for i in range(nwin + 1):
            box('post', (0.13, 0.1, fh), (-W / 2 + i * sp, fy, z0 + fh / 2), m=mm['beam'], parent=root)
        for i in range(nwin):
            wx = -W / 2 + sp * (i + 0.5)
            window(root, wx, z0 + fh * 0.55, sp * 0.62, 1.25, mm, depth=fy + 0.03, frame='frame_wood', sill=False, kafes=(f == 0 and rr.random() < 0.35), lit=rr.random() < 0.06)
            if rr.random() < 0.4:
                flower_box(root, wx, fy - 0.12, z0 + fh * 0.55 - 0.72, sp * 0.62, mm, rr)
        # diagonal braces on sides
        for s in (-1, 1):
            o = box('brace', (0.1, 0.1, fh * 1.1), (s * (W / 2 + 0.02), d / 2 - ov / 2, z0 + fh / 2), (0, 0, 0), m=mm['beam'], parent=root)
            o.rotation_euler = (math.radians(35 * s), 0, 0)
            box('corner', (0.12, d + ov, 0.14), (s * (W / 2 + 0.03), d / 2 - ov / 2, z0 + 0.07), m=mm['beam'], parent=root)
        # brackets under first overhang
        if f == 0:
            for i in range(nwin + 1):
                o = box('bracket', (0.1, 0.95, 0.1), (-W / 2 + i * sp, -ov / 2 + 0.05, gh - 0.3), (-35, 0, 0), m=mm['beam'], parent=root)
    if cumba and W > 6:
        z0 = gh + 0.2
        cb = empty('cumba', (0, -ov, 0), root)
        box('cumba_b', (2.6, 0.7, fh - 0.3), (0, -0.35, z0 + (fh - 0.3) / 2), m=mm[color], parent=cb)
        for i in range(3):
            window(cb, -0.85 + i * 0.85, z0 + 1.5, 0.6, 1.3, mm, depth=-0.72, frame='frame_wood', sill=False)
        box('cumba_roof', (2.8, 0.85, 0.08), (0, -0.4, z0 + fh - 0.25), m=mm['beam'], parent=cb)
        o = box('cumba_br', (2.4, 0.8, 0.1), (0, -0.33, z0 - 0.2), (-25, 0, 0), m=mm['beam'], parent=cb)
    H = gh + floors * fh
    box('eave', (W + 1.5, d + ov + 1.5, 0.12), (0, d / 2 - ov / 2, H + 0.06), m=mm['beam'], parent=root)
    hip_roof('roof', 0, d / 2 - ov / 2, W, d + ov, H + 0.1, 2.6, mm['roof'], 0.75, root)
    if rr.random() < 0.6:
        box('chimney', (0.5, 0.5, 1.6), (W / 4, d / 2, H + 1.8), m=mm['stone'], parent=root)
    return root


def mosque(x, y, s, mm, minarets=2):
    root = empty('mosque', (x, y, 0))
    box('m_body', (14 * s, 14 * s, 9 * s), (0, 0, 4.5 * s), m=mm['stone'], parent=root, uv=0.3)
    sphere('m_dome', 7 * s, (0, 0, 9 * s), m=mm['dome'], parent=root, seg=32, rings=16, scale=(1, 1, 0.8))
    cyl('m_drum', 6.5 * s, 2 * s, (0, 0, 9.5 * s), m=mm['stone'], parent=root, axis='Z', verts=32)
    for i in range(4):
        a = i * math.pi / 2
        sphere('m_half', 4 * s, (math.cos(a) * 7 * s, math.sin(a) * 7 * s, 8 * s), m=mm['dome'], parent=root, seg=24, rings=12, scale=(1, 1, 0.7))
    cyl('m_finial', 0.15 * s, 3 * s, (0, 0, 16.5 * s), m=mm['chrome'], parent=root, axis='Z', verts=8)
    for k in range(minarets):
        mx = (-1 if k == 0 else 1) * 9 * s
        cyl('minaret', 1.2 * s, 32 * s, (mx, -7 * s, 16 * s), m=mm['marble'], parent=root, axis='Z', verts=16)
        cyl('balcony', 1.7 * s, 0.6 * s, (mx, -7 * s, 24 * s), m=mm['marble'], parent=root, axis='Z', verts=16)
        lathe('cone', [(0, 0), (1.25 * s, 0), (1.2 * s, 0.2 * s), (0, 7 * s)], (mx, -7 * s, 32 * s), m=mm['dome'], parent=root, seg=16)


def container(x, y, z, rot, m, mm, length=6.06, collide=True, doors=True):
    root = empty('cont', (x, y, z)); root.rotation_euler = (0, 0, math.radians(rot))
    W, H = 2.44, 2.59
    cname = m.name.split('.')[0]
    if cname.startswith('container_'):
        cb = box('c_body', (W - 0.08, length - 0.1, H - 0.1), (0, 0, H / 2), m=M('cont_' + cname[10:], (0.5, 0.5, 0.5), 0.55), parent=root)
        cb['normuv'] = True
        # door end: hinges, handles and seal plate
        for sx in (-1, 1):
            for hz in (0.4, 1.3, 2.2):
                box('c_hinge', (0.1, 0.06, 0.12), (sx * (W / 2 - 0.12), -length / 2 - 0.03, hz), m=mm['steel'], parent=root)
        box('c_seam', (0.03, 0.04, H - 0.3), (0, -length / 2 - 0.02, H / 2), m=mm['steel'], parent=root)
    else:
        box('c_body', (W - 0.08, length - 0.1, H - 0.1), (0, 0, H / 2), m=m, parent=root, uv=0.5)
    # frame
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('c_post', (0.16, 0.16, H), (sx * (W / 2 - 0.08), sy * (length / 2 - 0.08), H / 2), m=m, parent=root, bevel=0.01)
        box('c_rail_b', (0.12, length, 0.16), (sx * (W / 2 - 0.06), 0, 0.08), m=m, parent=root)
        box('c_rail_t', (0.12, length, 0.12), (sx * (W / 2 - 0.06), 0, H - 0.06), m=m, parent=root)
    for sy in (-1, 1):
        box('c_end_t', (W, 0.12, 0.16), (0, sy * (length / 2 - 0.06), H - 0.08), m=m, parent=root)
        box('c_end_b', (W, 0.12, 0.2), (0, sy * (length / 2 - 0.06), 0.1), m=m, parent=root)
    if doors:
        for sx in (-1, 1):
            for k in (-0.3, 0.3):
                box('c_lockbar', (0.035, 0.05, H - 0.4), (sx * 0.6 + k, -length / 2 - 0.02, H / 2), m=mm['steel'], parent=root)
    if collide:
        col((x, y, z + H / 2), (W, length, H), rotz=rot)
    return root


def decal_plane(x, y, z, sx, sy, kind, rot=0.0):
    o = box('decal_' + kind, (sx, sy, 0.005), (x, y, z + 0.012), (0, 0, rot), m=M(kind + '_dec', (0.1, 0.1, 0.1), 0.05))
    o['normuv'] = True
    return o


def pallet_stack(x, y, n, mm, rot=0):
    root = empty('pallets', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for k in range(n):
        z = k * 0.15
        for i in range(5):
            box('pl_top', (1.2, 0.1, 0.022), (0, -0.4 + i * 0.2, z + 0.135), m=mm['pallet'], parent=root)
        for i in range(3):
            box('pl_blk', (1.2, 0.1, 0.1), (0, -0.4 + i * 0.4, z + 0.07), m=mm['pallet'], parent=root)
    col((x, y, n * 0.075), (1.2, 1.0, n * 0.15), rotz=rot)


def cable_reel(x, y, mm, r=0.8):
    root = empty('reel', (x, y, 0))
    for s in (-1, 1):
        cyl('reel_side', r, 0.06, (s * 0.35, 0, r), m=mm['planks'], parent=root, axis='X', verts=24)
    cyl('reel_core', r * 0.65, 0.66, (0, 0, r), m=M('cable_black', (0.05, 0.05, 0.05), 0.6), parent=root, axis='X', verts=24)
    col((x, y, r), (0.8, r * 2, r * 2))


def cone(x, y):
    cyl('cone', 0.17, 0.7, (x, y, 0.35), m=M('cone_orange', (0.95, 0.35, 0.05), 0.5), axis='Z', verts=12, r2=0.03)
    box('cone_base', (0.4, 0.4, 0.04), (x, y, 0.02), m=M('cone_orange', (0.95, 0.35, 0.05), 0.5))
    cyl('cone_band', 0.11, 0.1, (x, y, 0.42), m=M('cone_white', (0.95, 0.95, 0.95), 0.4), axis='Z', verts=12, r2=0.08)


def light_tower(x, y, mm, h=14):
    cyl('lt_pole', 0.18, h, (x, y, h / 2), m=mm['steel'], axis='Z', verts=12)
    box('lt_head', (2.4, 0.4, 0.8), (x, y, h + 0.3), m=mm['steel'])
    for i in range(4):
        box('lt_lamp', (0.45, 0.06, 0.35), (x - 0.85 + i * 0.57, y - 0.23, h + 0.25), m=mm['glass_lit'])
    col((x, y, h / 2), (0.4, 0.4, h))


def jersey(x, y, rot, mm):
    root = empty('jersey', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    prof('jb', [(-0.3, 0), (0.3, 0), (0.12, 0.25), (0.1, 0.9), (-0.1, 0.9), (-0.12, 0.25)], 3.0, m=mm['concrete'], parent=root, plane='XZ', bevel=0.02) if False else None
    box('jb_base', (0.6, 3.0, 0.3), (0, 0, 0.15), m=mm['concrete'], parent=root, bevel=0.03)
    box('jb_top', (0.24, 3.0, 0.62), (0, 0, 0.6), m=mm['concrete'], parent=root, bevel=0.03)
    for k in range(3):
        box('jb_stripe', (0.25, 0.5, 0.12), (0, -1.0 + k * 1.0, 0.75), m=M('stripe_red', (0.8, 0.1, 0.08), 0.5), parent=root)
    col((x, y, 0.45), (0.6, 3.0, 0.9), rotz=rot)


def truck(tx, ty, r, mm, cmat):
    tr = empty('truck', (tx, ty, 0)); tr.rotation_euler = (0, 0, math.radians(r))
    paint = M('truck_paint_white', (0.9, 0.9, 0.88), 0.3, 0.4)
    # cab with sloped windscreen, grille, bumper, lights, mirrors, steps, side tanks, exhaust stacks
    prof('tr_cabp', [(3.3, 0.9), (5.75, 0.9), (5.85, 1.5), (5.7, 2.6), (5.3, 3.35), (3.3, 3.4)], 2.45, m=paint, parent=tr, plane='YZ', bevel=0.12, segs=3)
    prof('tr_ws', [(5.62, 2.1), (5.75, 2.55), (5.32, 3.25), (5.2, 2.15)], 2.2, m=mm['carglass'], parent=tr, plane='YZ', bevel=0.02)
    for s in (-1, 1):
        box('tr_sidewin', (0.03, 0.9, 0.8), (s * 1.23, 4.6, 2.7), m=mm['carglass'], parent=tr)
        box('tr_mirror_arm', (0.4, 0.05, 0.05), (s * 1.42, 5.2, 2.9), m=mm['black'], parent=tr)
        box('tr_mirror', (0.08, 0.22, 0.45), (s * 1.62, 5.2, 2.75), m=mm['black'], parent=tr, bevel=0.02)
        box('tr_step', (0.25, 0.6, 0.06), (s * 1.2, 4.2, 0.75), m=mm['steel'], parent=tr)
        cyl('tr_tank', 0.32, 1.3, (s * 1.0, 2.4, 0.95), m=mm['chrome'], parent=tr, axis='Y', verts=16)
        cyl('tr_stack', 0.08, 1.8, (s * 1.05, 3.25, 3.3), m=mm['chrome'], parent=tr, axis='Z', verts=10)
        box('tr_hl', (0.45, 0.05, 0.22), (s * 0.85, 5.88, 1.15), m=mm['headlight'], parent=tr, bevel=0.03)
        box('tr_flap', (0.6, 0.03, 0.6), (s * 1.05, -6.4, 0.6), m=mm['black'], parent=tr)
    box('tr_grille', (1.3, 0.04, 0.8), (0, 5.88, 1.65), m=mm['chrome'], parent=tr)
    for k in range(6):
        box('tr_grille_bar', (1.3, 0.05, 0.03), (0, 5.9, 1.3 + k * 0.13), m=mm['black'], parent=tr)
    box('tr_bumper', (2.5, 0.22, 0.35), (0, 5.95, 0.75), m=mm['black'], parent=tr, bevel=0.04)
    box('tr_chassis', (1.0, 12.4, 0.4), (0, -0.4, 0.8), m=mm['black'], parent=tr)
    box('tr_trailer', (2.5, 9.6, 0.25), (0, -1.7, 1.08), m=mm['steel'], parent=tr)
    for wy_ in (4.7, 0.8, -4.6, -5.8):
        for s in (-1, 1):
            cyl('tr_wh', 0.52, 0.4, (s * 1.02, wy_, 0.52), m=mm['tire'], parent=tr, axis='X', verts=20, bevel=0.03)
            cyl('tr_hub', 0.28, 0.42, (s * 1.02, wy_, 0.52), m=mm['chrome'], parent=tr, axis='X', verts=12)
    c = container(0, -1.7, 1.2, 0, cmat, mm, collide=False, length=9)
    c.parent = tr
    cc = Matrix.Rotation(math.radians(r), 3, 'Z') @ Vector((0, 0.0, 0))
    col((tx + cc.x, ty + cc.y, 1.9), (2.5, 12.8, 3.8), rotz=r)



def rooftop_block(x, y, rot, w, d, h, mm, wall_m, stair_side=1):
    """single-storey block with a walkable flat roof, parapet and external steel stairs (elevated position)"""
    root = empty('rblock', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('rb_body', (w, d, h), (0, 0, h / 2), m=wall_m, parent=root, uv=0.5)
    box('rb_plinth', (w + 0.08, d + 0.08, 0.7), (0, 0, 0.35), m=mm['stone'], parent=root)
    box('rb_roof', (w + 0.2, d + 0.2, 0.2), (0, 0, h + 0.1), m=mm['concrete'], parent=root)
    for sx in (-1, 1):
        box('rb_par', (0.25, d + 0.2, 1.0), (sx * (w / 2 + 0.0), 0, h + 0.7), m=wall_m, parent=root)
    box('rb_par_f', (w + 0.2, 0.25, 1.0), (0, -d / 2, h + 0.7), m=wall_m, parent=root)
    box('rb_par_b', (w + 0.2, 0.25, 1.0), (0, d / 2, h + 0.7), m=wall_m, parent=root)
    box('rb_door', (1.2, 0.06, 2.2), (0, -d / 2 - 0.01, 1.1), m=mm['shutter'], parent=root)
    R = Matrix.Rotation(math.radians(rot), 3, 'Z')
    def wpt(lx, ly):
        v = R @ Vector((lx, ly, 0)); return x + v.x, y + v.y
    cx, cy = wpt(0, 0)
    col((cx, cy, h / 2), (w, d, h), rotz=rot)
    col((cx, cy, h + 0.1), (w + 0.2, d + 0.2, 0.2), rotz=rot)
    for (lx, ly, sx_, sy_) in [(-w / 2, 0, 0.25, d + 0.2), (w / 2, 0, 0.25, d + 0.2), (0, -d / 2, w + 0.2, 0.25), (0, d / 2, w + 0.2, 0.25)]:
        # leave a gap in the parapet where the stairs arrive
        if abs(lx - stair_side * w / 2) < 0.01 and sx_ < 1:
            continue
        px, py = wpt(lx, ly)
        col((px, py, h + 0.7), (sx_, sy_, 1.0), rotz=rot)
    # external stairs along the side wall, rising from the front toward the back and arriving on the roof
    sl = (h + 0.2) / 0.18 * 0.27
    ax = stair_side * (w / 2 + 0.8)
    scx, scy = wpt(ax, -d / 2 + sl / 2 + 0.3)
    up = R @ Vector((0, 1, 0))
    if abs(up.y) > 0.5:
        stairs('rb_st', scx, scy, 0, h + 0.2, sl, 1.4, mm['steel'], axis='Y', direction=1 if up.y > 0 else -1)
    else:
        stairs('rb_st', scx, scy, 0, h + 0.2, sl, 1.4, mm['steel'], axis='X', direction=1 if up.x > 0 else -1)
    return root


def bus_stop(x, y, rot, mm):
    root = empty('busstop', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for sx in (-1.4, 1.4):
        box('bs_post', (0.08, 0.08, 2.5), (sx, 0.5, 1.25), m=mm['metal'], parent=root)
    box('bs_roof', (3.2, 1.4, 0.08), (0, 0.2, 2.5), m=mm['metal'], parent=root)
    gl = box('bs_back', (3.0, 0.03, 1.9), (0, 0.55, 1.35), m=mm['carglass'], parent=root)
    pz = box('bs_ad', (1.1, 0.04, 1.6), (1.0, 0.52, 1.3), m=poster_mat(2), parent=root); pz['normuv'] = True
    box('bs_bench', (2.2, 0.4, 0.06), (-0.3, 0.3, 0.5), m=mm['planks'], parent=root)
    c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, 0.55, 0))
    col((x + c.x, y + c.y, 1.0), (3.0, 0.15, 2.0), rotz=rot)


def kiosk(x, y, rot, mm):
    root = empty('kiosk', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('k_body', (2.4, 1.8, 2.5), (0, 0, 1.25), m=M('kiosk_red', (0.7, 0.1, 0.08), 0.5), parent=root, bevel=0.05)
    box('k_win', (2.0, 0.04, 1.0), (0, -0.91, 1.6), m=int_mat(2), parent=root)
    box('k_roof', (2.8, 2.2, 0.12), (0, 0, 2.6), m=mm['metal'], parent=root)
    sg = box('k_sign', (2.2, 0.06, 0.4), (0, -0.92, 2.35), m=sign_mat('bakkal'), parent=root)
    box('k_counter', (2.4, 0.4, 0.08), (0, -1.05, 1.05), m=mm['metal'], parent=root)
    col((x, y, 1.25), (2.4, 1.8, 2.5), rotz=rot)


def scaffold(x, y, rot, w, h, mm):
    root = empty('scaffold', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for i in range(int(w / 2) + 1):
        for sy in (0, 1.1):
            cyl('sc_pole', 0.03, h, (-w / 2 + i * 2, -sy, h / 2), m=mm['metal'], parent=root, axis='Z', verts=6)
    for z in range(1, int(h / 2) + 1):
        box('sc_plank', (w, 1.0, 0.05), (0, -0.55, z * 2.0), m=mm['planks'], parent=root)
        box('sc_rail', (w, 0.04, 0.04), (0, -1.1, z * 2.0 + 1.0), m=mm['metal'], parent=root)
    box('sc_net', (w, 0.02, h), (0, -1.15, h / 2), m=M('scaffold_net', (0.15, 0.4, 0.2), 0.9), parent=root)


# ======================================================================== export
def _uv_world(bm_, sign=False):
    uvl = bm_.loops.layers.uv.verify()
    if sign:
        xs = [v.co for v in bm_.verts]
        if not xs:
            return
        mn = Vector((min(c.x for c in xs), min(c.y for c in xs), min(c.z for c in xs)))
        mx = Vector((max(c.x for c in xs), max(c.y for c in xs), max(c.z for c in xs)))
        ext = mx - mn
    for f in bm_.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = l.vert.co
            if sign:
                if ax == 1:
                    u = (p.x - mn.x) / max(ext.x, 1e-4); v = (p.z - mn.z) / max(ext.z, 1e-4)
                    if n.y > 0: u = 1 - u
                elif ax == 0:
                    u = (p.y - mn.y) / max(ext.y, 1e-4); v = (p.z - mn.z) / max(ext.z, 1e-4)
                    if n.x < 0: u = 1 - u
                else:
                    u, v = 0.5, 0.5
                l[uvl].uv = (u, v)
                continue
            if ax == 0:
                uv = (p.y * math.copysign(1, n.x), p.z)
            elif ax == 1:
                uv = (-p.x * math.copysign(1, n.y), p.z)
            else:
                uv = (p.x, p.y * math.copysign(1, n.z))
            l[uvl].uv = uv


def finalize(mapid, env, bounds, extra=None):
    import time
    t0 = time.time()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    chunks = {}
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print('objects', len(objs), flush=True)
    scratch = bpy.data.meshes.new('scratch')
    for o in objs:
        has_mod = len(o.modifiers) > 0
        if has_mod:
            ev = o.evaluated_get(dg); me = ev.to_mesh()
        else:
            ev = None; me = o.data
        mw = o.matrix_world.copy()
        is_sign = (bool(me.materials) and me.materials[0] is not None and (me.materials[0].name.startswith('sign_') or me.materials[0].name in ('flag_tr', 'leaves'))) or bool(o.get('normuv'))
        tmp = bmesh.new(); tmp.from_mesh(me)
        if is_sign:
            _uv_world(tmp, sign=True)
            tmp.transform(mw)
        elif o.get('roofuv'):
            tmp.transform(mw)
            tmp.normal_update()
            uvl = tmp.loops.layers.uv.verify()
            for f in tmp.faces:
                nn = f.normal
                t_ = Vector((0, 0, 1)).cross(nn)
                if t_.length < 1e-4:
                    t_ = Vector((1, 0, 0))
                t_.normalize()
                b_ = nn.cross(t_).normalized()
                for l in f.loops:
                    l[uvl].uv = (l.vert.co.dot(t_), -l.vert.co.dot(b_))
        else:
            tmp.transform(mw)
            tmp.normal_update()
            _uv_world(tmp)
        p = mw.translation
        # small props -> 'det' chunks (no shadows, short draw range in game); scenery outside the playable
        # area -> 'far' chunks (no shadows). Keeps draw calls and shadow passes down.
        dims = o.dimensions
        cls = ''
        if o.get('terrain'):
            cls = 'terrain'
        elif bounds and (p.x < bounds[0] - 1 or p.x > bounds[2] + 1 or p.y < bounds[1] - 1 or p.y > bounds[3] + 1):
            cls = 'far'
        elif max(dims.x, dims.y, dims.z) < 1.0 and not is_sign:
            cls = 'det'
        g = 48 if cls == 'terrain' else (36 if cls else 18)
        key = (cls, int(math.floor(p.x / g)), int(math.floor(p.y / g)))
        if key not in chunks:
            chunks[key] = (bmesh.new(), [])
        cbm, mlist = chunks[key]
        slot_map = []
        for m in me.materials:
            if m not in mlist:
                mlist.append(m)
            slot_map.append(mlist.index(m))
        smooth = bool(o.data.polygons) and o.data.polygons[0].use_smooth
        for f in tmp.faces:
            if slot_map:
                f.material_index = slot_map[min(f.material_index, len(slot_map) - 1)]
            f.smooth = smooth
        scratch.clear_geometry()
        tmp.to_mesh(scratch); tmp.free()
        cbm.from_mesh(scratch)
        if ev is not None:
            ev.to_mesh_clear()
    print('merged in', round(time.time() - t0, 1), flush=True)
    chunk_objs = []
    for key, (cbm, mlist) in chunks.items():
        me = bpy.data.meshes.new(f'{key[0] or "chunk"}_{key[1]}_{key[2]}')
        cbm.to_mesh(me); cbm.free()
        for m in mlist:
            me.materials.append(m)
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        chunk_objs.append(ob)
    print('chunks', len(chunk_objs), flush=True)
    export_glb(os.path.join(OUTD, mapid + '.glb'), chunk_objs)
    data = dict(colliders=COL, spawns=SPAWNS, env=env, bounds=bounds)
    if TREES:
        data['trees'] = TREES
    if extra:
        data.update(extra)
    with open(os.path.join(OUTD, mapid + '.json'), 'w') as f:
        json.dump(data, f)
    print(mapid, 'colliders', len(COL), 'spawns', len(SPAWNS), 'time', round(time.time() - t0, 1), flush=True)


def begin():
    reset(); COL.clear(); SPAWNS.clear(); TREES.clear(); RND.seed(1); WRND.seed(77)
    return mats()


def bounds_walls(x0, y0, x1, y1, h=12):
    t = 1.0
    col(((x0 + x1) / 2, y0 - t / 2, h / 2), (x1 - x0 + 2, t, h))
    col(((x0 + x1) / 2, y1 + t / 2, h / 2), (x1 - x0 + 2, t, h))
    col((x0 - t / 2, (y0 + y1) / 2, h / 2), (t, y1 - y0 + 2, h))
    col((x1 + t / 2, (y0 + y1) / 2, h / 2), (t, y1 - y0 + 2, h))


# ======================================================================== MAP 1: ESKİ MAHALLE
def map_mahalle():
    mm = begin()
    walls = ['p_yellow', 'p_terra', 'p_cream', 'p_mint', 'p_rose', 'p_blue', 'p_ochre', 'p_white', 'p_lilac', 'brick']
    shops = [('bakkal', 'aw_blue'), ('firin', 'aw_red'), ('cay', 'aw_green'), ('berber', None), ('eczane', 'aw_red'), ('lokanta', 'aw_red'),
             ('kasap', 'aw_red'), ('market', 'aw_green'), ('kuafor', None), ('tekel', 'aw_blue')]
    X0, X1, Y0, Y1 = -70, 70, -40, 40
    # ground: road + sidewalks + back lanes
    ground('road', X0 - 4, -5, X1 + 4, 5, 0, mm['cobble'])
    for s in (-1, 1):
        ground('walk', X0 - 4, 5 if s > 0 else -8.5, X1 + 4, 8.5 if s > 0 else -5, 0.15, mm['paver'])
        box('curb', (X1 - X0 + 8, 0.25, 0.18), (0, s * 5.0, 0.06), m=mm['curb'], bevel=0.02)
    ground('backN', X0 - 4, 8.5, X1 + 4, Y1 + 4, 0.15, mm['asphalt'])
    ground('backS', X0 - 4, Y0 - 4, X1 + 4, -8.5, 0.15, mm['paver'])
    for xx in range(-64, 65, 10):
        cyl('manhole', 0.35, 0.02, (xx + 3, 0, 0.005), m=mm['metal'], axis='Z', verts=20)

    def row(seed, alley_every):
        rr = random.Random(seed)
        out, x, n = [], X0, 0
        while x < X1 - 5:
            w = rr.choice([7, 8, 9, 10, 10])
            w = min(w, X1 - x)
            alley = (n % alley_every == alley_every - 1)
            out.append((x, w, alley))
            x += w if not alley else 6
            n += 1
        return out
    # ---- north row (facades face the street, -Y)
    k = 0
    for (x, w, alley) in row(11, 4):
        if alley:
            continue
        floors = RND.choice([4, 5, 5, 6])
        apartment(f'n{k}', x + w / 2, 8.5, 0, w - 0.2, 10, floors, mm, mm[walls[k % len(walls)]], shop=shops[k % len(shops)], seed=k, side_windows=True)
        k += 1
    # ---- south row faces north (rot 180) ; facade at y=-8.5
    for (x, w, alley) in row(23, 5):
        if alley:
            continue
        floors = RND.choice([4, 4, 5, 6])
        apartment(f's{k}', x + w / 2, -8.5, 180, w - 0.2, 10, floors, mm, mm[walls[k % len(walls)]], shop=shops[(k + 3) % len(shops)], seed=k + 50, side_windows=True)
        k += 1
    # back rows (outer boundary)
    for i, x in enumerate(range(X0, X1, 11)):
        apartment(f'bn{i}', x + 5.5, Y1, 0, 10.8, 8, RND.choice([5, 6, 7]), mm, mm[walls[(i + 2) % len(walls)]], seed=100 + i, roof='flat', side_windows=True)
        apartment(f'bs{i}', x + 5.5, Y0, 180, 10.8, 8, RND.choice([4, 5, 6]), mm, mm[walls[(i + 5) % len(walls)]], seed=200 + i, roof='flat', side_windows=True)
    # end caps (east/west)
    for sgn in (-1, 1):
        apartment(f'cap{sgn}', sgn * (X1 + 6), 0, -90 * sgn, 2 * Y1 + 16, 6, 6, mm, mm['p_grey'], seed=300 + sgn, roof='flat', collide=True)
    # bus blocking east end
    bus = empty('bus', (X1 - 4, 1.5, 0)); bus.rotation_euler = (0, 0, math.radians(90))
    box('bus_body', (2.5, 11, 2.8), (0, 0, 1.8), m=M('bus_blue', (0.1, 0.3, 0.7), 0.4, 0.5), parent=bus, bevel=0.15, segs=3)
    box('bus_win', (2.52, 9.5, 0.9), (0, 0.3, 2.4), m=mm['carglass'], parent=bus)
    for sy in (-3.8, 3.6):
        for sx in (-1, 1):
            cyl('bus_wh', 0.5, 0.35, (sx * 1.1, sy, 0.5), m=mm['tire'], parent=bus, axis='X', verts=20)
    col((X1 - 4, 1.5, 1.6), (11, 2.6, 3.2))
    # barricade west
    sandbags(X0 + 5, -1.5, 6, 3, mm, 90)
    sandbags(X0 + 5, 3.5, 3.5, 3, mm, 90)
    for i, yy in enumerate((-4, 2)):
        box('jersey', (0.6, 3.0, 0.9), (X0 + 7.5, yy, 0.45), m=mm['concrete'], bevel=0.08)
        col((X0 + 7.5, yy, 0.45), (0.6, 3.0, 0.9))
    # cars along street
    cols = [('red', (0.6, 0.05, 0.04)), ('white', (0.85, 0.85, 0.82)), ('blue', (0.1, 0.2, 0.45)), ('black', (0.04, 0.04, 0.05)), ('grey', (0.4, 0.42, 0.44)), ('yellow', (0.8, 0.6, 0.05))]
    for i, (cx, cy, r) in enumerate([(-54, -3.6, -90), (-30, 3.6, 90), (-12, -3.6, -90), (2, 3.6, 90), (20, -3.6, 90), (31, 3.5, 92), (-22, -3.4, 88), (46, 3.6, 90), (58, -3.5, -88)]):
        car(cx, cy, r, cols[i % len(cols)], mm, f'car{i}')
    car(-16, 25, 0, cols[1], mm, 'carN1'); car(8, 26, 180, cols[4], mm, 'carN2'); car(30, 22, 10, cols[0], mm, 'carN3')
    car(-52, 30, 90, cols[2], mm, 'carN4'); car(55, 24, 0, cols[5], mm, 'carN5')
    # ---- PAZAR YERİ (open-air market) in the north back lane
    pz = random.Random(31)
    awn = ['aw_red', 'aw_blue', 'aw_green', 'aw_orange'] if 'aw_orange' in mm else ['aw_red', 'aw_blue', 'aw_green']
    fruits = ['fruit_r', 'fruit_o', 'fruit_g']
    for i, sx in enumerate(range(-58, 59, 7)):
        if abs(sx) < 4:
            continue
        for row_y in (27.0, 33.0):
            if pz.random() < 0.25:
                continue
            st = empty('pazar', (sx, row_y, 0.15))
            box('pz_table', (4.6, 1.6, 0.85), (0, 0, 0.42), m=mm['planks'], parent=st, bevel=0.02)
            for k2 in range(14):
                sphere('pz_fruit', 0.1, (-2.0 + (k2 % 7) * 0.62, -0.45 + (k2 // 7) * 0.5, 0.95), m=mm[fruits[(i + k2) % 3]], parent=st, seg=8, rings=5)
            for sxx in (-2.2, 2.2):
                for syy in (-0.8, 0.8):
                    cyl('pz_pole', 0.035, 2.6, (sxx, syy, 1.3), m=mm['metal'], parent=st, axis='Z', verts=8)
            box('pz_roof', (5.0, 2.4, 0.04), (0, 0, 2.62), m=mm[awn[(i + int(row_y)) % len(awn)]], parent=st)
            col((sx, row_y, 0.6), (4.6, 1.6, 0.9))
    # market crates/sacks clusters for cover
    for (cx, cy) in [(-40, 30), (-12, 30), (16, 30), (44, 30)]:
        crate(cx, cy, 0.15, 1.0, mm); crate(cx + 1.05, cy + 0.1, 0.15, 1.0, mm, rot=12); crate(cx + 0.5, cy, 1.15, 0.9, mm, rot=-8)
    # dumpsters, crates, stall, props on sidewalks
    dumpster(-8, 7.2, 0, mm); dumpster(26, -7.0, 180, mm); dumpster(-26, 20, 90, mm); dumpster(19.5, 21, 0, mm)
    for (cx, cy) in [(-33, -6.8), (11, 6.8), (37, -6.8)]:
        crate(cx, cy, 0.15, 1.0, mm); crate(cx + 1.05, cy, 0.15, 1.0, mm, rot=8)
    crate(-33, -6.8, 1.15, 0.8, mm, rot=15)
    # fruit stall
    st = empty('stall', (-2, -6.6, 0.15))
    box('st_table', (3.2, 1.4, 0.9), (0, 0, 0.45), m=mm['planks'], parent=st, bevel=0.02)
    for i, fm in enumerate(['fruit_r', 'fruit_o', 'fruit_g', 'fruit_r']):
        for k2 in range(10):
            sphere('fruit', 0.09, (-1.3 + i * 0.85 + (k2 % 4) * 0.17, -0.4 + (k2 // 4) * 0.25, 1.0), m=mm[fm], parent=st, seg=8, rings=5)
    for sx in (-1.5, 1.5):
        cyl('st_pole', 0.04, 2.4, (sx, 0.6, 1.2), m=mm['metal'], parent=st, axis='Z', verts=8)
    box('st_roof', (3.6, 2.0, 0.04), (0, 0, 2.45), (-10, 0, 0), m=mm['aw_red'], parent=st)
    col((-2, -6.6, 0.6), (3.2, 1.4, 0.9))
    # tea tables near cay ocagi
    for i in range(3):
        tx = -40 + i * 2.5
        cyl('tbl', 0.35, 0.05, (tx, 6.8, 0.85), m=mm['planks'], axis='Z', verts=16)
        cyl('tbl_leg', 0.04, 0.7, (tx, 6.8, 0.5), m=mm['metal'], axis='Z', verts=8)
        for s in (-1, 1):
            box('stool', (0.32, 0.32, 0.35), (tx + s * 0.6, 6.8, 0.33), m=mm['planks'], bevel=0.02)
        cyl('tea', 0.03, 0.08, (tx + 0.1, 6.8, 0.92), m=mm['tea'], axis='Z', verts=8)
    # lamps & bunting & cables
    for xx in range(-62, 64, 12):
        street_lamp(xx, 7.8, 180, mm)
        street_lamp(xx + 6, -7.8, 0, mm)
    for xx in (-62, -48, -34, -20, -6, 8, 22, 36, 50, 62):
        bunting((xx, 8.4, 8.5), (xx + 4, -8.4, 8.0), mm, sag=0.9)
        power_cable((xx + 2, 8.4, 10.5), (xx + 5, -8.4, 10.2), mm, sag=1.0)
    # trees & benches in south back area (park)
    for i, (tx, ty) in enumerate([(-30, -22), (-10, -26), (8, -20), (28, -25), (-50, -24), (48, -22), (-62, -30), (62, -30)]):
        tree(tx, ty, mm, h=6.5, seed=i)
    for (bx, by, r) in [(-24, -20, 0), (0, -24, 90), (18, -22, 0), (-44, -20, 0), (40, -26, 90)]:
        bench(bx, by, r, mm)
    # park low walls (cover)
    for (wx, wy, sx, sy) in [(-15, -17, 8, 0.4), (14, -17, 8, 0.4), (0, -28, 0.4, 5), (-20, 15, 0.4, 6), (20, 15, 0.4, 6), (-52, -16, 8, 0.4), (52, -16, 8, 0.4), (-58, -30, 0.4, 6), (58, -30, 0.4, 6)]:
        wall('lowwall', wx, wy, 0.15, sx, sy, 1.1, mm['stone'])
    # small fountain square south
    cyl('fountain', 2.0, 0.7, (0, -21, 0.5), m=mm['marble'], axis='Z', verts=32)
    cyl('fountain_w', 1.8, 0.05, (0, -21, 0.82), m=mm['water'], axis='Z', verts=32)
    cyl('fountain_c', 0.3, 1.8, (0, -21, 1.0), m=mm['marble'], axis='Z', verts=16)
    col((0, -21, 0.5), (3.6, 3.6, 0.85))
    lr = random.Random(77)
    for (ax, y0, y1) in [(-23, 8.5, 18.5), (-20, 8.5, 18.5), (17, 8.5, 18.5), (-16, -8.5, -18.5), (26, -8.5, -18.5)]:
        for k in range(3):
            yy = y0 + (y1 - y0) * (0.25 + k * 0.25)
            laundry_line(None, (ax - 3.0, yy, 6.0 + k * 2.2), (ax + 3.0, yy, 6.0 + k * 2.2), mm, lr, sag=0.25)
    for xx in range(-60, 61, 9):
        laundry_line(None, (xx, Y1 - 0.5, 7.5), (xx + 4, 31.5, 7.5), mm, lr)
    # mosque in background
    mosque(95, 25, 1.0, mm)
    mosque(-100, -35, 0.8, mm, 1)
    # ---- cover, chokepoints and elevated spots
    rooftop_block(-26, -31, 0, 8, 8, 3.6, mm, mm['p_ochre'], stair_side=-1)
    rooftop_block(34, -31, 0, 8, 8, 3.6, mm, mm['p_mint'], stair_side=1)
    bus_stop(-40, -7.0, 180, mm); bus_stop(44, 7.0, 0, mm)
    kiosk(10, 7.0, 0, mm); kiosk(-52, -7.0, 180, mm)
    for (jx, jy) in [(-8, -1.6), (2, 1.8), (14, -1.3), (-34, 1.4), (30, -1.6), (50, 1.5)]:
        jersey(jx, jy, 0, mm)
    car(-60, 3.4, 90, cols[3], mm, 'carX1'); car(10, -3.5, -90, cols[2], mm, 'carX2'); car(-44, 3.5, 92, cols[5], mm, 'carX3')
    scaffold(24, 8.45, 0, 8, 10, mm)
    # spawns
    for i, xx in enumerate(range(-60, 61, 12)):
        spawn(xx + 2, 22, 0.2, 180, 'a' if i % 2 else None)
        spawn(xx + 4, -30, 0.2, 0, 'b' if i % 2 else None)
    for xx in (-54, -30, -12, 6, 24, 42, 56):
        spawn(xx, 0, 0.05, 90, None)
    for i in range(5):
        spawn(-60 + i * 3, 21, 0.2, 180, 'a'); spawn(60 - i * 3, -31, 0.2, 0, 'b')
    bounds_walls(X0, Y0, X1, Y1)
    finalize('mahalle', dict(preset='day', sun=[-35, 40], fog=0.008, sky='clear'), [X0, Y0, X1, Y1])


# ======================================================================== MAP 2: SAFRANBOLU
def map_safranbolu_old():
    mm = begin()
    X0, X1, Y0, Y1 = -42, 42, -40, 40
    ground('base', X0 - 10, Y0 - 10, X1 + 10, Y1 + 10, 0, mm['cobble'])
    # upper terrace (north-east) at +2.6
    T = 2.6
    wall('terrace', 14, 24, 0, 56, 32, T, mm['stone'])  # x -14..42, y 8..40
    ground('terrace_top', -14, 8, 42, 40, T + 0.05, mm['cobble'], thick=0.05, collide=False)
    # retaining wall cap
    box('cap', (56.2, 0.6, 0.2), (14, 8.0, T + 0.1), m=mm['stone'])
    # stairs from square to terrace
    stairs('st1', -4, 4.5, 0, T, 7, 4, mm['stone'], axis='Y', direction=1)
    stairs('st2', 30, 4.5, 0, T, 7, 4, mm['stone'], axis='Y', direction=1)
    # side ramp (west)
    ramp('rmp', -18, 22, T, 0, 8, 4, mm['cobble'], axis='X', direction=1)
    # central square "Arasta" with şadırvan and plane tree
    lathe('sadirvan', [(0, 0), (3.2, 0), (3.2, 0.9), (2.9, 0.9), (2.9, 0.4), (0.0, 0.4)], (-8, -12, 0), m=mm['marble'], seg=12)
    for i in range(8):
        a = i / 8 * math.tau
        cyl('sd_col', 0.15, 3.2, (-8 + math.cos(a) * 2.6, -12 + math.sin(a) * 2.6, 1.6), m=mm['marble'], axis='Z', verts=12)
    lathe('sd_roof', [(0, 0), (3.8, 0), (0.0, 2.2)], (-8, -12, 3.2), m=mm['dome'], seg=8)
    cyl('sd_water', 2.85, 0.05, (-8, -12, 0.75), m=mm['water'], axis='Z', verts=24)
    col((-8, -12, 0.45), (6.2, 6.2, 0.9))
    tree(6, -14, mm, h=11, r=4.5, seed=3)
    tree(-26, -2, mm, h=9, r=3.5, seed=5)
    # Cinci Han style big stone building (south-west) with arches
    han = empty('han', (-30, -30, 0))
    box('han_body', (22, 16, 10), (0, 0, 5), m=mm['stone'], parent=han, uv=0.4)
    for i in range(6):
        box('han_arch', (2.0, 0.3, 3.0), (-8.5 + i * 3.4, 8.05, 1.5), m=mm['beam'], parent=han)
        torus('arch_t', 1.0, 0.18, (-8.5 + i * 3.4, 8.1, 3.0), (90, 0, 0), m=mm['stone'], parent=han, arc=180)
    for i in range(7):
        window(empty('hw', (0, 8.05, 0), han), -9 + i * 3, 7, 0.8, 1.4, mm, frame='frame_wood')
    box('han_sign', (8, 0.15, 1.0), (0, 8.1, 4.4), m=sign_mat('han'), parent=han)
    hip_roof('han_roof', 0, 0, 22, 16, 10, 3.5, mm['roof'], 0.5, han)
    col((-30, -30, 5), (22, 16, 10))
    # konaks around the square (south & west sides on ground level)
    kon = [(-14, -34, 0, 9, 9), (-4, -34, 0, 8, 9), (6, -34, 0, 10, 9), (17, -34, 0, 9, 9), (28, -34, 0, 9, 9), (38, -32, 0, 7, 9),
           (-40, -12, 90, 9, 9), (-40, -2, 90, 8, 9), (40, -16, -90, 10, 9), (40, -4, -90, 9, 8)]
    colors = ['p_white', 'p_white', 'p_cream', 'p_white', 'p_rose', 'p_white', 'p_cream']
    for i, (x, y, r, w, d) in enumerate(kon):
        # rotation: facade faces -Y local; south row facing north -> rot 180 ; given rot param relative
        rot = 180 if r == 0 else r
        konak(f'k{i}', x, y, rot, w, d, mm, seed=i, floors=RND.choice([1, 2, 2]), color=colors[i % len(colors)])
    # shops (arasta) along terrace retaining wall: small stalls
    for i, (sx, key) in enumerate([(-12, 'lokum'), (6, 'bakir'), (20, 'kahve')]):
        sp = empty('shop', (sx, 7.6, 0))
        box('shop_aw', (5, 1.6, 0.06), (0, -0.8, 2.6), (-15, 0, 0), m=mm['beam'], parent=sp)
        box('shop_sign', (4.0, 0.1, 0.6), (0, 0.0, 2.2), m=sign_mat(key), parent=sp)
        box('shop_door', (1.4, 0.1, 2.0), (-1.2, 0.05, 1.0), m=mm['frame_wood'], parent=sp)
        box('shop_win', (2.0, 0.08, 1.2), (1.0, 0.05, 1.2), m=mm['glass'], parent=sp)
        box('shop_counter', (3.6, 0.8, 0.9), (0, -0.6, 0.45), m=mm['planks'], parent=sp, bevel=0.02)
        col((sx, 7.0, 0.45), (3.6, 0.8, 0.9))
    # konaks on the terrace (z = T)
    tk = [(-8, 36, 0, 10, 8), (4, 36, 0, 9, 8), (16, 36, 0, 10, 8), (28, 36, 0, 9, 8), (38, 30, -90, 8, 8), (10, 20, 0, 9, 8), (26, 18, 0, 8, 8)]
    for i, (x, y, r, w, d) in enumerate(tk):
        rot = 180 if r == 0 else r
        if (x, y) in ((-8, 36), (4, 36), (16, 36), (28, 36)):
            rot = 0
            y = y - 8
            y = 32
        g = konak(f'tk{i}', x, y, rot, w, d, mm, seed=20 + i, floors=RND.choice([1, 2]), color=colors[(i + 2) % len(colors)], collide=False)
        g.location.z = T
        gh, fh, ov = 3.0, 2.9, 0.7
        fl = 2
        c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2, 0))
        col((x + c.x, y + c.y, T + 3.0), (w + 1.4, d + 0.7, 6.0), rotz=rot)
    # cover on the square: carts, crates, barrels, low walls
    for (cx, cy) in [(-20, -18), (16, -20), (24, -6), (-2, -4)]:
        crate(cx, cy, 0, 1.0, mm); crate(cx + 1.0, cy + 0.2, 0, 1.0, mm, 10)
    for (bx, by) in [(-18, 2), (12, 0), (34, -24)]:
        barrel(bx, by, mm, 'red'); barrel(bx + 0.7, by + 0.3, mm, 'blue')
    for (wx, wy, sx, sy) in [(-22, -24, 6, 0.5), (22, -26, 0.5, 6), (0, -24, 5, 0.5), (30, 2, 6, 0.5)]:
        wall('sw', wx, wy, 0, sx, sy, 1.15, mm['stone'])
    # horse cart
    hc = empty('cart', (-14, -6, 0)); hc.rotation_euler = (0, 0, math.radians(30))
    box('cart_bed', (1.6, 3.0, 0.15), (0, 0, 0.9), m=mm['planks'], parent=hc, bevel=0.02)
    for s in (-1, 1):
        box('cart_side', (0.08, 3.0, 0.5), (s * 0.78, 0, 1.2), m=mm['planks'], parent=hc)
        torus('wheel', 0.6, 0.05, (s * 0.95, -0.3, 0.6), (0, 90, 0), m=mm['beam'], parent=hc, seg=24, mseg=6)
        for k in range(6):
            box('spoke', (0.04, 1.2, 0.04), (s * 0.95, -0.3, 0.6), (k * 30, 0, 0), m=mm['beam'], parent=hc)
        box('shaft', (0.08, 2.2, 0.08), (s * 0.5, 2.4, 0.8), m=mm['beam'], parent=hc)
    col((-14, -6, 0.9), (1.8, 3.2, 1.6), rotz=30)
    # terrace props
    for (cx, cy) in [(0, 16), (20, 12), (34, 16)]:
        crate(cx, cy, T, 1.1, mm)
    for (wx, wy) in [(-6, 14), (24, 26)]:
        wall('tw', wx, wy, T, 4, 0.5, 1.1, mm['stone'])
    tree(-10, 22, mm, h=8, r=3, seed=9)
    tree(36, 12, mm, h=7, r=2.8, seed=10)
    for i in range(6):
        street_lamp(-30 + i * 12, -20, 0, mm, ottoman=True)
    # bunting across square
    bunting((-20, 7.5, 5.5), (-20, -28, 6.5), mm, 1.0)
    bunting((10, 7.5, 5.5), (10, -28, 6.5), mm, 1.0)
    # background: clock tower + mosques on hills, hills
    ct = empty('clock', (55, 55, 12))
    box('ct_body', (5, 5, 14), (0, 0, 7), m=mm['stone'], parent=ct)
    box('ct_face', (5.1, 5.1, 2), (0, 0, 11), m=mm['p_white'], parent=ct)
    hip_roof('ct_roof', 0, 0, 5, 5, 14, 4, mm['dome'], 0.3, ct)
    mosque(-20, 80, 1.1, mm, 1)
    for i in range(10):
        a = i / 10 * math.tau
        sphere('hill', 40, (math.cos(a) * 140, math.sin(a) * 140, -10), m=mm['grass'], seg=16, rings=8, scale=(1.4, 1.0, 0.5))
    for i in range(14):
        a = i / 14 * math.tau + 0.2
        konak(f'bg{i}', math.cos(a) * 75, math.sin(a) * 75, math.degrees(a) + 90, 9, 8, mm, seed=60 + i, floors=2, collide=False)
    # spawns
    for i, (sx, sy, sz, yaw) in enumerate([(-30, -10, 0, 90), (-14, -19, 0, 0), (0, -28, 0, 0), (20, -28, 0, 0), (34, -10, 0, -90), (12, -10, 0, 0),
                                            (-6, 20, T, 180), (8, 26, T, 180), (22, 24, T, 180), (34, 22, T, 180), (-10, 30, T, 90), (2, 12, T, 180)]):
        spawn(sx, sy, sz + 0.1, yaw, 'b' if i < 6 else 'a')
    bounds_walls(X0, Y0, X1, Y1, 16)
    finalize('safranbolu', dict(preset='day', sun=[-50, 140], fog=0.004, sky='clear'), [X0, Y0, X1, Y1])



# ======================================================================== SAFRANBOLU v2 (Zula-style alleys)
def roof_ridges(root, cx, cy, w, d, z, h, over, m):
    """ridge + hip caps (half-round tiles) on a hip roof built by hip_roof()"""
    w2, d2 = w / 2 + over, d / 2 + over
    if w >= d:
        r0, r1 = Vector((cx - w2 + d2, cy, z + h)), Vector((cx + w2 - d2, cy, z + h))
        corners = [(Vector((cx - w2, cy - d2, z)), r0), (Vector((cx - w2, cy + d2, z)), r0), (Vector((cx + w2, cy - d2, z)), r1), (Vector((cx + w2, cy + d2, z)), r1)]
    else:
        r0, r1 = Vector((cx, cy - d2 + w2, z + h)), Vector((cx, cy + d2 - w2, z + h))
        corners = [(Vector((cx - w2, cy - d2, z)), r0), (Vector((cx + w2, cy - d2, z)), r0), (Vector((cx - w2, cy + d2, z)), r1), (Vector((cx + w2, cy + d2, z)), r1)]
    segs = [(r0, r1)] + corners
    for a, b in segs:
        L = (b - a).length
        if L < 0.1:
            continue
        o = cyl('ridge', 0.11, L, (a + b) / 2 + Vector((0, 0, 0.1)), m=m, parent=root, axis='Z', verts=10)
        o.rotation_euler = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_euler()


def konak2(name, x, y, rot, w, d, mm, seed=0, floors=2, color='p_white', collide=True):
    """detailed Safranbolu house: rubble-stone ground floor with quoins and arched door, jettied timber-framed
    plaster floors on carved brackets, many small white-framed windows, deep eaves with rafter ends,
    half-round tile ridges, stone chimneys"""
    rr = random.Random(seed)
    root = empty(name, (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    gh, fh, ov = 2.9, 2.75, 0.6
    box('ground', (w, d, gh), (0, d / 2, gh / 2), m=mm['stone'], parent=root, uv=0.45)
    for sx in (-1, 1):
        for k in range(5):
            box('quoin', (0.38 if k % 2 else 0.26, 0.03, 0.26), (sx * (w / 2 - 0.16), -0.012, 0.25 + k * 0.55), m=mm['stone'], parent=root, bevel=0.02)
    if collide:
        c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2, gh / 2))
        col((x + c.x, y + c.y, gh / 2), (w, d, gh), rotz=rot)
        c2 = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, d / 2 - ov / 2, gh + floors * fh / 2))
        col((x + c2.x, y + c2.y, gh + floors * fh / 2), (w + ov * 2, d + ov, floors * fh), rotz=rot)
    # arched double door with stone frame
    dx = rr.uniform(-w / 5, w / 5)
    box('door_frame', (1.7, 0.1, 2.5), (dx, -0.03, 1.25), m=mm['marble'], parent=root, bevel=0.03)
    box('door', (1.35, 0.08, 2.15), (dx, -0.07, 1.08), m=mm['frame_wood'], parent=root, bevel=0.02)
    torus('door_arch', 0.68, 0.09, (dx, -0.06, 2.15), (90, 0, 0), m=mm['marble'], parent=root, seg=20, mseg=6, arc=180)
    for k in range(4):
        box('door_plank', (0.02, 0.09, 2.1), (dx - 0.5 + k * 0.33, -0.1, 1.08), m=mm['beam'], parent=root)
    sphere('door_knock', 0.04, (dx + 0.3, -0.13, 1.2), m=mm['brass'] if 'brass' in mm else mm['metal'], parent=root, seg=8, rings=4)
    box('door_step', (1.9, 0.45, 0.16), (dx, -0.22, 0.08), m=mm['marble'], parent=root, bevel=0.02)
    # small barred windows on the stone floor
    for wx in (-w / 2 + 1.1, w / 2 - 1.1):
        if abs(wx - dx) < 1.4:
            continue
        window(root, wx, 1.75, 0.6, 0.75, mm, frame='frame_wood', sill=True)
        for k in range(3):
            box('grate', (0.025, 0.04, 0.75), (wx - 0.2 + k * 0.2, -0.08, 1.75), m=mm['metal'], parent=root)
    W = w + ov * 2
    wall_m = mm[color]
    for f in range(floors):
        z0 = gh + f * fh
        box('upper', (W, d + ov, fh), (0, d / 2 - ov / 2, z0 + fh / 2), m=wall_m, parent=root, uv=0.5)
        fy = -ov - 0.015
        box('sill_beam', (W + 0.08, 0.14, 0.2), (0, fy - 0.02, z0 + 0.1), m=mm['beam'], parent=root, bevel=0.015)
        box('top_beam', (W + 0.08, 0.12, 0.15), (0, fy, z0 + fh - 0.075), m=mm['beam'], parent=root, bevel=0.01)
        nwin = max(2, int(W / 1.1))
        sp = W / nwin
        for i in range(nwin + 1):
            box('post', (0.12, 0.09, fh - 0.3), (-W / 2 + i * sp, fy, z0 + fh / 2), m=mm['beam'], parent=root)
        for i in range(nwin):
            wx = -W / 2 + sp * (i + 0.5)
            # tall Ottoman window: lower pane pair + small upper light (tepe penceresi)
            window(root, wx, z0 + fh * 0.48, sp * 0.56, 1.15, mm, depth=fy + 0.02, frame='frame', sill=False, kafes=(rr.random() < 0.2))
            box('w_top', (sp * 0.4, 0.05, 0.32), (wx, fy + 0.01, z0 + fh - 0.45), m=int_mat(rr.choice([0, 3, 7])), parent=root)
            box('w_topf', (sp * 0.48, 0.07, 0.4), (wx, fy + 0.0, z0 + fh - 0.45), m=mm['frame'], parent=root)
            if rr.random() < 0.3:
                flower_box(root, wx, fy - 0.12, z0 + fh * 0.48 - 0.66, sp * 0.56, mm, rr)
        # timber X braces on the side walls
        for sgn in (-1, 1):
            for k in range(2):
                yy = d * (0.25 + k * 0.5) - ov / 2
                o = box('brace', (0.09, 0.09, fh * 1.08), (sgn * (W / 2 + 0.015), yy, z0 + fh / 2), m=mm['beam'], parent=root)
                o.rotation_euler = (math.radians(32 * (1 if k else -1)), 0, 0)
            box('corner', (0.12, d + ov, 0.14), (sgn * (W / 2 + 0.03), d / 2 - ov / 2, z0 + 0.07), m=mm['beam'], parent=root)
            box('corner_post', (0.14, 0.14, fh), (sgn * (W / 2 + 0.02), fy, z0 + fh / 2), m=mm['beam'], parent=root)
        if f == 0:
            # carved brackets (eli böğründe) carrying the jetty
            for i in range(nwin + 1):
                bx_ = -W / 2 + i * sp
                prof('bracket', [(0.0, 0.0), (-0.12, 0.0), (-ov + 0.05, -0.08), (-ov + 0.05, -0.2), (-0.3, -0.75), (0.0, -0.95)], 0.1,
                     (bx_, 0, gh), m=mm['beam'], parent=root, plane='YZ', bevel=0.015)
    # cumba (projecting bay) on the first upper floor
    if W > 7 and rr.random() < 0.75:
        z0 = gh + 0.1
        cb = empty('cumba', (rr.uniform(-W / 6, W / 6), -ov, 0), root)
        box('cumba_b', (2.7, 0.75, fh - 0.25), (0, -0.37, z0 + (fh - 0.25) / 2), m=wall_m, parent=cb)
        for i in range(3):
            window(cb, -0.88 + i * 0.88, z0 + 1.35, 0.62, 1.2, mm, depth=-0.76, frame='frame', sill=False)
        box('cumba_roof', (2.95, 0.95, 0.1), (0, -0.42, z0 + fh - 0.2), m=mm['beam'], parent=cb, bevel=0.02)
        prof('cumba_br', [(0.0, 0.0), (-0.75, 0.0), (-0.75, -0.12), (0.0, -0.7)], 2.6, (0, 0, z0), m=mm['beam'], parent=cb, plane='YZ', bevel=0.02)
    H = gh + floors * fh
    # deep eaves with exposed rafter ends
    ex = 0.85
    box('eave', (W + ex * 2, d + ov + ex * 2, 0.1), (0, d / 2 - ov / 2, H + 0.05), m=mm['planks'], parent=root)
    nr = int((W + ex * 2) / 0.55)
    for i in range(nr):
        box('rafter', (0.08, ex + 0.1, 0.1), (-W / 2 - ex + 0.27 + i * 0.55, -ov - ex / 2, H - 0.03), m=mm['beam'], parent=root)
        box('rafter_b', (0.08, ex + 0.1, 0.1), (-W / 2 - ex + 0.27 + i * 0.55, d + ex / 2, H - 0.03), m=mm['beam'], parent=root)
    box('fascia', (W + ex * 2, 0.04, 0.16), (0, -ov - ex, H + 0.04), m=mm['beam'], parent=root)
    rh = rr.uniform(2.2, 2.8)
    hip_roof('roof', 0, d / 2 - ov / 2, W, d + ov, H + 0.1, rh, mm['roof'], ex, root)
    roof_ridges(root, 0, d / 2 - ov / 2, W, d + ov, H + 0.1, rh, ex, mm['ridge'])
    for k in range(rr.randint(1, 2)):
        chx = rr.uniform(-W / 3, W / 3); chy = rr.uniform(d * 0.3, d * 0.7)
        box('chimney', (0.55, 0.55, 2.0), (chx, chy, H + rh * 0.55 + 0.6), m=mm['stone'], parent=root)
        box('chimney_cap', (0.75, 0.75, 0.1), (chx, chy, H + rh * 0.55 + 1.65), m=mm['marble'], parent=root)
        box('chimney_top', (0.3, 0.3, 0.3), (chx, chy, H + rh * 0.55 + 1.85), m=mm['roof'], parent=root)
    return root


def garden_wall(a, b, mm, h=2.2, gate=False):
    """rubble-stone garden wall with a half-round tile coping"""
    a = Vector(a); b = Vector(b)
    L = (b - a).length
    if L < 0.5:
        return
    u = (b - a).normalized()
    ang = math.degrees(math.atan2(u.y, u.x))
    mid = (a + b) / 2
    root = empty('gwall', (mid.x, mid.y, 0)); root.rotation_euler = (0, 0, math.radians(ang))
    if gate and L > 3.2:
        side = (L - 1.6) / 2
        for sgn in (-1, 1):
            box('gw', (side, 0.5, h), (sgn * (0.8 + side / 2), 0, h / 2), m=mm['stone'], parent=root, uv=0.45)
            box('gw_cap', (side + 0.1, 0.7, 0.12), (sgn * (0.8 + side / 2), 0, h + 0.06), m=mm['marble'], parent=root)
            cyl('gw_tile', 0.16, side + 0.1, (sgn * (0.8 + side / 2), 0, h + 0.17), m=mm['roof'], parent=root, axis='X', verts=10)
            c = Vector((math.cos(math.radians(ang)), math.sin(math.radians(ang)))) * sgn * (0.8 + side / 2)
            col((mid.x + c.x, mid.y + c.y, h / 2), (side, 0.5, h), rotz=ang)
        box('gate', (1.6, 0.08, h - 0.1), (0, 0.05, (h - 0.1) / 2), m=mm['frame_wood'], parent=root, bevel=0.02)
        box('gate_roof', (2.2, 1.1, 0.1), (0, 0, h + 0.55), m=mm['roof'], parent=root)
        for sgn in (-1, 1):
            box('gate_post', (0.2, 0.2, h + 0.5), (sgn * 0.9, 0, (h + 0.5) / 2), m=mm['beam'], parent=root)
        cmid = Vector((mid.x, mid.y))
        col((cmid.x, cmid.y, h / 2), (1.6, 0.3, h), rotz=ang)
    else:
        box('gw', (L, 0.5, h), (0, 0, h / 2), m=mm['stone'], parent=root, uv=0.45)
        box('gw_cap', (L + 0.1, 0.7, 0.12), (0, 0, h + 0.06), m=mm['marble'], parent=root)
        cyl('gw_tile', 0.16, L + 0.1, (0, 0, h + 0.17), m=mm['roof'], parent=root, axis='X', verts=10)
        col((mid.x, mid.y, h / 2), (L, 0.5, h), rotz=ang)


def wood_barrel(x, y, mm, z=0.0, lying=False, rot=0):
    pts = [(0.0, 0.0), (0.29, 0.0), (0.33, 0.2), (0.35, 0.45), (0.33, 0.7), (0.29, 0.9), (0.0, 0.9)]
    if lying:
        o = lathe('wbarrel', pts, (x, y, z + 0.35), (0, 90, rot), m=mm['planks'], seg=20)
    else:
        o = lathe('wbarrel', pts, (x, y, z), m=mm['planks'], seg=20)
        for hz, hr in ((0.12, 0.31), (0.32, 0.345), (0.58, 0.345), (0.78, 0.31)):
            torus('hoop', hr, 0.018, (x, y, z + hz), m=mm['metal'], seg=20, mseg=4)
    col((x, y, z + 0.45 if not lying else z + 0.35), (0.7, 0.7, 0.9 if not lying else 0.7))


def brick_stack(x, y, mm, rot=0, layers=None):
    rr = random.Random(int(x * 7 + y * 13))
    root = empty('bricks', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('bk_pallet', (1.2, 1.0, 0.14), (0, 0, 0.07), m=mm['pallet'], parent=root)
    hgt = layers or rr.choice([0.6, 0.8, 1.0])
    box('bk_block', (1.12, 0.94, hgt), (0, 0, 0.14 + hgt / 2), m=mm['brick'], parent=root, uv=1.6)
    for k in range(3):
        box('bk_strap', (1.14, 0.02, hgt + 0.01), (0, -0.3 + k * 0.3, 0.14 + hgt / 2), m=mm['metal'], parent=root)
    col((x, y, (0.14 + hgt) / 2), (1.2, 1.0, 0.14 + hgt), rotz=rot)


def wall_fountain(x, y, rot, mm):
    root = empty('cesme', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('ce_back', (2.0, 0.5, 2.6), (0, 0.25, 1.3), m=mm['marble'], parent=root, bevel=0.03)
    torus('ce_arch', 0.7, 0.1, (0, -0.02, 1.9), (90, 0, 0), m=mm['marble'], parent=root, seg=20, mseg=6, arc=180)
    box('ce_basin', (1.6, 0.7, 0.6), (0, -0.3, 0.3), m=mm['marble'], parent=root, bevel=0.04)
    box('ce_water', (1.4, 0.5, 0.02), (0, -0.3, 0.58), m=mm['water'], parent=root)
    cyl('ce_tap', 0.025, 0.2, (0, -0.1, 1.2), (90, 0, 0), m=mm['brass'] if 'brass' in mm else mm['metal'], parent=root, axis='Z', verts=8)
    box('ce_roof', (2.3, 0.8, 0.12), (0, 0.05, 2.65), m=mm['roof'], parent=root)
    c = Matrix.Rotation(math.radians(rot), 3, 'Z') @ Vector((0, 0, 0))
    col((x, y, 0.5), (2.0, 1.1, 1.0), rotz=rot)


def castle_ruins(x, y, mm, s=1.0, seed=0):
    rr = random.Random(seed)
    for k in range(7):
        a = k / 7 * math.pi * 1.2
        px, py = x + math.cos(a) * 26 * s, y + math.sin(a) * 12 * s
        hh = rr.uniform(8, 14) * s
        box('kale_wall', (12 * s, 3 * s, hh), (px, py, hh / 2), (0, 0, math.degrees(a) + 90), m=mm['stone'], uv=0.2)
        for m_ in range(5):
            box('merlon', (1.2 * s, 3.2 * s, 1.4 * s), (px + math.cos(a + math.pi / 2) * (-4.8 + m_ * 2.4) * s, py + math.sin(a + math.pi / 2) * (-4.8 + m_ * 2.4) * s, hh + 0.7 * s), (0, 0, math.degrees(a) + 90), m=mm['stone'], uv=0.3)
        if k % 2 == 0:
            cyl('kale_tower', 3.2 * s, hh + 5 * s, (px, py, (hh + 5 * s) / 2), m=mm['stone'], axis='Z', verts=16, uv=0.2)


def map_safranbolu():
    mm = begin()
    mm['ridge'] = M('ridge_tile', (0.5, 0.22, 0.14), 0.7)
    X0, X1, Y0, Y1 = -52, 52, -52, 52
    ground('base', X0 - 12, Y0 - 12, X1 + 12, Y1 + 12, 0, mm['cobble'])
    # ---- street network (centre lines, half widths)
    alleys = [
        ([(-4, -54), (-3, -38), (3, -22), (1, -8), (-5, 6), (-3, 22), (3, 38), (2, 54)], 2.6),        # main winding alley
        ([(-54, 4), (-38, 2), (-22, 6), (-5, 6)], 2.3),                                                   # west lane
        ([(1, -8), (12, -4)], 2.6),                                                                       # to the square
        ([(30, 12), (32, 28), (27, 42), (30, 54)], 2.3),                                                  # north-east lane
        ([(-3, -38), (-18, -36), (-34, -26), (-46, -12), (-54, -10)], 2.2),                               # south-west lane
        ([(36, -14), (38, -30), (32, -44), (34, -54)], 2.3),                                              # south-east lane
    ]
    SQ = (12, -16, 44, 12)    # çarşı meydanı (x0, y0, x1, y1)

    def seg_dist(p, a, b):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-6)))
        return (a + ab * t - p).length

    def clear_of_streets(pts, own=None, margin=0.4):
        for ai, (poly, hw) in enumerate(alleys):
            for i in range(len(poly) - 1):
                a, b = Vector(poly[i]), Vector(poly[i + 1])
                for p in pts:
                    if seg_dist(Vector(p), a, b) < hw + margin and not (own == (ai, i)):
                        return False
        for p in pts:
            if SQ[0] - 0.5 < p[0] < SQ[2] + 0.5 and SQ[1] - 0.5 < p[1] < SQ[3] + 0.5:
                return False
        return True

    placed = []   # footprints for overlap tests (centre, radius)
    rr = random.Random(5)
    colors = ['p_white', 'p_white', 'p_white', 'p_cream', 'p_white', 'p_rose', 'p_white', 'p_ochre']
    hn = 0
    for ai, (poly, hw) in enumerate(alleys):
        for i in range(len(poly) - 1):
            a, b = Vector(poly[i]), Vector(poly[i + 1])
            u = (b - a).normalized(); nrm = Vector((-u.y, u.x))
            L = (b - a).length
            for side in (1, -1):
                t = 1.5
                while t < L - 1.5:
                    wdt = rr.choice([7.0, 8.0, 8.5, 9.5, 10.5])
                    dep = rr.uniform(7.0, 9.0)
                    gap = rr.choice([0.0, 0.0, 2.5, 3.5])
                    if t + wdt > L - 0.5:
                        wdt = L - 0.5 - t
                    if wdt < 5.5:
                        break
                    ns = nrm * side
                    fc = a + u * (t + wdt / 2) + ns * hw          # facade centre (ground floor face)
                    corners = [fc + u * (wdt / 2) + ns * 0.2, fc - u * (wdt / 2) + ns * 0.2, fc + u * (wdt / 2) + ns * dep, fc - u * (wdt / 2) + ns * dep,
                               fc + ns * dep * 0.5, fc + u * (wdt / 2) + ns * dep * 0.5, fc - u * (wdt / 2) + ns * dep * 0.5]
                    cen = fc + ns * dep / 2
                    ok = clear_of_streets([(c.x, c.y) for c in corners], own=(ai, i))
                    ok = ok and all((cen - pc).length > pr + max(wdt, dep) * 0.45 for pc, pr in placed)
                    ok = ok and X0 + 2 < cen.x < X1 - 2 and Y0 + 2 < cen.y < Y1 - 2
                    if ok:
                        rot = math.degrees(math.atan2(-ns.x, ns.y))
                        konak2(f'sk{hn}', fc.x, fc.y, rot, wdt, dep, mm, seed=hn * 3 + 1, floors=rr.choice([1, 2, 2, 2]), color=colors[hn % len(colors)])
                        placed.append((cen, max(wdt, dep) * 0.45))
                        hn += 1
                    else:
                        gap = max(gap, 2.0)
                        wdt = min(wdt, 4.0)
                    # garden wall in the gap (keeps alleys closed and readable)
                    if gap > 0 and t + wdt + gap < L - 0.5:
                        p0 = a + u * (t + wdt + 0.1) + ns * (hw + 0.3)
                        p1 = a + u * (t + wdt + gap - 0.1) + ns * (hw + 0.3)
                        if clear_of_streets([(p0.x, p0.y), (p1.x, p1.y)], own=(ai, i), margin=0.1):
                            garden_wall(p0, p1, mm, gate=gap > 3)
                    t += wdt + gap
    # ---- Çarşı meydanı: şadırvan, çınar, arasta shops, tea garden
    sx0, sy0, sx1, sy1 = SQ
    scx, scy = (sx0 + sx1) / 2, (sy0 + sy1) / 2
    lathe('sadirvan', [(0, 0), (3.0, 0), (3.0, 0.85), (2.75, 0.85), (2.75, 0.4), (0.0, 0.4)], (scx - 4, scy, 0), m=mm['marble'], seg=16)
    for i in range(8):
        a = i / 8 * math.tau
        cyl('sd_col', 0.14, 3.0, (scx - 4 + math.cos(a) * 2.45, scy + math.sin(a) * 2.45, 1.5), m=mm['marble'], axis='Z', verts=12)
    lathe('sd_roof', [(0, 0), (3.6, 0), (0.0, 2.0)], (scx - 4, scy, 3.0), m=mm['dome'], seg=8)
    cyl('sd_water', 2.7, 0.05, (scx - 4, scy, 0.7), m=mm['water'], axis='Z', verts=24)
    col((scx - 4, scy, 0.45), (5.8, 5.8, 0.9))
    tree(scx + 1, scy + 8, mm, h=12, r=5.0, seed=3)
    # raised stone 'seki' with stairs and low parapets: an elevated fighting position over the square
    PH = 1.5
    wall('seki', 38, 2, 0, 8, 8, PH, mm['stone'])
    ground('seki_top', 34, -2, 42, 6, PH + 0.02, mm['paver'], thick=0.02, collide=False)
    stairs('seki_st', 32.4, 2, 0, PH, 3.2, 2.4, mm['marble'], axis='X', direction=1)
    for (wx, wy, sx_, sy_) in [(38, 5.85, 8, 0.3), (38, -1.85, 8, 0.3), (41.85, 2, 0.3, 8)]:
        wall('seki_par', wx, wy, PH, sx_, sy_, 0.9, mm['marble'])
    for i, key in enumerate(['lokum', 'bakir', 'kahve', 'lokum', 'bakir']):
        x = sx0 + 3 + i * ((sx1 - sx0 - 6) / 4)
        konak2(f'arasta{i}', x, sy1 + 0.5, 0, 6.2, 6, mm, seed=200 + i, floors=1, color='p_cream')
        box('ar_aw', (5.6, 1.5, 0.06), (x, sy1 - 0.4, 2.55), (15, 0, 0), m=mm['beam'])
        box('ar_sign', (3.8, 0.1, 0.55), (x, sy1 + 0.35, 2.2), m=sign_mat(key))
        box('ar_counter', (3.4, 0.8, 0.9), (x, sy1 - 0.6, 0.45), m=mm['planks'], bevel=0.02)
        col((x, sy1 - 0.6, 0.45), (3.4, 0.8, 0.9))
    for k in range(3):
        tx = sx0 + 5 + k * 3.2
        cyl('tbl', 0.4, 0.05, (tx, sy0 + 4, 0.8), m=mm['planks'], axis='Z', verts=16)
        cyl('tbl_leg', 0.04, 0.75, (tx, sy0 + 4, 0.4), m=mm['metal'], axis='Z', verts=8)
        for s2 in (-1, 1):
            box('stool', (0.34, 0.34, 0.4), (tx + s2 * 0.65, sy0 + 4, 0.2), m=mm['planks'], bevel=0.02)
    for (bx, by, r) in [(sx0 + 2, scy, 90), (sx1 - 2, scy - 6, 90)]:
        bench(bx, by, r, mm)
    wall_fountain(sx1 - 0.3, sy0 + 6, 90, mm)
    # konaks around the square (south + east edge)
    for i in range(4):
        konak2(f'sqs{i}', sx0 + 4 + i * 8.5, sy0 - 0.2, 180, 7.8, 8, mm, seed=300 + i, floors=2, color=colors[(i + 3) % len(colors)])
    konak2('sqe', sx1 + 0.2, scy - 2, -90, 10, 8, mm, seed=320, floors=2)
    # ---- alley dressing: barrels, brick stacks, crates, carts, lamps, pots
    dr = random.Random(9)
    for poly, hw in alleys:
        for i in range(len(poly) - 1):
            a, b = Vector(poly[i]), Vector(poly[i + 1])
            u = (b - a).normalized(); nrm = Vector((-u.y, u.x))
            L = (b - a).length
            t = 3.0
            while t < L - 3:
                side = dr.choice([1, -1])
                p = a + u * t + nrm * side * (hw - 0.55)
                k = dr.random()
                if k < 0.25:
                    wood_barrel(p.x, p.y, mm)
                    if dr.random() < 0.5:
                        q = p + u * 0.75
                        wood_barrel(q.x, q.y, mm)
                elif k < 0.4:
                    brick_stack(p.x, p.y, mm, math.degrees(math.atan2(u.y, u.x)))
                elif k < 0.55:
                    crate(p.x, p.y, 0, 1.0, mm, rot=dr.uniform(-10, 10))
                elif k < 0.7:
                    street_lamp(p.x, p.y, math.degrees(math.atan2(-nrm.x * side, nrm.y * side)), mm, ottoman=True)
                else:
                    flower_pot(None, p.x, p.y, 0.0, mm, dr)
                t += dr.uniform(6, 11)
    # horse cart + hay at the west lane
    hc = empty('cart', (-26, 3.2, 0)); hc.rotation_euler = (0, 0, math.radians(8))
    box('cart_bed', (3.0, 1.6, 0.15), (0, 0, 0.9), m=mm['planks'], parent=hc, bevel=0.02)
    for s2 in (-1, 1):
        box('cart_side', (3.0, 0.08, 0.5), (0, s2 * 0.78, 1.2), m=mm['planks'], parent=hc)
        torus('wheel', 0.6, 0.05, (-0.3, s2 * 0.95, 0.6), (90, 0, 0), m=mm['beam'], parent=hc, seg=24, mseg=6)
        for k in range(6):
            box('spoke', (1.2, 0.04, 0.04), (-0.3, s2 * 0.95, 0.6), (0, k * 30, 0), m=mm['beam'], parent=hc)
    box('hay', (2.4, 1.3, 0.6), (0, 0, 1.3), m=M('hay', (0.78, 0.66, 0.32), 0.9), parent=hc, bevel=0.15)
    col((-26, 3.2, 0.9), (3.2, 1.8, 1.8), rotz=8)
    # alley end caps (closed by walls so nobody walks off the map)
    for (ex, ey, r) in [(-4, -52.5, 0), (2, 52.5, 0), (-52.5, 4, 90), (30, 52.5, 0), (-52.5, -10, 90), (34, -52.5, 0)]:
        e = Vector((ex, ey))
        uu = Vector((1, 0)) if r == 0 else Vector((0, 1))
        garden_wall(e - uu * 3.2, e + uu * 3.2, mm, h=2.6)
    # ---- backyards become little gardens (grass, trees, pots) instead of empty ground
    gr = random.Random(17)
    gx = X0 + 3
    trees_n = 0
    while gx < X1 - 3:
        gy = Y0 + 3
        while gy < Y1 - 3:
            pt = Vector((gx, gy))
            far = True
            for poly, hw in alleys:
                for k in range(len(poly) - 1):
                    if seg_dist(pt, Vector(poly[k]), Vector(poly[k + 1])) < hw + 2.5:
                        far = False
            if SQ[0] - 2 < gx < SQ[2] + 2 and SQ[1] - 2 < gy < SQ[3] + 2:
                far = False
            if far and all((pt - pc).length > pr_ + 1.5 for pc, pr_ in placed):
                box('garden', (4.2, 4.2, 0.04), (gx, gy, 0.02), m=mm['grass'])
                r_ = gr.random()
                if r_ < 0.22 and trees_n < 30:
                    tree(gx + gr.uniform(-1.6, 1.6), gy + gr.uniform(-1.6, 1.6), mm, h=gr.uniform(6, 9), r=gr.uniform(2.2, 3.2), seed=gr.randint(0, 99))
                    trees_n += 1
                elif r_ < 0.32:
                    brick_stack(gx + gr.uniform(-1, 1), gy + gr.uniform(-1, 1), mm, rot=gr.choice([0, 90]))
                elif r_ < 0.40:
                    wood_barrel(gx + gr.uniform(-1, 1), gy + gr.uniform(-1, 1), mm, lying=gr.random() < 0.4, rot=gr.randint(0, 180))
                # low dry-stone garden walls on some cell edges: cover + narrow passages between yards
                for (ex, ey, sx_, sy_) in ((gx + 2.1, gy, 0.45, 4.2), (gx, gy + 2.1, 4.2, 0.45)):
                    if gr.random() < 0.28:
                        e = Vector((ex, ey))
                        ok = all((e - pc).length > pr_ + 1.0 for pc, pr_ in placed)
                        for poly, hw in alleys:
                            for k in range(len(poly) - 1):
                                if seg_dist(e, Vector(poly[k]), Vector(poly[k + 1])) < hw + 2.2:
                                    ok = False
                        if ok:
                            L_ = gr.uniform(2.4, 3.6)
                            wall('gwall', ex, ey, 0, L_ if sx_ > 1 else sx_, L_ if sy_ > 1 else sy_, gr.choice([1.1, 1.3, 1.6]), mm['stone'])
            gy += 4.2
        gx += 4.2
    # ---- closed outer ring of houses right behind the map border (no empty horizon)
    for k in range(12):
        xx = X0 + 4 + k * 8.9
        konak2(f'ringN{k}', xx, Y1 + 2.5, 0, 8.4, 8, mm, seed=800 + k, floors=2, collide=False, color=colors[k % len(colors)])
        konak2(f'ringS{k}', xx, Y0 - 2.5, 180, 8.4, 8, mm, seed=820 + k, floors=2, collide=False, color=colors[(k + 2) % len(colors)])
        yy = Y0 + 4 + k * 8.9
        konak2(f'ringE{k}', X1 + 2.5, yy, -90, 8.4, 8, mm, seed=840 + k, floors=2, collide=False, color=colors[(k + 4) % len(colors)])
        konak2(f'ringW{k}', X0 - 2.5, yy, 90, 8.4, 8, mm, seed=860 + k, floors=2, collide=False, color=colors[(k + 5) % len(colors)])
    # ---- backdrop: castle on the hill, mosque with minaret, distant houses, hills
    castle_ruins(-30, 95, mm, 1.0, 1)
    mosque(48, 78, 1.0, mm, 1)
    mosque(-70, -70, 0.8, mm, 1)
    for i in range(10):
        a = i / 10 * math.tau
        sphere('hill', 45, (math.cos(a) * 150, math.sin(a) * 150, -12), m=mm['grass'], seg=16, rings=8, scale=(1.4, 1.0, 0.55))
    for i in range(22):
        a = i / 22 * math.tau + 0.1
        rr2 = 68 + (i % 3) * 9
        konak2(f'bg{i}', math.cos(a) * rr2, math.sin(a) * rr2, math.degrees(a) + 90, 9, 8, mm, seed=600 + i, floors=2, collide=False)
    # ---- spawns: always on alley centre lines
    def on_alley(ai, f):
        poly = [Vector(q) for q in alleys[ai][0]]
        lens = [(poly[k + 1] - poly[k]).length for k in range(len(poly) - 1)]
        tot = sum(lens); d = f * tot
        for k, Lk in enumerate(lens):
            if d <= Lk:
                pt = poly[k] + (poly[k + 1] - poly[k]).normalized() * d
                dirv = (poly[k + 1] - poly[k]).normalized()
                return pt, dirv
            d -= Lk
        return poly[-1], (poly[-1] - poly[-2]).normalized()

    def yaw_of(v):
        return math.degrees(math.atan2(-v.x, v.y)) + 180
    team_a = [(0, 0.06, 1), (0, 0.12, 1), (4, 0.35, -1), (4, 0.6, -1), (5, 0.85, -1), (5, 0.7, -1)]
    team_b = [(0, 0.94, -1), (0, 0.86, -1), (0, 0.76, -1), (3, 0.9, -1), (3, 0.6, -1), (1, 0.15, 1)]
    for team, lst in (('a', team_a), ('b', team_b)):
        for (ai, f, sgn) in lst:
            pt, dv = on_alley(ai, f)
            spawn(pt.x, pt.y, 0.1, yaw_of(dv * sgn) + 180, team)
    for (px, py) in [(scx, scy - 6), (scx + 6, scy - 8)]:
        spawn(px, py, 0.1, 0, None)
    pt, dv = on_alley(1, 0.6); spawn(pt.x, pt.y, 0.1, 90, None)
    bounds_walls(X0, Y0, X1, Y1, 16)
    finalize('safranbolu', dict(preset='day', sun=[-50, 140], fog=0.004, sky='clear'), [X0, Y0, X1, Y1])



# ======================================================================== MAP 3: GEMİ (cargo ship)
def map_gemi():
    mm = begin()
    L, W = 164, 32
    HX = L / 2
    D = 0.0  # deck height
    # hull (visual)
    # hull top sits just under the deck plate (it used to stick 2.5 m above it and hid the deck from upper floors)
    hp = [(-L / 2, -8), (L / 2 - 14, -8), (L / 2, -2), (L / 2 + 4, -0.12), (L / 2 - 2, -0.12), (-L / 2, -0.12)]
    prof('hull', [(p[0], p[1]) for p in hp], W, (0, 0, 0), (0, 0, 90), m=mm['hull_red'], plane='YZ', bevel=0.2)
    # Easier: build hull along X: use plane 'XZ' extrude along Y
    bpy.data.objects.remove(bpy.data.objects['hull'], do_unlink=True)
    prof('hull', hp, W, m=mm['hull_dark'], plane='XZ', bevel=0.3)
    box('boot', (L + 2, W + 0.2, 2.5), (0, 0, -6.6), m=mm['hull_red'])
    # deck plate
    ground('deck', -L / 2 + 1, -W / 2 + 0.5, L / 2 - 1, W / 2 - 0.5, D, mm['ship_green'], thick=0.4)
    box('deckline', (L, W - 1, 0.01), (0, 0, D + 0.005), m=mm['ship_green'])
    # railings (with invisible tall walls)
    for s in (-1, 1):
        y = s * (W / 2 - 0.4)
        box('bulwark', (L - 2, 0.15, 1.1), (0, y, D + 0.55), m=mm['ship_white'])
        for i in range(0, int(L) - 4, 3):
            box('rail_post', (0.06, 0.06, 0.5), (-L / 2 + 3 + i, y, D + 1.35), m=mm['ship_white'])
        box('rail_top', (L - 2, 0.06, 0.06), (0, y, D + 1.6), m=mm['ship_white'])
        col((0, y, D + 3), (L, 0.4, 6))
    col((-L / 2 + 0.5, 0, D + 3), (0.6, W, 6))
    col((L / 2 - 0.5, 0, D + 3), (0.6, W, 6))
    # forecastle (bow) raised deck x 44..59 at +2.8
    F = 2.8
    fc0, fc1 = HX - 17, HX - 1
    wall('fcastle', (fc0 + fc1) / 2, 0, D, fc1 - fc0, W - 1, F, mm['ship_white'])
    ground('fc_top', fc0, -W / 2 + 0.5, fc1, W / 2 - 0.5, D + F + 0.05, mm['deck'], 0.05, collide=False)
    stairs('fc_st1', fc0 - 2.5, -9, D, D + F, 5, 2, mm['steel'], axis='X', direction=1)
    stairs('fc_st2', fc0 - 2.5, 9, D, D + F, 5, 2, mm['steel'], axis='X', direction=1)
    for (cx, cy) in [(fc0 + 6, -7), (fc0 + 6, 7)]:
        cyl('windlass', 1.0, 1.6, (cx, cy, D + F + 1.0), m=mm['ship_yellow'], axis='Y', verts=20)
        col((cx, cy, D + F + 1.0), (2, 1.6, 2))
    cyl('mast_f', 0.4, 12, (fc1 - 4, 0, D + F + 6), m=mm['ship_yellow'], axis='Z', verts=16)
    # superstructure (stern), 5 levels
    sx0, sx1 = -HX + 2, -HX + 20
    levels = 5
    lh = 3.0
    for lv in range(levels):
        shrink = 0 if lv == 0 else 1.5
        wy = W - 7 - shrink * 2
        wall(f'ss{lv}', (sx0 + sx1) / 2 - lv * 0.3, 0, D + lv * lh, sx1 - sx0 - lv * 0.6, wy, lh, mm['ship_white'], collide=(lv < 2))
        for k in range(int(wy / 2.2)):
            window(empty('ssw', (sx1 - lv * 0.3 + 0.0, -wy / 2 + 1.1 + k * 2.2, 0)), 0, 0, 0.8, 0.9, mm, depth=0) if False else None
        # windows on front face (facing +X)
        for k in range(int(wy / 2.2)):
            yy = -wy / 2 + 1.1 + k * 2.2
            box('sswin', (0.05, 1.2, 0.9), (sx1 - lv * 0.3 + 0.01 - lv * 0.3 + (lv * 0.3), yy, D + lv * lh + 1.8), m=mm['glass'] if lv < 4 else mm['glass_lit'])
    col(((sx0 + sx1) / 2, 0, D + 2 * lh + 4.5), (sx1 - sx0, W - 7, 9))
    # bridge wings and funnel
    box('bridge_wing', (4, W + 1, 0.3), (sx1 - 3, 0, D + 5 * lh), m=mm['ship_white'])
    box('funnel', (5, 4, 9), (sx0 + 3, 0, D + 5 * lh + 4.5), m=mm['ship_orange'], bevel=0.4)
    box('funnel_top', (5.1, 4.1, 1.2), (sx0 + 3, 0, D + 5 * lh + 8.4), m=mm['black'], bevel=0.3)
    cyl('radar_mast', 0.2, 6, (sx1 - 6, 0, D + 5 * lh + 3), m=mm['ship_white'], axis='Z', verts=8)
    box('radar', (0.3, 3, 0.2), (sx1 - 6, 0, D + 5 * lh + 6), m=mm['black'])
    # playable external walkway level 1 (+3.0) on both sides of superstructure with stairs
    P = lh
    for s in (-1, 1):
        y = s * (W / 2 - 1.75)
        wall(f'walk{s}', (sx0 + sx1) / 2, y, D + P - 0.2, sx1 - sx0, 2.2, 0.2, mm['steel'])
        box(f'walkrail{s}', (sx1 - sx0, 0.05, 1.0), ((sx0 + sx1) / 2, y + s * 1.05, D + P + 0.5), m=mm['ship_white'])
        stairs(f'ss_st{s}', sx1 + 3.25, y, D, D + P, 6.5, 2.0, mm['steel'], axis='X', direction=-1)
    wall('aftdeck', (sx1 + 1.5), 0, D + P - 0.2, 3, W - 7, 0.2, mm['steel'])  # front balcony of superstructure
    box('aftrail', (0.05, W - 4, 1.0), (sx1 + 3, 0, D + P + 0.5), m=mm['ship_white'])
    col((sx1 + 3, 0, D + P + 0.5), (0.1, W - 8, 1.0))
    # container bays: rows along X with corridors; stacks of 1-3
    cmats = [mm['c_red'], mm['c_blue'], mm['c_orange'], mm['c_green'], mm['c_grey'], mm['c_yellow'], mm['c_white']]
    bays = [-50, -42, -28, -20, -6, 2, 16, 24, 38, 46]
    rows = [-W / 2 + 3.4, -W / 2 + 6.0, -2.5, 2.5, W / 2 - 6.0, W / 2 - 3.4]
    rr = random.Random(5)
    for bi, bx in enumerate(bays):
        for ri, ry in enumerate(rows):
            if rr.random() < 0.18:
                continue
            h = rr.choice([1, 1, 2, 2, 3]) if abs(ry) > 5 else rr.choice([1, 2])
            for k in range(h):
                container(bx, ry, D + k * 2.59, 90, cmats[rr.randrange(len(cmats))], mm, collide=(k == 0), length=6.06)
            col((bx, ry, D + h * 2.59 / 2), (6.06, 2.44, h * 2.59))
    # hatch covers (low cover)
    for hx in (-35, -13, 9, 31):
        wall('hatch', hx, 0, D, 6, 11, 1.0, mm['ship_green'])
        box('hatch_rim', (6.2, 11.2, 0.15), (hx, 0, D + 1.0), m=mm['ship_yellow'])
    # containers lashed on two hatch covers: break the long centre and side lanes
    for hx, ys in ((-13, (0.0, 4.4)), (31, (-4.4, 0.0))):
        for k, hy in enumerate(ys):
            container(hx, hy, D + 1.0, 90, cmats[(k + hx) % len(cmats)], mm, collide=True, length=6.06)
            col((hx, hy, D + 1.0 + 1.3), (6.06, 2.44, 2.59))
    # cranes (pedestal + jib)
    for cx in (-35, -13, 9, 31):
        cy = W / 2 - 2.2
        cyl('crane_ped', 1.2, 9, (cx, cy, D + 4.5), m=mm['ship_yellow'], axis='Z', verts=20)
        col((cx, cy, D + 4.5), (2.4, 2.4, 9))
        box('crane_cab', (3, 3, 2.5), (cx, cy, D + 10), m=mm['ship_yellow'], bevel=0.2)
        # jib hinged at the cab, rising 25 deg out over the deck (it used to float detached)
        ang = math.radians(25)
        box('crane_jib', (0.8, 24, 0.8), (cx, cy - 1.2 - 12 * math.cos(ang), D + 10.6 + 12 * math.sin(ang)), (-25, 0, 0), m=mm['ship_yellow'])
        cyl('crane_hinge', 0.55, 2.2, (cx, cy - 1.2, D + 10.6), m=mm['steel'], axis='X', verts=16)
        box('crane_cwt', (2.4, 1.6, 1.6), (cx, cy + 1.6, D + 10.8), m=mm['ship_yellow'], bevel=0.1)
        tip = (cx, cy - 1.2 - 24 * math.cos(ang), D + 10.6 + 24 * math.sin(ang))
        cyl('crane_wire', 0.04, tip[2] - D - 3.5, (tip[0], tip[1], (tip[2] + D + 3.5) / 2), m=mm['black'], axis='Z', verts=6)
        box('crane_hook', (0.5, 0.5, 0.7), (tip[0], tip[1], D + 3.3), m=mm['ship_yellow'])
    # misc deck props
    for (bx, by) in [(-56, -9), (-56, 9), (54, -7), (54, 8), (14, -4), (-14, 5)]:
        cyl('bollard', 0.3, 0.6, (bx, by, D + 0.3), m=mm['black'], axis='Z', verts=12)
    for (cx, cy) in [(-46, 0), (42, 0), (-24, 0), (20, 0), (-2, 0)]:
        crate(cx, cy, D, 1.2, mm)
        crate(cx + 1.25, cy + 0.3, D, 1.0, mm, rot=15)
    sandbags(-2, 1.0, 3, 3, mm, 0)
    cyl('lifeboat', 1.2, 7, (sx0 + 6, W / 2 + 0.5, D + 2 * lh + 1), m=mm['ship_orange'], axis='X', verts=16)
    # water plane
    box('sea', (2000, 2000, 0.1), (0, 0, -6.0), m=mm['water'])
    # spawns
    for i, (x, y, z, yaw) in enumerate([(-58, -12, 0, -90), (-58, 12, 0, -90), (-60, 0, 0, -90), (-70, W / 2 - 1.7, P, -90), (-70, -W / 2 + 1.7, P, -90), (-54, 4.5, 0, -90),
                                         (56, -12, 0, 90), (56, 12, 0, 90), (fc0 + 10, 0, F, 90), (54, 4, 0, 90), (52, -4.5, 0, 90), (fc0 + 12, 6, F, 90)]):
        spawn(x, y, z + 0.2, yaw + 90, 'a' if i < 6 else 'b')
    finalize('gemi', dict(preset='sunset', sun=[-6, 280], fog=0.004, sky='sunset', water=True), [-L / 2, -W / 2, L / 2, W / 2])


# ======================================================================== MAP 4: LİMAN DEPOSU
def map_liman():
    mm = begin()
    X0, X1, Y0, Y1 = -48, 48, -40, 40
    ground('yard', X0 - 10, Y0 - 10, X1 + 10, Y1 + 10, 0, mm['asphalt'])
    # quay edge east with water
    box('quay', (4, 120, 1), (X1 + 6, 0, -0.5), m=mm['concrete'])
    box('sea', (2000, 2000, 0.1), (900 + X1 + 8, 0, -2.5), m=mm['water'])
    # painted lines
    for i in range(-40, 41, 8):
        box('line', (0.15, 70, 0.01), (i, 0, 0.005), m=M('paint_line', (0.85, 0.75, 0.1), 0.6))
    # warehouse (north-west) enterable
    wx, wy, ww, wd, wh = -26, 22, 34, 22, 9
    t = 0.4
    wm = M('warehouse_wall', (0.55, 0.57, 0.6), 0.6, 0.4)
    wall('wh_n', wx, wy + wd / 2, 0, ww, t, wh, wm)
    wall('wh_w', wx - ww / 2, wy, 0, t, wd, wh, wm)
    wall('wh_e', wx + ww / 2, wy, 0, t, wd, wh, wm)
    # south wall with 2 big doors
    seg = [(-17, -11), (-5, 3), (11, 17)]
    for (a, b) in seg:
        wall('wh_s', wx + (a + b) / 2, wy - wd / 2, 0, b - a, t, wh, wm)
    for (a, b) in [(-11, -5), (3, 11)]:
        box('wh_lintel', (b - a, t, 2.5), (wx + (a + b) / 2, wy - wd / 2, wh - 1.25), m=wm)
        box('wh_shutter', (b - a, 0.1, 1.2), (wx + (a + b) / 2, wy - wd / 2 - 0.1, wh - 3.1), m=mm['shutter'])
    hip_roof('wh_roof', wx, wy, ww, wd, wh, 2.5, M('warehouse_roof', (0.4, 0.42, 0.45), 0.5, 0.5), 0.6)
    box('wh_floor', (ww, wd, 0.05), (wx, wy, 0.02), m=mm['concrete'])
    box('wh_sign', (10, 0.2, 1.6), (wx, wy - wd / 2 - 0.25, wh - 0.9), m=sign_mat('depo'))
    for i in range(4):
        box('skylight', (2, 8, 0.1), (wx - 12 + i * 8, wy, wh + 1.3), (0, 0, 0), m=mm['glass_lit'])
    # interior shelves (racks) with boxes
    for i in range(3):
        rx = wx - 10 + i * 9
        for s in (-1, 1):
            cyl_y = wy + 4
        for k in range(2):
            ry = wy + 2 + k * 5
            box('rack', (6, 1.2, 0.1), (rx, ry, 1.6), m=mm['ship_orange'])
            box('rack2', (6, 1.2, 0.1), (rx, ry, 3.2), m=mm['ship_orange'])
            for px in (-2.9, 2.9):
                for py in (-0.55, 0.55):
                    box('rack_post', (0.1, 0.1, 4.5), (rx + px, ry + py, 2.25), m=mm['ship_blue'] if False else mm['c_blue'])
            for b in range(4):
                crate(rx - 2.2 + b * 1.45, ry, 0.0, 1.1, mm, collide=False)
                if (b + i) % 2 == 0:
                    crate(rx - 2.2 + b * 1.45, ry, 1.65, 1.0, mm, collide=False)
            col((rx, ry, 2.25), (6, 1.3, 4.5))
    # forklift inside
    fk = empty('forklift', (wx + 10, wy - 6, 0)); fk.rotation_euler = (0, 0, math.radians(30))
    box('fk_body', (1.2, 2.2, 1.2), (0, 0, 0.9), m=mm['ship_yellow'], parent=fk, bevel=0.1)
    box('fk_cage', (1.1, 1.0, 1.2), (0, -0.3, 2.1), m=mm['black'], parent=fk)
    box('fk_mast', (1.0, 0.15, 2.8), (0, 1.15, 1.4), m=mm['black'], parent=fk)
    for s in (-0.3, 0.3):
        box('fk_fork', (0.12, 1.2, 0.06), (s, 1.8, 0.15), m=mm['steel'], parent=fk)
    col((wx + 10, wy - 6, 1.1), (1.4, 2.6, 2.2), rotz=30)
    # catwalk inside warehouse (east side) +3.5 with stairs
    wall('catwalk', wx + 14.5, wy, 3.3, 4, wd - 1, 0.2, mm['steel'])
    box('cw_rail', (0.05, wd - 1, 1.0), (wx + 12.5, wy, 4.0), m=mm['ship_yellow'])
    col((wx + 12.5, wy - 2, 4.0), (0.1, wd - 6, 1.0))
    stairs('cw_st', wx + 14.5, wy - wd / 2 + 3.5, 0, 3.5, 6, 2.5, mm['steel'], axis='Y', direction=-1)
    # container yard (south + east)
    cmats = [mm['c_red'], mm['c_blue'], mm['c_orange'], mm['c_green'], mm['c_grey'], mm['c_yellow'], mm['c_white']]
    rr = random.Random(11)
    for rowi, ry in enumerate([-34, -27, -20, -13, -6]):
        for ci, cx in enumerate([-40, -32.5, -25, -12, -4.5, 3, 16, 23.5, 31, 40]):
            if rr.random() < 0.2:
                continue
            h = rr.choice([1, 1, 2, 2, 3])
            for k in range(h):
                container(cx, ry, k * 2.59, 0 if rowi % 2 else 0, cmats[rr.randrange(len(cmats))], mm, collide=False)
            col((cx, ry, h * 2.59 / 2), (2.44, 6.06, h * 2.59))
    for (cx, cy, r) in [(8, 4, 90), (8, 10, 90), (30, 12, 90), (30, 20, 90), (36, 30, 0)]:
        container(cx, cy, 0, r, cmats[rr.randrange(len(cmats))], mm)
    container(8, 7, 2.59, 90, mm['c_blue'], mm, collide=False)
    col((8, 7, 2.59 + 1.3), (6.06, 2.44, 2.59))
    # gantry crane over yard (visual)
    for sx in (-30, 30):
        for sy in (-38, 0):
            box('gantry_leg', (1.2, 1.2, 22), (sx, sy, 11), m=mm['ship_yellow'])
            col((sx, sy, 11), (1.2, 1.2, 22))
    box('gantry_beam', (62, 2, 2.5), (0, -38, 22), m=mm['ship_yellow'])
    box('gantry_beam2', (62, 2, 2.5), (0, 0, 22), m=mm['ship_yellow'])
    box('trolley', (4, 40, 1.5), (10, -19, 20.5), m=mm['ship_yellow'])
    # trucks
    truck(20, -2, 0, mm, mm['c_green'])
    truck(-8, 2, 90, mm, mm['c_red'])
    # yard dressing: pallets, cable reels, cones, jersey barriers, light towers, puddles and oil stains
    for (px, py, n, r) in [(-30, 4, 6, 10), (-28.5, 4.2, 4, -5), (12, -9.5, 7, 30), (34, 6, 5, 0), (-42, 10, 8, 90), (4, 30, 6, 15)]:
        pallet_stack(px, py, n, mm, r)
    for (rx, ry) in [(-14, 8), (27, -9), (-40, -8)]:
        cable_reel(rx, ry, mm)
    for (cx, cy) in [(-4, -9.5), (-2.5, -9.6), (-1, -9.5), (18, 6), (19.5, 6.2), (42, 0), (42, -2)]:
        cone(cx, cy)
    for (jx, jy, r) in [(-10, -9.5, 90), (28, -16, 0), (-32, -9.5, 90)]:
        jersey(jx, jy, r, mm)
    for (lx, ly) in [(-46, -38), (46, -38), (-46, 0), (46, 34), (0, -39)]:
        light_tower(lx, ly, mm)
    pr = random.Random(21)
    for k in range(16):
        decal_plane(pr.uniform(X0 + 4, X1 - 4), pr.uniform(Y0 + 3, -8), 0.0, pr.uniform(2, 5), pr.uniform(1.5, 3.5), pr.choice(['puddle', 'oilstain']), pr.uniform(0, 3))
    # misc cover
    for (bx, by) in [(-2, -2), (14, -8), (-20, 4), (38, -10)]:
        barrel(bx, by, mm, rr.choice(['blue', 'red', 'yellow'])); barrel(bx + 0.7, by, mm, 'blue')
    for (cx, cy) in [(-36, 6), (24, 30), (0, 28), (-44, -2)]:
        crate(cx, cy, 0, 1.2, mm); crate(cx, cy + 1.25, 0, 1.2, mm, 5); crate(cx, cy + 0.6, 1.2, 1.0, mm, 20)
    for (sx, sy, r) in [(-18, -2, 0), (2, 16, 90), (24, 4, 0)]:
        sandbags(sx, sy, 4, 3, mm, r)
    for (bx, by) in [(X1 - 1, -30), (X1 - 1, -10), (X1 - 1, 10), (X1 - 1, 30)]:
        cyl('bollard', 0.35, 0.8, (bx + 4, by, 0.4), m=mm['black'], axis='Z', verts=12)
    # office block (west) visual + perimeter fence
    apartment('office', -46, -18, -90, 16, 6, 3, mm, mm['p_grey'], seed=7, roof='flat')
    # closed perimeter: stacked container walls (no view into the void)
    pr2 = random.Random(41)
    for xx in [X0 + 3 + k * 6.2 for k in range(int((X1 - X0) / 6.2))]:
        for (yy, r) in ((Y1 + 2.0, 90), (Y0 - 2.0, 90)):
            for k in range(pr2.choice([2, 3, 3])):
                container(xx, yy, k * 2.59, r, cmats[pr2.randrange(len(cmats))], mm, collide=False)
    for yy in [Y0 + 3 + k * 6.2 for k in range(int((Y1 - Y0) / 6.2))]:
        for k in range(pr2.choice([2, 3])):
            container(X0 - 2.0, yy, k * 2.59, 0, cmats[pr2.randrange(len(cmats))], mm, collide=False)
    # elevated container platform with stairs + cover on top
    container(16, 22, 0, 0, mm['c_blue'], mm)
    container(18.5, 22, 0, 0, mm['c_orange'], mm)
    stairs('lc_st', 16.0, 16.9, 0, 2.6, 4.2, 2.2, mm['steel'], axis='Y', direction=1)
    crate(18.5, 24.2, 2.59, 1.0, mm)
    crate(15.6, 24.4, 2.59, 1.0, mm, rot=12)
    for (jx, jy, r) in [(0, -2, 90), (-24, -9.5, 90), (6, 14, 0), (38, 2, 0)]:
        jersey(jx, jy, r, mm)
    for i in range(6):
        street_lamp(-40 + i * 16, Y0 + 2, 0, mm)
    box('liman_sign', (14, 0.3, 2), (0, Y1 + 1.2, 4), m=sign_mat('liman'))
    # distant ship at quay
    box('bg_ship', (12, 110, 14), (X1 + 16, 0, 3), m=mm['hull_dark'])
    box('bg_ship_super', (10, 12, 10), (X1 + 16, -45, 15), m=mm['ship_white'])
    for i in range(5):
        container(X1 + 16, -30 + i * 14, 10, 0, cmats[i], mm, collide=False)
    # spawns
    for i, (x, y, z, yaw) in enumerate([(-30, 26, 0, 180), (-20, 18, 0, 180), (-36, 16, 0, 90), (-31.5, 30, 0, 180), (-14, 28, 0, 180), (-22.5, 23, 0, 90),
                                         (40, -36, 0, 0), (12, -36, 0, 0), (-5, -38, 0, 0), (25, -38, 0, 0), (-30, -36, 0, 30), (44, -24, 0, -30)]):
        spawn(x, y, z + 0.1, yaw, 'a' if i < 6 else 'b')
    bounds_walls(X0, Y0, X1, Y1, 20)
    # west lane: 2-high stack across the gap between the warehouse door and the container yard
    for k, cm in enumerate(('c_blue', 'c_red')):
        container(-30.5, 3.2, k * 2.59, 90, mm[cm], mm, collide=(k == 0), length=6.06)
    col((-30.5, 3.2, 2.59), (6.06, 2.44, 5.18))
    finalize('liman', dict(preset='overcast', sun=[-40, 120], fog=0.012, sky='overcast', water=True), [X0, Y0, X1, Y1])


# ======================================================================== user props (USD) placed in maps
PROPS = {
    'cosmo': ('/home/claude/ext3d/new/8845cf3c-Eunos_Cosmo_1990/scene.usdc', 4.82),
    'sr5': ('/home/claude/ext3d/new/357cd1a1-SR-5_GMLRS__MWT_Tank_Battles/scene.usdc', 10.5),
}


def usd_prop(key, x, y, rot, collide=True, z=0.0):
    """import a user supplied USD model, scale its length, keep its textured materials (ext_ prefix)"""
    path, length = PROPS[key]
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    dg = bpy.context.evaluated_depsgraph_get()
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = mx - mn
    s = length / max(size.x, size.y)
    long_x = size.x > size.y
    root = empty('prop_' + key, (x, y, z))
    root.rotation_euler = (0, 0, math.radians(rot + (90 if long_x else 0)))
    ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = Matrix.Scale(s, 4) @ Matrix.Translation(-ctr) @ mw
        for sl in o.material_slots:
            if sl.material and not sl.material.name.startswith('ext_'):
                sl.material.name = 'ext_%s_%s' % (key, sl.material.name)
    # props render opaque (alpha-blended chunks of a merged map mesh sort badly and are expensive)
    for o in meshes:
        for sl in o.material_slots:
            mt = sl.material
            if mt and mt.node_tree:
                for nd in mt.node_tree.nodes:
                    if nd.type == 'BSDF_PRINCIPLED':
                        for lk in list(nd.inputs['Alpha'].links):
                            mt.node_tree.links.remove(lk)
                        nd.inputs['Alpha'].default_value = 1.0
                try:
                    mt.surface_render_method = 'DITHERED'
                except Exception:
                    pass
                mt.use_backface_culling = True
    # props are scenery: cap their textures at 512 px (keeps VRAM and download size down)
    for o in meshes:
        for sl in o.material_slots:
            if sl.material and sl.material.node_tree:
                for nd in sl.material.node_tree.nodes:
                    im = getattr(nd, 'image', None)
                    if im and not im.get('capped') and max(im.size) > 512:
                        f = 512 / max(im.size)
                        im.scale(max(1, int(im.size[0] * f)), max(1, int(im.size[1] * f)))
                        im['capped'] = True
    for o in new:
        if o.type != 'MESH' and o is not root and o.name in bpy.data.objects:
            if not o.children:
                bpy.data.objects.remove(o)
    if collide:
        w, l, h = (size.y if long_x else size.x) * s, max(size.x, size.y) * s, size.z * s
        col((x, y, z + h / 2), (w * 0.95, l * 0.95, h), rotz=rot)
    return root


def fence_panel(x, y, rot, mm, length=3.4):
    root = empty('fence', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for s_ in (-1, 1):
        box('f_foot', (0.25, 0.6, 0.12), (s_ * length / 2, 0, 0.06), m=mm['concrete'], parent=root)
        cyl('f_post', 0.025, 2.0, (s_ * length / 2, 0, 1.0), m=mm['steel'], parent=root, axis='Z', verts=6)
    box('f_mesh', (length, 0.02, 1.9), (0, 0, 1.05), m=M('fence_mesh', (0.75, 0.78, 0.8), 0.4, 0.8), parent=root)
    box('f_banner', (length * 0.95, 0.03, 0.9), (0, -0.02, 1.0), m=M('fence_banner', (0.1, 0.32, 0.55), 0.7), parent=root)


def hoarding(x0, y0, x1, y1, mm, h=5.2, gate=None):
    """v4.2: solid construction-site hoarding around the whole map (no more see-through fence):
    corrugated sheet panels on a concrete kerb, steel posts, a yellow/black safety stripe and
    printed site banners. gate=(side, centre, width) leaves a closed double gate."""
    panel_m = [M('container_blue', (0.1, 0.27, 0.58), 0.6), M('container_grey', (0.52, 0.54, 0.55), 0.6)]
    stripe = M('site_sign', (0.95, 0.75, 0.1), 0.5)
    dark = M('hoard_dark', (0.06, 0.06, 0.07), 0.7)
    banner = M('fence_banner', (0.1, 0.32, 0.55), 0.7)
    def run(ax, ay, bx, by, inward):
        L = math.hypot(bx - ax, by - ay)
        rot = math.degrees(math.atan2(by - ay, bx - ax))
        n = max(1, int(round(L / 3.0)))
        seg = L / n
        for i in range(n):
            t = (i + 0.5) / n
            cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
            m = panel_m[0] if (i // 4) % 2 == 0 else panel_m[1]
            box('hd_panel', (seg - 0.04, 0.12, h - 0.5), (cx, cy, 0.5 + (h - 0.5) / 2), (0, 0, rot), m=m, uv=0.6)
            box('hd_kerb', (seg, 0.35, 0.5), (cx, cy, 0.25), (0, 0, rot), m=mm['concrete'])
            box('hd_post', (0.14, 0.3, h + 0.2), (ax + (bx - ax) * i / n, ay + (by - ay) * i / n, (h + 0.2) / 2), (0, 0, rot), m=mm['steel'])
            # safety stripe band along the top
            for k in range(3):
                box('hd_stripe', (seg / 6 - 0.02, 0.14, 0.32), (cx + math.cos(math.radians(rot)) * (k - 1) * seg / 3, cy + math.sin(math.radians(rot)) * (k - 1) * seg / 3, h - 0.25), (0, 0, rot + 0), m=stripe)
            box('hd_top', (seg, 0.16, 0.08), (cx, cy, h + 0.02), (0, 0, rot), m=dark)
            if i % 4 == 1 and i + 2 < n:
                ox, oy = -math.sin(math.radians(rot)) * inward * 0.09, math.cos(math.radians(rot)) * inward * 0.09
                bm = M('poster_site%d' % (1 + (i // 4) % 2), (0.8, 0.8, 0.8), 0.7)
                bz = box('hd_banner', (5.2, 0.03, 1.9), (cx + ox + math.cos(math.radians(rot)) * seg * 0.5, cy + oy + math.sin(math.radians(rot)) * seg * 0.5, 2.5), (0, 0, rot), m=bm)
                bz['normuv'] = True
        col(((ax + bx) / 2, (ay + by) / 2, h / 2), (L + 0.3, 0.4, h), rotz=rot)
    run(x0, y1, x1, y1, -1)
    run(x0, y0, x1, y0, 1)
    run(x0, y0, x0, y1, 1)
    run(x1, y0, x1, y1, -1)
    for (cx, cy) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]:
        box('hd_corner', (0.5, 0.5, h + 0.4), (cx, cy, (h + 0.4) / 2), m=mm['concrete'])


def formwork_column(x, y, mm, h=3.4, rot=0):
    """red steel column formwork with a concrete cap and rebar sticking out (cover pillar)"""
    fm = M('poster_formwork', (0.8, 0.8, 0.8), 0.55, 0.3)
    b = box('fw_col', (1.3, 1.3, h), (x, y, h / 2), (0, 0, rot), m=fm); b['normuv'] = True
    box('fw_cap', (1.42, 1.42, 0.22), (x, y, h + 0.11), (0, 0, rot), m=mm['concrete'])
    for dx in (-0.45, -0.15, 0.15, 0.45):
        for dy in (-0.45, 0.45):
            cyl('fw_rebar', 0.018, 0.9, (x + dx, y + dy, h + 0.65), m=M('rebar_rust', (0.35, 0.18, 0.1), 0.8, 0.6), axis='Z', verts=5)
    col((x, y, h / 2), (1.3, 1.3, h), rotz=rot)


def block_stack(x, y, sx, sy, sz, rot=0):
    """pallet-stacked hollow concrete blocks"""
    bm = M('poster_blocks', (0.8, 0.8, 0.8), 0.9)
    b = box('blocks', (sx, sy, sz), (x, y, 0.12 + sz / 2), (0, 0, rot), m=bm); b['normuv'] = True
    box('blk_pallet', (sx, sy, 0.12), (x, y, 0.06), (0, 0, rot), m=M('pallet_wood', (0.55, 0.42, 0.28), 0.9))
    col((x, y, (sz + 0.12) / 2), (sx, sy, sz + 0.12), rotz=rot)


def sand_pile(x, y, r, h, m):
    cyl('sand', r, h, (x, y, h / 2), m=m, axis='Z', verts=18, r2=r * 0.15)
    col((x, y, h * 0.35), (r * 1.3, r * 1.3, h * 0.7))


def rebar_bundle(x, y, rot, mm, n=14, length=6):
    root = empty('rebar', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    rm = M('rebar_rust', (0.35, 0.18, 0.1), 0.8, 0.6)
    for i in range(n):
        cyl('rb', 0.012, length, ((i % 7) * 0.05 - 0.15, 0, 0.15 + (i // 7) * 0.05), m=rm, parent=root, axis='Y', verts=5)
    for k in (-2, 0, 2):
        box('rb_wood', (0.5, 0.1, 0.1), (0, k, 0.05), m=mm['planks'], parent=root)


def tower_crane(x, y, mm, h=34, jib=36):
    cm = M('crane_yellow', (0.95, 0.68, 0.05), 0.5, 0.3)
    box('crane_base', (4.5, 4.5, 1.2), (x, y, 0.6), m=mm['concrete'])
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('cr_leg', (0.2, 0.2, h), (x + sx * 0.8, y + sy * 0.8, h / 2), m=cm)
    for k in range(int(h / 2)):
        z = k * 2 + 1
        for sy in (-1, 1):
            box('cr_x', (1.6, 0.1, 0.1), (x, y + sy * 0.8, z), (0, 35 if k % 2 else -35, 0), m=cm)
            box('cr_y', (0.1, 1.6, 0.1), (x + sy * 0.8, y, z), (35 if k % 2 else -35, 0, 0), m=cm)
    box('cr_cab', (2.2, 2.4, 2.2), (x + 1.6, y, h + 1.1), m=cm, bevel=0.1)
    box('cr_cab_win', (0.05, 2.0, 1.2), (x + 2.72, y, h + 1.3), m=mm['carglass'])
    box('cr_jib', (jib, 1.2, 1.2), (x + jib / 2 - 8, y, h + 2.8), m=cm)
    box('cr_counter', (4, 2, 2), (x - 9, y, h + 2.0), m=mm['concrete'])
    box('cr_apex', (0.8, 0.8, 6), (x, y, h + 5.5), m=cm)
    cyl('cr_cable', 0.02, h - 6, (x + 18, y, h / 2 + 4), m=mm['cable'], axis='Z', verts=4)
    box('cr_hook', (0.4, 0.3, 0.6), (x + 18, y, 9.5), m=mm['ship_orange'])
    box('cr_load', (1.2, 4.5, 0.6), (x + 18, y, 7.8), m=M('rebar_rust', (0.35, 0.18, 0.1), 0.8, 0.6))
    col((x, y, h / 2), (2.2, 2.2, h))


def mixer(x, y, rot, mm):
    root = empty('mixer', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    w = M('mixer_white', (0.9, 0.9, 0.88), 0.35, 0.3)
    box('mx_cab', (2.4, 2.2, 2.4), (0, 3.2, 1.9), m=w, parent=root, bevel=0.12)
    box('mx_ws', (2.2, 0.05, 1.0), (0, 4.31, 2.4), m=mm['carglass'], parent=root)
    box('mx_chassis', (2.2, 8.4, 0.5), (0, 0, 0.9), m=mm['metal'], parent=root)
    cyl('mx_drum', 1.25, 4.6, (0, -1.0, 2.5), (14, 0, 0), m=M('mixer_drum', (0.85, 0.42, 0.06), 0.4, 0.3), parent=root, axis='Y', verts=24, r2=0.7, bevel=0.05)
    for sy in (3.2, -1.2, -2.8):
        for sx in (-1, 1):
            cyl('mx_wheel', 0.5, 0.35, (sx * 1.05, sy, 0.5), m=mm['tire'], parent=root, axis='X', verts=18)
    col((x, y, 1.6), (2.5, 8.6, 3.2), rotz=rot)


def site_slab(name, x0, y0, x1, y1, z, mm, holes=()):
    """floor slab with stair holes: split into rectangles around holes (single hole supported)"""
    t = 0.3
    if not holes:
        wall(name, (x0 + x1) / 2, (y0 + y1) / 2, z - t, x1 - x0, y1 - y0, t, mm['concrete'])
        return
    hx0, hy0, hx1, hy1 = holes[0]
    parts = [(x0, y0, hx0, y1), (hx1, y0, x1, y1), (hx0, y0, hx1, hy0), (hx0, hy1, hx1, y1)]
    for i, (a, b, c, d) in enumerate(parts):
        if c - a > 0.05 and d - b > 0.05:
            wall(f'{name}{i}', (a + c) / 2, (b + d) / 2, z - t, c - a, d - b, t, mm['concrete'])


# ======================================================================== MAP 5: İNŞAAT (small construction site)
def map_insaat_v42():   # v4.2 layout, kept for reference (not in ALL)
    mm = begin()
    X0, X1, Y0, Y1 = -34, 34, -30, 30
    dirt = M('site_dirt', (0.45, 0.37, 0.28), 0.95)
    gravel = M('gravel', (0.5, 0.48, 0.45), 0.95)
    ground('site', X0 - 260, Y0 - 260, X1 + 260, Y1 + 260, 0, dirt)
    box('pad', (X1 - X0 + 1, Y1 - Y0 + 1, 0.04), (0, 0, 0.02), m=M('site_floor', (0.62, 0.62, 0.6), 0.6))
    box('pad2', (30, 22, 0.06), (0, 4, 0.03), m=mm['concrete'])
    box('road', (68, 7, 0.05), (0, -24, 0.025), m=gravel)
    # ---- unfinished 3-storey concrete frame (20 x 14) with an open roof slab
    BX, BY, BW, BD, FH = 0, 6, 20, 14, 3.6
    cols_x = [BX - BW / 2 + 0.25 + i * (BW - 0.5) / 4 for i in range(5)]
    cols_y = [BY - BD / 2 + 0.25 + i * (BD - 0.5) / 2 for i in range(3)]
    for lv in range(3):
        z = lv * FH
        for cx in cols_x:
            for cy in cols_y:
                wall('column', cx, cy, z, 0.5, 0.5, FH, mm['concrete'])
        hole = (BX + 5.5, BY - 6.4, BX + 9.5, BY - 3.6)
        site_slab(f'slab{lv}', BX - BW / 2, BY - BD / 2, BX + BW / 2, BY + BD / 2, z + FH, mm, holes=[hole] if lv < 2 else [hole])
        # stairs inside the hole (east side)
        stairs(f'st{lv}', BX + 7.5, BY - 5.0, z, z + FH, 2.8, 1.8 if lv < 2 else 1.8, mm['concrete'], axis='X', direction=-1) if lv < 2 else None
        # brick infill: partial walls with window gaps; ground floor north wall full, upper floors broken
        bm = mm['brick']
        if lv == 0:
            wall('bw_n', BX - 3, BY + BD / 2 - 0.15, z, 12, 0.25, FH - 0.3, bm)
            wall('bw_w1', BX - BW / 2 + 0.15, BY + 3.5, z, 0.25, 5, FH - 0.3, bm)
            wall('bw_s1', BX - 6, BY - BD / 2 + 0.15, z, 6, 0.25, 1.1, bm)
        elif lv == 1:
            wall('bw_n2', BX + 4, BY + BD / 2 - 0.15, z, 8, 0.25, FH - 0.3, bm)
            wall('bw_e2', BX + BW / 2 - 0.15, BY + 3.0, z, 0.25, 6, 1.2, bm)
            wall('bw_mid2', BX - 2, BY + 1.0, z, 0.25, 6, FH - 0.3, bm)
        else:
            wall('bw_w3', BX - BW / 2 + 0.15, BY - 2, z, 0.25, 7, 1.0, bm)
            wall('bw_n3', BX - 5, BY + BD / 2 - 0.15, z, 6, 0.25, 1.0, bm)
        # rebar sticking out of the top columns
    for cx in cols_x:
        for cy in cols_y:
            for dx in (-0.12, 0.12):
                cyl('rebar_top', 0.012, 1.2, (cx + dx, cy, 3 * FH + 0.6), m=M('rebar_rust', (0.35, 0.18, 0.1), 0.8, 0.6), axis='Z', verts=5)
    # roof parapet low walls (cover on the top floor)
    for sy in (-1, 1):
        wall('parapet', BX, BY + sy * (BD / 2 - 0.1), 3 * FH, BW, 0.2, 0.8, mm['concrete'])
    stairs('st2', BX + 7.5, BY - 5.0, 2 * FH, 3 * FH, 2.8, 1.8, mm['concrete'], axis='X', direction=-1)
    scaffold(BX - 2, BY - BD / 2 - 0.2, 0, 14, 10, mm)
    col((BX - 2, BY - BD / 2 - 1.2, 5), (14, 0.2, 10))
    # ---- crane, site office containers, mixer and materials
    tower_crane(-24, 20, mm)
    container(24, 20, 0, 90, mm['c_white'], mm)
    container(24, 17.3, 0, 90, mm['c_grey'], mm)
    container(24, 18.6, 2.59, 90, mm['c_blue'], mm)
    stairs('off_st', 27.6, 14.5, 0, 2.6, 4.0, 1.4, mm['steel'], axis='Y', direction=1)
    box('office_sign', (5, 0.1, 0.9), (24, 15.9, 4.2), m=M('site_sign', (0.95, 0.75, 0.1), 0.5))
    mixer(20, -6, 15, mm)
    sand_pile(-22, -6, 3.2, 2.4, M('sand', (0.82, 0.7, 0.5), 0.95))
    sand_pile(-17, -12, 2.4, 1.8, gravel)
    for (bx, by, r) in [(-14, 18, 0), (-10, 19, 0), (14, -10, 30), (8, -12, 0), (-27, 2, 90)]:
        brick_stack(bx, by, mm, rot=r)
    for (px, py) in [(-6, -10), (-4.6, -10), (28, 2), (28, 4)]:
        pallet_stack(px, py, RND.randint(2, 6), mm)
    rebar_bundle(-12, -16, 80, mm)
    rebar_bundle(12, 22, 10, mm)
    for (rx, ry) in [(-28, -14), (6, 24), (30, -12)]:
        cable_reel(rx, ry, mm)
    for i in range(5):
        cyl('pipe', 0.45, 6, (-30 + i * 0.0, 12 + i * 0.95, 0.45 if i < 3 else 1.25), m=mm['concrete'], axis='Y', verts=18) if False else None
    for k in range(3):
        cyl('big_pipe', 0.55, 5.5, (-30 + k * 1.15, 10, 0.55), m=mm['concrete'], axis='Y', verts=20)
    cyl('big_pipe', 0.55, 5.5, (-29.4, 10, 1.5), m=mm['concrete'], axis='Y', verts=20)
    col((-28.85, 10, 1.0), (3.5, 5.5, 2.0))
    for (jx, jy, r) in [(-6, -18, 90), (6, -18, 90), (-20, -20, 0), (18, 8, 0)]:
        jersey(jx, jy, r, mm)
    for (cx, cy) in [(-3, -21), (0, -21), (3, -21), (15, 0), (16, 1.5)]:
        cone(cx, cy)
    for (lx, ly) in [(-32, -28), (32, 28), (-32, 28)]:
        light_tower(lx, ly, mm, h=11)
    crate(10, 16, 0, 1.2, mm); crate(11.3, 16.2, 0, 1.2, mm, rot=10); crate(10.6, 16.1, 1.2, 1.1, mm, rot=-6)
    barrel(-8, 22, mm, 'yellow'); barrel(-7.3, 22.6, mm, 'red'); barrel(16, -16, mm, 'blue')
    car(-14, -24, 90, ('red', (0.55, 0.03, 0.03)), mm)
    car(-8, -25, 90, ('white', (0.85, 0.85, 0.82)), mm)
    # ---- v4.2 lane structure: west container lane, east precast-slab yard, staggered mid cover
    wood = M('formwork', (0.62, 0.48, 0.3), 0.85)
    # WEST lane: two stacked container rows form a long wall with a gap (peek window) + ladder side
    container(-22, -4, 0, 90, mm['c_blue'], mm)
    container(-22, 3.5, 0, 90, mm['c_grey'], mm)
    container(-22, -4, 2.59, 90, mm['c_white'], mm)
    container(-15.5, -14, 0, 0, mm['c_grey'], mm)
    for (fx, fy, r) in [(-28, -8, 90), (-17, 4, 0)]:
        wall('formwork', fx, fy, 0, 3.2, 0.25, 2.2, wood, rot=r)
    # EAST yard: stacked precast slabs (waist / head high), a site trailer
    for (sx, sy, n, r) in [(17, -14, 3, 0), (24, -4, 5, 90), (14, 2, 2, 0), (27, -16, 4, 0)]:
        for k in range(n):
            box('precast', (3.8, 1.6, 0.3), (sx, sy, 0.15 + k * 0.32), (0, 0, r + RND.uniform(-3, 3)), m=mm['concrete'])
        col((sx, sy, n * 0.16), (3.8 if r == 0 else 1.6, 1.6 if r == 0 else 3.8, n * 0.32))
    container(20, 6, 0, 0, mm['c_white'], mm)
    # MID: red column formwork pillars + stacked block pallets (tall cover / waist cover / a jump-up platform)
    for (fx, fy) in [(-7, -5), (3, -6.5), (11, -9), (-3, -14), (15, -15)]:
        formwork_column(fx, fy, mm)
    block_stack(-11, -9, 3.6, 1.3, 1.0)
    block_stack(-11, -10.3, 3.6, 1.3, 1.0)
    block_stack(6.5, -11.5, 1.3, 1.3, 1.7)
    block_stack(0, -10, 2.6, 1.3, 1.0)
    block_stack(14, -3, 1.3, 2.6, 1.3)
    block_stack(-15, 0, 1.3, 1.3, 1.7)
    jersey(9, -2, 0, mm)
    jersey(-1, -19, 0, mm)
    crate(-5.5, -9.5, 0, 1.25, mm, rot=15)
    for (px, py) in [(7.5, -7), (12.5, -1)]:
        pallet_stack(px, py, RND.randint(3, 5), mm)
    # NORTH yard (behind the building): rebar racks + formwork stacks so the A side has cover to the frame
    for (fx, fy) in [(-6, 18), (4, 19.5), (12, 17)]:
        for k in range(4):
            box('formwork_stack', (2.6, 1.3, 0.12), (fx, fy, 0.06 + k * 0.13), (0, 0, RND.uniform(-6, 6)), m=wood)
        col((fx, fy, 0.3), (2.6, 1.3, 0.6))
    wall('formwork', 0, 22.5, 0, 4.2, 0.25, 2.2, wood)
    # v4.2: closed site hoarding all the way round (the outside is no longer visible)
    hoarding(X0 - 0.6, Y0 - 0.6, X1 + 0.6, Y1 + 0.6, mm)
    # background city blocks
    for i, (ax, ay, h) in enumerate([(-60, 50, 26), (-30, 62, 34), (10, 58, 22), (45, 55, 30), (70, 10, 24), (66, -40, 36), (-70, -20, 28), (-55, -60, 20), (20, -66, 26)]):
        box('bg_block', (18, 16, h), (ax, ay, h / 2), m=[mm['p_grey'], mm['p_cream'], mm['concrete']][i % 3])
        for f in range(int(h / 3.2)):
            box('bg_win', (16, 16.1, 1.2), (ax, ay, f * 3.2 + 1.8), m=mm['glass'])
    spawns_a = [(-28, 26, 180), (-22, 26, 180), (-16, 27, 180), (-30, 18, 120), (-10, 27, 180), (-26, 14, 135)]
    spawns_b = [(28, -27, 0), (22, -27, 0), (14, -27, 0), (30, -18, 300), (8, -27, 0), (26, -10, 330)]
    for i, (x, y, yaw) in enumerate(spawns_a + spawns_b):
        spawn(x, y, 0.1, yaw, 'a' if i < 6 else 'b')
    bounds_walls(X0, Y0, X1, Y1, 22)
    finalize('insaat', dict(preset='day', sun=[-50, 40], fog=0.006, sky='day'), [X0, Y0, X1, Y1])


# ======================================================================== MAP 6: ÇANAKKALE (coastal fortress + trenches)
# ======================================================================== MAP 5 (v4.11): İNŞAAT — "Kartal Konutları" şantiyesi
# Spliced into maps.py (exec'd in its namespace). Design notes: docs/MAP_DESIGN.md#insaat
#
#   N (A spawn, site office row y≈23)
#   W lane: BLOK-A, 3-storey RC frame with brick infill (x -36..-18, y -12..12), walk-through ground floor,
#           stair core to floors 1-2, east windows over mid
#   MID   : foundation pit 20x16, 2.6 m deep (x -10..10, y -10..6), sunken ramps NW + SE, steel stair NE,
#           tower crane + cement silo as landmarks
#   E lane: container alley (x≈21.5) + BLOK-B 2-storey shell (x 26..38, y -2..12) + precast yard
#   S (B spawn behind gatehouse + parked truck y≈-25)

INS_FH = 3.2


def ins_mats(mm):
    return dict(
        conc=mm['concrete'], slab=M('site_floor', (0.62, 0.62, 0.6), 0.6), brick=mm['brick'],
        steel=mm['steel'], dark=mm['metal'], planks=mm['planks'], wood=M('formwork', (0.62, 0.48, 0.3), 0.85),
        dirt=M('site_dirt', (0.45, 0.37, 0.28), 0.95), gravel=M('gravel', (0.5, 0.48, 0.45), 0.95),
        sand=M('sand', (0.82, 0.7, 0.5), 0.95), rebar=M('rebar_rust', (0.35, 0.18, 0.1), 0.8, 0.6),
        yellow=M('crane_yellow', (0.95, 0.68, 0.05), 0.5, 0.3), orange=mm['ship_orange'],
        red=M('stripe_red', (0.8, 0.1, 0.08), 0.5), white=M('mixer_white', (0.9, 0.9, 0.88), 0.35, 0.3),
        bag=M('sandbag', (0.62, 0.6, 0.56)), tarp=M('tarp_blue', (0.1, 0.25, 0.5), 0.7),
        plastic=M('cone_white', (0.95, 0.95, 0.95), 0.4), net=M('scaffold_net', (0.15, 0.4, 0.2), 0.9),
        lean=M('lean_concrete', (0.5, 0.5, 0.48), 0.8), membrane=M('membrane_black', (0.05, 0.05, 0.05), 0.5),
        mud=M('mud_ground', (0.38, 0.32, 0.26), 0.9), soil=M('soil_wall', (0.42, 0.34, 0.26), 0.95),
        pbrick=M('plaster_brick', (0.7, 0.62, 0.55), 0.85),
    )


def ins_mound(name, x, y, r, h, m, sq=1.0, rot=0):
    """natural angle-of-repose heap (aggregate / sand), not a ball"""
    pts = [(r, 0.0), (r * 0.82, h * 0.28), (r * 0.6, h * 0.62), (r * 0.36, h * 0.88), (r * 0.12, h * 0.99), (0.0, h)]
    o = lathe(name, pts, (x, y, 0), (0, 0, (rot)), m=m, seg=28)
    o.scale = (1.0, sq, 1.0)
    col((x, y, h * 0.3), (r * 1.2, r * 1.2 * sq, h * 0.6), rotz=rot)
    return o


def ins_bin(x, y, w, d, h, rot, k):
    """3-sided aggregate bay made of interlocking concrete blocks (open side faces -Y local)"""
    root = empty('agg_bin', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for (sx, sy, lx, ly) in [(-w / 2, 0, 0.6, d), (w / 2, 0, 0.6, d), (0, d / 2, w + 0.6, 0.6)]:
        for row in range(int(h / 0.6)):
            box('agg_blk', (lx, ly, 0.58), (sx, sy, 0.3 + row * 0.6), m=k['conc'], parent=root, bevel=0.03)
    c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for (sx, sy, lx, ly) in [(-w / 2, 0, 0.6, d), (w / 2, 0, 0.6, d), (0, d / 2, w + 0.6, 0.6)]:
        col((x + sx * c - sy * s_, y + sx * s_ + sy * c, h / 2), (lx, ly, h), rotz=rot)
    return root


def ins_rail(x0, y0, x1, y1, k, h=1.05, z=0.0):
    """temporary edge-protection guard rail: steel posts on clamps + 2 tubes + toe board"""
    L = math.hypot(x1 - x0, y1 - y0); rot = math.degrees(math.atan2(y1 - y0, x1 - x0))
    n = max(1, int(L / 2.0))
    for i in range(n + 1):
        t = i / n
        cyl('gr_post', 0.025, h, (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z + h / 2), m=k['yellow'], axis='Z', verts=6)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for hz in (h * 0.5, h):
        cyl('gr_tube', 0.022, L, (cx, cy, z + hz), (0, 0, (rot - 90)), m=k['yellow'], axis='Y', verts=6)
    box('gr_toe', (L, 0.03, 0.15), (cx, cy, z + 0.075), (0, 0, (rot)), m=k['wood'])
    col((cx, cy, z + h / 2), (L, 0.12, h), rotz=rot)


def ins_infill(name, ax, ay, bx, by, z, kind, k):
    """brick infill for one structural bay between two columns, floor z..z+FH (under the next slab)
    kind: full | win | wide | door | low | none"""
    if kind == 'none':
        return
    H = INS_FH - 0.25
    L = math.hypot(bx - ax, by - ay) - 0.4
    rot = math.degrees(math.atan2(by - ay, bx - ax))
    cx, cy = (ax + bx) / 2, (ay + by) / 2
    c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    T = 0.2
    bm_ = k['pbrick'] if z < 1.0 else k['brick']
    def seg(off, w, z0, h):
        if w <= 0.05 or h <= 0.05:
            return
        wall(name, cx + c * off, cy + s_ * off, z + z0, w, T, h, bm_, rot=rot)
    if kind == 'full':
        seg(0, L, 0, H)
    elif kind == 'low':                      # unfinished: three courses only (waist cover)
        seg(0, L, 0, 1.0)
    elif kind in ('win', 'wide'):
        ow = 1.4 if kind == 'win' else min(L - 1.2, 3.2)
        side = (L - ow) / 2
        seg(-(ow + side) / 2, side, 0, H)
        seg((ow + side) / 2, side, 0, H)
        seg(0, ow, 0, 0.95)                  # sill (crouch cover)
        seg(0, ow, 2.15, H - 2.15)           # lintel
        box('sill', (ow, 0.32, 0.06), (cx, cy, z + 0.98), (0, 0, (rot)), m=k['conc'])
    elif kind == 'door':
        ow = 1.6
        side = (L - ow) / 2
        seg(-(ow + side) / 2, side, 0, H)
        seg((ow + side) / 2, side, 0, H)
        seg(0, ow, 2.25, H - 2.25)


def ins_rc_block(name, X0, Y0, nx, ny, bay, floors, k, faces, stair=None, roof_open=False, scaffold_south=False):
    """reinforced-concrete frame building: columns, edge beams, slabs (with stair hole), brick infill per
    bay/face/floor from `faces`[floor][face] = list of kinds, stairs between floors."""
    X1, Y1 = X0 + nx * bay, Y0 + ny * bay
    xs = [X0 + i * bay for i in range(nx + 1)]
    ys = [Y0 + j * bay for j in range(ny + 1)]
    # ground slab + apron
    box(name + '_gslab', (X1 - X0 + 1.2, Y1 - Y0 + 1.2, 0.16), ((X0 + X1) / 2, (Y0 + Y1) / 2, 0.08), m=k['slab'])
    col(((X0 + X1) / 2, (Y0 + Y1) / 2, 0.08), (X1 - X0 + 1.2, Y1 - Y0 + 1.2, 0.16))
    for f in range(floors):
        z = 0.16 if f == 0 else f * INS_FH
        top = (f + 1) * INS_FH
        for x in xs:
            for y in ys:
                wall(name + '_col', x, y, z, 0.4, 0.4, top - z - 0.25, k['conc'])
        # slab above this floor (with stair hole)
        holes = [stair['hole']] if (stair and f + 1 <= stair['to_floor']) else []
        if f + 1 == floors and roof_open:
            # roof: only half poured, the other half is formwork decking with rebar mats (cover, not walkable edge)
            midx = (X0 + X1) / 2
            site_slab(name + f'_slab{f}', X0 - 0.2, Y0 - 0.2, midx, Y1 + 0.2, top, {'concrete': k['conc']}, holes=[])
            box(name + '_deck', (X1 - midx, Y1 - Y0 + 0.4, 0.06), ((midx + X1) / 2, (Y0 + Y1) / 2, top - 0.27), m=k['wood'])
            col(((midx + X1) / 2, (Y0 + Y1) / 2, top - 0.27), (X1 - midx, Y1 - Y0 + 0.4, 0.06))
            for i in range(int((X1 - midx) / 0.6)):
                cyl('roof_mesh', 0.008, Y1 - Y0, (midx + 0.3 + i * 0.6, (Y0 + Y1) / 2, top - 0.15), m=k['rebar'], axis='Y', verts=4)
        else:
            site_slab(name + f'_slab{f}', X0 - 0.2, Y0 - 0.2, X1 + 0.2, Y1 + 0.2, top, {'concrete': k['conc']}, holes=holes)
        # perimeter edge beams (downstand) on each storey: reads as real structure, not a stack of plates
        zb = top - 0.3 - 0.225
        box(name + '_beam', (X1 - X0 + 0.4, 0.3, 0.45), ((X0 + X1) / 2, Y0, zb), m=k['conc'])
        box(name + '_beam', (X1 - X0 + 0.4, 0.3, 0.45), ((X0 + X1) / 2, Y1, zb), m=k['conc'])
        box(name + '_beam', (0.3, Y1 - Y0 + 0.4, 0.45), (X0, (Y0 + Y1) / 2, zb), m=k['conc'])
        box(name + '_beam', (0.3, Y1 - Y0 + 0.4, 0.45), (X1, (Y0 + Y1) / 2, zb), m=k['conc'])
        # brick infill
        fl = faces.get(f, {})
        for face, kinds in fl.items():
            if face == 'S':
                segs = [(xs[i], Y0, xs[i + 1], Y0) for i in range(nx)]
            elif face == 'N':
                segs = [(xs[i], Y1, xs[i + 1], Y1) for i in range(nx)]
            elif face == 'W':
                segs = [(X0, ys[j], X0, ys[j + 1]) for j in range(ny)]
            else:
                segs = [(X1, ys[j], X1, ys[j + 1]) for j in range(ny)]
            for (sg, kind) in zip(segs, kinds):
                ins_infill(name + '_inf', sg[0], sg[1], sg[2], sg[3], z if f else 0.16, kind, k)
        # open slab edges on upper floors get guard rails where there is no infill (edge protection)
        if f >= 1:
            for face, kinds in fl.items():
                for i, kind in enumerate(kinds):
                    if kind != 'none':
                        continue
                    if face == 'S':
                        ins_rail(xs[i] + 0.25, Y0 - 0.05, xs[i + 1] - 0.25, Y0 - 0.05, k, z=z)
                    elif face == 'N':
                        ins_rail(xs[i] + 0.25, Y1 + 0.05, xs[i + 1] - 0.25, Y1 + 0.05, k, z=z)
                    elif face == 'W':
                        ins_rail(X0 - 0.05, ys[i] + 0.25, X0 - 0.05, ys[i + 1] - 0.25, k, z=z)
                    else:
                        ins_rail(X1 + 0.05, ys[i] + 0.25, X1 + 0.05, ys[i + 1] - 0.25, k, z=z)
    # stairs: straight concrete flights alternating in the stair hole
    if stair:
        hx0, hy0, hx1, hy1 = stair['hole']
        wdt = (hx1 - hx0 - 0.2) if stair['to_floor'] == 1 else (hx1 - hx0) / 2 - 0.1
        for f in range(stair['to_floor']):
            z0 = 0.16 if f == 0 else f * INS_FH
            z1 = (f + 1) * INS_FH
            if f % 2 == 0:
                stairs(name + f'_st{f}', hx0 + wdt / 2 + 0.1, (hy0 + hy1) / 2, z0, z1, hy1 - hy0, wdt, k['conc'], axis='Y', direction=1)
            else:
                stairs(name + f'_st{f}', hx1 - wdt / 2 - 0.05, (hy0 + hy1) / 2, z0, z1, hy1 - hy0, wdt, k['conc'], axis='Y', direction=-1)
        # landings rail around the hole on the top served floor
        zt = stair['to_floor'] * INS_FH
        ins_rail(hx0, hy0, hx1, hy0, k, z=zt) if stair['to_floor'] % 2 == 1 else ins_rail(hx0, hy1, hx1, hy1, k, z=zt)
    # rebar starter bars on top of the columns (building will grow)
    if roof_open:
        for x in xs:
            for y in ys:
                for dx in (-0.12, 0.12):
                    for dy in (-0.12, 0.12):
                        cyl('starter', 0.012, 1.1, (x + dx, y + dy, floors * INS_FH + 0.55), m=k['rebar'], axis='Z', verts=5)
    return X1, Y1


def ins_scaffold(x0, x1, y, h, k, facing=-1):
    """facade scaffold (tube & fitting) with toe boards and green shade net; blocked volume (not climbable)"""
    root = empty('scaff', (0, 0, 0))
    n = max(1, int((x1 - x0) / 2.0))
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        for d in (0.25, 1.35):
            cyl('sc_std', 0.024, h, (x, y + facing * d, h / 2), m=k['steel'], parent=root, axis='Z', verts=6)
    for lv in range(1, int(h / 2.0) + 1):
        z = lv * 2.0
        box('sc_board', (x1 - x0, 0.95, 0.05), ((x0 + x1) / 2, y + facing * 0.8, z), m=k['planks'], parent=root)
        for d in (0.25, 1.35):
            cyl('sc_ledger', 0.022, x1 - x0, ((x0 + x1) / 2, y + facing * d, z + 1.0), (0, 0, (90)), m=k['steel'], parent=root, axis='Y', verts=6)
    for i in range(n):
        xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
        ang = math.degrees(math.atan2(2.0, xb - xa))
        cyl('sc_brace', 0.02, math.hypot(xb - xa, 2.0), ((xa + xb) / 2, y + facing * 1.4, 1.0 + (i % 4) * 2.0), (0, (90 - ang), 0), m=k['steel'], parent=root, axis='Z', verts=6)
    box('sc_net', (x1 - x0, 0.02, h - 0.6), ((x0 + x1) / 2, y + facing * 1.45, h / 2 + 0.3), m=k['net'], parent=root)
    col(((x0 + x1) / 2, y + facing * 0.85, h / 2), (x1 - x0, 1.5, h))


def ins_silo(x, y, k):
    """cement silo on four legs (walk underneath), the second tall landmark after the crane"""
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('silo_leg', (0.22, 0.22, 4.4), (x + sx * 1.05, y + sy * 1.05, 2.2), m=k['white'])
            col((x + sx * 1.05, y + sy * 1.05, 2.2), (0.24, 0.24, 4.4))
        box('silo_brace', (2.1, 0.08, 0.08), (x, y + sx * 1.05, 1.5), (0, (32), 0), m=k['white'])
    lathe('silo_hopper', [(0.25, 3.2), (1.45, 4.9)], (x, y, 0), m=k['white'], seg=20)
    cyl('silo_body', 1.45, 7.5, (x, y, 8.65), m=k['white'], axis='Z', verts=24)
    cyl('silo_band', 1.47, 0.6, (x, y, 10.8), m=k['red'], axis='Z', verts=24)
    lathe('silo_roof', [(1.45, 12.4), (0.3, 13.1)], (x, y, 0), m=k['white'], seg=20)
    cyl('silo_pipe', 0.09, 12.0, (x + 1.55, y, 6.6), m=k['steel'], axis='Z', verts=8)
    for i in range(16):
        box('silo_ladder', (0.4, 0.04, 0.03), (x - 1.55, y, 4.9 + i * 0.45), m=k['steel'])
    col((x, y, 8.65), (2.9, 2.9, 7.5))


def ins_rebar_rack(x, y, rot, k, n_bundles=4):
    root = empty('rebar_rack', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    for sy in (-2.6, 0, 2.6):
        for sx in (-0.75, 0.75):
            box('rr_post', (0.12, 0.12, 1.5), (sx, sy, 0.75), m=k['dark'], parent=root)
        for z in (0.45, 1.05):
            box('rr_arm', (1.7, 0.1, 0.08), (0, sy, z), m=k['dark'], parent=root)
    for b in range(n_bundles):
        z = 0.53 if b < 2 else 1.13
        xo = -0.4 if b % 2 == 0 else 0.4
        for i in range(10):
            cyl('rr_bar', 0.014, 6.2, (xo + (i % 5) * 0.04 - 0.08, 0, z + (i // 5) * 0.035), m=k['rebar'], parent=root, axis='Y', verts=5)
    c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    col((x, y, 0.75), (1.7, 6.2, 1.5), rotz=rot)


def ins_cement_pallet(x, y, rot, k, layers=4):
    root = empty('cem', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('cem_pal', (1.2, 1.0, 0.14), (0, 0, 0.07), m=k['planks'], parent=root)
    for L in range(layers):
        for i in range(2):
            for j in range(3 if L % 2 == 0 else 2):
                if L % 2 == 0:
                    box('cem_bag', (0.58, 0.32, 0.13), (-0.3 + i * 0.6, -0.33 + j * 0.33, 0.21 + L * 0.14), m=k['bag'], parent=root, bevel=0.04)
                else:
                    box('cem_bag', (0.38, 0.48, 0.13), (-0.4 + j * 0.4 + 0.2, -0.25 + i * 0.5, 0.21 + L * 0.14), m=k['bag'], parent=root, bevel=0.04)
    box('cem_wrap', (1.18, 0.98, 0.02), (0, 0, 0.16 + layers * 0.14), m=k['tarp'], parent=root) if layers >= 4 else None
    col((x, y, (0.14 + layers * 0.14) / 2), (1.2, 1.0, 0.14 + layers * 0.14), rotz=rot)


def ins_precast_stack(x, y, rot, n, k):
    """precast hollow-core floor planks on timber bearers"""
    root = empty('precast', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    z = 0
    for i in range(n):
        for by in (-1.5, 1.5):
            box('pc_bearer', (1.3, 0.1, 0.1), (0, by, z + 0.05), m=k['wood'], parent=root)
        box('pc_plank', (1.2, 4.6, 0.26), (RND.uniform(-0.04, 0.04), RND.uniform(-0.06, 0.06), z + 0.23), m=k['conc'], parent=root, bevel=0.02)
        for c_ in range(4):
            cyl('pc_core', 0.07, 4.62, (-0.42 + c_ * 0.28, 0, z + 0.23), m=k['dark'], parent=root, axis='Y', verts=8)
        z += 0.36
    col((x, y, z / 2), (1.3, 4.7, z), rotz=rot)


def ins_wheelbarrow(x, y, rot, k):
    root = empty('wb', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    lathe('wb_tray', [(0.15, 0.32), (0.42, 0.62)], (0, 0, 0), m=k['orange'], parent=root, seg=10).scale = (0.85, 1.25, 1.0)
    cyl('wb_wheel', 0.18, 0.08, (0, 0.62, 0.18), m=M('tire', (0.03, 0.03, 0.03), 0.9), parent=root, axis='X', verts=14)
    for sx in (-0.25, 0.25):
        cyl('wb_handle', 0.018, 1.4, (sx, -0.25, 0.45), ((-12), 0, 0), m=k['dark'], parent=root, axis='Y', verts=6)
        box('wb_leg', (0.03, 0.03, 0.32), (sx, -0.3, 0.16), m=k['dark'], parent=root)


def ins_toilet(x, y, rot, k, col_=None):
    root = empty('wc', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    shell = M('wc_blue', (0.1, 0.32, 0.6), 0.45) if col_ is None else col_
    box('wc_body', (1.1, 1.1, 2.2), (0, 0, 1.12), m=shell, parent=root, bevel=0.04)
    box('wc_roof', (1.2, 1.2, 0.1), (0, 0, 2.28), m=k['plastic'], parent=root, bevel=0.03)
    box('wc_door', (0.8, 0.04, 1.85), (0, -0.57, 1.05), m=k['plastic'], parent=root, bevel=0.02)
    col((x, y, 1.15), (1.15, 1.15, 2.3), rotz=rot)


def ins_generator(x, y, rot, k):
    root = empty('gen', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('gen_skid', (1.3, 3.2, 0.16), (0, 0, 0.08), m=k['dark'], parent=root)
    box('gen_body', (1.2, 3.0, 1.7), (0, 0, 1.0), m=M('gen_yellow', (0.85, 0.62, 0.08), 0.45, 0.3), parent=root, bevel=0.05)
    for i in range(6):
        box('gen_louvre', (1.22, 0.06, 0.6), (0, -1.0 + i * 0.12, 1.05), m=k['dark'], parent=root)
    cyl('gen_exh', 0.06, 0.6, (0.3, 1.1, 2.1), m=k['steel'], parent=root, axis='Z', verts=8)
    col((x, y, 0.92), (1.3, 3.2, 1.85), rotz=rot)


def ins_mortar_mixer(x, y, rot, k):
    root = empty('mm', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    box('mm_frame', (0.9, 1.2, 0.08), (0, 0, 0.42), m=k['dark'], parent=root)
    for sx in (-0.4, 0.4):
        cyl('mm_wheel', 0.22, 0.08, (sx, -0.45, 0.22), m=M('tire', (0.03, 0.03, 0.03), 0.9), parent=root, axis='X', verts=12)
        box('mm_leg', (0.05, 0.05, 0.42), (sx, 0.5, 0.21), m=k['dark'], parent=root)
    lathe('mm_drum', [(0.18, 0.0), (0.42, 0.3), (0.42, 0.55), (0.2, 0.85)], (0, 0.1, 0.55), ((35), 0, 0), m=k['orange'], parent=root, seg=16)
    col((x, y, 0.6), (1.0, 1.3, 1.2), rotz=rot)


def map_insaat():
    mm = begin()
    k = ins_mats(mm)
    X0, X1, Y0, Y1 = -40, 40, -34, 34
    PX0, PX1, PY0, PY1, PD = -10, 10, -10, 6, 2.6        # foundation pit

    # ---------------------------------------------------------------- ground (with the pit cut out)
    E = 260
    G0, G1, H0, H1 = X0 - 2, X1 + 2, Y0 - 2, Y1 + 2
    for (a, b, c_, d) in [(G0, PY1, G1, H1), (G0, H0, G1, PY0), (G0, PY0, PX0, PY1), (PX1, PY0, G1, PY1)]:
        ground('site', a, b, c_, d, 0, k['dirt'])
    for (a, b, c_, d) in [(X0 - E, H1, X1 + E, Y1 + E), (X0 - E, Y0 - E, X1 + E, H0), (X0 - E, H0, G0, H1), (G1, H0, X1 + E, H1)]:
        ground('site_far', a, b, c_, d, 0, k['dirt'])
    # haul road (gravel) from the south gate to the pit, and a compacted gravel strip along the east
    box('road_s', (7, 22, 0.04), (1, -23, 0.02), m=k['mud'])
    box('road_e', (4, 38, 0.04), (18.2, -5, 0.02), m=k['mud'])
    for (px, py, sx, sy, r) in [(2, -16, 2.4, 1.6, 20), (-3, 10.5, 3.0, 1.8, -10), (16, -8, 2.0, 1.4, 0), (-28, -22, 2.6, 1.6, 35), (30, 22, 2.2, 1.5, 0)]:
        decal_plane(px, py, 0.04, sx, sy, 'puddle', (r))
    for (px, py, r) in [(14, -20, 0), (-4, -28, 90)]:
        decal_plane(px, py, 0.04, 1.6, 1.2, 'oilstain', (r))

    # ---------------------------------------------------------------- MID: foundation pit
    ground('pit_floor', PX0, PY0, PX1, PY1, -PD, k['lean'])
    # waterproofing membrane strip + footings and starter columns inside (cover, readable shapes)
    box('pit_membrane', (PX1 - PX0 - 0.6, 0.8, 0.02), (0, PY1 - 0.7, -PD + 0.01), m=k['membrane'])
    T = 0.3
    # retaining walls (shotcrete) — openings where the ramps arrive
    wall('pit_w', PX0 - T / 2, (PY0 + PY1) / 2, -PD, T, PY1 - PY0 + T * 2, PD, k['soil'])
    wall('pit_e', PX1 + T / 2, (PY0 + PY1) / 2, -PD, T, PY1 - PY0 + T * 2, PD, k['soil'])
    wall('pit_n', (PX0 + 4 + PX1) / 2, PY1 + T / 2, -PD, PX1 - PX0 - 4, T, PD, k['soil'])          # gap x -10..-6 (NW ramp)
    wall('pit_s', (PX0 + PX1 - 4) / 2, PY0 - T / 2, -PD, PX1 - PX0 - 4, T, PD, k['soil'])          # gap x 6..10 (SE ramp)
    # NW ramp: earth ramp hugging the west wall, descends south from the north edge (y 6 -> -2)
    ramp('ramp_nw', -8, 2, -PD, 0, 8, 4, k['mud'], 'Y', 1)
    prof('ramp_nw_fill', [(-2, -PD), (6, -PD), (6, -0.25)], 4, (-8, 0, 0), m=k['soil'], plane='YZ', bevel=0.0)
    wall('ramp_nw_side', -5.85, 2, -PD, 0.3, 8, PD, k['conc'])
    # SE ramp: hugs the east wall, descends north from the south edge (y -10 -> -2)
    ramp('ramp_se', 8, -6, -PD, 0, 8, 4, k['mud'], 'Y', -1)
    prof('ramp_se_fill', [(-10, -0.25), (-10, -PD), (-2, -PD)], 4, (8, 0, 0), m=k['soil'], plane='YZ', bevel=0.0)
    wall('ramp_se_side', 5.85, -6, -PD, 0.3, 8, PD, k['conc'])
    # NE steel stair (third way in/out of the pit)
    stairs('pit_stair', 7.6, 4.4, -PD, 0, 4.6, 1.3, k['steel'], axis='X', direction=1)
    for sy in (3.7, 5.1):
        cyl('ps_rail', 0.025, 5.3, (7.6, sy, -PD / 2 + 0.95), (0, (90 - math.degrees(math.atan2(PD, 4.6))), 0), m=k['yellow'], axis='Z', verts=6)
    # pit interior cover: footings with starter bars, formwork columns, rebar mats, a pump
    for (fx, fy) in [(-3.5, -6.5), (2.5, -5.0), (-1.0, 1.5), (3.5, 2.0), (-4.5, -1.5)]:
        wall('footing', fx, fy, -PD, 2.2, 2.2, 0.7, k['conc'])
        wall('pit_col', fx, fy, -PD + 0.7, 0.45, 0.45, 2.6 if (fx, fy) in [(2.5, -5.0), (-1.0, 1.5)] else 1.2, k['conc'])
        for dx in (-0.14, 0.14):
            for dy in (-0.14, 0.14):
                cyl('ft_bar', 0.012, 1.1, (fx + dx, fy + dy, -PD + (3.3 if (fx, fy) in [(2.5, -5.0), (-1.0, 1.5)] else 1.9) + 0.5), m=k['rebar'], axis='Z', verts=5)
    for (mx, my, r) in [(0.5, -8.2, 0), (-6.5, -7.8, 90)]:
        box('rebar_mat', (2.4, 4.8, 0.32), (mx, my, -PD + 0.16), (0, 0, (r)), m=k['rebar'])
        col((mx, my, -PD + 0.16), (2.4, 4.8, 0.32), rotz=r)
    # rebar cages waiting on the short starter columns (vertical bars + stirrups every 25 cm)
    for (fx, fy) in [(-3.5, -6.5), (3.5, 2.0), (-4.5, -1.5)]:
        z0 = -PD + 1.9
        for i in range(8):
            ang = i / 8 * math.tau
            cyl('cage_bar', 0.012, 2.4, (fx + math.cos(ang) * 0.2, fy + math.sin(ang) * 0.2, z0 + 1.2), m=k['rebar'], axis='Z', verts=4)
        for j in range(9):
            torus('cage_ring', 0.2, 0.008, (fx, fy, z0 + 0.15 + j * 0.27), m=k['rebar'], seg=12, mseg=3)
    # plywood formwork panels leaning on the retaining walls, water drums
    ply = M('formwork', (0.62, 0.48, 0.3), 0.85)
    for (px, py, r, n) in [(-9.55, -4.0, 90, 4), (-9.55, -7.5, 90, 3), (9.55, 0.0, 270, 4), (2.0, 5.55, 180, 3)]:
        c_, s2 = math.cos(math.radians(r)), math.sin(math.radians(r))
        for i in range(n):
            box('ply', (1.22, 0.02, 2.44), (px + c_ * (i * 0.05) + (-s2) * (i * 0.3 - 0.4), py + s2 * (i * 0.05) + c_ * (i * 0.3 - 0.4), -PD + 1.15), (-12, 0, r), m=ply)
        col((px, py, -PD + 1.1), (1.4 if r in (0, 180) else 0.5, 0.5 if r in (0, 180) else 1.4, 2.2), rotz=0)
    for (bx2, by2) in [(-8.6, 4.6), (-7.9, 4.9), (6.8, -9.0)]:
        cyl('drum', 0.29, 0.88, (bx2, by2, -PD + 0.44), m=M('barrel_blue', (0.1, 0.25, 0.6), 0.4, 0.3), axis='Z', verts=16)
        col((bx2, by2, -PD + 0.44), (0.58, 0.58, 0.88))
    box('pump', (0.8, 1.1, 0.7), (4.2, -1.8, -PD + 0.35), m=M('gen_yellow', (0.85, 0.62, 0.08), 0.45, 0.3), bevel=0.05)
    col((4.2, -1.8, -PD + 0.35), (0.8, 1.1, 0.7))
    cyl('pump_hose', 0.06, 9.0, (4.2, 2.8, -PD + 0.07), m=mm['cable'], axis='Y', verts=6)
    # pit edge protection: jersey barriers + guard rails, gaps at the three ways in
    for (jx, jy, r) in [(-2.2, 7.1, 90), (1.0, 7.1, 90), (4.2, 7.1, 90), (-6.2, -10.8, 90), (-3.0, -10.8, 90), (0.2, -10.8, 90)]:
        jersey(jx, jy, r, mm)
    ins_rail(-10.6, -9.8, -10.6, 5.6, k)
    ins_rail(10.6, -9.8, 10.6, 3.2, k)
    ins_rail(5.8, 6.6, 9.8, 6.6, k)
    ins_rail(3.4, -10.6, 5.6, -10.6, k)

    # ---------------------------------------------------------------- landmarks
    tower_crane(14, 10, mm)
    ins_silo(-14.5, 21.5, k)

    # ---------------------------------------------------------------- WEST: BLOK-A (3 storeys, 3x4 bays of 6 m)
    W, D = 'win', 'door'
    faces_a = {
        0: {'E': ['full', 'wide', 'full', 'wide'], 'W': ['win', 'full', 'win', 'full'],
            'S': ['full', 'full', 'door'], 'N': ['full', 'full', 'door']},
        1: {'E': [W, W, 'none', W], 'W': [W, W, W, 'full'], 'S': ['full', W, 'low'], 'N': [W, 'full', W]},
        2: {'E': ['low', 'none', 'low', 'none'], 'W': ['low', 'none', 'none', 'low'], 'S': ['none', 'low', 'none'], 'N': ['low', 'none', 'none']},
    }
    ins_rc_block('blokA', -36, -12, 3, 4, 6.0, 3, k, faces_a, stair=dict(hole=(-29.6, -5.8, -25.4, -0.2), to_floor=2), roof_open=True)
    # ground floor partitions: rooms on the west two bays, open corridor along the east bay (walk-through lane)
    for (ax, ay, bx, by, kind) in [(-30, -12, -30, -6, 'full'), (-30, -6, -30, 0, D), (-30, 0, -30, 6, 'full'), (-30, 6, -30, 12, D),
                                   (-24, -12, -24, -6, D), (-24, 0, -24, 6, D), (-36, 0, -30, 0, D), (-30, 6, -24, 6, 'full')]:
        ins_infill('blokA_part', ax, ay, bx, by, 0.16, kind, k)
    ins_scaffold(-36.2, -24.3, -12.25, 9.0, k, facing=-1)
    # interior dressing (sparse, readable): cement pallets, block pallets, a work light, plaster buckets
    for (px, py, r, L) in [(-21, -8, 0, 5), (-21.5, 9, 15, 3), (-33, 3, 90, 4), (-27, 9, 0, 5)]:
        ins_cement_pallet(px, py, r, k, L)
    block_stack(-33.5, -9.5, 1.3, 1.3, 1.4)
    block_stack(-20.5, 2.5, 1.3, 2.6, 0.9)
    ins_cement_pallet(-21, -4, 0, k, 3)                                            # floor 1
    for (px, py) in [(-21.0, 4.0), (-33.0, -8.0)]:
        ins_cement_pallet(px, py, 0, k, 4)
    # floor-1 cover (they rest on the slab at z=3.2): stacked blocks
    for (bx_, by_, sx, sy) in [(-21.0, -2.0, 1.3, 1.3), (-21.0, 7.5, 2.6, 1.3), (-33.0, -3.5, 1.3, 1.3)]:
        box('blocks1', (sx, sy, 1.0), (bx_, by_, INS_FH + 0.5), m=k['conc'], bevel=0.02)
        col((bx_, by_, INS_FH + 0.5), (sx, sy, 1.0))

    # ---------------------------------------------------------------- EAST: container alley, BLOK-B, precast yard
    container(21.5, -14, 0, 0, mm['c_blue'], mm)
    container(21.5, -14, 2.59, 0, mm['c_white'], mm)
    container(21.5, -5.0, 0, 0, mm['c_grey'], mm)
    container(22.4, 24.5, 0, 0, mm['c_red'], mm)
    faces_b = {
        0: {'N': ['full', 'full'], 'E': ['full', 'full'], 'W': ['none', 'none'], 'S': ['none', 'none']},
        1: {'N': ['full', W], 'E': ['full', 'full'], 'W': [W, W], 'S': ['low', 'none']},
    }
    ins_rc_block('blokB', 26, -2, 2, 2, 6.0, 2, k, faces_b, stair=dict(hole=(33.0, -1.6, 34.6, 4.0), to_floor=1))
    for (px, py, r, n) in [(29, -10, 0, 3), (35, -16, 90, 4), (27, -21, 0, 2), (32, 22, 90, 3)]:
        ins_precast_stack(px, py, r, n, k)
    container(34.5, -26.5, 0, 90, mm['c_orange'], mm)
    container(34.5, -26.5, 2.59, 90, mm['c_grey'], mm)
    ins_generator(26.5, -27, 90, k)
    for (rx, ry) in [(36, 1.5), (28.5, 16.5)]:
        cable_reel(rx, ry, mm)

    # ---------------------------------------------------------------- NORTH: A side — site office row + yard
    for (cx, r, cm) in [(-6.1, 90, mm['c_white']), (0.0, 90, mm['c_white']), (6.1, 90, mm['c_grey'])]:
        container(cx, 23.0, 0, r, cm, mm)
    container(0.0, 23.0, 2.59, 90, mm['c_white'], mm)
    container(6.1, 23.0, 2.59, 90, mm['c_blue'], mm)
    stairs('office_st', -9.75, 21.0, 0, 2.59, 4.2, 1.2, k['steel'], axis='Y', direction=1)   # roof of the west office
    ins_rail(-9.1, 24.3, -3.1, 24.3, k, z=2.59)
    box('office_sign', (5.6, 0.08, 0.95), (3.0, 21.7, 4.0), m=sign_mat('santiye'))
    ins_generator(11.2, 23.0, 90, k)
    ins_toilet(-11.0, 24.5, 0, k); ins_toilet(-12.3, 24.5, 0, k)
    container(-14.0, 15.5, 0, 0, mm['c_green'], mm)                    # material store (blocks the W diagonal)
    container(16.5, 17.8, 0, 90, mm['c_grey'], mm)                    # tool store (blocks the E lane sightline)
    ins_rebar_rack(-29, 18, 90, k)
    ins_rebar_rack(-22, 18, 90, k, 3)
    ins_rebar_rack(28.5, 26.5, 90, k)
    for (fx, fy) in [(-5.5, 15.0), (5.0, 14.0)]:
        for kk in range(5):
            box('formwork_stack', (2.5, 1.25, 0.1), (fx, fy, 0.05 + kk * 0.11), (0, 0, (RND.uniform(-5, 5))), m=k['wood'])
        col((fx, fy, 0.3), (2.5, 1.25, 0.6))
    ins_mortar_mixer(-18, 14.5, 30, k)
    ins_wheelbarrow(-16.5, 13.2, 200, k)
    ins_wheelbarrow(24.5, 15.0, 80, k)
    ins_cement_pallet(-8.5, 12.5, 10, k, 5)
    ins_cement_pallet(9.0, 13.5, -8, k, 4)
    pallet_stack(30.5, 30.0, 4, mm)
    pallet_stack(-31, 29.5, 5, mm, rot=10)

    # ---------------------------------------------------------------- SOUTH: B side — gate, gatehouse, trucks, aggregate bays
    container(-12.0, -25.0, 0, 90, mm['c_white'], mm)                 # gatehouse
    stairs('gate_st', -15.65, -27.0, 0, 2.59, 4.2, 1.2, k['steel'], axis='Y', direction=1)
    ins_rail(-15.0, -23.7, -9.0, -23.7, k, z=2.59)
    truck(2.0, -25.0, 90, mm, mm['c_red'])
    mixer(14.0, -19.0, 0, mm)
    ins_bin(-14.5, -15.5, 4.2, 3.2, 1.8, 180, k)
    ins_mound('sand', -14.5, -15.8, 2.0, 1.5, k['sand'], 0.75)
    ins_bin(-9.4, -15.5, 4.2, 3.2, 1.8, 180, k)
    ins_mound('gravel_pile', -9.4, -15.8, 2.0, 1.4, k['gravel'], 0.75)
    ins_mound('spoil', -30.5, -27.0, 4.2, 2.1, k['dirt'], 0.8, 25)     # excavated spoil heap (SW cover)
    for (bx_, by_, sx, sy, sz) in [(-3.5, -16.5, 2.6, 1.3, 1.0), (5.5, -15.0, 1.3, 1.3, 1.7), (-22.5, -19.5, 1.3, 2.6, 1.3), (24.5, -4.0, 1.3, 1.3, 1.0)]:
        block_stack(bx_, by_, sx, sy, sz)
    for (jx, jy, r) in [(-22, -26, 0), (22, -24, 0), (-6, -21, 90)]:
        jersey(jx, jy, r, mm)
    for (cx, cy) in [(-1.5, -18.5), (3.5, -18.5), (-1.5, -29), (3.5, -29.5), (10.0, -13.0)]:
        cone(cx, cy)
    ins_toilet(-36.5, -30.5, 90, k); ins_toilet(-36.5, -29.2, 90, k)
    ins_wheelbarrow(-25, -16.5, 120, k)
    for (rx, ry) in [(-34.5, -20.5), (8.5, -30.5)]:
        cable_reel(rx, ry, mm)
    # west back alley (flank behind BLOK-A): narrowed by block pallets
    for (bx_, by_) in [(-38.2, -6.5), (-38.2, 5.0)]:
        block_stack(bx_, by_, 1.3, 1.3, 1.7)

    # ---------------------------------------------------------------- perimeter + lights
    hoarding(X0 - 0.6, Y0 - 0.6, X1 + 0.6, Y1 + 0.6, mm)
    for (lx, ly) in [(-38.5, -32.5), (38.5, 32.5), (-38.5, 32.5), (38.5, -32.5)]:
        light_tower(lx, ly, mm, h=11)

    # ---------------------------------------------------------------- spawns (8 + 8)
    spawns_a = [(-14, 29.5, 180), (-8, 30.5, 180), (-2, 29.5, 180), (4, 30.5, 180), (10, 29.5, 180), (15, 30.5, 185), (-18, 31, 170), (19, 31.5, 190)]
    spawns_b = [(14, -30.5, 0), (8, -29.5, 0), (-2, -30.5, 0), (-8, -29.5, 0), (-14, -30.5, 5), (18, -31, 355), (-19, -31, 10), (24, -30.5, 350)]
    for i, (x, y, yaw) in enumerate(spawns_a + spawns_b):
        spawn(x, y, 0.1, yaw, 'a' if i < len(spawns_a) else 'b')
    bounds_walls(X0, Y0, X1, Y1, 22)
    # terrain under the foundation pit is cut out (Godot x/z: z = -blender y)
    finalize('insaat', dict(preset='day', sun=[-48, 35], fog=0.004, sky='day'), [X0, Y0, X1, Y1],
             extra=dict(terrain_holes=[[PX0 - 1.0, -PY1 - 1.0, PX1 + 1.0, -PY0 + 1.0]], hide=['bg_block', 'bg_win']))


def berm(x, y, length, rot, mm, h=1.5):
    """earth trench wall with a sandbag crest (cover on both sides)"""
    root = empty('berm', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    prof('berm_body', [(-1.4, 0), (1.4, 0), (0.45, h), (-0.45, h)], length, m=M('earth', (0.42, 0.33, 0.22), 0.95), parent=root, plane='XZ', bevel=0.05)
    for i in range(int(length / 0.6)):
        box('crest_bag', (0.55, 0.38, 0.17), (RND.uniform(-0.15, 0.15), -length / 2 + 0.3 + i * 0.6, h + 0.08), (0, 0, RND.uniform(-8, 8)), m=mm['sandbag'], parent=root, bevel=0.07, segs=3)
    col((x, y, (h + 0.2) / 2), (1.6, length, h + 0.2), rotz=rot)


def cannon(x, y, rot, mm, z=0.0):
    root = empty('cannon', (x, y, z)); root.rotation_euler = (0, 0, math.radians(rot))
    iron = M('cannon_iron', (0.12, 0.12, 0.12), 0.45, 0.85)
    cyl('cn_barrel', 0.32, 3.4, (0, 0.9, 1.25), (-6, 0, 0), m=iron, parent=root, axis='Y', verts=24, r2=0.22, bevel=0.03)
    torus('cn_ring', 0.33, 0.05, (0, -0.6, 1.1), (90, 0, 0), m=iron, parent=root, seg=24, mseg=6)
    cyl('cn_muzzle', 0.26, 0.25, (0, 2.6, 1.42), (-6, 0, 0), m=iron, parent=root, axis='Y', verts=24)
    box('cn_carriage', (1.1, 2.4, 0.7), (0, 0, 0.55), m=mm['beam'], parent=root, bevel=0.05)
    for sx in (-1, 1):
        cyl('cn_wheel', 0.55, 0.14, (sx * 0.62, 0.4, 0.55), m=mm['beam'], parent=root, axis='X', verts=20)
    col((x, y, z + 0.8), (1.4, 3.4, 1.6), rotz=rot)


def tent(x, y, rot, mm, w=4, l=5, h=2.6):
    root = empty('tent', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    prof('tent_body', [(-w / 2, 0), (w / 2, 0), (0, h)], l, m=M('canvas', (0.55, 0.52, 0.4), 0.9), parent=root, plane='XZ', bevel=0.02)
    col((x, y, h / 3), (w * 0.8, l, h * 0.66), rotz=rot)


def map_canakkale_v3():   # pre-v4.12 layout, kept for reference (not in ALL)
    mm = begin()
    X0, X1, Y0, Y1 = -62, 56, -46, 46
    grass = M('dry_grass', (0.5, 0.48, 0.28), 0.95)
    ground('land', X0 - 260, Y0 - 260, X1 + 2, Y1 + 260, 0, grass)
    box('path', (6, 92, 0.04), (-8, 0, 0.02), m=M('path_dirt', (0.55, 0.45, 0.32), 0.95))
    # cliff edge and the strait (Boğaz) to the east, far shore on the Asian side
    prof('cliff', [(0, 0), (6, 0), (9, -14), (0, -14)], 300, m=mm['stone'], plane='XZ', loc=(X1 + 2, 0, 0), bevel=0.2) if False else None
    box('cliff', (8, 600, 14), (X1 + 6, 0, -7), m=M('cliff_rock', (0.6, 0.55, 0.45), 0.9))
    box('beach', (30, 600, 1), (X1 + 22, 0, -2.6), m=M('sand', (0.82, 0.7, 0.5), 0.95))
    box('sea', (3000, 3000, 0.1), (X1 + 1530, 0, -2.2), m=mm['water'])
    box('far_shore', (120, 2400, 40), (X1 + 1300, 0, -10), m=M('far_hills', (0.45, 0.5, 0.35), 0.95))
    for i in range(5):
        box('far_ship', (80, 14, 14), (X1 + 500 + i * 120, -500 + i * 260, -2), m=mm['hull_dark'])
    # ---- coastal fortress (north-east), enterable courtyard
    FX, FY, FW, FD, FH = 22, 22, 40, 28, 7.0
    stone = M('fort_stone', (0.72, 0.66, 0.55), 0.9)
    for (cx, cy, sx, sy) in [(FX, FY + FD / 2, FW, 2.4), (FX - FW / 2, FY, 2.4, FD)]:
        wall('fort_wall', cx, cy, 0, sx, sy, FH, stone, uv=0.25)
    # east (sea) wall with gun embrasures, south wall with gate
    for k in range(5):
        a = FY - FD / 2 + 2.5 + k * 5.8
        wall('fort_e', FX + FW / 2, a, 0, 2.4, 3.6, FH, stone, uv=0.25)
    wall('fort_e_low', FX + FW / 2, FY, 0, 2.4, FD, 1.6, stone, uv=0.25)
    for (a, b) in [(-20, -4), (4, 20)]:
        wall('fort_s', FX + (a + b) / 2, FY - FD / 2, 0, b - a, 2.4, FH, stone, uv=0.25)
    box('gate_arch', (8, 2.6, 2.2), (FX, FY - FD / 2, FH - 1.1), m=stone)
    # merlons
    for i in range(int(FW / 2.4)):
        box('merlon', (1.3, 2.5, 1.2), (FX - FW / 2 + 1.2 + i * 2.4, FY + FD / 2, FH + 0.6), m=stone)
    # wall-walk ramps (inside) so the battlements are playable
    stairs('fort_r1', FX - FW / 2 + 3.2, FY + 2, 0, FH, 12, 3, stone, axis='Y', direction=1)
    stairs('fort_r2', FX + 6, FY + FD / 2 - 3.2, 0, FH, 12, 3, stone, axis='X', direction=-1)
    ground('walkway_n', FX - FW / 2, FY + FD / 2 - 4.7, FX + FW / 2, FY + FD / 2 - 1.2, FH - 0.05, stone, thick=0.3)
    # bastion towers
    for (tx, ty) in [(FX - FW / 2, FY + FD / 2), (FX + FW / 2, FY - FD / 2), (FX - FW / 2, FY - FD / 2)]:
        cyl('bastion', 5.0, FH + 3, (tx, ty, (FH + 3) / 2), m=stone, axis='Z', verts=24, uv=0.25)
        col((tx, ty, (FH + 3) / 2), (8.6, 8.6, FH + 3))
    # cannons at the sea embrasures + cannonball stacks
    for k in range(4):
        cannon(FX + FW / 2 - 3.2, FY - FD / 2 + 5.4 + k * 5.8, -90, mm)
    for (bx, by) in [(FX + 12, FY - 9), (FX + 12, FY + 7)]:
        for i in range(10):
            sphere('ball', 0.18, (bx + (i % 4) * 0.37 - 0.55, by + (i // 4) * 0.37, 0.18 + (i // 4) * 0.2), m=M('cannon_iron', (0.12, 0.12, 0.12), 0.45, 0.85))
    for (cx, cy) in [(FX - 8, FY - 2), (FX + 4, FY + 6), (FX - 14, FY + 8)]:
        crate(cx, cy, 0, 1.3, mm, rot=RND.uniform(-20, 20))
        wood_barrel(cx + 1.6, cy, mm)
    # flag on the bastion
    cyl('flagpole', 0.08, 12, (FX - FW / 2, FY + FD / 2, FH + 3 + 6), m=mm['steel'], axis='Z', verts=8)
    box('flag', (0.05, 5.4, 3.6), (FX - FW / 2, FY + FD / 2 + 2.75, FH + 3 + 10), m=mm['flag_tr'])
    # ---- trench line (south-west), zig-zag earth berms
    for (x, y, l, r) in [(-44, -20, 18, 0), (-38, -20, 18, 0), (-41, -6, 10, 90), (-30, -30, 14, 60), (-24, -24, 14, 60),
                         (-48, 4, 14, 0), (-42, 4, 14, 0), (-34, 16, 12, 120), (-28, 12, 12, 120), (-52, -34, 10, 90)]:
        berm(x, y, l, r, mm)
    for (x, y, r) in [(-20, -8, 0), (-14, 8, 90), (-26, 28, 20), (0, -30, 90), (4, 12, 0), (-4, 30, 90)]:
        sandbags(x, y, 4.5, 4, mm, rot=r)
    for (x, y, r) in [(-46, 22, 0), (-52, 30, 90), (-36, 34, 30)]:
        tent(x, y, r, mm)
    # wooden barbed-wire posts (visual)
    for i in range(14):
        cyl('wire_post', 0.06, 1.3, (-60 + i * 3.2, -42, 0.65), m=mm['beam'], axis='Z', verts=6)
    box('wire', (44, 0.03, 0.03), (-39, -42, 1.1), m=mm['cable'])
    # rocks and pines
    for i in range(18):
        rx, ry = RND.uniform(X0 + 4, X1 - 8), RND.uniform(Y0 + 4, Y1 - 4)
        if (FX - FW / 2 - 6 < rx < FX + FW / 2 + 6 and FY - FD / 2 - 6 < ry < FY + FD / 2 + 6) or abs(rx + 8) < 4:
            continue
        sphere('rock', RND.uniform(0.8, 1.6), (rx, ry, 0.3), m=M('rock', (0.55, 0.52, 0.47), 0.9), scale=(1.3, 1.0, 0.7))
        col((rx, ry, 0.6), (2.0, 1.6, 1.2))
    for i, (tx, ty) in enumerate([(-58, 40), (-50, 42), (-30, 40), (-12, 42), (-58, -10), (-6, -40), (8, -42), (30, -40), (-20, 22)]):
        tree(tx, ty, mm, h=RND.uniform(6, 8), r=2.2, seed=i)
    # modern visitor road with the military display
    box('asphalt_road', (8, 92, 0.05), (40, -30, 0.03), (0, 0, 90), m=mm['asphalt'])
    usd_prop('sr5', 30, -30, 90)
    car(6, -36, 180, ('blue', (0.06, 0.15, 0.4)), mm)
    for (jx, jy, r) in [(18, -24, 0), (44, -24, 0)]:
        jersey(jx, jy, r, mm)
    spawns_a = [(10, 18, 180), (16, 14, 200), (26, 16, 180), (32, 20, 160), (20, 26, 180), (28, 12, 210)]
    spawns_b = [(-50, -30, 30), (-44, -36, 20), (-56, -18, 60), (-38, -40, 10), (-52, -4, 70), (-30, -40, 0)]
    for i, (x, y, yaw) in enumerate(spawns_a + spawns_b):
        spawn(x, y, 0.1, yaw, 'a' if i < 6 else 'b')
    bounds_walls(X0, Y0, X1, Y1, 22)
    finalize('canakkale', dict(preset='golden', sun=[-40, 250], fog=0.008, sky='sunset', water=True), [X0, Y0, X1, Y1])


# ======================================================================== MAP (v4.12): ÇANAKKALE — Mecidiye Tabyası (Boğaz kıyı bataryası)
# Spliced into maps.py. Design notes: docs/MAP_DESIGN.md#canakkale
#   centre : stone redoubt (kale) x -8..18, y -13..13 — N/S gates, E/W posterns, wall-walk ring at 5 m,
#            courtyard with a barrack and a depot (rotational symmetry about (5, 0))
#   east   : coastal battery on the cliff — 4 gun pits between 5 earth traverses (y -30..30), each traverse
#            pierced by a vaulted magazine tunnel that links the pits (N-S lane under cover)
#   west   : zig-zag trench line (x -50..-42) + stone farmhouse with a walled yard + olive grove
#   N / S  : opposing army camps (spawns), sandbag + crate screens

CK_C = (5.0, 0.0)          # symmetry centre


def ck_mats(mm):
    return dict(
        fort=M('fort_stone', (0.72, 0.66, 0.55), 0.9), stone=M('ruin_stone_dark', (0.6, 0.56, 0.5), 0.9), revet=M('fort_wall', (0.7, 0.64, 0.54), 0.9),
        grass=M('dry_grass2', (0.55, 0.5, 0.3), 0.95), house=mm['stone'],
        path=M('site_dirt', (0.55, 0.45, 0.32), 0.95), cobble=mm['cobble'], soil=M('soil_wall', (0.45, 0.36, 0.26), 0.95),
        earth=M('earth', (0.42, 0.33, 0.22), 0.95), bag=mm['sandbag'], beam=mm['beam'], planks=mm['planks'],
        iron=M('cannon_iron', (0.12, 0.12, 0.12), 0.45, 0.85), roof=mm['roof'], white=M('white_plaster', (0.88, 0.86, 0.8), 0.9),
        canvas=M('canvas', (0.62, 0.58, 0.45), 0.9), rock=M('cliff_rock', (0.6, 0.55, 0.45), 0.9), gravel=M('gravel', (0.5, 0.48, 0.45), 0.95),
        brass=M('gun_brass', (0.72, 0.55, 0.25), 0.35, 0.9), lamp=mm['lamp'], sand=M('sand', (0.82, 0.7, 0.5), 0.95), mm=mm,
    )


def ck_mound(name, x0, x1, y, h, k, base=6.0, top=2.0, m=None):
    """earth traverse running along X (x0..x1) centred on y: trapezoid section, grass-capped"""
    L = x1 - x0
    if L <= 0.1:
        return
    prof(name, [(-base / 2, 0), (base / 2, 0), (top / 2, h), (-top / 2, h)], L, ((x0 + x1) / 2, y, 0), m=m or k['grass'], plane='YZ', bevel=0.0)
    box(name + '_cap', (L, top + 0.3, 0.12), ((x0 + x1) / 2, y, h + 0.02), m=k['grass'])
    for (w, z0, z1) in [(base * 0.92, 0, h * 0.4), (base * 0.6, h * 0.4, h * 0.75), (top + 0.4, h * 0.75, h)]:
        col(((x0 + x1) / 2, y, (z0 + z1) / 2), (L, w, z1 - z0))


def ck_traverse(y, x0, x1, tx, k, h=3.4):
    """earth traverse with a vaulted magazine tunnel (2.6 wide, 2.5 high) running N-S through it at x = tx"""
    hw = 1.3
    ck_mound('trav', x0, tx - hw - 0.6, y, h, k)
    ck_mound('trav', tx + hw + 0.6, x1, y, h, k)
    # tunnel: masonry side walls, vault (barrel of stone segments), earth on top, portals both faces
    for sx in (-1, 1):
        wall('mag_wall', tx + sx * (hw + 0.3), y, 0, 0.6, 6.0, 2.5, k['revet'])
    for i in range(7):
        a = math.radians(180 * (i + 0.5) / 7)
        box('mag_vault', (2 * hw * math.sin(math.pi / 14) * 1.15, 6.0, 0.35), (tx - math.cos(a) * hw, y, 2.4 + math.sin(a) * 0.55), (0, math.degrees(a) - 90, 0), m=k['fort'])
    wall('mag_roof', tx, y, 2.5, 2 * hw + 1.2, 6.0, 0.5, k['revet'])
    prof('mag_earth', [(-3.0, 3.0), (3.0, 3.0), (1.0, h), (-1.0, h)], 2 * hw + 1.2, (tx, y, 0), m=k['grass'], plane='YZ', bevel=0.0)
    col((tx, y, (3.0 + h) / 2), (2 * hw + 1.2, 4.0, h - 3.0))
    for sy in (-1, 1):
        fy = y + sy * 3.05
        for sx in (-1, 1):
            box('portal_pier', (0.7, 0.4, 2.9), (tx + sx * (hw + 0.35), fy, 1.45), m=k['revet'], bevel=0.03)
        box('portal_lintel', (2 * hw + 1.4, 0.45, 0.6), (tx, fy, 3.1), m=k['revet'], bevel=0.03)
        box('portal_key', (0.5, 0.5, 0.7), (tx, fy, 3.15), m=k['stone'], bevel=0.04)
    # shell racks inside the magazine
    for sx in (-1, 1):
        for i in range(9):
            ssx, ssy = tx + sx * (hw - 0.25), y - 2.2 + i * 0.55
            cyl('shell_case', 0.12, 0.42, (ssx, ssy, 0.35), m=k['brass'], axis='Z', verts=12)
            cyl('shell_band', 0.125, 0.04, (ssx, ssy, 0.58), m=M('copper_band', (0.6, 0.3, 0.15), 0.4, 0.9), axis='Z', verts=12)
            lathe('shell_nose', [(0.115, 0.0), (0.1, 0.12), (0.06, 0.24), (0.0, 0.3)], (ssx, ssy, 0.6), m=k['iron'], seg=12)
        box('shell_rack', (0.35, 5.0, 0.08), (tx + sx * (hw - 0.25), y, 0.12), m=k['beam'])
    box('mag_lamp', (0.2, 0.2, 0.25), (tx, y, 2.2), m=k['lamp'])


def ck_krupp(x, y, rot, k):
    """WWI-era coastal gun on a pivot mount (procedural, period-correct silhouette)"""
    root = empty('krupp', (x, y, 0)); root.rotation_euler = (0, 0, math.radians(rot))
    cyl('kr_pivot', 1.25, 0.35, (0, 0, 0.42), m=k['iron'], parent=root, axis='Z', verts=28, bevel=0.03)
    cyl('kr_race', 1.6, 0.12, (0, 0, 0.3), m=k['iron'], parent=root, axis='Z', verts=32)
    for sx in (-1, 1):
        prof('kr_cheek', [(-1.2, 0.6), (0.9, 0.6), (0.6, 1.9), (-0.8, 1.6)], 0.16, (sx * 0.55, 0, 0), m=k['iron'], parent=root, plane='YZ', bevel=0.02)
    cyl('kr_trunnion', 0.14, 1.4, (0, 0, 1.6), m=k['iron'], parent=root, axis='X', verts=12)
    cyl('kr_barrel', 0.3, 5.6, (0, 2.0, 1.72), (-4, 0, 0), m=k['iron'], parent=root, axis='Y', verts=24, r2=0.19, bevel=0.02)
    cyl('kr_jacket', 0.36, 1.8, (0, 0.2, 1.62), (-4, 0, 0), m=k['iron'], parent=root, axis='Y', verts=24)
    torus('kr_muzzle', 0.2, 0.05, (0, 4.75, 2.06), (86, 0, 0), m=k['iron'], parent=root, seg=20, mseg=6)
    box('kr_breech', (0.62, 0.55, 0.62), (0, -0.95, 1.56), m=k['iron'], parent=root, bevel=0.05)
    torus('kr_handwheel', 0.32, 0.03, (0.85, -0.4, 1.2), (0, 90, 0), m=k['iron'], parent=root, seg=18, mseg=5)
    col((x, y, 1.0), (2.6, 2.6, 2.0), rotz=rot)


def ck_gun_pit(x, y, k):
    """circular stone gun platform with an earth parapet (stone-revetted) towards the sea (east)"""
    cyl('pit_floor', 3.6, 0.22, (x, y, 0.11), m=k['fort'], axis='Z', verts=32)
    col((x, y, 0.11), (7.0, 7.0, 0.22))
    n = 9
    for i in range(n):
        a = math.radians(-78 + 156 * i / (n - 1))
        px, py = x + math.cos(a) * 4.6, y + math.sin(a) * 4.6
        wall('pit_rev', px, py, 0, 1.0, 2.1, 1.35, k['revet'], rot=math.degrees(a))
        prof('pit_earth', [(-1.5, 0), (1.5, 0), (0.6, 1.5), (-0.6, 1.5)], 2.1, (px + math.cos(a) * 1.4, py + math.sin(a) * 1.4, 0), (0, 0, math.degrees(a) + 90), m=k['grass'], plane='YZ', bevel=0.0)
        col((px + math.cos(a) * 1.2, py + math.sin(a) * 1.2, 0.75), (2.4, 2.1, 1.5), rotz=math.degrees(a))
    ck_krupp(x, y, -90, k)
    # ready-use ammunition: shells on a cradle + a wooden fuse box (west side of the pit)
    for i in range(6):
        cyl('shell_r', 0.13, 0.7, (x - 3.1, y - 1.0 + i * 0.36, 0.36), m=k['brass'], axis='X', verts=10, r2=0.07)
    box('cradle', (0.9, 2.4, 0.18), (x - 3.1, y - 0.1, 0.09), m=k['beam'])
    col((x - 3.1, y - 0.1, 0.3), (0.9, 2.4, 0.6))
    crate(x - 3.3, y + 2.2, 0, 0.9, k['mm'], rot=10)


def ck_tent(x, y, rot, k, r=2.6, h=3.0):
    """conical army bell tent with pole and guy ropes"""
    lathe('tent_cone', [(r, 0.0), (r * 0.96, 0.35), (r * 0.55, h * 0.55), (0.06, h)], (x, y, 0), (0, 0, rot), m=k['canvas'], seg=18)
    cyl('tent_pole', 0.04, 0.6, (x, y, h + 0.25), m=k['beam'], axis='Z', verts=6)
    for i in range(6):
        a = math.radians(rot + i * 60)
        cyl('tent_rope', 0.01, 1.6, (x + math.cos(a) * (r + 0.55), y + math.sin(a) * (r + 0.55), 0.4), (0, 50, i * 60 + rot), m=M('rope', (0.5, 0.42, 0.3), 0.9), axis='Z', verts=3)
    col((x, y, h * 0.35), (r * 1.4, r * 1.4, h * 0.7))


def ck_trench(x, y0, y1, k, inner=2.6, east_gaps=(), west_gaps=(), bays=()):
    """N-S fire trench: earth parapets with sandbag crests both sides, duckboard floor, alternating sandbag
    traverses (zig-zag walking line, no straight shot down the trench), exits as gaps in the parapets"""
    off = inner / 2 + 1.25
    for (sx, gaps) in [(-1, west_gaps), (1, east_gaps)]:
        pos = y0
        for (g0, g1) in sorted(gaps) + [(y1, y1)]:
            if g0 - pos > 1.0:
                berm(x + sx * off, (pos + g0) / 2, g0 - pos, 0, {'sandbag': k['bag']}, h=1.45)
            pos = g1
    for i in range(int((y1 - y0) / 1.2)):
        box('duckboard', (1.4, 1.0, 0.05), (x, y0 + 0.6 + i * 1.2, 0.03), m=k['planks'])
    for j, by in enumerate(bays):
        sx = -1 if j % 2 == 0 else 1
        bx = x + sx * (inner / 2 - 0.7)
        for lv in range(8):
            box('trav_bag', (1.4, 0.4, 0.18), (bx + RND.uniform(-0.04, 0.04), by + (lv % 2) * 0.42 - 0.21, 0.09 + (lv // 2) * 0.18 * 2), (0, 0, RND.uniform(-5, 5)), m=k['bag'], bevel=0.06, segs=3)
        col((bx, by, 0.75), (1.4, 1.0, 1.5))


def ck_mg_nest(x, y, k, r=2.0):
    for i in range(10):
        a = math.radians(30 + i * 30)
        for lv in range(4):
            box('mg_bag', (0.6, 0.36, 0.17), (x + math.cos(a) * r, y + math.sin(a) * r, 0.09 + lv * 0.17), (0, 0, i * 30 + 120 + RND.uniform(-6, 6)), m=k['bag'], bevel=0.06, segs=3)
        col((x + math.cos(a) * r, y + math.sin(a) * r, 0.35), (0.7, 0.45, 0.7), rotz=i * 30 + 120)


def ck_stone_house(name, x, y, w, d, k, rot=0, door_sides=('N', 'S'), floors=1, partition=True):
    """two-room rural stone house: 0.6 m rubble walls, timber lintels, hipped tile roof"""
    H = 3.2
    T = 0.6
    x0, x1, y0, y1 = x - w / 2, x + w / 2, y - d / 2, y + d / 2
    def side(ax, ay, bx, by, door):
        L = math.hypot(bx - ax, by - ay); r = math.degrees(math.atan2(by - ay, bx - ax))
        c_, s_ = math.cos(math.radians(r)), math.sin(math.radians(r))
        cx, cy = (ax + bx) / 2, (ay + by) / 2
        ops = [(-L / 4, 1.0, 1.0, 1.1), (L / 4, 1.0, 1.0, 1.1)]           # windows (offset, width, sill, height)
        if door:
            ops[0] = (-L / 6, 1.3, 0.0, 2.2)
        cuts = sorted([(o - wdt / 2, o + wdt / 2, sl, sl + hh) for (o, wdt, sl, hh) in ops])
        pos = -L / 2
        for (a0, a1, z0, z1) in cuts:
            if a0 > pos:
                wall(name, cx + c_ * (pos + a0) / 2, cy + s_ * (pos + a0) / 2, 0, a0 - pos, T, H, k['house'], rot=r)
            if z0 > 0.05:
                wall(name, cx + c_ * (a0 + a1) / 2, cy + s_ * (a0 + a1) / 2, 0, a1 - a0, T, z0, k['house'], rot=r)
            wall(name, cx + c_ * (a0 + a1) / 2, cy + s_ * (a0 + a1) / 2, z1, a1 - a0, T, H - z1, k['house'], rot=r)
            box('lintel', (a1 - a0 + 0.4, T + 0.06, 0.18), (cx + c_ * (a0 + a1) / 2, cy + s_ * (a0 + a1) / 2, z1 + 0.09), (0, 0, r), m=k['beam'])
            if z0 > 0.05:
                box('shutter', (a1 - a0, 0.05, z1 - z0), (cx + c_ * (a0 + a1) / 2 - s_ * T * 0.55, cy + s_ * (a0 + a1) / 2 + c_ * T * 0.55, (z0 + z1) / 2), (0, 0, r + 12), m=M('shutter_brown', (0.45, 0.28, 0.15)))
            pos = a1
        if pos < L / 2:
            wall(name, cx + c_ * (pos + L / 2) / 2, cy + s_ * (pos + L / 2) / 2, 0, L / 2 - pos, T, H, k['house'], rot=r)
    side(x0, y1, x1, y1, 'N' in door_sides)
    side(x1, y0, x0, y0, 'S' in door_sides)
    side(x0, y0, x0, y1, 'W' in door_sides)
    side(x1, y1, x1, y0, 'E' in door_sides)
    # interior partition with a door, floor boards, ceiling beams
    if partition:
        wall(name + '_part', x - 0.7 - (w / 2 - T) / 2 + 0.35, y, 0, w / 2 - T - 0.7, 0.3, H, k['stone'])
        wall(name + '_part', x + 0.7 + (w / 2 - T) / 2 - 0.35, y, 0, w / 2 - T - 0.7, 0.3, H, k['stone'])
        wall(name + '_part', x, y, 2.2, 1.4, 0.3, H - 2.2, k['stone'])
    box('floor', (w - 2 * T, d - 2 * T, 0.05), (x, y, 0.025), m=k['planks'])
    for i in range(int(w / 0.9)):
        box('ceil_beam', (0.18, d - 0.2, 0.2), (x0 + 0.5 + i * 0.9, y, H - 0.1), m=k['beam'])
    wall(name + '_ceil', x, y, H, w + 0.2, d + 0.2, 0.12, k['beam'])
    hip_roof(name + '_roof', x, y, w, d, H + 0.12, 1.7, k['roof'], over=0.5)


def ck_well(x, y, k):
    lathe('well', [(0.9, 0.0), (0.9, 0.85), (0.7, 0.85), (0.7, 0.1)], (x, y, 0), m=k['fort'], seg=20)
    for sx in (-1, 1):
        box('well_post', (0.14, 0.14, 2.0), (x + sx * 0.8, y, 1.0), m=k['beam'])
    box('well_beam', (1.9, 0.14, 0.14), (x, y, 2.0), m=k['beam'])
    col((x, y, 0.45), (1.8, 1.8, 0.9))


def map_canakkale():
    mm = begin()
    k = ck_mats(mm)
    X0, X1, Y0, Y1 = -60, 52, -46, 46
    # ---------------------------------------------------------------- ground, paths, coast
    ground('land', X0 - 2, Y0 - 2, X1, Y1 + 2, 0, k['grass'])
    ground('land_far', X0 - 260, Y0 - 260, X1, Y0 - 2, 0, k['grass'])
    ground('land_far', X0 - 260, Y1 + 2, X1, Y1 + 260, 0, k['grass'])
    ground('land_far', X0 - 260, Y0 - 2, X0 - 2, Y1 + 2, 0, k['grass'])
    for (cx, cy, sx, sy, r) in [(5, 24, 4, 26, 0), (5, -24, 4, 26, 0), (32, 0, 4.5, 84, 0), (-21, 0, 3.5, 70, 0),
                                (-8, 33, 30, 3.5, 0), (18, -33, 30, 3.5, 0), (24, 0, 12, 3.5, 0), (-14, 0, 12, 3.5, 0)]:
        box('track', (sx, sy, 0.035), (cx, cy, 0.018), (0, 0, r), m=k['path'])
    # cliff to the strait (Boğaz): rock face down to a sand beach and the sea
    # (sea itself: outskirts, theme sea_y -9 m; the terrain under the bluff is cut via terrain_holes)
    prof('cliff', [(0, 0.0), (1.2, -0.6), (3.0, -3.8), (4.6, -5.2), (6.5, -8.4), (9.0, -9.6), (16, -9.8), (16, -16), (0, -16)], 600, (X1, 0, 0), m=k['rock'], plane='XZ', bevel=0.0)
    box('beach', (9, 600, 1), (X1 + 12.5, 0, -9.45), m=k['sand'])
    for i in range(26):
        sphere('shore_rock', WRND.uniform(0.8, 2.2), (X1 + WRND.uniform(7, 18), WRND.uniform(-140, 140), -9.5), m=k['rock'], scale=(1.4, 1.0, 0.6))
    # ---------------------------------------------------------------- EAST: coastal battery (x 30..50)
    BX = 44.0
    for y in (-26.0, -9.0, 9.0, 26.0):
        ck_gun_pit(BX, y, k)
    for y in (-35.0, -17.5, 0.0, 17.5, 35.0):
        ck_traverse(y, 37.0, 50.5, 42.0, k)
    # battery road wall (west side), with openings at the traverse ends
    for (ya, yb) in [(-44, -37), (-33, -20), (-15, -3), (3, 15), (20, 33), (37, 44)]:
        wall('batt_wall', 35.2, (ya + yb) / 2, 0, 0.6, yb - ya, 1.1, k['revet'])
    # observation post on the middle traverse (gun-laying hut)
    wall('op_wall', 46.8, 0, 3.4, 2.4, 0.3, 1.2, k['fort'])
    for (ox, oy) in [(44.2, 12.5), (44.2, -12.5)]:
        crate(ox, oy, 0, 1.0, mm, rot=RND.uniform(-15, 15))
        wood_barrel(ox + 1.2, oy + 0.3, mm)
    # ---------------------------------------------------------------- CENTRE: stone redoubt
    FX0, FX1, FY0, FY1, FT, FH = -8.0, 18.0, -13.0, 13.0, 2.2, 5.0
    GW = 3.4         # main gate width (N/S, x = 5)
    PW = 1.6         # postern width
    def fwall(ax, ay, bx, by, gaps):
        """straight fort wall from a to b (axis aligned) with gate gaps [(centre, width, height)]"""
        horiz = abs(by - ay) < 1e-6
        L = abs(bx - ax) if horiz else abs(by - ay)
        s0 = min(ax, bx) if horiz else min(ay, by)
        pos = s0
        cuts = sorted([(c - w / 2, c + w / 2, h) for (c, w, h) in gaps])
        for (c0, c1, gh) in cuts + [(s0 + L, s0 + L, 0)]:
            if c0 > pos + 0.01:
                if horiz:
                    wall('fwall', (pos + c0) / 2, ay, 0, c0 - pos, FT, FH, k['fort'])
                else:
                    wall('fwall', ax, (pos + c0) / 2, 0, FT, c0 - pos, FH, k['fort'])
            if c1 > c0:
                if horiz:
                    wall('fwall_over', (c0 + c1) / 2, ay, gh, c1 - c0, FT, FH - gh, k['fort'])
                    box('gate_arch_l', (0.3, FT + 0.1, gh), (c0 + 0.15, ay, gh / 2), m=k['stone'])
                    box('gate_arch_r', (0.3, FT + 0.1, gh), (c1 - 0.15, ay, gh / 2), m=k['stone'])
                else:
                    wall('fwall_over', ax, (c0 + c1) / 2, gh, FT, c1 - c0, FH - gh, k['fort'])
            pos = c1
    fwall(FX0, FY1 - FT / 2, FX1, FY1 - FT / 2, [(5.0, GW, 3.6)])
    fwall(FX0, FY0 + FT / 2, FX1, FY0 + FT / 2, [(5.0, GW, 3.6)])
    fwall(FX0 + FT / 2, FY0 + FT, FX0 + FT / 2, FY1 - FT, [(5.0, PW, 2.3)])
    fwall(FX1 - FT / 2, FY0 + FT, FX1 - FT / 2, FY1 - FT, [(-5.0, PW, 2.3)])
    # parapet with merlons (crenels to shoot through) on the outer edge of the wall-walk, all four sides
    for (ax, ay, bx, by, ox, oy) in [(FX0, FY1, FX1, FY1, 0, -0.3), (FX0, FY0, FX1, FY0, 0, 0.3), (FX0, FY0, FX0, FY1, 0.3, 0), (FX1, FY0, FX1, FY1, -0.3, 0)]:
        L = math.hypot(bx - ax, by - ay); n = int(L / 2.0)
        for i in range(n):
            t = (i + 0.5) / n
            px, py = ax + (bx - ax) * t + ox, ay + (by - ay) * t + oy
            horiz = abs(by - ay) < 1e-6
            wall('merlon', px, py, FH, 1.1 if horiz else 0.6, 0.6 if horiz else 1.1, 1.15, k['fort'])
        box('parapet_low', (L if abs(by - ay) < 1e-6 else 0.6, 0.6 if abs(by - ay) < 1e-6 else L, 0.55), ((ax + bx) / 2 + ox, (ay + by) / 2 + oy, FH + 0.27), m=k['fort'])
        col(((ax + bx) / 2 + ox, (ay + by) / 2 + oy, FH + 0.27), (L if abs(by - ay) < 1e-6 else 0.6, 0.6 if abs(by - ay) < 1e-6 else L, 0.55))
    # string course + plinth (reads as masonry architecture, not flat boxes)
    for (cx, cy, sx, sy) in [((FX0 + FX1) / 2, FY1 + 0.05, FX1 - FX0 + 0.2, 0.25), ((FX0 + FX1) / 2, FY0 - 0.05, FX1 - FX0 + 0.2, 0.25),
                             (FX0 - 0.05, 0, 0.25, FY1 - FY0 + 0.2), (FX1 + 0.05, 0, 0.25, FY1 - FY0 + 0.2)]:
        box('string_course', (sx, sy, 0.22), (cx, cy, FH - 0.35), m=k['stone'])
        box('plinth', (sx + (0.3 if sx < 1 else 0), sy + (0.3 if sy < 1 else 0), 0.7), (cx, cy, 0.35), m=k['stone'])
    # corner bastions (NW, SE): octagonal, same level as the wall-walk
    for (tx, ty) in [(FX0, FY1), (FX1, FY0)]:
        cyl('bastion', 4.0, FH, (tx, ty, FH / 2), m=k['fort'], axis='Z', verts=8)
        col((tx, ty, FH / 2), (6.6, 6.6, FH))
        for i in range(8):
            a = math.radians(i * 45 + 22.5)
            wall('b_merlon', tx + math.cos(a) * 3.6, ty + math.sin(a) * 3.6, FH, 1.2, 0.6, 1.15, k['fort'], rot=i * 45 + 22.5 + 90)
    # stone stairs up to the wall-walk (W wall inner face going N, E wall inner face going S — symmetric)
    stairs('fort_st_w', FX0 + FT + 0.8, -4.5, 0, FH, 9.0, 1.6, k['stone'], axis='Y', direction=1)
    stairs('fort_st_e', FX1 - FT - 0.8, 4.5, 0, FH, 9.0, 1.6, k['stone'], axis='Y', direction=-1)
    # courtyard: cobbles, well, barrack (SW) and depot (NE) — mirror images through the centre
    box('court', (FX1 - FX0 - 2 * FT, FY1 - FY0 - 2 * FT, 0.04), ((FX0 + FX1) / 2, 0, 0.02), m=k['cobble'])
    ck_well(5.0, 0.0, k)
    # each gate opens onto a building (no straight shot through the fort from gate to gate)
    ck_stone_house('barrack', 5.0, -6.8, 6.4, 4.2, k, door_sides=('N',), partition=False)
    ck_stone_house('depot', 5.0, 6.8, 6.4, 4.2, k, door_sides=('S',), partition=False)
    for (px, py) in [(9.5, -8.5), (0.5, 8.5)]:
        for i in range(10):
            sphere('ball', 0.17, (px + (i % 4) * 0.35 - 0.5, py + (i // 4) * 0.33, 0.17 + (i // 4) * 0.19), m=k['iron'])
        col((px, py, 0.4), (1.6, 1.2, 0.8))
    for (cx, cy, r) in [(12.0, -3.0, 15), (-2.0, 3.0, -20)]:
        crate(cx, cy, 0, 1.2, mm, rot=r)
        crate(cx + 1.3, cy + 0.2, 0, 1.2, mm, rot=r + 8)
    # flag on the NW bastion
    cyl('flagpole', 0.07, 9, (FX0, FY1, FH + 4.5), m=mm['steel'], axis='Z', verts=8)
    box('flag', (0.05, 3.6, 2.4), (FX0, FY1 + 1.85, FH + 7.6), m=mm['flag_tr'])
    # ---------------------------------------------------------------- WEST: trench line + farmhouse + olive grove
    TX = -46.0
    ck_trench(TX, -36, 36, k, east_gaps=[(-13, -9), (-2, 2), (9, 13)], west_gaps=[(-24, -20), (20, 24)],
              bays=[-30, -22, -6, 6, 22, 30])
    for (mx, my) in [(TX, -38.5), (TX, 38.5)]:
        ck_mg_nest(mx, my, k)
    ck_stone_house('farm', -28.0, 0.0, 9.0, 7.0, k, door_sides=('N', 'S', 'E'))
    garden_wall((-36, -9), (-20, -9), mm, h=1.4)
    garden_wall((-36, 9), (-20, 9), mm, h=1.4)
    garden_wall((-36, -9), (-36, -3), mm, h=1.4)
    garden_wall((-36, 3), (-36, 9), mm, h=1.4)
    for (bx2, by2) in [(-22.5, -6.5), (-33.5, 6.5)]:
        wood_barrel(bx2, by2, mm)
    sandbags(-20.5, 0.0, 3.0, 3, mm, rot=90)
    # olive grove (rows) west of the trench, around the farm and between the camps
    for row in range(3):
        for i in range(9):
            x = -57.8 + row * 3.0 + WRND.uniform(-0.3, 0.3)
            y = -36 + i * 9 + WRND.uniform(-1.2, 1.2) + (row % 2) * 4.5
            if abs(y) > 42:
                continue
            imp_tree(x, y, WRND.uniform(4.2, 6.0), 'olive')
    for (x, y, h) in [(-24, 13, 9.5), (-32, -13, 10.0), (-14, 22, 5.5), (24, -22, 5.5), (-14, -24, 5.2), (24, 24, 5.0)]:
        imp_tree(x, y, h, 'broad' if h > 7 else 'olive')
    # ---------------------------------------------------------------- flank sight-line breakers (mirror pairs)
    for sy in (1, -1):
        # stone guardhouse on the battery road, hay barn between farm and fort
        ck_stone_house('guard', 31.5, sy * 21.0, 4.4, 4.0, k, door_sides=('W',), partition=False)
        for lv in range(3):
            for i in range(4 - lv):
                box('hay', (1.2, 2.4, 0.95), (-17.0 - 1.5 + i * 1.25 + lv * 0.62, sy * 20.0, 0.47 + lv * 0.95), m=M('dry_grass', (0.75, 0.65, 0.35), 0.95), bevel=0.12, segs=2)
        col((-17.0, sy * 20.0, 1.43), (5.0, 2.4, 2.85))
    # ---------------------------------------------------------------- NORTH / SOUTH camps (spawns, mirror y)
    for sy in (1, -1):
        for (tx, ty) in [(-36, 43.0), (-10, 43.6), (18, 43.6), (40, 42.0)]:
            ck_tent(tx, sy * ty, 0, k, r=2.2, h=2.8)
        # sandbag screen (1.9 m) in front of the camp, gaps for the west track, centre path and battery road
        for (xa, xb) in [(-40, -24), (-18, 1), (9, 28)]:
            n_ = max(1, int((xb - xa) / 4.6))
            for q in range(n_):
                qa, qb = xa + (xb - xa) * q / n_, xa + (xb - xa) * (q + 1) / n_
                sandbags((qa + qb) / 2, sy * (29.5 + (0.12 if q % 2 else -0.12)), qb - qa - 0.35, 11 if q % 3 != 1 else 10, mm, rot=RND.uniform(-1.5, 1.5))
                cyl('screen_post', 0.09, 2.3, (qb - 0.17, sy * 29.15, 1.15), m=k['beam'], axis='Z', verts=8)
                cyl('screen_post', 0.09, 2.3, (qb - 0.17, sy * 29.85, 1.15), m=k['beam'], axis='Z', verts=8)
        for (cx, r) in [(-6.0, 0), (17.0, 30)]:
            crate(cx, sy * 32.0, 0, 1.3, mm, rot=r)
            crate(cx + 1.4, sy * 32.2, 0, 1.3, mm, rot=r + 12)
            crate(cx + 0.6, sy * 32.1, 1.3, 1.2, mm, rot=r - 9)
        for (bx2, dy) in [(-28, 44.0), (32, 44.0)]:
            wood_barrel(bx2, sy * dy, mm)
    # ---------------------------------------------------------------- spawns (8 + 8, mirror across y = 0)
    sp = [(-26, 39, 180), (-16, 38.5, 180), (-4, 39, 180), (6, 38.5, 180), (16, 39, 180), (26, 38.5, 180), (-32, 35.5, 165), (34, 36, 195)]
    for (x, y, yaw) in sp:
        spawn(x, y, 0.1, yaw, 'a')
    for (x, y, yaw) in sp:
        spawn(x, -y, 0.1, (180 - yaw) % 360, 'b')
    bounds_walls(X0, Y0, X1 + 1, Y1, 22)
    finalize('canakkale', dict(preset='golden', sun=[-38, 250], fog=0.006, sky='sunset', water=True), [X0, Y0, X1, Y1],
             extra=dict(hide=['far_ship', 'far_shore'], terrain_holes=[[X1 + 0.2, -400, X1 + 140, 400]]))


def map_ayvadisi():
    """v3.8 Kurt Adam map, rebuilt: AY VADİSİ is a mountain valley. Snow-capped peaks ring a green meadow; a
    river runs north-south through the middle and splits the map into two mirrored clan camps (KARTAL west,
    AKREP east). Three lanes cross the river: a stone arch bridge in the north, a rune island with a shallow
    ford in the centre, a wooden bridge through the pine forest in the south. Walls, towers and rock ledges
    are placed on purpose for wolf climbing and flanking. Real terrain (trimesh collision)."""
    mm = begin()
    RR = random.Random(77)
    X0, X1, Y0, Y1 = -58, 58, -42, 42

    def nz(x, y):
        return (math.sin(x * 0.11 + 1.3) * math.cos(y * 0.13 - 0.7) + 0.5 * math.sin(x * 0.27 + y * 0.21) + 0.25 * math.cos(x * 0.53 - y * 0.47))

    def river_x(y):
        return 2.2 * math.sin(y / 13.0)

    def sm(a, b, x):
        t = max(0.0, min(1.0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)

    def H(x, y):
        # meadow: gentle rolls, flatter on the camps and lanes
        h = 0.55 * nz(x, y) * (1 - sm(36, 44, abs(x)) * 0.8)
        # river channel (shallow at the ford y≈0)
        d = abs(x - river_x(y))
        depth = 1.9 * (1 - sm(-12, -4, -abs(y)) * 0.0)
        depth = 1.9 - 1.25 * (1 - sm(3.5, 9.0, abs(y)))
        h -= depth * (1 - sm(2.4, 6.0, d))
        # rune island in the middle of the ford
        h += 1.6 * (1 - sm(4.0, 7.5, math.hypot(x, y)))
        # the valley walls: hills inside the edge, high peaks beyond it
        ox = max(0.0, abs(x) - (X1 - 8)); oy = max(0.0, abs(y) - (Y1 - 7))
        out = math.hypot(ox, oy)
        h += 4.0 * sm(0, 8, out) + 52.0 * sm(6, 60, out) * (0.7 + 0.3 * nz(x * 0.5, y * 0.5)) + 14.0 * sm(30, 90, out) * nz(x * 0.2 + 4, y * 0.2)
        return h

    grass = M('moss_ground', (0.24, 0.3, 0.2), 0.95)
    rock = M('mountain_rock', (0.36, 0.34, 0.33), 0.95)
    snow = M('snow', (0.9, 0.92, 0.96), 0.7)
    mud = M('river_bed', (0.3, 0.26, 0.22), 0.9)
    # ---- terrain grid
    bm = bmesh.new()
    TX0, TX1, TY0, TY1 = -190, 190, -170, 170
    def step_at(v):
        return 2.0 if abs(v) < 70 else 6.0
    xs = []; v = TX0
    while v <= TX1:
        xs.append(v); v += step_at(v)
    ys = []; v = TY0
    while v <= TY1:
        ys.append(v); v += step_at(v)
    grid = [[bm.verts.new((x, y, H(x, y))) for x in xs] for y in ys]
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            zc = sum(vv.co.z for vv in f.verts) / 4
            f.normal_update()
            slope = 1 - abs(f.normal.z)
            f.material_index = 2 if zc > 34 + 6 * nz(xs[i] * 0.3, ys[j] * 0.3) else (1 if slope > 0.28 or zc > 9 else (3 if zc < -0.5 else 0))
            f.smooth = True
    me = bpy.data.meshes.new('terrain')
    bm.to_mesh(me); bm.free()
    for m_ in (grass, rock, snow, mud):
        me.materials.append(m_)
    ter = bpy.data.objects.new('terrain', me)
    bpy.context.scene.collection.objects.link(ter)
    ter['terrain'] = True
    for pl in me.polygons:
        pl.use_smooth = True
    # river water (no collision): wading depth
    box('river', (14, 400, 0.05), (0, 0, -0.72), m=mm['water'])

    def put(x, y):
        return H(x, y)

    stone = M('ruin_stone', (0.6, 0.57, 0.54), 0.9)
    dark = M('ruin_stone_dark', (0.42, 0.4, 0.39), 0.92)
    logm = M('log_wood', (0.32, 0.22, 0.14), 0.9)
    rune = M('rune_glow', (0.55, 0.2, 1.0), 0.4, emission=(0.6, 0.25, 1.0), emit_strength=4)
    ember = M('ember_glow', (1.0, 0.45, 0.15), 0.4, emission=(1.0, 0.45, 0.15), emit_strength=5)
    pine_m = M('pine_needles', (0.1, 0.22, 0.12), 0.9)

    def pine(x, y, h, seed=0):
        z = put(x, y)
        rr = random.Random(seed)
        cyl('pine_trunk', 0.22, h * 0.35, (x, y, z + h * 0.17), m=mm['bark'], axis='Z', verts=8, r2=0.16)
        for k in range(4):
            t = k / 4
            r0 = h * (0.24 - t * 0.045) * rr.uniform(0.9, 1.1)
            cyl('pine_cone', r0, h * 0.34, (x, y, z + h * (0.28 + t * 0.19)), m=pine_m, axis='Z', verts=9, r2=0.02)
        col((x, y, z + h * 0.3), (0.5, 0.5, h * 0.6))

    def log_wall(x, y, length, rot, h=3.2):
        # palisade of sharpened logs
        z = put(x, y)
        n = int(length / 0.42)
        ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        for k in range(n):
            t = -length / 2 + 0.21 + k * 0.42
            px, py = x + ca * t, y + sa * t
            hh = h + RR.uniform(-0.25, 0.25)
            pz = put(px, py)
            cyl('palisade', 0.2, hh, (px, py, pz + hh / 2 - 0.3), m=logm, axis='Z', verts=7)
            cyl('palisade_tip', 0.2, 0.45, (px, py, pz + hh - 0.08), m=logm, axis='Z', verts=7, r2=0.01)
        col((x, y, z + h / 2 - 0.3), (length, 0.45, h + 0.6), rotz=rot)

    def boulder(x, y, sz, seed=0):
        z = put(x, y)
        rr = random.Random(seed)
        sphere('boulder', sz, (x, y, z + sz * 0.35), m=dark, scale=(rr.uniform(1.1, 1.5), rr.uniform(0.9, 1.2), rr.uniform(0.7, 0.95)))
        col((x, y, z + sz * 0.4), (sz * 2.3, sz * 1.9, sz * 1.5))

    def ruin(x, y, sx, sy, h, seed=0):
        z = put(x, y) - 0.3
        wall('ruin_wall', x, y, z, sx, sy, h + 0.3, stone, uv=0.3)
        rr = random.Random(seed)
        L = max(sx, sy)
        for k in range(int(L / 2.2)):
            t = -L / 2 + 1.1 + k * 2.2
            bx, by = (x + t, y) if sx > sy else (x, y + t)
            hh = rr.uniform(0.2, 1.4)
            box('ruin_cap', (1.6 if sx > sy else min(sx, 1.7), min(sy, 1.7) if sx > sy else 1.6, hh), (bx, by, z + h + 0.3 + hh / 2), m=stone)

    def torch(x, y):
        z = put(x, y)
        cyl('torch_pole', 0.07, 2.2, (x, y, z + 1.1), m=logm, axis='Z', verts=6)
        cyl('torch_bowl', 0.22, 0.18, (x, y, z + 2.25), m=mm['metal'], axis='Z', verts=8, r2=0.12)
        sphere('torch_fire', 0.16, (x, y, z + 2.42), m=ember, scale=(1, 1, 1.5))

    # ---- the two clan camps (mirrored: KARTAL west x<0, AKREP east x>0)
    for sgn in (-1, 1):
        cx = 44 * sgn
        # palisade: back wall + side walls with a gap (gate) facing the river
        log_wall(cx + 7 * sgn, 0, 40, 90)
        log_wall(cx - 2 * sgn, 19.5, 18, 0)
        log_wall(cx - 2 * sgn, -19.5, 18, 0)
        log_wall(cx - 11.5 * sgn, 13.5, 9, 90)
        log_wall(cx - 11.5 * sgn, -13.5, 9, 90)
        # gate towers (climbable for wolves: 7 m)
        for gy in (8.0, -8.0):
            tz = put(cx - 11.5 * sgn, gy)
            box('gate_tower', (2.6, 2.6, 7.0), (cx - 11.5 * sgn, gy, tz + 3.2), m=logm)
            col((cx - 11.5 * sgn, gy, tz + 3.2), (2.6, 2.6, 7.0))
            box('gate_roof', (3.2, 3.2, 0.4), (cx - 11.5 * sgn, gy, tz + 6.9), m=mm['roof'])
            torch(cx - 13.2 * sgn, gy - 1.8 * (1 if gy > 0 else -1))
        # houses inside, around a campfire
        for i, (hx, hy, r) in enumerate([(cx + 1 * sgn, 13, 180), (cx + 1 * sgn, -13, 0), (cx + 2.5 * sgn, 0, 90 if sgn < 0 else 270)]):
            hz = put(hx, hy)
            n0 = set(bpy.context.scene.objects); c0 = len(COL)
            konak('wolf_house', hx, hy, r, 8, 7, mm, seed=i + (40 if sgn < 0 else 50), floors=2, cumba=(i == 2), color='p_white' if i % 2 == 0 else 'p_cream')
            for o in [o for o in bpy.context.scene.objects if o not in n0]:
                if o.parent is None:
                    o.location.z += hz
            for cc in COL[c0:]:
                cc['c'][1] += hz
        fz = put(cx - 5 * sgn, 0)
        cyl('fire_ring', 1.2, 0.35, (cx - 5 * sgn, 0, fz + 0.15), m=stone, axis='Z', verts=12)
        sphere('campfire', 0.6, (cx - 5 * sgn, 0, fz + 0.5), m=ember, scale=(1, 1, 1.4))
        for k in range(5):
            a = k / 5 * math.tau
            box('fire_log', (1.6, 0.25, 0.25), (cx - 5 * sgn + math.cos(a) * 0.5, math.sin(a) * 0.5, fz + 0.35), (0, 20, math.degrees(a)), m=logm)
        # big watch tower behind the camp (13 m, wolves climb it)
        tx = cx + 3 * sgn; ty = 24.0 * (1 if sgn < 0 else -1)
        tz = put(tx, ty)
        cyl('tower', 3.2, 13, (tx, ty, tz + 6.3), m=dark, axis='Z', verts=18, uv=0.25)
        col((tx, ty, tz + 6.3), (6.0, 6.0, 13))
        for k in range(8):
            a = k / 8 * math.tau
            box('tower_merlon', (1.0, 1.0, 1.1), (tx + math.cos(a) * 2.8, ty + math.sin(a) * 2.8, tz + 13.3), m=dark)
        box('tower_fire', (0.9, 0.9, 0.5), (tx, ty, tz + 13.05), m=ember)
        # crates, barrels, a cart of logs as cover at the gate
        for (ox, oy) in [(-15, 4), (-15, -4), (-9, 15), (-9, -15)]:
            px, py = cx + ox * sgn, oy
            pz = put(px, py)
            n0 = set(bpy.context.scene.objects); c0 = len(COL)
            crate(px, py, 0, 1.2, mm, rot=RR.uniform(-20, 20))
            wood_barrel(px + 1.4 * sgn, py + 0.5, mm)
            for o in [o for o in bpy.context.scene.objects if o not in n0]:
                if o.parent is None:
                    o.location.z += pz
            for cc in COL[c0:]:
                cc['c'][1] += pz
        for (ox, oy) in [(-6, 6), (-6, -6), (4, 8), (4, -8)]:
            torch(cx + ox * sgn, oy)

    # ---- NORTH lane: stone arch bridge over the river, guarded by ruined walls
    by = 24.0
    bx = river_x(by)
    deck = 1.25
    box('bridge_deck', (16, 5, 0.6), (bx, by, deck - 0.3), m=stone)
    col((bx, by, deck - 0.3), (16, 5, 0.6))
    for side in (-1, 1):
        box('bridge_parapet', (16, 0.5, 1.0), (bx, by + side * 2.3, deck + 0.5), m=dark)
        col((bx, by + side * 2.3, deck + 0.5), (16, 0.5, 1.0))
    for k in (-1, 1):
        cyl('bridge_pier', 1.2, 3.2, (bx + k * 3.5, by, -1.0), m=dark, axis='Z', verts=12)
    for side in (-1, 1):
        ramp('bridge_ramp', bx + side * 10.5, by, deck, put(bx + side * 13.5, by) + 0.05, 5.0, 5.0, stone, axis='X', direction=-side)
    for sgn in (-1, 1):
        ruin(14 * sgn, 30, 1.4, 9, 4.5, seed=3)
        ruin(20 * sgn, 18, 8, 1.4, 3.2, seed=4)
        ruin(26 * sgn, 31, 6, 1.4, 6.0, seed=5)
        boulder(11 * sgn, 17, 1.4, seed=6)
        torch(9.5 * sgn, 21.5)

    # ---- CENTRE: rune island in the ford (stone circle + altar), stepping stones
    for i in range(10):
        a = i / 10 * math.tau
        hgt = 3.4 + 1.6 * ((i * 7) % 5) / 4
        x, y = math.cos(a) * 5.6, math.sin(a) * 5.6
        z = put(x, y)
        if i % 5 == 2:
            continue   # two gaps east-west so the lane runs through
        box('menhir', (1.1, 0.75, hgt), (x, y, z + hgt / 2 - 0.2), (0, 0, math.degrees(a) + 90), m=dark)
        col((x, y, z + hgt / 2 - 0.2), (1.1, 1.1, hgt))
        box('rune_line', (0.06, 0.78, hgt * 0.65), (x * 0.89, y * 0.89, z + hgt * 0.45), (0, 0, math.degrees(a) + 90), m=rune)
    az = put(0, 0)
    cyl('altar', 1.4, 0.9, (0, 0, az + 0.35), m=stone, axis='Z', verts=16)
    col((0, 0, az + 0.35), (2.8, 2.8, 0.9))
    cyl('altar_rune', 1.1, 0.06, (0, 0, az + 0.82), m=rune, axis='Z', verts=16)
    for sgn in (-1, 1):
        for k in range(3):
            sx_, sy_ = sgn * (8.5 + k * 1.6), (k - 1) * 1.2
            cyl('step_stone', 0.75, 0.6, (sx_, sy_, put(sx_, sy_) + 0.1), m=dark, axis='Z', verts=9)
            col((sx_, sy_, put(sx_, sy_) + 0.1), (1.4, 1.4, 0.6))
        ruin(17 * sgn, 6, 1.4, 6, 2.2, seed=7)
        ruin(17 * sgn, -6, 1.4, 6, 2.2, seed=8)
        boulder(23 * sgn, 0, 1.6, seed=9)
        torch(12 * sgn, 4)
        torch(12 * sgn, -4)

    # ---- SOUTH lane: wooden bridge through the pine forest
    by2 = -24.0
    bx2 = river_x(by2)
    plank = mm['planks']
    box('wbridge_deck', (15, 4, 0.35), (bx2, by2, 0.95), m=plank)
    col((bx2, by2, 0.95), (15, 4, 0.35))
    for k in range(-3, 4):
        cyl('wbridge_post', 0.15, 3.0, (bx2 + k * 2.2, by2 + 2.1, 0.2), m=logm, axis='Z', verts=6)
        cyl('wbridge_post', 0.15, 3.0, (bx2 + k * 2.2, by2 - 2.1, 0.2), m=logm, axis='Z', verts=6)
    for side in (-1, 1):
        box('wbridge_rail', (15, 0.12, 0.12), (bx2, by2 + side * 2.1, 1.75), m=logm)
        col((bx2, by2 + side * 2.1, 1.4), (15, 0.25, 0.9))
        ramp('wbridge_ramp', bx2 + side * 9.5, by2, 1.1, put(bx2 + side * 12.5, by2) + 0.05, 4.5, 4.0, plank, axis='X', direction=-side)
    for sgn in (-1, 1):
        # forest: placed on a loose grid (both sides mirrored), the lane itself kept clear
        k = 0
        for gx in range(10, 36, 5):
            for gy in range(-38, -12, 5):
                if abs(gy - by2) < 3.5 and gx < 16:
                    continue
                jx = ((gx * 7 + gy * 3) % 5) * 0.5 - 1.0
                jy = ((gx * 3 + gy * 11) % 5) * 0.5 - 1.0
                if (gx + gy) % 3 == 0:
                    continue
                pine(sgn * (gx + jx), gy + jy, 8.5 + ((gx * gy) % 4), seed=k)
                k += 1
        boulder(14 * sgn, -16, 1.5, seed=10)
        boulder(28 * sgn, -30, 1.8, seed=11)
        ruin(22 * sgn, -18, 1.4, 7, 3.0, seed=12)
        torch(9.5 * sgn, -21.5)

    # ---- pines and rocks on the slopes outside the play area (scenery)
    for i in range(160):
        a = RR.uniform(0, math.tau)
        r = RR.uniform(66, 120)
        x, y = math.cos(a) * r * 1.15, math.sin(a) * r * 0.95
        if abs(x) < X1 + 4 and abs(y) < Y1 + 4:
            continue
        if put(x, y) > 30:
            continue
        pine(x, y, RR.uniform(8, 14), seed=200 + i)
    # spawns inside each camp
    for sgn, team in ((-1, 'a'), (1, 'b')):
        cx = 44 * sgn
        for (ox, oy) in [(2, 5), (2, -5), (-2, 9), (-2, -9), (4, 2), (4, -2)]:
            x, y = cx + ox * sgn, oy
            spawn(x, y, put(x, y) + 0.1, 90 if sgn < 0 else 270, team)
    bounds_walls(X0, Y0, X1, Y1, 40)
    finalize('ayvadisi', dict(preset='alaca', sun=[-14, 235], fog=0.0022, sky='sunset'), [X0, Y0, X1, Y1], extra=dict(trimesh=['terrain']))


ALL = dict(ayvadisi=map_ayvadisi, mahalle=map_mahalle, safranbolu=map_safranbolu, gemi=map_gemi, liman=map_liman, insaat=map_insaat, canakkale=map_canakkale)
if __name__ == '__main__':
    for n in [a for a in sys.argv[1:] if a in ALL] or list(ALL):
        try:
            ALL[n]()
        except Exception:
            import traceback; traceback.print_exc(); print('FAILED', n)
