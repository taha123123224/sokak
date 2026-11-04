"""SOKAK v2.5 — new weapons from parametric recipes -> assets/models/w_<id>.glb
Same conventions as weapons.py: +Y muzzle, +Z up, origin = right hand grip point.
Materials starting with gun_paint receive the weapon skin.
run:  python3.13 tools/weapons2.py [ids...]
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import weapons as W
from weapons import *          # start, points, rail, reddot, holo, scope, grip, trigger_guard, curved_mag, finish_export, M ...
from bkit import *

W.REAL_LEN.update({
    'mpt76': 0.94, 'g36c': 0.72, 'famas': 0.76, 'galil': 0.92, 'hk416': 0.84, 'sg553': 0.74, 'tavor': 0.72,
    'mp7': 0.64, 'uzi': 0.47, 'mac10': 0.55, 'bizon': 0.66, 'mp9': 0.52,
    'barrett': 1.45, 'ssg08': 1.05, 'svd': 1.22,
    'nova': 1.0, 'xm1014': 1.01, 'sawed': 0.6,
    'negev': 1.02, 'pkm': 1.19,
    'usp': 0.24, 'p250': 0.19, 'fiveseven': 0.21, 'yavuz': 0.2, 'tec9': 0.3,
    'kama': 0.36, 'sunguu': 0.33, 'kelebek': 0.22, 'pala': 0.45,
})


# ---------------------------------------------------------------- building blocks
def muzzle_dev(b, m, kind, y, z, r):
    d = m['dark']
    if kind == 'brake':
        lathe('mz_brake', [(0, 0), (r * 1.5, 0), (r * 1.5, 0.05), (r * 1.2, 0.055), (0, 0.055)], (0, y, z), m=d, parent=b, axis='Y', seg=24)
        for i in range(3):
            box(f'mz_port{i}', (r * 3.4, 0.006, r * 1.0), (0, y + 0.012 + i * 0.013, z), m=m['metal'], parent=b, bevel=0.001)
        return y + 0.055
    if kind == 'flash':
        lathe('mz_flash', [(0, 0), (r * 1.15, 0), (r * 1.15, 0.045), (r * 1.3, 0.05), (r * 1.0, 0.055), (0, 0.055)], (0, y, z), m=d, parent=b, axis='Y', seg=24)
        for i in range(5):
            a = i / 5 * math.tau
            box(f'mz_slot{i}', (0.0025, 0.03, 0.0025), (math.cos(a) * r * 1.2, y + 0.035, z + math.sin(a) * r * 1.2), m=m['metal'], parent=b)
        return y + 0.055
    if kind == 'can':
        cyl('mz_can', r * 2.2, 0.16, (0, y + 0.08, z), m=d, parent=b, verts=32, bevel=0.003)
        for i in range(4):
            torus(f'mz_ring{i}', r * 2.2, 0.0015, (0, y + 0.02 + i * 0.04, z), (90, 0, 0), m=m['metal'], parent=b, seg=32, mseg=6)
        return y + 0.16
    if kind == 'cone':
        lathe('mz_cone', [(0, 0), (r * 1.2, 0), (r * 1.6, 0.04), (r * 1.6, 0.05), (0, 0.05)], (0, y, z), m=d, parent=b, axis='Y', seg=24)
        return y + 0.05
    return y


def handguard(b, m, kind, y0, y1, z, w, h, mat):
    L = y1 - y0
    yc = (y0 + y1) / 2
    d = m['dark']
    if kind == 'rail':
        box('hg', (w, L, h), (0, yc, z), m=mat, parent=b, bevel=0.007, segs=3)
        rail(b, d, L * 0.95, (0, yc, z + h / 2 + 0.003), 'hg_rt')
        rail(b, d, L * 0.6, (0, yc + L * 0.15, z - h / 2 - 0.003), 'hg_rb')
        for s in (-1, 1):
            for i in range(int(L / 0.035)):
                box(f'hg_v{s}{i}', (0.003, 0.02, h * 0.3), (s * w / 2, y0 + 0.02 + i * 0.035, z), m=d, parent=b, bevel=0.001)
    elif kind == 'mlok':
        box('hg', (w, L, h), (0, yc, z), m=mat, parent=b, bevel=0.009, segs=3)
        rail(b, d, L * 0.95, (0, yc, z + h / 2 + 0.003), 'hg_rt')
        for s in (-1, 1):
            for i in range(int(L / 0.045)):
                box(f'hg_ml{s}{i}', (0.004, 0.028, 0.008), (s * w / 2, y0 + 0.03 + i * 0.045, z - h * 0.12), m=d, parent=b, bevel=0.002)
    elif kind == 'round':
        cyl('hg', h / 2, L, (0, yc, z), m=mat, parent=b, verts=32, bevel=0.004)
        for i in range(int(L / 0.03)):
            for s in (-1, 1):
                box(f'hg_h{s}{i}', (0.003, 0.012, 0.008), (s * h / 2, y0 + 0.02 + i * 0.03, z + 0.004), m=d, parent=b)
    elif kind == 'wood':
        prof('hg', [(y0, z - h / 2), (y1, z - h / 2 + 0.006), (y1, z + h / 2 - 0.004), (y0, z + h / 2)], w, m=m['wood'], parent=b, bevel=0.008, segs=3)
    elif kind == 'poly':
        prof('hg', [(y0, z - h / 2 - 0.006), (y1 - 0.01, z - h / 2), (y1, z - h / 2 + 0.01), (y1, z + h / 2), (y0, z + h / 2)], w, m=mat, parent=b, bevel=0.009, segs=3)
        for i in range(int(L / 0.03)):
            box(f'hg_g{i}', (w + 0.002, 0.006, h * 0.35), (0, y0 + 0.02 + i * 0.03, z - h * 0.15), m=m['rubber'], parent=b, bevel=0.001)


def stock(b, m, kind, y, z, mat, L=0.25):
    d = m['dark']
    if kind == 'fixed':
        prof('stk', [(y, z + 0.03), (y - L, z + 0.035), (y - L - 0.01, z + 0.015), (y - L - 0.01, z - 0.1), (y - L + 0.03, z - 0.1), (y - 0.08, z - 0.03), (y, z - 0.02)], 0.042, m=mat, parent=b, bevel=0.008, segs=3)
        box('stk_pad', (0.044, 0.014, 0.13), (0, y - L - 0.016, z - 0.035), m=m['rubber'], parent=b, bevel=0.005)
    elif kind == 'skeleton':
        cyl('stk_tube', 0.013, L * 0.75, (0, y - L * 0.37, z), m=d, parent=b, verts=24)
        g = prof('stk', [(y - L * 0.35, z + 0.022), (y - L, z + 0.028), (y - L - 0.01, z + 0.01), (y - L - 0.01, z - 0.1), (y - L + 0.03, z - 0.1), (y - L * 0.35, z - 0.02)], 0.03, m=mat, parent=b, bevel=0.006, segs=3)
        cut = prof('stk_cut', [(y - L * 0.5, z + 0.005), (y - L + 0.015, z + 0.01), (y - L + 0.015, z - 0.075), (y - L * 0.5, z - 0.025)], 0.1, m=mat, parent=b, bevel=0)
        boolean_diff(g, cut)
        box('stk_pad', (0.034, 0.012, 0.13), (0, y - L - 0.014, z - 0.035), m=m['rubber'], parent=b, bevel=0.004)
    elif kind == 'wire':
        for s in (-1, 1):
            cyl(f'stk_w{s}', 0.004, L, (s * 0.016, y - L / 2, z - 0.01), m=d, parent=b, verts=10)
        box('stk_pad', (0.04, 0.01, 0.09), (0, y - L, z - 0.03), m=d, parent=b, bevel=0.003)
    elif kind == 'thumbhole':
        g = prof('stk', [(y, z + 0.03), (y - L, z + 0.04), (y - L - 0.015, z + 0.02), (y - L - 0.015, z - 0.12), (y - L + 0.04, z - 0.12), (y - 0.04, z - 0.06), (y, z - 0.04)], 0.042, m=mat, parent=b, bevel=0.008, segs=3)
        cut = prof('stk_cut', [(y - 0.06, z - 0.005), (y - 0.14, z - 0.005), (y - 0.14, z - 0.07), (y - 0.07, z - 0.05)], 0.1, m=mat, parent=b, bevel=0)
        boolean_diff(g, cut)
        box('stk_pad', (0.044, 0.016, 0.15), (0, y - L - 0.022, z - 0.045), m=m['rubber'], parent=b, bevel=0.005)
    elif kind == 'wood':
        prof('stk', [(y, z + 0.02), (y - L, z + 0.03), (y - L - 0.01, z + 0.01), (y - L - 0.01, z - 0.11), (y - L + 0.05, z - 0.11), (y - 0.06, z - 0.04), (y, z - 0.03)], 0.04, m=m['wood'], parent=b, bevel=0.01, segs=3)
        box('stk_pad', (0.042, 0.012, 0.13), (0, y - L - 0.015, z - 0.04), m=m['rubber'], parent=b, bevel=0.004)


def mag(root, m, kind, y, z, mat, w=0.026, h=0.12, angle=0.0, d=0.07):
    if kind == 'straight':
        box('mag', (w, d, h), (0, y, z - h / 2), (-angle, 0, 0), m=mat, parent=root, bevel=0.004)
        box('magbase', (w + 0.004, d + 0.006, 0.01), (0, y + math.sin(math.radians(angle)) * h * 0.5, z - h - 0.002), (-angle, 0, 0), m=m['dark'], parent=root, bevel=0.003)
    elif kind == 'curved':
        curved_mag('mag', root, mat, (y + 0.38, z), 0.38 - d * 0.1, 0.38 - d * 1.1, 180, 180 + math.degrees(h / 0.36), w, n=10)
    elif kind == 'drum':
        cyl('mag', 0.075, w * 2.2, (0, y, z - 0.09), m=mat, parent=root, axis='X', verts=40, bevel=0.006)
        box('magneck', (w, 0.05, 0.05), (0, y, z - 0.02), m=mat, parent=root, bevel=0.003)
    elif kind == 'box':
        box('mag', (0.075, 0.11, 0.1), (-0.03, y, z - 0.05), m=mat, parent=root, bevel=0.01)
    elif kind == 'helical':
        cyl('mag', 0.026, 0.3, (0, y, z - 0.03), m=mat, parent=root, verts=28, bevel=0.004)
    elif kind == 'none':
        box('mag', (0.004, 0.004, 0.004), (0, y, z), m=m['dark'], parent=root)


def sight(b, m, kind, y, z):
    """returns eye/sight point (x, y, z) for ADS"""
    d = m['dark']
    if kind == 'iron':
        box('rs', (0.022, 0.016, 0.018), (0, y - 0.1, z + 0.009), m=d, parent=b, bevel=0.002)
        box('rs_notch', (0.006, 0.02, 0.006), (0, y - 0.1, z + 0.016), m=m['metal'], parent=b)
        box('fs', (0.004, 0.01, 0.022), (0, y + 0.25, z + 0.011), m=d, parent=b, bevel=0.001)
        return (0, y - 0.1, z + 0.02)
    if kind == 'reddot':
        rail(b, d, 0.1, (0, y, z), 'sr')
        reddot(b, m, (0, y, z + 0.009))
        return (0, y, z + 0.037)
    if kind == 'holo':
        rail(b, d, 0.12, (0, y, z), 'sr')
        holo(b, m, (0, y, z + 0.01))
        return (0, y, z + 0.041)
    if kind == 'scope':
        rail(b, d, 0.14, (0, y, z), 'sr')
        scope(b, m, (0, y, z + 0.045), length=0.34)
        return (0, y, z + 0.045)
    if kind == 'bigscope':
        rail(b, d, 0.2, (0, y, z), 'sr')
        scope(b, m, (0, y, z + 0.055), length=0.42, r=0.019, obj_r=0.032, mount_dy=(-0.08, 0.08))
        return (0, y, z + 0.055)
    if kind == 'carry':
        c = prof('carry', [(y - 0.08, z), (y + 0.1, z), (y + 0.09, z + 0.04), (y - 0.07, z + 0.04)], 0.022, m=d, parent=b, bevel=0.004)
        cut = prof('carry_cut', [(y - 0.05, z + 0.006), (y + 0.07, z + 0.006), (y + 0.06, z + 0.028), (y - 0.04, z + 0.028)], 0.1, m=d, parent=b, bevel=0)
        boolean_diff(c, cut)
        box('carry_rs', (0.012, 0.01, 0.012), (0, y - 0.06, z + 0.046), m=d, parent=b, bevel=0.002)
        return (0, y - 0.06, z + 0.052)
    return (0, y, z + 0.02)


def bipod(b, m, y, z):
    box('bp_mount', (0.03, 0.03, 0.02), (0, y, z), m=m['dark'], parent=b, bevel=0.003)
    for s in (-1, 1):
        cyl(f'bp_leg{s}', 0.006, 0.2, (s * 0.02, y + 0.09, z - 0.005), (0, 0, s * 6), m=m['dark'], parent=b, verts=12)


# ---------------------------------------------------------------- generic long gun
def longgun(wid, R):
    """R: recipe dict. Coordinates in metres before true_scale."""
    root, b = start(wid); m = M()
    paint = m[R.get('paint', 'paint')]
    rz = R.get('rz', 0.0)           # receiver bottom
    rh = R.get('rh', 0.085)         # receiver height
    rw = R.get('rw', 0.036)
    ry0, ry1 = R.get('ry', (-0.11, 0.15))
    # receiver: lower + upper with chamfered top edge
    prof('rcv_lo', [(ry0, rz), (ry1, rz), (ry1 + 0.01, rz + rh * 0.45), (ry0 + 0.01, rz + rh * 0.5)], rw, m=paint, parent=b, bevel=0.005, segs=2)
    prof('rcv_up', [(ry0, rz + rh * 0.5), (ry1 + 0.01, rz + rh * 0.45), (ry1 + 0.02, rz + rh), (ry0 + 0.02, rz + rh), (ry0, rz + rh * 0.85)], rw - 0.002, m=m[R.get('upper', 'paint')], parent=b, bevel=0.006, segs=3)
    # ejection port + dust cover + bolt handle
    box('ejp', (0.003, 0.06, rh * 0.25), (rw / 2, ry0 + (ry1 - ry0) * 0.55, rz + rh * 0.6), m=m['dark'], parent=b, bevel=0.001)
    if R.get('chandle', 'side') == 'side':
        box('bolt', (0.016, 0.014, 0.012), (rw / 2 + 0.006, ry0 + (ry1 - ry0) * 0.55, rz + rh * 0.72), m=m['metal'], parent=root, bevel=0.003)
    else:
        box('bolt', (0.012, 0.02, 0.012), (0, ry0 + 0.01, rz + rh + 0.004), m=m['metal'], parent=root, bevel=0.003)
    # pins / screws detail
    for i in range(R.get('pins', 3)):
        cyl(f'pin_d{i}', 0.0035, rw + 0.003, (0, ry0 + 0.04 + i * 0.06, rz + rh * 0.3), m=m['metal'], parent=b, axis='X', verts=12)
    if R.get('brand', True):
        box('brand', (0.001, 0.05, 0.012), (rw / 2 + 0.0005, ry0 + (ry1 - ry0) * 0.25, rz + rh * 0.3), m=m['metal'], parent=b)
    bz = rz + rh * R.get('bz', 0.68)  # barrel height
    hg = R.get('hg')
    if hg:
        handguard(b, m, hg[0], ry1 + 0.01, ry1 + hg[1], bz + hg[3], hg[2], hg[4], m[hg[5]] if len(hg) > 5 else paint)
    br = R.get('br', 0.0095)
    blen = R.get('blen', 0.3)
    by0 = ry1 + (hg[1] if hg else 0.02) - 0.02
    cyl('barrel', br, blen, (0, by0 + blen / 2, bz), m=m['dark'], parent=b, verts=24)
    if R.get('gasblock', True) and hg:
        box('gas', (br * 3.2, 0.03, br * 3.6), (0, by0 + 0.03, bz + br * 0.6), m=m['dark'], parent=b, bevel=0.003)
    tip = muzzle_dev(b, m, R.get('muzzle', 'flash'), by0 + blen, bz, br)
    if R.get('tube'):
        cyl('tubemag', br * 1.6, blen * 0.8, (0, by0 + blen * 0.4, bz - br * 3.2), m=m['dark'], parent=b, verts=24)
        box('pump', (rw + 0.008, 0.14, 0.04), (0, by0 + 0.1, bz - br * 3.2), m=m['rubber'], parent=b, bevel=0.008, segs=3)
    if R.get('bipod'):
        bipod(b, m, by0 + blen * 0.55, bz - br * 2)
    # grip + trigger guard
    gy = R.get('gy', -0.035)
    grip(b, m[R.get('gripm', 'poly')], (0, gy, rz), R.get('ga', 20), h=R.get('gh', 0.105))
    trigger_guard(b, m['dark'] if R.get('tgdark', True) else paint, gy + 0.025, gy + 0.105, rz)
    # stock
    st = R.get('stock')
    if st:
        stock(b, m, st, ry0, rz + rh * 0.6, m[R.get('stockm', 'poly')], R.get('sl', 0.25))
    # mag
    mg = R.get('mag')
    if mg:
        mag(root, m, mg[0], mg[1], rz, m[mg[2]] if len(mg) > 2 else m['metal'], w=mg[3] if len(mg) > 3 else 0.026, h=mg[4] if len(mg) > 4 else 0.12, angle=mg[5] if len(mg) > 5 else 0, d=mg[6] if len(mg) > 6 else 0.07)
        box('magwell', (rw + 0.004, (mg[6] if len(mg) > 6 else 0.07) + 0.012, 0.02), (0, mg[1], rz - 0.006), m=paint, parent=b, bevel=0.004)
    # sight
    sp = sight(b, m, R.get('sight', 'iron'), R.get('sy', 0.02), rz + rh)
    if R.get('extra'):
        R['extra'](b, m, root)
    lh = R.get('lhand', (0, ry1 + (hg[1] if hg else 0.1) * 0.55, bz - 0.03))
    points(root, (0, tip, bz), sp, lh, (rw / 2 + 0.01, ry0 + (ry1 - ry0) * 0.55, rz + rh * 0.6))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    join_children_named(root, ['mag', 'magbase', 'magneck'], 'mag')
    finish_export(wid)


# ---------------------------------------------------------------- pistols
def pistol(wid, P):
    root, b = start(wid); m = M()
    paint = m[P.get('paint', 'paint')]
    sm = m[P.get('slide', 'dark')]
    L = P.get('L', 0.18)       # slide length
    fh = P.get('fh', 0.022)    # frame height
    sh = P.get('sh', 0.03)     # slide height
    w = P.get('w', 0.028)
    y0 = -0.06
    prof('frame', [(y0, 0.0), (y0 + L - 0.01, 0.0), (y0 + L - 0.01, fh), (y0, fh)], w, m=paint, parent=b, bevel=0.004, segs=2)
    if P.get('rail', True):
        rail(b, m['poly'], 0.035, (0, y0 + L - 0.05, -0.002), 'frail')
    grip(b, paint, (0, -0.03, 0.0), P.get('ga', 20), h=P.get('gh', 0.1), w=w + 0.002, d=0.046)
    # grip texture panels
    for i in range(6):
        box(f'gtex{i}', (w + 0.004, 0.03, 0.004), (0, -0.045 - i * 0.004, -0.02 - i * 0.012), (-P.get('ga', 20), 0, 0), m=m['rubber'], parent=b, bevel=0.001)
    trigger_guard(b, paint, 0.0, 0.06, 0.0, depth=0.03, w=0.014)
    box('magbase', (w + 0.004, 0.05, 0.01), (0, -0.068, -0.097), (-P.get('ga', 20), 0, 0), m=m['dark'], parent=root, bevel=0.003).name = 'mag'
    # slide with chamfer, serrations front + rear, ejection port, sights
    sl = prof('slide', [(y0 - 0.005, fh), (y0 + L, fh), (y0 + L, fh + sh - 0.004), (y0 + L - 0.005, fh + sh), (y0, fh + sh), (y0 - 0.005, fh + sh - 0.005)], w - 0.002, m=sm, parent=root, bevel=0.003, segs=2)
    sl.name = 'slide'
    names = ['slide']
    for i in range(P.get('serr', 7)):
        n = f'slserr{i}'
        box(n, (w, 0.002, sh * 0.75), (0, y0 + 0.008 + i * 0.006, fh + sh * 0.5), m=m['metal'], parent=root).name = n
        names.append(n)
    if P.get('fserr', True):
        for i in range(4):
            n = f'slfs{i}'
            box(n, (w, 0.002, sh * 0.6), (0, y0 + L - 0.035 + i * 0.006, fh + sh * 0.45), m=m['metal'], parent=root).name = n
            names.append(n)
    box('slport', (0.002, 0.035, sh * 0.5), (w / 2 - 0.0005, y0 + L * 0.55, fh + sh * 0.6), m=m['metal'], parent=root).name = 'slport'
    box('slrs', (0.018, 0.008, 0.008), (0, y0 + 0.012, fh + sh + 0.004), m=m['dark'], parent=root, bevel=0.001).name = 'slrs'
    box('slfsight', (0.004, 0.006, 0.008), (0, y0 + L - 0.008, fh + sh + 0.004), m=m['dark'], parent=root, bevel=0.001).name = 'slfsight'
    for n0, x in (('sldot0', -0.005), ('sldot1', 0.005)):
        sphere(n0, 0.0012, (x, y0 + 0.008, fh + sh + 0.006), m=m['dot'], parent=root, seg=8, rings=4)
        names.append(n0)
    names += ['slport', 'slrs', 'slfsight']
    cyl('barrel', 0.0075, 0.012, (0, y0 + L + 0.002, fh + sh * 0.45), m=m['poly'], parent=b, verts=16)
    if P.get('hammer'):
        box('hammer', (0.008, 0.012, 0.016), (0, y0 - 0.008, fh + sh * 0.6), (25, 0, 0), m=m['dark'], parent=b, bevel=0.002)
    if P.get('comp'):
        box('comp', (w, 0.03, sh), (0, y0 + L + 0.015, fh + sh / 2), m=m['dark'], parent=b, bevel=0.003)
    tip = y0 + L + (0.03 if P.get('comp') else 0.004)
    points(root, (0, tip, fh + sh * 0.45), (0, y0 + 0.012, fh + sh + 0.008), (0, -0.02, -0.04), (0.02, y0 + L * 0.55, fh + sh * 0.6))
    apply_all_modifiers(); box_uv_all(4.0)
    j = join_children(b, 'body'); j.parent = root
    W.join_children_named(root, names, 'slide')
    finish_export(wid)


# ---------------------------------------------------------------- knives
def blade_knife(wid, K):
    root, b = start(wid); m = M()
    bl = m['blade']
    pts = K['pts']
    o = prof('blade', pts, K.get('t', 0.006), m=m.get(K.get('bm', 'blade'), bl), parent=b, bevel=0.0012, segs=2)
    W._sharpen(o, edge_z=K.get('edge', 0.004), spine_z=K.get('spine', 0.02))
    if K.get('fuller'):
        box('fuller', (K.get('t', 0.006) - 0.0005, K['fuller'][0], 0.004), (0, K['fuller'][1], K['fuller'][2]), m=m['dark'], parent=b)
    if K.get('guard'):
        g = K['guard']
        box('guard', (0.022, 0.01, g), (0, 0.025, 0.008), m=m['dark'], parent=b, bevel=0.003)
    hl = K.get('hl', 0.11)
    prof('handle', [(-hl, -0.012), (0.02, -0.01), (0.02, 0.028), (-hl, 0.026), (-hl - 0.01, 0.007)], 0.024, m=m['paint'], parent=b, bevel=0.007, segs=3)
    for i in range(K.get('wraps', 5)):
        box(f'wrap{i}', (0.026, 0.006, 0.042), (0, -hl + 0.02 + i * (hl - 0.02) / max(K.get('wraps', 5), 1), 0.008), m=m['rubber'], parent=b, bevel=0.0015)
    if K.get('pommel', True):
        cyl('pommel', 0.012, 0.012, (0, -hl - 0.006, 0.008), m=m['dark'], parent=b, verts=16, bevel=0.002)
    if K.get('ring'):
        torus('ring', 0.02, 0.005, (0, -hl - 0.02, 0.0), (0, 90, 0), m=m['dark'], parent=b, seg=32, mseg=10)
    tip = max(p[0] for p in pts)
    points(root, (0, tip, 0.01), (0, 0, 0.05), (0, 0, 0), (0, 0, 0))
    apply_all_modifiers(); box_uv_all(8.0)
    j = join_children(b, 'body'); j.parent = root
    finish_export(wid)


# ---------------------------------------------------------------- recipes
def _ak_like(**k):
    R = dict(ry=(-0.11, 0.16), rh=0.08, hg=('wood', 0.17, 0.042, 0.0, 0.045), blen=0.36, muzzle='brake', stock='wood', stockm='wood',
             mag=('curved', 0.11, 'metal', 0.026, 0.17, 0, 0.07), sight='iron', sy=0.12, chandle='side')
    R.update(k); return R


RECIPES = {
    # Türk piyade tüfeği: düz şarjör, M-LOK el kundağı, ayarlanabilir dipçik, holografik nişangah
    'mpt76': dict(ry=(-0.12, 0.17), rh=0.09, hg=('mlok', 0.28, 0.048, 0.0, 0.05), blen=0.36, muzzle='flash', stock='skeleton', sl=0.27,
                  mag=('straight', 0.12, 'metal', 0.026, 0.14, 8, 0.075), sight='holo', sy=0.03, br=0.011),
    'g36c': dict(ry=(-0.11, 0.14), rh=0.1, paint='poly', upper='poly', hg=('poly', 0.17, 0.05, -0.005, 0.055, 'poly'), blen=0.24, muzzle='flash',
                 stock='skeleton', stockm='poly', sl=0.24, mag=('straight', 0.11, 'poly', 0.026, 0.14, 10, 0.072), sight='carry', sy=0.02),
    'famas': dict(ry=(-0.32, 0.1), rh=0.11, paint='poly', upper='poly', hg=('poly', 0.12, 0.048, -0.01, 0.05, 'poly'), blen=0.3, muzzle='cone',
                  stock=None, mag=('straight', -0.2, 'metal', 0.024, 0.11, 0, 0.065), sight='carry', sy=-0.08, gy=-0.02,
                  extra=lambda b, m, r: prof('famas_handle', [(-0.25, 0.11), (0.08, 0.11), (0.06, 0.15), (-0.23, 0.15)], 0.022, m=m['poly'], parent=b, bevel=0.006)),
    'galil': _ak_like(hg=('poly', 0.18, 0.046, 0.0, 0.048, 'poly'), stock='skeleton', stockm='poly', sight='reddot', sy=0.03, mag=('curved', 0.11, 'metal', 0.026, 0.16, 0, 0.07)),
    'hk416': dict(ry=(-0.11, 0.16), rh=0.088, hg=('rail', 0.27, 0.046, 0.0, 0.048), blen=0.3, muzzle='flash', stock='skeleton', sl=0.26,
                  mag=('curved', 0.12, 'metal', 0.024, 0.15, 0, 0.068), sight='reddot', sy=0.03),
    'sg553': dict(ry=(-0.1, 0.16), rh=0.095, hg=('poly', 0.2, 0.05, 0.0, 0.052), blen=0.26, muzzle='brake', stock='skeleton', sl=0.25,
                  mag=('curved', 0.12, 'poly', 0.026, 0.15, 0, 0.07), sight='scope', sy=0.02),
    'tavor': dict(ry=(-0.34, 0.08), rh=0.11, paint='poly', upper='poly', hg=('poly', 0.1, 0.05, -0.012, 0.06, 'poly'), blen=0.26, muzzle='flash',
                  stock=None, mag=('straight', -0.22, 'metal', 0.025, 0.13, 0, 0.068), sight='reddot', sy=-0.1, gy=-0.02, ga=8),
    'mp7': dict(ry=(-0.09, 0.1), rh=0.075, paint='poly', upper='poly', hg=None, blen=0.1, muzzle='flash', stock='wire', sl=0.2,
                mag=('straight', -0.03, 'poly', 0.022, 0.13, 6, 0.04), sight='reddot', sy=0.0, gy=-0.045, ga=12,
                extra=lambda b, m, r: (box('mp7_fg', (0.022, 0.025, 0.07), (0, 0.06, -0.035), m=m['poly'], parent=b, bevel=0.006))),
    'uzi': dict(ry=(-0.12, 0.12), rh=0.07, hg=None, blen=0.08, muzzle='none', stock='wire', sl=0.24, gy=-0.06, ga=5,
                mag=('straight', -0.06, 'metal', 0.022, 0.16, 5, 0.035), sight='iron', sy=0.0, pins=4),
    'mac10': dict(ry=(-0.09, 0.09), rh=0.09, hg=None, blen=0.06, muzzle='can', stock='wire', sl=0.22, gy=-0.05, ga=4,
                  mag=('straight', -0.05, 'metal', 0.02, 0.16, 4, 0.035), sight='iron', sy=0.0),
    'bizon': _ak_like(rh=0.075, blen=0.22, muzzle='cone', stock='wire', sl=0.24, mag=('helical', 0.14, 'poly', 0.026, 0.12, 0, 0.07),
                      hg=('poly', 0.13, 0.046, 0.0, 0.05, 'poly'), sight='iron', sy=0.05),
    'mp9': dict(ry=(-0.09, 0.11), rh=0.08, paint='poly', upper='poly', hg=None, blen=0.11, muzzle='flash', stock='wire', sl=0.2, gy=-0.05, ga=10,
                mag=('straight', -0.05, 'poly', 0.022, 0.13, 6, 0.035), sight='reddot', sy=0.0,
                extra=lambda b, m, r: box('mp9_fg', (0.022, 0.025, 0.06), (0, 0.07, -0.03), m=m['poly'], parent=b, bevel=0.006)),
    'barrett': dict(ry=(-0.16, 0.24), rh=0.12, hg=('round', 0.32, 0.06, 0.0, 0.06), blen=0.56, br=0.014, muzzle='brake', stock='fixed', stockm='paint', sl=0.25,
                    mag=('straight', 0.1, 'metal', 0.034, 0.12, 0, 0.09), sight='bigscope', sy=0.03, bipod=True, chandle='side'),
    'ssg08': dict(ry=(-0.1, 0.14), rh=0.075, hg=('poly', 0.22, 0.042, -0.005, 0.045, 'poly'), blen=0.4, muzzle='flash', stock='thumbhole', stockm='poly', sl=0.27,
                  mag=('straight', 0.06, 'poly', 0.024, 0.06, 0, 0.06), sight='scope', sy=0.02, chandle='side', gasblock=False),
    'svd': _ak_like(rh=0.08, hg=('wood', 0.22, 0.044, 0.0, 0.048), blen=0.5, muzzle='flash', stock='thumbhole', stockm='wood', sl=0.28,
                    mag=('straight', 0.1, 'metal', 0.026, 0.1, 6, 0.07), sight='scope', sy=0.02),
    'xm1014': dict(ry=(-0.12, 0.14), rh=0.08, hg=None, blen=0.44, br=0.011, muzzle='none', stock='skeleton', sl=0.24, tube=True,
                   mag=('none', 0.0), sight='holo', sy=0.02, gasblock=False),
    'sawed': dict(ry=(-0.1, 0.1), rh=0.075, hg=('wood', 0.12, 0.048, -0.02, 0.05), blen=0.2, br=0.013, muzzle='none', stock=None,
                  mag=('none', 0.0), sight='iron', sy=0.05, gasblock=False, gripm='wood', ga=30,
                  extra=lambda b, m, r: cyl('sawed_b2', 0.013, 0.2, (0, 0.2, 0.08), m=m['dark'], parent=b, verts=24)),
    'negev': dict(ry=(-0.08, 0.26), rh=0.11, hg=('rail', 0.16, 0.06, 0.0, 0.06), blen=0.42, br=0.013, muzzle='flash', stock='skeleton', sl=0.26,
                  mag=('box', 0.13, 'olive'), sight='reddot', sy=0.04, bipod=True),
    'pkm': _ak_like(rh=0.1, ry=(-0.1, 0.26), hg=None, blen=0.56, br=0.013, muzzle='flash', stock='thumbhole', stockm='wood', sl=0.28,
                    mag=('box', 0.12, 'green'), sight='iron', sy=0.08, bipod=True,
                    extra=lambda b, m, r: (box('pkm_cover', (0.06, 0.25, 0.02), (0, 0.1, 0.12), m=m['dark'], parent=b, bevel=0.004),
                                           box('pkm_handle', (0.016, 0.1, 0.016), (0, 0.48, 0.11), m=m['wood'], parent=b, bevel=0.004))),
}

PISTOLS = {
    'usp': dict(L=0.2, w=0.03, sh=0.032, comp=False, paint='poly', slide='dark', serr=8),
    'p250': dict(L=0.17, w=0.028, sh=0.03, paint='poly', slide='dark', serr=6, fserr=False),
    'fiveseven': dict(L=0.19, w=0.026, sh=0.028, paint='tan', slide='dark', serr=7),
    'yavuz': dict(L=0.2, w=0.03, sh=0.032, paint='dark', slide='dark', hammer=True, serr=9, rail=True),
    'tec9': dict(L=0.24, w=0.032, sh=0.03, paint='poly', slide='dark', serr=0, fserr=False, rail=False, ga=12),
}

KNIVES = {
    'kama': dict(pts=[(0.03, -0.006), (0.26, -0.004), (0.3, 0.006), (0.26, 0.018), (0.03, 0.022)], t=0.007, fuller=(0.15, 0.13, 0.007), guard=0.06, wraps=6),
    'sunguu': dict(pts=[(0.03, -0.006), (0.2, -0.006), (0.25, 0.01), (0.19, 0.02), (0.15, 0.024), (0.03, 0.024)], guard=0.05, ring=True, wraps=4),
    'kelebek': dict(pts=[(0.03, -0.004), (0.17, -0.004), (0.2, 0.006), (0.16, 0.018), (0.03, 0.018)], t=0.005, hl=0.12, wraps=8, pommel=False),
    'pala': dict(pts=[(0.03, -0.008), (0.2, -0.012), (0.33, -0.004), (0.38, 0.012), (0.33, 0.02), (0.2, 0.022), (0.03, 0.026)], t=0.007, guard=0.07, wraps=6),
}


def build(ids):
    for wid in ids:
        try:
            if wid in RECIPES:
                longgun(wid, dict(RECIPES[wid]))
            elif wid in PISTOLS:
                pistol(wid, PISTOLS[wid])
            elif wid in KNIVES:
                blade_knife(wid, KNIVES[wid])
            print('BUILT', wid)
        except Exception:
            import traceback; traceback.print_exc()
            print('FAILED', wid)


if __name__ == '__main__':
    ids = [a for a in sys.argv[1:] if not a.startswith('-')] or (list(RECIPES) + list(PISTOLS) + list(KNIVES))
    build(ids)
