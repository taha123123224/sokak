"""First-person gloved hands + sleeves -> assets/models/arms.glb
hand_r: grips a rod along local Z (pistol grip) through origin. Forearm goes back (-Y).
hand_l: grips a rod along local Y (handguard) through origin, hand below rod.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector
from bkit import *

reset()
glove = mat('arm_glove', (0.05, 0.05, 0.05), 0.0, 0.7)
glove2 = mat('arm_glove_pad', (0.18, 0.15, 0.1), 0.0, 0.8)
sleeve = mat('arm_sleeve', (0.3, 0.33, 0.24), 0.0, 0.9)
watch = mat('arm_watch', (0.02, 0.02, 0.02), 0.5, 0.3)


def seg(name, a, b, r1, r2, m, parent, verts=12):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cyl(name, r1, d.length, (0, 0, 0), m=m, parent=parent, verts=verts, r2=r2, axis='Z')
    o.location = (a + b) / 2
    o.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    sphere(name + 'j', r2 * 1.02, b, m=m, parent=parent, seg=10, rings=6)
    return o


def finger_curve(base, center, axis, radius, start_ang, sweep, lengths, r, m, parent, name):
    """finger bending around a rod: points on circle around `center` in plane perpendicular to axis"""
    pts = [Vector(base)]
    ang = start_ang
    c = Vector(center)
    for i, L in enumerate(lengths):
        ang += sweep[i]
        if axis == 'Z':
            p = Vector((c.x + math.cos(ang) * radius, c.y + math.sin(ang) * radius, base[2]))
        else:  # rod along Y: circle in XZ
            p = Vector((c.x + math.cos(ang) * radius, base[1], c.z + math.sin(ang) * radius))
        pts.append(p)
    for i in range(len(pts) - 1):
        rr = r * (1 - 0.1 * i)
        seg(f'{name}{i}', pts[i], pts[i + 1], rr, rr * 0.93, m, parent)
    sphere(name + 'b', r * 1.05, pts[0], m=m, parent=parent, seg=10, rings=6)


# ---------------- right hand (rod along Z)
R = empty('hand_r')
box('r_palm', (0.03, 0.075, 0.095), (0.034, -0.012, -0.005), (0, 0, 8), m=glove, parent=R, bevel=0.012, segs=3)
box('r_back', (0.012, 0.06, 0.07), (0.051, -0.015, -0.005), m=glove2, parent=R, bevel=0.005)
for i, z in enumerate([0.03, 0.008, -0.014, -0.036]):
    finger_curve((0.03, 0.03, z), (0, 0, 0), 'Z', 0.03, math.radians(40), [math.radians(40), math.radians(60), math.radians(55)], [0.03, 0.025, 0.02], 0.0095 - i * 0.0006, glove, R, f'rf{i}')
# thumb over top-left
seg('rt0', (0.03, -0.03, 0.04), (0.005, -0.02, 0.058), 0.011, 0.01, glove, R)
seg('rt1', (0.005, -0.02, 0.058), (-0.022, 0.0, 0.05), 0.01, 0.009, glove, R)
# wrist + forearm
seg('r_wrist', (0.036, -0.05, -0.01), (0.05, -0.1, -0.03), 0.026, 0.028, glove, R, 16)
seg('r_cuff', (0.05, -0.1, -0.03), (0.06, -0.14, -0.045), 0.033, 0.036, glove, R, 16)
seg('r_fore', (0.06, -0.13, -0.045), (0.13, -0.45, -0.17), 0.04, 0.055, sleeve, R, 16)
seg('r_fore2', (0.13, -0.45, -0.17), (0.16, -0.62, -0.26), 0.055, 0.06, sleeve, R, 16)
torus('r_watch', 0.03, 0.006, (0.051, -0.098, -0.03), (70, 0, -15), m=watch, parent=R, seg=20, mseg=6)

# ---------------- left hand (rod along Y, hand under the rod, fingers wrap over the right side)
L = empty('hand_l')
box('l_palm', (0.08, 0.09, 0.03), (-0.012, 0.0, -0.034), (0, -15, 0), m=glove, parent=L, bevel=0.012, segs=3)
box('l_back', (0.06, 0.07, 0.012), (-0.015, 0.0, -0.051), m=glove2, parent=L, bevel=0.005)
for i, y in enumerate([0.033, 0.011, -0.011, -0.033]):
    finger_curve((0.025, y, -0.03), (0, 0, 0), 'Y', 0.03, math.radians(-60), [math.radians(45), math.radians(55), math.radians(50)], [0.03, 0.025, 0.02], 0.0095 - abs(i - 1.5) * 0.0005, glove, L, f'lf{i}')
seg('lt0', (-0.035, 0.03, -0.03), (-0.035, 0.05, -0.005), 0.011, 0.01, glove, L)
seg('lt1', (-0.035, 0.05, -0.005), (-0.028, 0.07, 0.018), 0.01, 0.009, glove, L)
seg('l_wrist', (-0.02, -0.04, -0.045), (-0.04, -0.09, -0.07), 0.026, 0.028, glove, L, 16)
seg('l_cuff', (-0.04, -0.09, -0.07), (-0.05, -0.13, -0.09), 0.033, 0.036, glove, L, 16)
seg('l_fore', (-0.05, -0.12, -0.09), (-0.16, -0.40, -0.25), 0.04, 0.055, sleeve, L, 16)
seg('l_fore2', (-0.16, -0.40, -0.25), (-0.2, -0.58, -0.34), 0.055, 0.06, sleeve, L, 16)

apply_all_modifiers()
box_uv_all(8.0)
join_children(R, 'hand_r_mesh').parent = R
join_children(L, 'hand_l_mesh').parent = L
export_glb(os.path.join(ROOT, 'assets', 'models', 'arms.glb'))
