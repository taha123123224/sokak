"""Weapon attachment models -> assets/models/att_<id>.glb (real size, Blender +Y = forward, +Z = up).
Origin = mounting point. Empties: 'muzzle' (new muzzle tip on barrel devices), 'sight' (window centre on optics)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from bkit import *
import weapons as W

OUT = W.OUT


def mats():
    m = W.M()
    m['grey'] = mat('gun_metal', (0.2, 0.2, 0.21), 0.9, 0.35)
    m['lens'] = mat('gun_glass', (0.25, 0.55, 0.6), 0.2, 0.03, alpha=0.18)
    m['ret'] = mat('gun_dot', (1, 0.12, 0.06), 0, 0.3, emission=(1, 0.08, 0.03), emit_strength=10)
    m['laser'] = mat('gun_dot', (1, 0.1, 0.05), 0, 0.3, emission=(1, 0.05, 0.02), emit_strength=12)
    return m


def done(name):
    apply_all_modifiers(); box_uv_all(4.0)
    export_glb(os.path.join(OUT, f'att_{name}.glb'))
    print('att', name)


def suppressor():
    reset(); m = mats(); root = empty('ATT_sus')
    L = 0.165
    prof = [(0.0, 0.0), (0.0125, 0.0), (0.0125, 0.022), (0.0165, 0.026), (0.0172, 0.03), (0.0172, L - 0.012), (0.0158, L - 0.004), (0.0075, L), (0.0055, L), (0.0055, L - 0.006), (0.0, L - 0.006)]
    lathe('sus_body', prof, (0, 0, 0), m=m['dark'], parent=root, seg=40, axis='Y')
    for i in range(5):
        y = 0.05 + i * 0.022
        lathe(f'sus_ring{i}', [(0.0174, 0), (0.0176, 0), (0.0176, 0.004), (0.0174, 0.004)], (0, y, 0), m=m['grey'], parent=root, seg=40, axis='Y')
    lathe('sus_collar', [(0.0128, 0), (0.0135, 0), (0.0135, 0.016), (0.0128, 0.016)], (0, 0.004, 0), m=m['grey'], parent=root, seg=24, axis='Y')
    for k in range(8):   # wrench flats on the collar
        a = k / 8 * math.tau
        box(f'sus_flat{k}', (0.004, 0.012, 0.002), (math.cos(a) * 0.0136, 0.012, math.sin(a) * 0.0136), (0, -math.degrees(a) + 90, 0), m=m['dark'], parent=root)
    empty('muzzle', (0, L + 0.002, 0), root)
    done('sus')


def compensator():
    reset(); m = mats(); root = empty('ATT_kompen')
    L = 0.058
    lathe('cmp', [(0.0, 0.0), (0.0118, 0.0), (0.0128, 0.006), (0.0128, L - 0.004), (0.011, L), (0.006, L), (0.0, L)], (0, 0, 0), m=m['dark'], parent=root, seg=32, axis='Y')
    for i in range(3):
        y = 0.016 + i * 0.013
        box(f'cmp_top{i}', (0.012, 0.006, 0.004), (0, y, 0.0122), m=m['poly'], parent=root)
        for s in (-1, 1):
            box(f'cmp_side{i}{s}', (0.004, 0.006, 0.01), (s * 0.0122, y, 0.002), m=m['poly'], parent=root)
    empty('muzzle', (0, L + 0.002, 0), root)
    done('kompen')


def holosight():
    # EOTech-style: low base on a picatinny clamp, open window with a hood, glass and a red ring+dot reticle
    reset(); m = mats(); root = empty('ATT_optik')
    box('ho_clamp', (0.032, 0.075, 0.008), (0, 0, 0.004), m=m['dark'], parent=root, bevel=0.002)
    box('ho_base', (0.034, 0.1, 0.014), (0, 0.005, 0.015), m=m['dark'], parent=root, bevel=0.004)
    box('ho_bat', (0.03, 0.03, 0.02), (0, -0.032, 0.03), m=m['dark'], parent=root, bevel=0.004)
    for i in range(3):
        box(f'ho_btn{i}', (0.006, 0.005, 0.003), (-0.009 + i * 0.009, -0.047, 0.033), m=m['rubber'], parent=root, bevel=0.001)
    zc = 0.048   # window centre height
    for s in (-1, 1):
        box(f'ho_wall{s}', (0.004, 0.06, 0.046), (s * 0.0185, 0.01, zc - 0.004), m=m['dark'], parent=root, bevel=0.0015)
    box('ho_hood', (0.041, 0.064, 0.005), (0, 0.01, zc + 0.022), m=m['dark'], parent=root, bevel=0.002)
    box('ho_hood_lip', (0.041, 0.004, 0.008), (0, 0.042, zc + 0.019), m=m['dark'], parent=root, bevel=0.0015)
    box('ho_glass_r', (0.033, 0.002, 0.036), (0, -0.012, zc), m=m['lens'], parent=root)
    box('ho_glass_f', (0.033, 0.002, 0.036), (0, 0.032, zc), m=m['lens'], parent=root)
    torus = bpy.ops.mesh.primitive_torus_add
    torus(major_radius=0.0062, minor_radius=0.0004, location=(0, 0.031, zc), rotation=(math.radians(90), 0, 0), major_segments=32, minor_segments=4)
    t = bpy.context.active_object; t.name = 'ho_ring'; t.parent = root; t.data.materials.append(m['ret'])
    sphere('ho_dot', 0.0007, (0, 0.031, zc), m=m['ret'], parent=root, seg=8, rings=4)
    empty('sight', (0, 0.0, zc), root)
    done('optik')


def foregrip():
    reset(); m = mats(); root = empty('ATT_tutamak')
    box('fg_clamp', (0.03, 0.05, 0.012), (0, 0, -0.006), m=m['dark'], parent=root, bevel=0.003)
    lathe('fg_body', [(0.0, 0.0), (0.0145, 0.0), (0.0155, 0.01), (0.0145, 0.075), (0.0165, 0.082), (0.0165, 0.088), (0.0, 0.088)], (0, 0, -0.012), (180, 0, 0), m=m['poly'], parent=root, seg=28)
    for i in range(5):
        lathe(f'fg_rib{i}', [(0.0148, 0), (0.0156, 0), (0.0156, 0.003), (0.0148, 0.003)], (0, 0, -0.03 - i * 0.011), m=m['rubber'], parent=root, seg=28)
    done('tutamak')


def laser():
    reset(); m = mats(); root = empty('ATT_lazer')
    box('lz_clamp', (0.012, 0.035, 0.022), (0.006, 0, 0), m=m['dark'], parent=root, bevel=0.002)
    box('lz_body', (0.024, 0.058, 0.026), (0.022, 0.004, 0), m=m['dark'], parent=root, bevel=0.005)
    box('lz_switch', (0.008, 0.012, 0.006), (0.022, -0.016, 0.015), m=m['rubber'], parent=root, bevel=0.002)
    cyl('lz_lens_r', 0.0045, 0.004, (0.016, 0.034, 0.004), m=m['laser'], parent=root, verts=16)
    cyl('lz_lens_l', 0.0055, 0.004, (0.028, 0.034, -0.004), m=m['lens'], parent=root, verts=16)
    done('lazer')


if __name__ == '__main__':
    for f in (suppressor, compensator, holosight, foregrip, laser):
        f()
