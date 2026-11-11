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

FG = '/home/claude/ext3d/fak/weapons/'
SPECS['scar'] = dict(file=FG + 'flat_guns_west/Flat Guns West/GLB/Rifle_Battle_West.glb', axis='Y', real=0.95,
                     # CC0 "Flat Guns West" battle rifle (petroulacl/fps-asset-kit) - a proper SCAR-H silhouette
                     rhand=(-0.13, -0.055), muzzle=(0.455, 0.018), sight=(0.0, 0.09), lhand=(0.15, -0.008), eject=(0.05, 0.015),
                     drop=['Icosphere'], keep_mats=True, flat_shade=True,
                     mat_fix={'M_PCL_Flat_Grey_Darker': ((0.36, 0.28, 0.18), 0.0), 'M_PCL_Flat_Black_Lighter': ((0.045, 0.043, 0.04), 0.0)},
                     mat_pbr={'M_PCL_Flat_Grey_Darker': (0.62, 0.0), 'M_PCL_Flat_Black_Lighter': (0.55, 0.0), 'M_PCL_Flat_Black': (0.4, 0.6),
                              'M_PCL_Flat_Grey_Dark': (0.45, 0.5)},
                     zones=[((0.30, 0.41), (0.0, 0.035), ((0.03, 0.03, 0.032), 0.7, 0.4))],
                     split_mag=((-0.035, 0.05), (-0.16, -0.045)))

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

SPECS.update({
    'm4k': dict(file=NEW + '/m4carbine.fbx', axis='Y', flip=True, real=0.84,
                rhand=(-1.2, -0.55), muzzle=(6.53, 0.42), sight=(-1.0, 1.18), lhand=(2.3, 0.25), eject=(0.11, 0.45),
                flat={'Base_low': ((0.055, 0.057, 0.062), 0.75, 0.42), 'front_low': ((0.06, 0.062, 0.066), 0.6, 0.5),
                      'Stock_low': ((0.045, 0.045, 0.048), 0.0, 0.72), 'grip_low': ((0.04, 0.04, 0.042), 0.0, 0.78),
                      'magazine_low': ((0.07, 0.07, 0.075), 0.7, 0.45), 'Iron sight_low': ((0.04, 0.04, 0.045), 0.8, 0.4),
                      'small parts_low': ((0.08, 0.08, 0.085), 0.9, 0.35), 'trigger_low': ((0.08, 0.08, 0.085), 0.9, 0.35)},
                skin=['Base_low', 'front_low', 'Stock_low'],
                parts={'mag': ['magazine_low']}),
    'usp': dict(file=NEW + '/usp.fbx', axis='X', real=0.20,
                rhand=(-1.3, 0.45), muzzle=(2.12, 1.0), sight=(-1.55, 1.36), lhand=(-1.2, -0.6), eject=(-0.05, 1.1),
                keep_mats=True, mat_fix={'silver metal': ((0.075, 0.08, 0.088), 0.85)},
                parts={'slide': ['Cube.001', 'Cube.006'], 'mag': ['Cube.002', 'Cube.005']}),
    # revolver: restyled (own colours, steel frame + walnut grip)
    'kartal': dict(file=NEW + '/revolver.fbx', axis='X', flip=True, real=0.30,
                   rhand=(-1.45, -0.5), muzzle=(1.40, 0.04), sight=(-1.25, 0.24), lhand=(-1.4, -0.9), eject=(-0.65, -0.05),
                   flat_mat={'Material': ((0.11, 0.115, 0.125), 0.9, 0.3)}, skin_mats=['Material'],
                   wood_box=((-2.4, -0.95), (-1.6, -0.42), ((0.30, 0.16, 0.075), 0.0, 0.55))),
})

