# v4.17: ccransh's AK-74M pack has no inspect; his rifle pack (same DJMaesen arms rig, same bone names apart from the
# glTF index suffix) has 'rifle_inspect'. Copy that clip onto the AK rig and write the pack back out as one glb.
import bpy, sys, re
a = sys.argv[sys.argv.index('--') + 1:]
dst, src, out, clip, newname = a[0], a[1], a[2], a[3], a[4]
base = lambda n: re.sub(r'_\d+$', '', n)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src, guess_original_bind_pose=False)
sarm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
sact = [x for x in bpy.data.actions if x.name.endswith(clip)][0]
def fcurves(act):
    if hasattr(act, 'layers') and act.layers:
        out = []
        for L in act.layers:
            for st in L.strips:
                for cb in st.channelbags: out += list(cb.fcurves)
        return out
    return list(act.fcurves)
data = []
for fc in fcurves(sact):
    m = re.match(r'pose\.bones\["(.+)"\]\.(\w+)', fc.data_path)
    if not m: continue
    data.append((base(m.group(1)), m.group(2), fc.array_index, [(k.co[0], k.co[1]) for k in fc.keyframe_points]))
frames = sact.frame_range[:]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
for x in list(bpy.data.actions): bpy.data.actions.remove(x)
bpy.ops.import_scene.gltf(filepath=dst, guess_original_bind_pose=False)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
names = {base(b.name): b.name for b in arm.data.bones}
act = bpy.data.actions.new(newname); act.use_fake_user = True
arm.animation_data_create(); arm.animation_data.action = act
miss = set(); n = 0
for b, prop, idx, keys in data:
    if b not in names: miss.add(b); continue
    pb = arm.pose.bones[names[b]]
    for f, v in keys:
        if prop == 'rotation_quaternion':
            q = list(pb.rotation_quaternion); q[idx] = v; pb.rotation_quaternion = q
        elif prop == 'location':
            l = list(pb.location); l[idx] = v; pb.location = l
        elif prop == 'scale':
            s = list(pb.scale); s[idx] = v; pb.scale = s
        else: continue
        pb.keyframe_insert(data_path=prop, index=idx, frame=f); n += 1
print('COPIED', n, 'keys; missing', sorted(miss), 'range', frames)
for x in bpy.data.actions: x.use_fake_user = True
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_yup=True, export_apply=False)
print('WROTE', out, [x.name for x in bpy.data.actions])
