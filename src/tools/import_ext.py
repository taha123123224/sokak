"""Imported (user supplied, 3DExport royalty-free) weapon models -> assets/models/w_<id>.glb
Each model is rotated so the muzzle points +Y, scaled to real length, re-centred on the right-hand grip point,
given the game's marker empties (muzzle / sight / lhand / rhand / eject) and its moving parts (mag / slide / bolt).
Skin-able materials are named gun_paint_ext_<id>_<n>: the game keeps their PBR textures for the standard skin.
run: python3.13 tools/import_ext.py [ak47 awp fn502 r870]
"""
import sys, os, math, statistics
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector, Matrix
from bkit import ROOT, export_glb
import weapons as W

E = '/home/claude/ext3d'
OUT = os.path.join(ROOT, 'assets', 'models')
TEX = os.path.join(ROOT, 'assets', 'tex', 'ext')
os.makedirs(TEX, exist_ok=True)
AKT = E + '/3dexport_dx02_ak_47_staobj_lowpol_exp_v2_1674068658/DX02_AK_47_StaObj_LowPol_Exp_v2/T01_Texture_AK_47_Static/PBR_2K/dx_s_ak47_export_LowPol_v2_Mat01_BaseTex_v1_'
SNB = E + '/3dexport_sniper_1722149628/3dexport_sniper_1722149628/bakes/'

# raw points measured on the original files (long axis, up); lateral centre is taken from the mesh
SPECS = {
    'ak47': dict(file=E + '/3dexport_dx02_ak_47_staobj_lowpol_exp_v2_1674068658/DX02_AK_47_StaObj_LowPol_Exp_v2/Dx00_1_ak47_export_v1.0.3.fbx',
                 axis='Y', real=0.88, rhand=(-0.356, 0.072), muzzle=(0.943, 0.187), sight=(0.087, 0.30), lhand=(0.355, 0.107), eject=(-0.03, 0.176),
                 tex={'Mat01_BaseTex_v1': (AKT + 'BaseColor.png', AKT + 'Normal.png', AKT + 'Roughness.png', AKT + 'Metallic.png')},
                 split_mag=((0.02, 0.36), (-0.32, 0.10))),
    'awp': dict(file=E + '/3dexport_sniper_1722149628/3dexport_sniper_1722149628/finalized_lowpoly.fbx',
                axis='Y', real=1.25, rhand=(-1.01, -0.03), muzzle=(4.13, 0.48), lhand=(1.30, 0.09), eject=(-0.4, 0.32), rail=(0.4, 0.68),
                tex={'Material.001': (SNB + '1st_basecolor.png', SNB + '1st_normal.png', SNB + '1st_roughness.png', SNB + '1st_metallic.png'),
                     'Material.002': (SNB + '2nd_basecolor.png', SNB + '2nd_normal.png', SNB + '2nd_roughness.png', SNB + '2nd_metallic.png')},
                parts={'mag': ['magazine.002_low', 'magazine.003_low'], 'bolt': ['bolt_handle .001_low']}),
    'fn502': dict(file=E + '/12f9a100-3dexport_fn502_1687540411/fn502/fn502.fbx',
                  axis='Y', real=0.20, rhand=(-2.94, 0.30), muzzle=(11.16, 2.99), sight=(-5.28, 5.0), lhand=(-4.0, -3.47), eject=(1.43, 3.3),
                  flat={'Shutter': ((0.07, 0.072, 0.078), 0.55, 0.38), 'Handle': ((0.035, 0.035, 0.038), 0.0, 0.7), 'Magazine': ((0.05, 0.05, 0.055), 0.6, 0.45),
                        'Cap': ((0.05, 0.05, 0.055), 0.8, 0.35), 'Plate': ((0.06, 0.06, 0.065), 0.7, 0.4), 'Bullet': ((0.75, 0.55, 0.25), 1.0, 0.3)},
                  skin=['Shutter', 'Handle'],
                  parts={'slide': ['Shutter'], 'mag': ['Magazine']}),
    'r870': dict(file=E + '/1c24b91b-3dexport_remington870_1661021571/remington870.blend',
                 axis='X', real=1.06, rhand=(-0.232, 0.018), muzzle=(0.531, 0.071), sight=(-0.048, 0.097), lhand=(0.218, 0.027), eject=(-0.03, 0.073),
                 # textures are not in the archive: game materials (blued steel + walnut wood)
                 flat_mat={'1': ((0.05, 0.05, 0.055), 0.85, 0.35), '2': ((0.32, 0.17, 0.08), 0.0, 0.5)},
                 skin_mats=['1', '2'],
                 parts={'pump': ['pump']}),
}

