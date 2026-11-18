"""Static checks on a built map JSON (no engine needed).

    python3 tools/map_check.py insaat [--top out.png]

- spawn-to-spawn line of sight at eye height (1.65 m) through the box colliders
- nearest enemy spawn distance per spawn
- spawns standing inside a collider / spawns without ground under them
- optional top-down plot (collider height colour, spawns, LOS lines that are open)
Colliders are oriented boxes in Godot space: c (centre), s (size), r (euler x,y,z radians, Godot order YXZ).
"""
import json, math, sys, os
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def rot_matrix(r):
    rx, ry, rz = r
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Ry @ Rx @ Rz          # Godot Basis.from_euler default order YXZ


def boxes(d):
    out = []
    for c in d['colliders']:
        R = rot_matrix(c['r'])
        out.append((np.array(c['c'], float), np.array(c['s'], float) / 2.0, R))
    return out


def seg_hits_box(p0, p1, b):
    c, h, R = b
    a = R.T @ (p0 - c); e = R.T @ (p1 - c)
    d = e - a
    t0, t1 = 0.0, 1.0
    for i in range(3):
        if abs(d[i]) < 1e-9:
            if a[i] < -h[i] or a[i] > h[i]:
                return False
        else:
            ta, tb = (-h[i] - a[i]) / d[i], (h[i] - a[i]) / d[i]
            if ta > tb:
                ta, tb = tb, ta
            t0, t1 = max(t0, ta), min(t1, tb)
            if t0 > t1:
                return False
    return True


def inside(p, b):
    c, h, R = b
    q = R.T @ (p - c)
    return bool(np.all(np.abs(q) < h - 1e-3))


def main():
    mid = sys.argv[1]
    d = json.load(open(os.path.join(ROOT, 'assets', 'maps', mid + '.json')))
    dp = os.path.join(ROOT, 'assets', 'maps', mid + '_dress.json')
    if os.path.exists(dp):
        dj = json.load(open(dp))
        d['colliders'] = d['colliders'] + dj.get('colliders', [])
        if dj.get('spawns'):
            d['spawns'] = dj['spawns']
    if d.get('mesh_collision'):
        print('   NOTE: imported map, its own meshes are collision -> sight-lines here only see box colliders')
    B = [b for b in boxes(d) if max(b[1]) * 2 < 200]          # skip giant ground plates for LOS
    G = boxes(d)
    sp = d['spawns']
    A = [s for s in sp if s['team'] == 'a']; Bt = [s for s in sp if s['team'] == 'b']
    eye = 1.65
    open_pairs = []
    for a in A:
        for b in Bt:
            p0 = np.array(a['p'], float) + [0, eye, 0]; p1 = np.array(b['p'], float) + [0, eye, 0]
            if not any(seg_hits_box(p0, p1, bx) for bx in B):
                open_pairs.append((a, b))
    print(f'{mid}: spawns A{len(A)} B{len(Bt)}  open spawn-to-spawn sightlines: {len(open_pairs)} / {len(A) * len(Bt)}')
    for a, b in open_pairs[:10]:
        print('   OPEN', [round(v, 1) for v in a['p']], '->', [round(v, 1) for v in b['p']])
    dmin = min(np.linalg.norm(np.array(a['p']) - np.array(b['p'])) for a in A for b in Bt)
    print(f'   closest enemy spawns: {dmin:.1f} m')
    bad = 0
    for s in sp:
        p = np.array(s['p'], float)
        body = p + [0, 0.9, 0]
        if any(inside(body, bx) for bx in G):
            print('   SPAWN INSIDE COLLIDER', [round(v, 1) for v in s['p']]); bad += 1
        down0, down1 = p + [0, 0.5, 0], p + [0, -0.6, 0]
        if not any(seg_hits_box(down0, down1, bx) for bx in G):
            print('   SPAWN WITHOUT GROUND', [round(v, 1) for v in s['p']]); bad += 1
    print('   spawn placement problems:', bad)
    if '--top' in sys.argv:
        import matplotlib; matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        from matplotlib.patches import Polygon
        out = sys.argv[sys.argv.index('--top') + 1]
        bd = d['bounds']
        fig, ax = plt.subplots(figsize=(11, 9.5))
        for (c, h, R) in sorted(B, key=lambda b: b[0][1] + b[1][1]):
            if h[0] * 2 > 120 or h[2] * 2 > 120:
                continue
            top = c[1] + h[1]
            corners = [R @ np.array([sx * h[0], 0, sz * h[2]]) + c for (sx, sz) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
            poly = [(q[0], -q[2]) for q in corners]
            colr = plt.cm.viridis(np.clip((top + 2.6) / 12.0, 0, 1)) if top > 0.25 or c[1] < -0.5 else (0.85, 0.85, 0.85, 0.5)
            ax.add_patch(Polygon(poly, fc=colr, ec='k', lw=0.25, alpha=0.85))
        for a, b in open_pairs:
            ax.plot([a['p'][0], b['p'][0]], [-a['p'][2], -b['p'][2]], 'r-', lw=0.6, alpha=0.6)
        for s in sp:
            ax.plot(s['p'][0], -s['p'][2], 'o', c='#3d8bff' if s['team'] == 'a' else '#ff4d3d', ms=8, mec='k')
        ax.set_xlim(bd[0] - 3, bd[2] + 3); ax.set_ylim(bd[1] - 3, bd[3] + 3); ax.set_aspect('equal'); ax.grid(alpha=0.3)
        ax.set_title(f'{mid} — üstten engel haritası (renk: engel tepe yüksekliği), kırmızı çizgi: açık doğuş görüş hattı')
        plt.savefig(out, dpi=80, bbox_inches='tight')
        print('   top view ->', out)


if __name__ == '__main__':
    main()