SPECS.update({
    'm4a1': dict(file=NEW + '/m4a1n.fbx', axis='X', real=0.84,
                 rhand=(-0.135, 0.0), muzzle=(0.469, 0.052), sight=(-0.13, 0.115), lhand=(0.168, 0.049), eject=(0.0, 0.059),
                 flat_mat={'UltimateLowPolyGuns': ((0.06, 0.062, 0.067), 0.7, 0.45)}, skin_mats=['UltimateLowPolyGuns'],
                 split_mag=((-0.06, 0.04), (-0.15, 0.0))),
    'akm': dict(file=NEW + '/akm.fbx', axis='Y', flip=True, real=0.88,
                rhand=(-0.124, -0.021), muzzle=(0.455, 0.020), sight=(0.056, 0.066), lhand=(0.271, 0.02), eject=(-0.027, 0.027),
                flat={'WPN_AKM_magazine': ((0.07, 0.07, 0.075), 0.7, 0.45), 'WPN_AKM': ((0.07, 0.072, 0.078), 0.8, 0.38)},
                skin=['WPN_AKM'],
                wood_boxes=([((-0.47, -0.185), (-0.17, 0.06)), ((-0.19, -0.105), (-0.15, -0.025)), ((0.105, 0.235), (-0.012, 0.075))],
                            ((0.29, 0.13, 0.065), 0.0, 0.5)),
                wood_objs=['WPN_AKM'],
                parts={'mag': ['WPN_AKM_magazine']}),
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
    elif f.endswith('.stl'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.wm.stl_import(filepath=f)
    elif f.endswith('.glb') or f.endswith('.gltf'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=f)
        for o in bpy.data.objects:
            if o.type == 'MESH':
                for md in list(o.modifiers):
                    o.modifiers.remove(md)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=f)
    for o in bpy.data.objects:
        o.animation_data_clear()
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
    if f.endswith('.stl'):
        pass
    if 'perm' in spec:
        a, b, c = spec['perm']
        for o in meshes:
            for v in o.data.vertices:
                q = v.co.copy(); v.co.x = q[a]; v.co.y = q[b]; v.co.z = q[c]
            o.data.flip_normals() if spec.get('perm_flip') else None
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
                if slot.material and slot.material.name.split('.')[0] in spec['flat_mat']:
                    key = slot.material.name.split('.')[0]
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
                    fx = spec.get('mat_fix', {}).get(key)
                    if fx and m2.node_tree:
                        b = next((n for n in m2.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
                        if b:
                            for sock in ('Base Color', 'Metallic'):
                                for l in list(b.inputs[sock].links):
                                    m2.node_tree.links.remove(l)
                            b.inputs['Base Color'].default_value = (*fx[0], 1); b.inputs['Metallic'].default_value = fx[1]
                slot.material = bpy.data.materials[nm]
                slot.material['src'] = key
    for zi, ((l0, l1), (u0, u1), zflat) in enumerate(spec.get('zones', [])):
        zm = bpy.data.materials.get('ext_%s_z%d' % (wid, zi)) or make_mat('ext_%s_z%d' % (wid, zi), flat=zflat)
        a, b = raw(l0, u0), raw(l1, u1)
        for o in meshes:
            if zm.name not in [mm.name for mm in o.data.materials if mm]:
                o.data.materials.append(zm)
            wi = [mm.name if mm else '' for mm in o.data.materials].index(zm.name)
            for pl in o.data.polygons:
                c = pl.center
                if min(a.y, b.y) < c.y < max(a.y, b.y) and min(a.z, b.z) < c.z < max(a.z, b.z):
                    pl.material_index = wi
    if 'wood_box' in spec or 'wood_boxes' in spec:
        if 'wood_box' in spec:
            (l0, l1), (u0, u1), flat = spec['wood_box']; boxes = [((l0, l1), (u0, u1))]
        else:
            boxes, flat = spec['wood_boxes']
        wm = make_mat('ext_%s_wood' % wid, flat=flat)
        bb = []
        for (l0, l1), (u0, u1) in boxes:
            a, b = raw(l0, u0), raw(l1, u1); bb.append((min(a.y, b.y), max(a.y, b.y), min(a.z, b.z), max(a.z, b.z)))
        only = spec.get('wood_objs')
        for o in meshes:
            if only and not any(o.name.startswith(k) for k in only):
                continue
            o.data.materials.append(wm); wi = len(o.data.materials) - 1
            for pl in o.data.polygons:
                c = pl.center
                if any(y0 < c.y < y1 and z0 < c.z < z1 for y0, y1, z0, z1 in bb):
                    pl.material_index = wi
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
            p.use_smooth = not spec.get('flat_shade', False)
    W.finish_export(wid) if False else export_glb(os.path.join(OUT, 'w_%s.glb' % wid))
    print('BUILT', wid, 'scale', round(s, 5))


if __name__ == '__main__':
    ids = [a for a in sys.argv[1:] if a in SPECS] or list(SPECS)
    for wid in ids:
        build(wid)