M19 = '/home/claude/ext3d/new/m1911/tex2k/m1911_'
NEW = '/home/claude/ext3d/new'
SPECS.update({
    'vityaz': dict(file=NEW + '/5cc142c0-PP-19-01_Vityaz/scene.usdc', axis='Y', flip=True, real=0.70,
                   rhand=(-0.073, -0.042), muzzle=(0.350, 0.0025), sight=(0.131, 0.0465), lhand=(0.2156, -0.0035), eject=(0.054, 0.016),
                   keep_mats=True, drop_above=0.15, parts_mat={'mag': ['pp19mag']}),
    'rpk16': dict(file=NEW + '/b9d78480-RPK-16/scene.usdc', axis='X', real=1.02,
                  rhand=(0.097, 0.020), muzzle=(6.103, 0.502), sight=(1.40, 1.16), lhand=(2.82, 0.344), eject=(1.437, 0.53),
                  keep_mats=True, mat_pbr={'mat0': (0.55, 0.35), 'mat0_001': (0.5, 0.5), 'mat0_002': (0.45, 0.45), 'mat0_004': (0.4, 0.6)},
                  parts={'mag': ['Mag_']}),
    'm1911': dict(file=NEW + '/m1911/source/1911 Sketchfab/m1911.fbx', axis='Y', real=0.362,
                  rhand=(-0.0574, 0.0122), muzzle=(0.2408, 0.042), sight=(-0.077, 0.058), lhand=(-0.07, -0.06), eject=(-0.0176, 0.038),
                  tex={'Mat_pistol': (M19 + 'pistol_albedo.png', M19 + 'pistol_normal.png', M19 + 'pistol_roughness.png', M19 + 'pistol_metallic.png'),
                       'Mat_silencer': (M19 + 'silencer_albedo.png', M19 + 'silencer_normal.png', M19 + 'silencer_roughness.png', M19 + 'silencer_metallic.png')},
                  drop=['Round_', 'Shell_'], parts={'slide': ['Shutter_lowTris'], 'mag': ['Magazine_', 'MagFollower_']}),
})

BR = NEW + '/br55/restyle/br_'
SPECS.update({
    'awm': dict(file=NEW + '/8aaf24d0-Sniper/scene.usdc', axis='Y', flip=True, real=1.20,
                rhand=(0.237, 0.453), muzzle=(11.873, 1.030), sight=(2.201, 1.803), lhand=(4.655, 0.662), eject=(1.587, 1.092),
                keep_mats=True, parts={'mag': ['mag_sniper', 'bullet_sniper'], 'bolt': ['bolt_sniper', 'boltback_sniper']}),
    'glock': dict(file=NEW + '/0dfb7aa7-Pistol_9mm_-_semi_auto/scene.usdc', axis='Y', real=0.19,
                  rhand=(-0.0809, 0.0253), muzzle=(0.1254, 0.0675), sight=(-0.098, 0.0839), lhand=(-0.09, -0.05), eject=(0.0202, 0.0698),
                  keep_mats=True, drop=['Bullet'], parts={'slide': ['GL_Slide_'], 'mag': ['GL_Magazine', 'GL_Follower']}),
    'spas': dict(file=NEW + '/933e0750-Shotgun/scene.usdc', axis='Y', flip=True, real=0.86,
                 rhand=(0.199, 0.267), muzzle=(11.132, 1.206), sight=(3.671, 1.534), lhand=(5.923, 0.783), eject=(3.296, 0.971),
                 keep_mats=True, drop=['slug_'], parts={'pump': ['pump_shotgun']}),
    'uzi': dict(file=NEW + '/14cb0444-Low_Poly_Uzi/scene.usdc', axis='Y', flip=True, real=0.30,
                rhand=(-0.0412, 0.0808), muzzle=(0.2203, 0.1648), sight=(-0.165, 0.223), lhand=(0.0888, 0.132), eject=(-0.0019, 0.2018),
                keep_mats=True, drop=['SubMachineGun_Shell']),
    'kuzgun': dict(file=NEW + '/br55/source/BR55 combined.fbx', axis='Y', flip=True, real=0.90,
                   rhand=(-0.1466, -0.0549), muzzle=(0.531, 0.0107), sight=(-0.0035, 0.126), lhand=(0.207, -0.055), eject=(-0.0035, 0.004),
                   tex_all=(BR + 'bc.png', BR + 'normal.png', BR + 'roughness.png', BR + 'metallic.png')),
})


