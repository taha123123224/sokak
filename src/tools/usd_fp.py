"""Bake an animated Sketchfab USDZ first-person rig (arms + gun) into a Godot-ready glb.
Blender's USD importer builds the meshes/skeleton but does not bring the skeletal animation in, and
drives animated xforms through live Transform Cache constraints. Here the skeleton pose is evaluated
with pxr (UsdSkel), converted to pose-bone basis matrices, and everything is baked to keyframes.
Usage: python3 usd_fp.py <usdc> <out.glb> [step] [drop_mesh_substr,...]
"""
import bpy, sys, os
from mathutils import Matrix
sys.path.insert(0, "/home/claude/sokak/tools")
from usdpose import Poser

def gf2m(g):
    return Matrix([[g[r][c] for r in range(4)] for c in range(4)])  # Gf is row-vector -> transpose

def bake(usd, out, step=4, drop=()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=usd, set_frame_range=True)
    sc = bpy.context.scene
    sc.render.fps = 120  # USD time codes are 1/120 s; keep frame == time code
    P = Poser(usd)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and any(d.lower() in o.name.lower() for d in drop):
            bpy.data.objects.remove(o)
    cached = [o for o in bpy.data.objects if any(c.type == 'TRANSFORM_CACHE' for c in o.constraints)]
    t0, t1 = int(sc.frame_start), int(sc.frame_end)
    frames = sorted(set(list(range(t0, t1 + 1, step)) + [t1]))
    bind = [gf2m(b) for b in P.bind]
    bones = arm.data.bones
    # bone index in USD order
    idx = {n: i for i, n in enumerate(P.names)}
    # per-frame object matrices from the transform caches
    rec = {o.name: [] for o in cached}
    for f in frames:
        sc.frame_set(f)
        for o in cached:
            rec[o.name].append(o.matrix_world.copy())
    for o in cached:
        for c in list(o.constraints):
            o.constraints.remove(c)
    # world -> local basis (parents may be animated too): process top-down
    def depth(o):
        d = 0
        while o.parent: o = o.parent; d += 1
        return d
    for fi, f in enumerate(frames):
        for o in sorted(cached, key=depth):
            W = rec[o.name][fi]
            pw = Matrix.Identity(4)
            if o.parent:
                pw = rec[o.parent.name][fi] if o.parent.name in rec else o.parent.matrix_world
            o.matrix_parent_inverse = Matrix.Identity(4)
            o.matrix_basis = pw.inverted() @ W
            o.keyframe_insert("location", frame=f); o.keyframe_insert("rotation_quaternion" if o.rotation_mode == 'QUATERNION' else "rotation_euler", frame=f); o.keyframe_insert("scale", frame=f)
    # skeleton
    corr = {}
    for b in bones:
        if b.name in idx:
            corr[b.name] = bind[idx[b.name]].inverted() @ b.matrix_local
    for f in frames:
        X = P.skel_xforms(f)
        pose = {}
        for b in bones:
            if b.name in idx:
                pose[b.name] = gf2m(X[idx[b.name]]) @ corr[b.name]
            else:
                pose[b.name] = b.matrix_local.copy()
        for b in bones:
            pb = arm.pose.bones[b.name]
            pb.rotation_mode = 'QUATERNION'
            if b.parent:
                rel = b.parent.matrix_local.inverted() @ b.matrix_local
                basis = rel.inverted() @ pose[b.parent.name].inverted() @ pose[b.name]
            else:
                basis = b.matrix_local.inverted() @ pose[b.name]
            pb.matrix_basis = basis
            pb.keyframe_insert("location", frame=f); pb.keyframe_insert("rotation_quaternion", frame=f); pb.keyframe_insert("scale", frame=f)
    return arm, frames

if __name__ == "__main__":
    a = sys.argv[sys.argv.index('--') + 1:]
    usd, out = a[0], a[1]
    step = int(a[2]) if len(a) > 2 else 4
    drop = a[3].split(',') if len(a) > 3 and a[3] else ()
    bake(usd, out, step, drop)
    bpy.ops.wm.save_as_mainfile(filepath=out.replace('.glb', '.blend'))
    print("BAKED")
