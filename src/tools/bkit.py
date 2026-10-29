"""Blender helper kit for procedural hard-surface modelling (bpy 5.x, background mode).
Conventions: Blender X right, Y forward (becomes -Z in glTF/Godot), Z up. Meters.
"""
import bpy, bmesh, math, os, json
from mathutils import Vector, Matrix, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
TEX = os.path.join(ROOT, 'assets', 'tex')

_mats = {}
_imgs = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear(); _imgs.clear()


def img(name, colorspace='sRGB'):
    key = (name, colorspace)
    if key in _imgs:
        return _imgs[key]
    path = os.path.join(TEX, name)
    if not os.path.exists(path):
        return None
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = colorspace
    _imgs[key] = im
    return im


def mat(name, color=(0.8, 0.8, 0.8), metal=0.0, rough=0.5, tex=None, emission=None, emit_strength=0.0,
        alpha=1.0, tint_tex=True, normal_strength=1.0, transmission=0.0):
    """tex: base name of a generated texture set, e.g. 'cobble' -> cobble_albedo.png / _normal / _orm"""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    if alpha < 1:
        bsdf.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1)
        bsdf.inputs['Emission Strength'].default_value = emit_strength
    if tex:
        alb = img(tex + '_albedo.png')
        if alb:
            n = nt.nodes.new('ShaderNodeTexImage'); n.image = alb
            if tint_tex and color != (1, 1, 1):
                mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
                mix.inputs['Factor'].default_value = 1.0
                nt.links.new(n.outputs['Color'], mix.inputs['A'])
                mix.inputs['B'].default_value = (*color, 1)
                nt.links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])
            else:
                nt.links.new(n.outputs['Color'], bsdf.inputs['Base Color'])
        nrm = img(tex + '_normal.png', 'Non-Color')
        if nrm:
            n2 = nt.nodes.new('ShaderNodeTexImage'); n2.image = nrm
            nm = nt.nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value = normal_strength
            nt.links.new(n2.outputs['Color'], nm.inputs['Color'])
            nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
        orm = img(tex + '_orm.png', 'Non-Color')
        if orm:
            n3 = nt.nodes.new('ShaderNodeTexImage'); n3.image = orm
            sep = nt.nodes.new('ShaderNodeSeparateColor')
            nt.links.new(n3.outputs['Color'], sep.inputs['Color'])
            nt.links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
            nt.links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
    _mats[name] = m
    return m