def load(spec):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    f = spec['file']
    if f.endswith('.usdc') or f.endswith('.usdz'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.wm.usd_import(filepath=f)
    elif f.endswith('.blend'):
        bpy.ops.wm.open_mainfile(filepath=f, load_ui=False, use_scripts=False)
        for o in list(bpy.data.objects):
            if o.type != 'MESH':
                bpy.data.objects.remove(o)
    else:
        bpy.ops.import_scene.fbx(filepath=f)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    # bake every transform into the meshes, drop parents
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in list(meshes):
        cz = sum((v.co.z for v in o.data.vertices)) / max(len(o.data.vertices), 1)
        if any(o.name.startswith(d) for d in spec.get('drop', [])) or ('drop_above' in spec and cz > spec['drop_above']):
            meshes.remove(o); bpy.data.objects.remove(o)
    if spec.get('flip'):
        # muzzle points to -long: turn the model 180 deg about the up axis
        for o in meshes:
            for v in o.data.vertices:
                v.co.x = -v.co.x; v.co.y = -v.co.y
    return meshes


def to_game(spec, meshes):
    """returns function raw(long, up) -> game Vector, and applies the transform to the meshes"""
    li = 0 if spec['axis'] == 'X' else 1
    lat = 1 if li == 0 else 0
    vals = []
    for o in meshes:
        for v in o.data.vertices:
            vals.append(v.co[lat])
    lat_c = statistics.median(vals)
    lo = min(v.co[li] for o in meshes for v in o.data.vertices)
    hi = max(v.co[li] for o in meshes for v in o.data.vertices)
    s = spec['real'] / (hi - lo)
    rl, ru = spec['rhand']

    def raw(l, u, la=None):
        x = ((la if la is not None else lat_c) - lat_c) * s
        if li == 0:   # X was the long axis: lateral was Y, and +Y (old) points to the left -> mirror to keep handedness
            x = -x
        return Vector((x, (l - rl) * s, (u - ru) * s))

    for o in meshes:
        for v in o.data.vertices:
            c = v.co.copy()
            v.co = raw(c[li], c[2], c[lat])
        if li == 0:
            o.data.flip_normals() if False else None
    return raw, s


def make_mat(name, files=None, flat=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    if files:
        bc, nrm, rgh, met = files
        def img(path, color=True):
            t = nt.nodes.new('ShaderNodeTexImage')
            t.image = bpy.data.images.load(path)
            if not color:
                t.image.colorspace_settings.name = 'Non-Color'
            return t
        t = img(bc); nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        t = img(rgh, False); nt.links.new(t.outputs['Color'], bsdf.inputs['Roughness'])
        t = img(met, False); nt.links.new(t.outputs['Color'], bsdf.inputs['Metallic'])
        t = img(nrm, False)
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(t.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    elif flat:
        col, metal, rough = flat
        bsdf.inputs['Base Color'].default_value = (*col, 1)
        bsdf.inputs['Metallic'].default_value = metal
        bsdf.inputs['Roughness'].default_value = rough
    return m


def build(wid):
    spec = SPECS[wid]
    meshes = load(spec)
    raw, s = to_game(spec, meshes)
    # ---- materials
    n = 0
    if 'tex' in spec:
        for o in meshes:
            for slot in o.material_slots:
                if slot.material and slot.material.name in spec['tex']:
                    key = slot.material.name
                    nm = 'gun_paint_ext_%s_%d' % (wid, list(spec['tex']).index(key))
                    if nm not in bpy.data.materials:
                        make_mat(nm, spec['tex'][key])
                    slot.material = bpy.data.materials[nm]
    if 'flat' in spec:
        for o in meshes:
            key = next((k for k in spec['flat'] if o.name.startswith(k)), None)
            if key:
                nm = ('gun_paint_ext_%s_%s' if key in spec.get('skin', []) else 'ext_%s_%s') % (wid, key.lower())
                if nm not in bpy.data.materials:
                    make_mat(nm, flat=spec['flat'][key])
                o.data.materials.clear(); o.data.materials.append(bpy.data.materials[nm])
    if 'flat_mat' in spec:
        for o in meshes:
            for slot in o.material_slots:
                if slot.material and slot.material.name in spec['flat_mat']:
                    key = slot.material.name
                    nm = ('gun_paint_ext_%s_%s' if key in spec.get('skin_mats', []) else 'ext_%s_%s') % (wid, key)
                    if nm not in bpy.data.materials:
                        make_mat(nm, flat=spec['flat_mat'][key])
                    slot.material = bpy.data.materials[nm]
    if 'tex_all' in spec:
        nm = 'gun_paint_ext_%s_0' % wid
        make_mat(nm, spec['tex_all'])
        for o in meshes:
            o.data.materials.clear(); o.data.materials.append(bpy.data.materials[nm])
    if spec.get('keep_mats'):
        names = []
        for o in meshes:
            for slot in o.material_slots:
                m = slot.material
                if m is None or m.name.startswith('gun_paint_ext_'):
                    continue
                key = m.name
                if key not in names:
                    names.append(key)
                nm = 'gun_paint_ext_%s_%d' % (wid, names.index(key))
                if nm not in bpy.data.materials:
                    m2 = m.copy(); m2.name = nm
                    pbr = spec.get('mat_pbr', {}).get(key)
                    if pbr and m2.node_tree:
                        b = m2.node_tree.nodes.get('Principled BSDF') or next((n for n in m2.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
                        if b:
                            b.inputs['Roughness'].default_value = pbr[0]; b.inputs['Metallic'].default_value = pbr[1]
                slot.material = bpy.data.materials[nm]
                slot.material['src'] = key
    # ---- moving parts
    groups = {}
    if 'parts_mat' in spec:
        for part, mats in spec['parts_mat'].items():
            groups[part] = [o for o in meshes if any((sl.material and sl.material.get('src', sl.material.name) in mats) for sl in o.material_slots)]
    if 'parts' in spec:
        for part, names in spec['parts'].items():  # noqa
            groups[part] = [o for o in meshes if any(o.name.startswith(nm.strip()) or o.name.strip() == nm.strip() for nm in names)]
    if 'split_mag' in spec:
        (y0, y1), (z0, z1) = spec['split_mag']
        body = meshes[0]
        bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')
        parts = [o for o in bpy.data.objects if o.type == 'MESH']
        lo_y, hi_y = raw(y0, 0).y, raw(y1, 0).y
        lo_z, hi_z = raw(0, z0).z, raw(0, z1).z
        mags = []
        for o in parts:
            c = sum((v.co for v in o.data.vertices), Vector()) / max(len(o.data.vertices), 1)
            if lo_y < c.y < hi_y and lo_z < c.z < hi_z:
                mags.append(o)
        groups['mag'] = mags
        meshes = parts
    root = bpy.data.objects.new('W_' + wid, None)
    bpy.context.scene.collection.objects.link(root)
    used = set()
    for part, objs in groups.items():
        objs = [o for o in objs if o.name in bpy.data.objects]
        if not objs:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True); used.add(o.name)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        j.name = part; j.data.name = part
        j.parent = root
    rest = [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in used and o.parent is None]
    bpy.ops.object.select_all(action='DESELECT')
    for o in rest:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rest[0]
    if len(rest) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = 'body'; body.data.name = 'body'; body.parent = root
    # ---- scope for the sniper (model ships with a rail only)
    sight_pt = None
    if 'rail' in spec:
        m = W.M()
        rp = raw(*spec['rail'])
        grp = bpy.data.objects.new('scope_grp', None); bpy.context.scene.collection.objects.link(grp); grp.parent = root
        W.scope(grp, m, (0, rp.y, rp.z + 0.042), length=0.36, r=0.018, obj_r=0.028, mount_dy=(-0.07, 0.07))
        sc = [o for o in bpy.data.objects if o.parent == grp]
        bpy.ops.object.select_all(action='DESELECT')
        for o in sc:
            for mod in o.modifiers:
                with bpy.context.temp_override(object=o):
                    try: bpy.ops.object.modifier_apply(modifier=mod.name)
                    except Exception: pass
            o.select_set(True)
        bpy.context.view_layer.objects.active = sc[0]
        bpy.ops.object.join()
        jo = bpy.context.view_layer.objects.active
        mw = jo.matrix_world.copy(); jo.parent = root; jo.matrix_world = mw
        jo.name = 'scope'
        # scope parts are plain game materials (scope tube = skin-able paint)
        for slot in jo.material_slots:
            if slot.material and slot.material.name == 'gun_metal_dark':
                slot.material = bpy.data.materials.get('gun_paint') or slot.material
        bpy.data.objects.remove(grp)
        sight_pt = Vector((0, rp.y, rp.z + 0.042))
    # ---- markers
    def emp(name, p):
        e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e); e.parent = root; e.location = p
    emp('muzzle', raw(*spec['muzzle']))
    emp('sight', sight_pt if sight_pt is not None else raw(*spec['sight']))
    emp('lhand', raw(*spec['lhand']))
    emp('rhand', Vector((0, 0, 0)))
    e = raw(*spec['eject']); e.x = 0.03
    emp('eject', e)
    # light decimation for very dense meshes (first-person budget ~30k tris)
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        if len(o.data.polygons) > 35000:
            d = o.modifiers.new('dec', 'DECIMATE'); d.ratio = 35000 / len(o.data.polygons)
            with bpy.context.temp_override(object=o):
                bpy.ops.object.modifier_apply(modifier='dec')
        for p in o.data.polygons:
            p.use_smooth = True
    W.finish_export(wid) if False else export_glb(os.path.join(OUT, 'w_%s.glb' % wid))
    print('BUILT', wid, 'scale', round(s, 5))


if __name__ == '__main__':
    ids = [a for a in sys.argv[1:] if a in SPECS] or list(SPECS)
    for wid in ids:
        build(wid)
