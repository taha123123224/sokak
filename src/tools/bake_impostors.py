"""Bake multi-view tree impostors from high-poly CC0 tree models (Poly Haven) -> one atlas pair.

    python3 tools/bake_impostors.py <spec.json> <out_prefix>

spec.json: [{"src": "/path/tree.gltf", "label": "olive_a", "pick": null | int}, ...]
  - a source file may contain several trees side by side (e.g. fir_tree_01 holds 3): each top-level
    root (or each spatially separate mesh cluster) becomes its own row; "pick" keeps just one of them.

Output (rows = trees, columns = VIEWS azimuths, cell CW x CH px):
  <out>_albedo.png  RGBA  straight albedo (unlit base colour) + alpha
  <out>_normal.png  RGB   view-space normal per cell (x right, y up, z towards camera) packed 0..1
  <out>.json        rows: label, aspect (w/h of the cell content), height_m, trunk_px
Renders are emission-only (no lighting) so the game lights the impostor itself -> it matches the sun.
"""
import bpy, sys, json, math, os
from mathutils import Vector

VIEWS = 8
CW, CH = 512, 512
SAMPLES = 12


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_gltf(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def world_bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == 'MESH' for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def clusters(objs):
    """group meshes into trees: by top-level root first, then by XY proximity"""
    meshes = [o for o in objs if o.type == 'MESH']
    groups = []
    for o in meshes:
        mn, mx = world_bbox([o])
        c = (mn + mx) / 2
        for g in groups:
            gmn, gmx = g['mn'], g['mx']
            if gmn.x - 0.5 <= c.x <= gmx.x + 0.5 and gmn.y - 0.5 <= c.y <= gmx.y + 0.5:
                g['objs'].append(o); g['mn'] = Vector(map(min, gmn, mn)); g['mx'] = Vector(map(max, gmx, mx)); break
        else:
            groups.append(dict(objs=[o], mn=mn, mx=mx))
    # merge groups whose boxes overlap (crown meshes vs trunk meshes)
    merged = True
    while merged:
        merged = False
        for i in range(len(groups)):
            for j in range(i + 1, len(groups)):
                a, b = groups[i], groups[j]
                if a['mn'].x <= b['mx'].x and b['mn'].x <= a['mx'].x and a['mn'].y <= b['mx'].y and b['mn'].y <= a['mx'].y:
                    a['objs'] += b['objs']; a['mn'] = Vector(map(min, a['mn'], b['mn'])); a['mx'] = Vector(map(max, a['mx'], b['mx']))
                    groups.pop(j); merged = True; break
            if merged:
                break
    groups.sort(key=lambda g: g['mn'].x)
    return groups


def make_emission_mats(mode):
    """mode 'albedo': emission = base colour, alpha kept.  mode 'normal': emission = camera-space normal."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if bsdf is None or out is None:
            continue
        key = '_orig_' + mode
        em = nt.nodes.new('ShaderNodeEmission')
        tr = nt.nodes.new('ShaderNodeBsdfTransparent')
        mix = nt.nodes.new('ShaderNodeMixShader')
        if mode == 'albedo':
            bc = bsdf.inputs['Base Color']
            if bc.is_linked:
                nt.links.new(bc.links[0].from_socket, em.inputs['Color'])
            else:
                em.inputs['Color'].default_value = bc.default_value
        else:
            geo = nt.nodes.new('ShaderNodeNewGeometry')
            nm = bsdf.inputs['Normal']
            src = nm.links[0].from_socket if nm.is_linked else geo.outputs['Normal']
            vt = nt.nodes.new('ShaderNodeVectorTransform')
            vt.vector_type = 'NORMAL'; vt.convert_from = 'WORLD'; vt.convert_to = 'CAMERA'
            nt.links.new(src, vt.inputs['Vector'])
            # blender camera space: x right, y up, z toward the viewer is -z... flip z so +z faces camera
            sep = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(vt.outputs['Vector'], sep.inputs['Vector'])
            neg = nt.nodes.new('ShaderNodeMath'); neg.operation = 'MULTIPLY'; neg.inputs[1].default_value = -1.0
            nt.links.new(sep.outputs['Z'], neg.inputs[0])
            comb = nt.nodes.new('ShaderNodeCombineXYZ')
            nt.links.new(sep.outputs['X'], comb.inputs['X']); nt.links.new(sep.outputs['Y'], comb.inputs['Y']); nt.links.new(neg.outputs['Value'], comb.inputs['Z'])
            mapr = nt.nodes.new('ShaderNodeVectorMath'); mapr.operation = 'MULTIPLY_ADD'
            nt.links.new(comb.outputs['Vector'], mapr.inputs[0])
            mapr.inputs[1].default_value = (0.5, 0.5, 0.5); mapr.inputs[2].default_value = (0.5, 0.5, 0.5)
            nt.links.new(mapr.outputs['Vector'], em.inputs['Color'])
        em.inputs['Strength'].default_value = 1.0
        al = bsdf.inputs['Alpha']
        if al.is_linked:
            nt.links.new(al.links[0].from_socket, mix.inputs['Fac'])
        else:
            mix.inputs['Fac'].default_value = al.default_value
        nt.links.new(tr.outputs['BSDF'], mix.inputs[1])
        nt.links.new(em.outputs['Emission'], mix.inputs[2])
        for l in list(out.inputs['Surface'].links):
            nt.links.remove(l)
        nt.links.new(mix.outputs['Shader'], out.inputs['Surface'])


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 0
    sc.cycles.transparent_max_bounces = 64
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = CW, CH
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.display_settings.display_device = 'sRGB'
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[1].default_value = 0.0
    cd = bpy.data.cameras.new('cam'); cam = bpy.data.objects.new('cam', cd)
    sc.collection.objects.link(cam); sc.camera = cam
    cd.type = 'ORTHO'
    return sc, cam


def main():
    spec = json.load(open(sys.argv[-2]))
    out = sys.argv[-1]
    tmpd = out + '_tmp'
    os.makedirs(tmpd, exist_ok=True)
    rows = []
    for si, sp in enumerate(spec):
        reset()
        objs = import_gltf(sp['src'])
        groups = clusters(objs)
        if sp.get('pick') is not None:
            groups = [groups[sp['pick']]]
        for gi, g in enumerate(groups):
            label = sp['label'] + ('' if len(groups) == 1 else chr(ord('a') + gi))
            # hide other trees of the same file
            keep = set(g['objs'])
            for o in bpy.data.objects:
                if o.type == 'MESH':
                    o.hide_render = o not in keep
            mn, mx = g['mn'], g['mx']
            H = mx.z - mn.z
            R = max(mx.x - mn.x, mx.y - mn.y) / 2
            ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
            rows.append(dict(label=label, height_m=round(H, 2), src=os.path.basename(sp['src']), group=gi))
            for mode in ('albedo', 'normal'):
                # fresh import per mode keeps the material rewiring simple
                reset(); objs = import_gltf(sp['src'])
                for o in bpy.data.objects:
                    if o.type == 'MESH':
                        mn2, mx2 = world_bbox([o]); c2 = (mn2 + mx2) / 2
                        o.hide_render = not (mn.x - 0.01 <= c2.x <= mx.x + 0.01 and mn.y - 0.01 <= c2.y <= mx.y + 0.01)
                make_emission_mats(mode)
                sc, cam = setup_scene()
                # ortho frame: square-ish width for the widest view, height = tree height (+2 % margin)
                half_w = R * 1.04
                aspect = (2 * half_w) / (H * 1.02)
                scale = max(H * 1.02, 2 * half_w)
                cam.data.ortho_scale = scale
                rows[-1]['frame_h_m'] = round(scale, 3)
                rows[-1]['frame_w_m'] = round(scale * CW / CH, 3)
                for v in range(VIEWS):
                    a = v / VIEWS * math.tau
                    d = Vector((math.sin(a), -math.cos(a), 0))
                    cam.location = ctr + Vector((0, 0, scale / 2)) + d * (R * 4 + 10)
                    cam.rotation_euler = (math.radians(90), 0, a)
                    cam.data.clip_end = R * 8 + 40
                    sc.render.filepath = os.path.join(tmpd, f'{len(rows) - 1:02d}_{v}_{mode}.png')
                    bpy.ops.render.render(write_still=True)
                print('BAKED', label, mode, flush=True)
    json.dump(dict(views=VIEWS, cell=[CW, CH], rows=rows), open(out + '.json', 'w'), indent=1)
    print('DONE rows', len(rows), flush=True)


if __name__ == '__main__':
    main()
