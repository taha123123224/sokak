"""User supplied melee models -> assets/models/w_<id>.glb (same layout as the built-in knives).
The mesh is aligned with PCA: long axis -> +Y (tip forward), blade width -> Z, thickness -> X.
Origin = right-hand grip point. Materials are game colours assigned by region along the length.
run: python3 tools/import_melee.py [hancer kasap balta]
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import bpy
import numpy as np
from mathutils import Vector, Matrix
from bkit import ROOT, export_glb

NEW = '/home/claude/ext3d/new'
OUT = os.environ.get('MELEE_OUT') or os.path.join(ROOT, 'assets', 'models')
STEEL = ((0.62, 0.64, 0.67), 0.95, 0.22)
DSTEEL = ((0.16, 0.17, 0.18), 0.9, 0.35)
BRASS = ((0.72, 0.52, 0.22), 1.0, 0.3)
WOOD = ((0.30, 0.17, 0.08), 0.0, 0.55)
LEATHER = ((0.07, 0.05, 0.04), 0.0, 0.75)
POLY = ((0.05, 0.05, 0.055), 0.0, 0.7)

# tip: +1 / -1 along the principal axis (sign picked from the preview), grip: grip point as a fraction from the butt
# zones: list of (from_frac, to_frac, mat, lateral_min) -- first match wins; lateral_min: only faces farther than this
#        (m, after scaling) from the long axis, used for the axe head
SPECS = {
    'hancer': dict(file=NEW + '/dagger/dagger STL.stl', real=0.32, grip=0.19, flipw=False, roll=35,
                   zones=[(0.0, 0.05, BRASS, 0), (0.05, 0.40, LEATHER, 0), (0.40, 0.47, BRASS, 0), (0.47, 1.01, STEEL, 0)]),
    'kasap': dict(file=NEW + '/kknife.fbx', real=0.30, grip=0.17, flipw=False, roll=35,
                  zones=[(0.0, 0.36, POLY, 0), (0.36, 0.40, STEEL, 0), (0.40, 1.01, STEEL, 0)]),
    'balta': dict(file=NEW + '/fbxfile/SM_Small_Axe_02.fbx', real=0.46, grip=0.16, flipw=False, roll=60,
                  zones=[(0.62, 1.01, DSTEEL, 0.016), (0.0, 1.01, WOOD, 0)]),
}


def mat(name, flat):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    col, metal, rough = flat
    b.inputs['Base Color'].default_value = (*col, 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    m.diffuse_color = (*col, 1)
    return m


def build(wid):
    spec = SPECS[wid]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    f = spec['file']
    if f.endswith('.stl'):
        bpy.ops.wm.stl_import(filepath=f)
    else:
        bpy.ops.import_scene.fbx(filepath=f)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in meshes:
        o.animation_data_clear(); mw = o.matrix_world.copy(); o.parent = None; o.matrix_parent_inverse = Matrix(); o.data.transform(mw); o.matrix_basis = Matrix()
    for o in [o for o in bpy.data.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.matrix_basis = Matrix()
    me = ob.data
    P = np.array([v.co[:] for v in me.vertices])
    c = P.mean(0)
    w, V = np.linalg.eigh(np.cov((P - c).T))
    ax_long, ax_w, ax_t = V[:, 2], V[:, 1], V[:, 0]
    proj = (P - c) @ ax_long
    # tip = the thinner end (blade); butt = the fatter end -- decide by spread of the far 10%
    lo, hi = proj.min(), proj.max()
    spread_hi = np.ptp(((P - c) @ ax_w)[proj > hi - 0.1 * (hi - lo)])
    spread_lo = np.ptp(((P - c) @ ax_w)[proj < lo + 0.1 * (hi - lo)])
    tip_sign = spec.get('tip', 1 if spread_hi < spread_lo else -1)
    if wid == 'balta':
        tip_sign = 1 if spread_hi > spread_lo else -1   # axe: the head (wide end) is "forward"
    ax_long = ax_long * tip_sign
    if spec.get('flipw'):
        ax_w = -ax_w
    ax_t = np.cross(ax_long, ax_w)  # right-handed basis: X = Y x Z
    R = np.array([ax_t, ax_long, ax_w])  # rows -> new X, Y, Z
    Q = (P - c) @ R.T
    L = Q[:, 1].max() - Q[:, 1].min()
    s = spec['real'] / L
    Q *= s
    y0 = Q[:, 1].min()
    grip_y = y0 + spec['grip'] * spec['real']
    Q[:, 1] -= grip_y
    # centre width/thickness on the grip section
    sec = np.abs(Q[:, 1]) < 0.02
    Q[:, 0] -= Q[sec, 0].mean() if sec.any() else 0
    Q[:, 2] -= Q[sec, 2].mean() if sec.any() else 0
    if spec.get('roll') and not os.environ.get('NOROLL'):
        a = np.radians(spec['roll'])
        ca, sa = np.cos(a), np.sin(a)
        x, z = Q[:, 0].copy(), Q[:, 2].copy()
        Q[:, 0] = ca * x - sa * z
        Q[:, 2] = sa * x + ca * z
    for i, v in enumerate(me.vertices):
        v.co = Vector(Q[i])
    me.update()
    # materials by zone
    me.materials.clear()
    mats = []
    for k, (a, b, flat, lat) in enumerate(spec['zones']):
        nm = ('gun_paint_ext_%s_%d' if k == len(spec['zones']) - 1 or flat is STEEL else 'ext_%s_%d') % (wid, k)
        me.materials.append(mat(nm, flat)); mats.append(k)
    ytip = Q[:, 1].max()
    for p in me.polygons:
        cc = p.center
        fr = (cc.y - (y0 - grip_y)) / spec['real']
        latd = (cc.x ** 2 + cc.z ** 2) ** 0.5
        for k, (a, b, flat, lat) in enumerate(spec['zones']):
            if a <= fr < b and latd >= lat:
                p.material_index = k
                break
        p.use_smooth = True
    root = bpy.data.objects.new('W_' + wid, None)
    bpy.context.scene.collection.objects.link(root)
    ob.name = 'body'; me.name = 'body'; ob.parent = root

    def emp(name, p):
        e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e); e.parent = root; e.location = p
    emp('muzzle', Vector((0, ytip, 0)))
    emp('sight', Vector((0, 0, 0.04)))
    for n in ('lhand', 'rhand', 'eject'):
        emp(n, Vector((0, 0, 0)))
    export_glb(os.path.join(OUT, 'w_%s.glb' % wid))
    print('BUILT', wid, 'tip', tip_sign, 'scale', round(s, 4), 'size', np.ptp(Q, 0).round(3))


if __name__ == '__main__':
    ids = [a for a in sys.argv[1:] if a in SPECS] or list(SPECS)
    for wid in ids:
        build(wid)