# ------------------------------------------------------------------ object creation helpers
def _link(obj, parent=None, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.empty_display_size = 0.02
    return _link(e, parent)


def _finish(bm, name, material, loc, rot, parent, bevel, segs, uv_scale, smooth=True, harden=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    obj = bpy.data.objects.new(name, me)
    if material is not None:
        me.materials.append(material)
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    _link(obj, parent)
    if bevel and bevel > 0:
        md = obj.modifiers.new('bevel', 'BEVEL')
        md.width = bevel; md.segments = segs; md.limit_method = 'ANGLE'; md.angle_limit = math.radians(35)
        md.harden_normals = harden
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
        if bevel and bevel > 0:
            wn = obj.modifiers.new('wn', 'WEIGHTED_NORMAL'); wn.keep_sharp = True
    obj['uv_scale'] = uv_scale
    return obj


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, bevel=0.0, segs=2, uv=1.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return _finish(bm, name, m, loc, rot, parent, bevel, segs, uv)


def cyl(name, r, length, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, verts=24, bevel=0.0, segs=2, r2=None, axis='Y', uv=1.0, cap=True):
    """cylinder along `axis` (default Y = forward)"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=length)
    if axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    elif axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    return _finish(bm, name, m, loc, rot, parent, bevel, segs, uv)


def tube(name, r_out, r_in, length, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, verts=24, axis='Y', bevel=0.0):
    """hollow cylinder (rings)"""
    bm = bmesh.new()
    rings = []
    for (rr, z) in [(r_out, -length / 2), (r_out, length / 2), (r_in, length / 2), (r_in, -length / 2)]:
        ring = [bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)) for a in [i / verts * math.tau for i in range(verts)]]
        rings.append(ring)
    for k in range(4):
        a, b = rings[k], rings[(k + 1) % 4]
        for i in range(verts):
            bm.faces.new((a[i], a[(i + 1) % verts], b[(i + 1) % verts], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    elif axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    return _finish(bm, name, m, loc, rot, parent, bevel, 2, 1.0)


def torus(name, R, r, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, seg=32, mseg=12, arc=360):
    bm = bmesh.new()
    rings = []
    n_major = seg if arc == 360 else seg + 1
    for i in range(n_major):
        a = math.radians(arc) * i / seg
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        ring = []
        for j in range(mseg):
            b = j / mseg * math.tau
            d = Vector((math.cos(a), math.sin(a), 0)) * math.cos(b) * r + Vector((0, 0, math.sin(b) * r))
            ring.append(bm.verts.new(c + d))
        rings.append(ring)
    for i in range(seg):
        a = rings[i]; b = rings[(i + 1) % n_major]
        for j in range(mseg):
            bm.faces.new((a[j], b[j], b[(j + 1) % mseg], a[(j + 1) % mseg]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _finish(bm, name, m, loc, rot, parent, 0, 2, 1.0)


def sphere(name, r, loc=(0, 0, 0), m=None, parent=None, seg=24, rings=12, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return _finish(bm, name, m, loc, (0, 0, 0), parent, 0, 2, 1.0)


def prof(name, pts, width, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, bevel=0.004, segs=2, plane='YZ', uv=1.0, x0=None):
    """Extrude a 2D side-profile polygon. plane='YZ': pts are (y,z), extruded along X symmetric.
    plane='XY': pts (x,y) extruded along Z. plane='XZ': pts (x,z) extruded along Y."""
    bm = bmesh.new()
    h = width / 2
    vs_a, vs_b = [], []
    for p in pts:
        if plane == 'YZ':
            a = (-h if x0 is None else x0, p[0], p[1]); b = (h if x0 is None else x0 + width, p[0], p[1])
        elif plane == 'XY':
            a = (p[0], p[1], -h); b = (p[0], p[1], h)
        else:
            a = (p[0], -h, p[1]); b = (p[0], h, p[1])
        vs_a.append(bm.verts.new(a)); vs_b.append(bm.verts.new(b))
    bm.faces.new(vs_a)
    bm.faces.new(list(reversed(vs_b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((vs_a[i], vs_a[j], vs_b[j], vs_b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # triangulate n-gons cleanly for bevel
    return _finish(bm, name, m, loc, rot, parent, bevel, segs, uv)


def lathe(name, pts, loc=(0, 0, 0), rot=(0, 0, 0), m=None, parent=None, seg=32, axis='Z'):
    """revolve (r, h) points around Z"""
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = i / seg * math.tau
        rings.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, hh)) for (r, hh) in pts])
    for i in range(seg):
        A, B = rings[i], rings[(i + 1) % seg]
        for k in range(len(pts) - 1):
            bm.faces.new((A[k], B[k], B[k + 1], A[k + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    return _finish(bm, name, m, loc, rot, parent, 0, 2, 1.0)


def arc_pts(c, r, a0, a1, n=12):
    return [(c[0] + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, c[1] + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r) for i in range(n + 1)]


def array(objfn, count, step):
    out = []
    for i in range(count):
        out.append(objfn(i, [s * i for s in step]))
    return out


def boolean_diff(target, cutter):
    md = target.modifiers.new('bool', 'BOOLEAN')
    md.operation = 'DIFFERENCE'; md.object = cutter; md.solver = 'EXACT'
    # move boolean to top of stack so bevel runs after
    while target.modifiers.find('bool') > 0:
        bpy.context.view_layer.objects.active = target
        with bpy.context.temp_override(object=target):
            bpy.ops.object.modifier_move_up(modifier='bool')
    cutter.hide_render = True
    cutter['cutter'] = True
    return target


# ------------------------------------------------------------------ UV + finalize
def box_uv_all(default_scale=1.0):
    """World-space box projection UVs for every mesh (after applying modifiers)."""
    dg = bpy.context.evaluated_depsgraph_get()
    for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
        if obj.get('cutter'):
            continue
        me = obj.data
        if not me.uv_layers:
            me.uv_layers.new(name='UV')
        s = obj.get('uv_scale', default_scale)
        bm = bmesh.new(); bm.from_mesh(me)
        uvl = bm.loops.layers.uv.verify()
        mw = obj.matrix_world
        rot = mw.to_3x3()
        for f in bm.faces:
            nrm = (rot @ f.normal)
            ax = max(range(3), key=lambda i: abs(nrm[i]))
            for l in f.loops:
                p = mw @ l.vert.co
                if ax == 0:
                    uv = (p.y * math.copysign(1, nrm.x), p.z)
                elif ax == 1:
                    uv = (-p.x * math.copysign(1, nrm.y), p.z)
                else:
                    uv = (p.x, p.y * math.copysign(1, nrm.z))
                l[uvl].uv = (uv[0] * s, uv[1] * s)
        bm.to_mesh(me); bm.free()


def remove_cutters():
    for o in list(bpy.context.scene.objects):
        if o.get('cutter'):
            pass  # keep until export; exporter skips hidden? We delete after applying.


def apply_all_modifiers():
    for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.get('cutter')]:
        bpy.context.view_layer.objects.active = obj
        for md in list(obj.modifiers):
            try:
                with bpy.context.temp_override(object=obj, active_object=obj):
                    bpy.ops.object.modifier_apply(modifier=md.name)
            except Exception as e:
                print('modifier apply failed', obj.name, md.name, e)
    for o in list(bpy.context.scene.objects):
        if o.get('cutter'):
            bpy.data.objects.remove(o, do_unlink=True)


def join_children(parent, name, keep=()):
    """join all mesh children of parent (except names in keep) into one mesh"""
    objs = [o for o in parent.children if o.type == 'MESH' and o.name not in keep and not o.get('cutter')]
    if len(objs) < 2:
        if objs:
            objs[0].name = name
        return objs[0] if objs else None
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def export_glb(path, objects=None):
    bpy.ops.object.select_all(action='DESELECT')
    if objects:
        for o in objects:
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=bool(objects), export_apply=True,
                              export_yup=True, export_extras=True, export_image_format='AUTO', export_texcoords=True,
                              export_normals=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
    print('exported', path, os.path.getsize(path) // 1024, 'KB')
