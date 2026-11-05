"""Animated first-person rigs (CC-BY Sketchfab USDZ packs) -> assets/models/fp_<id>.glb + .json
The whole rig (arms + its own gun) is fitted onto the game's w_<id> weapon space (muzzle +Y, up +Z,
real length, same centre), so ADS / muzzle / eject markers of the hidden w_ model still line up.
Gun meshes are renamed gun_* so skins and the upgrade glow can find them in game.
python3 -c "import sys;sys.argv=['b','--','awm'];exec(open('tools/rig_fp.py').read())"
"""
import bpy, sys, json, os
import numpy as np
from mathutils import Matrix, Vector
sys.path.insert(0, "/home/claude/sokak/tools")
exec(open("/home/claude/sokak/tools/usd_fp.py").read().split('if __name__ == "__main__":')[0])
U = "/home/claude/ext3d/usdz/"
M = "/home/claude/sokak/assets/models/"
SPECS = {
    'awm': dict(usd=U + 'sniper_animated/scene.usdc', gun=['_sniper_0', 'lens_lens', 'reticle_', 'scoperender'],
                rear='trigger', top='scope', ref=600, credit="Sniper animated — DJMaesen (CC-BY 4.0)",
                sections={'fire': (0, 48), 'bolt': (48, 244), 'reload': (244, 464), 'inspect': (464, 572), 'idle': (572, 664), 'draw': (664, 780)}),
    'uzi': dict(usd=U + 'UZI__First_Person_Animations_2026_Remake/scene.usdc', gun=['UZI_UZI'], drop=['Background', 'Aim'],
                rear=None, top=None, ref=260, credit="UZI First Person Animations (2026 Remake) — Matzh (CC-BY 4.0)",
                sections={'draw': (0, 232), 'idle': (236, 268)}),
    'akm': dict(usd=U + 'AKM_reload_animation/scene.usdc', gun=['AK_AK'], step=3,
                rear=None, top=None, ref=0, credit="AKM reload animation — Vlasov Daniil (CC-BY 4.0)",
                sections={'idle': (0, 12), 'reload': (0, 522)}),
    'm4a1': dict(glb='/home/claude/ext3d/new/m4pack/m4pack.glb', gun=['_M4_D_0', 'Bullet5'], fit=['Main_M4', 'Mag1_M4'], drop=['Icosphere'],
                 rear=None, top=None, ref=239, sight_dy=0.011, credit="M4 - FPS Weapon Animations Pack v.1 — BarcodeGames (CC-BY 4.0)",
                 sections={'draw': {'anim': 'Draw'}, 'fire': {'anim': 'Fire'}, 'reload': {'anim': 'Reload'},
                           'reload_empty': {'anim': 'Reload_Empty'}, 'idle': {'anim': 'Draw', 's': -0.05}}),
}

def evpts(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    P = []
    for o in objs:
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        mw = e.matrix_world
        P += [tuple(mw @ v.co) for v in me.vertices]
        e.to_mesh_clear()
    return np.array(P)

def run(wid):
    sp = SPECS[wid]
    if sp.get('glb'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=sp['glb'])
        for o in list(bpy.data.objects):
            if any(d in o.name for d in sp.get('drop', ())):
                bpy.data.objects.remove(o)
        frames = [0, 1]
        # play the reference action on every animated object
        act = bpy.data.actions.get(sp['sections']['idle']['anim'])
        for o in bpy.data.objects:
            ad = o.animation_data
            if ad and act:
                ad.action = act
                try:
                    sl = ad.action_suitable_slots
                    if sl:
                        ad.action_slot = sl[0]
                except Exception as ex:
                    print("slot", ex)
    else:
        arm, frames = bake(sp['usd'], None, sp.get('step', 4), sp.get('drop', ()))
    sc = bpy.context.scene
    sc.frame_set(sp['ref'])
    gun = [o for o in bpy.data.objects if o.type == 'MESH' and any(g in o.name for g in sp['gun'])]
    P = evpts([o for o in gun if any(f in o.name for f in sp['fit'])] if sp.get('fit') else gun)
    c = P.mean(0)
    w, V = np.linalg.eigh(np.cov((P - c).T))
    long = V[:, 2]
    # the arms come from the camera side: the muzzle points away from them (or from a named rear part)
    if sp.get('rear') and sp['rear'] in bpy.data.objects:
        rear = bpy.data.objects[sp['rear']].matrix_world.translation
    else:
        rear = evpts([o for o in bpy.data.objects if o.type == 'MESH' and o not in gun]).mean(0)
    proj = (P - c) @ long
    # muzzle = the far end on the side away from the grip/trigger
    if np.dot(np.array(rear) - c, long) > 0:
        long = -long
    topc = evpts([o for o in bpy.data.objects if o.type == 'MESH' and sp['top'] in o.name]).mean(0) if sp.get('top') else c + np.array([0.0, 0.0, 1.0])
    up = topc - c
    up = up - long * np.dot(up, long); up /= np.linalg.norm(up)
    side = np.cross(long, up)
    R = np.array([side, long, up])        # world -> aligned
    A = (P - c) @ R.T
    lo, hi = A.min(0), A.max(0)
    # game weapon box
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=M + 'w_%s.glb' % wid)
    wobj = [o for o in bpy.data.objects if o not in keep]
    WP = evpts([o for o in wobj if o.type == 'MESH'])
    wlo, whi = WP.min(0), WP.max(0)
    for o in wobj:
        bpy.data.objects.remove(o)
    s = (whi[1] - wlo[1]) / (hi[1] - lo[1])
    acen = (lo + hi) / 2 * s
    wcen = (wlo + whi) / 2
    Rm = Matrix(R.tolist()).to_4x4()
    T = Matrix.Translation(Vector(wcen - acen)) @ Matrix.Scale(s, 4) @ Rm @ Matrix.Translation(Vector(-c))
    print("scale", s, "len", hi[1] - lo[1], "wlen", whi[1] - wlo[1])
    root = bpy.data.objects.new('rig', None)
    sc.collection.objects.link(root)
    for o in list(bpy.data.objects):
        if o.parent is None and o is not root:
            o.parent = root
            o.matrix_parent_inverse = Matrix.Identity(4)
    root.matrix_world = T
    gm = set()
    for o in gun:
        o.name = 'gun_' + o.name
        for m in o.data.materials:
            if m: gm.add(m)
    for m in list(bpy.data.materials):
        m.name = ('gun_paint_ext_rig_%s_' % wid if m in gm else 'rb_rig_%s_' % wid) + m.name
    for o in bpy.data.objects:
        if o.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(o)
    out = M + 'fp_%s.glb' % wid
    if sp.get('glb'):
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_anim_slide_to_zero=True,
                                  export_force_sampling=True, export_yup=True, export_apply=False)
        meta = {"rig": 1, "credit": sp['credit'], "sections": sp['sections'], "sight_dy": sp.get('sight_dy', 0.0)}
    else:
        sc.frame_start, sc.frame_end = min(frames), max(frames)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='SCENE', export_anim_scene_split_object=False,
                                  export_force_sampling=False, export_yup=True, export_apply=False)
        fps = 120.0
        meta = {"rig": 1, "credit": sp['credit'], "sections": {k: [a / fps, b / fps] for k, (a, b) in sp['sections'].items()}}
    json.dump(meta, open(M + 'fp_%s.json' % wid, 'w'), indent=1)
    print("WROTE", out)

run(sys.argv[sys.argv.index('--') + 1])
