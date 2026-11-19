"""Animated first-person rigs (CC-BY Sketchfab USDZ packs) -> assets/models/fp_<id>.glb + .json
The whole rig (arms + its own gun) is fitted onto the game's w_<id> weapon space (muzzle +Y, up +Z,
real length, same centre), so ADS / muzzle / eject markers of the hidden w_ model still line up.
Gun meshes are renamed gun_* so skins and the upgrade glow can find them in game.
python3 -c "import sys;sys.argv=['b','--','awm'];exec(open('tools/rig_fp.py').read())"
"""
import bpy, sys, json, os, math
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
    'uzi_usd': dict(usd=U + 'UZI__First_Person_Animations_2026_Remake/scene.usdc', gun=['UZI_UZI'], drop=['Background', 'Aim'],
                rear=None, top=None, ref=260, credit="UZI First Person Animations (2026 Remake) — Matzh (CC-BY 4.0)",
                sections={'draw': (0, 232), 'idle': (236, 268)}),
    'akm': dict(usd=U + 'AKM_reload_animation/scene.usdc', gun=['AK_AK'], step=3,
                rear=None, top=None, ref=0, credit="AKM reload animation — Vlasov Daniil (CC-BY 4.0)",
                sections={'idle': (0, 12), 'reload': (0, 522)}),
    'm4a1': dict(glb='/home/claude/ext3d/new/m4pack/m4pack.glb', gun=['_M4_D_0', 'Bullet5'], fit=['Main_M4', 'Mag1_M4'], drop=['Icosphere'],
                 rear=None, top=None, ref=239, sight_dy=0.011, credit="M4 - FPS Weapon Animations Pack v.1 — BarcodeGames (CC-BY 4.0)",
                 sections={'draw': {'anim': 'Draw'}, 'fire': {'anim': 'Fire'}, 'reload': {'anim': 'Reload'},
                           'reload_empty': {'anim': 'Reload_Empty'}, 'idle': {'anim': 'Draw', 's': -0.05}}),
    # v4.16: DuqueCD7 "FPS Character Animation Pack Ak-47" (CC-BY 4.0): equip / idle / aim / fire / reload / walk / run
    'ak47_duque': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_ak_duque.glb', gun=['Object_14', 'Object_15', 'Object_17', 'Object_18'],
                 fit=['Object_15'], drop=['Icosphere'], rear=None, top=None, ref=0,
                 attach=('SKEL_AK_47_Rifle', 'Object_22', 'DEF-Weapon_013'), grip='Grip_01',
                 # v4.17: grip frame relative to DEF-Weapon, solved by fitting both palms to the gun over idle/fire/walk frames
                 rel=((-0.83652, 0.54709, -0.03046, -8.83192), (0.22414, 0.29093, -0.93012, -38.04624),
                      (-0.5, -0.78489, -0.366, 18.24123), (0, 0, 0, 1)),
                 credit="FPS Character Animation Pack Ak-47 — DuqueCD7 (CC-BY 4.0)",
                 sections={'draw': {'anim': 'RIG_UE5_Comando_AK_Equip'}, 'idle': {'anim': 'RIG_UE5_Comando_AK_Idle'},
                           'fire': {'anim': 'RIG_UE5_Comando_AK_Fire'}, 'reload': {'anim': 'RIG_UE5_Comando_AK_Reload'},
                           'ads_idle': {'anim': 'RIG_UE5_Comando_AK_Idle_Aim'}, 'ads_fire': {'anim': 'RIG_UE5_Comando_AK_Aim_Fire'},
                           'walk': {'anim': 'RIG_UE5_Comando_AK_Walk'}, 'sprint': {'anim': 'RIG_UE5_Comando_AK__Run'},
                           'inspect': {'anim': 'RIG_UE5_Comando_AK_Hold'}}),
    # v4.17: Matzh "Desert Eagle | First Person Animations" (CC-BY 4.0), 4K: equip / idle / walk / run / fire / reload / reload empty / inspect
    'deagle': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_deagle_matzh4k_fix.glb', guess=False,
                   gun=['Object_1082', 'Object_1083', 'Object_1084', 'Object_1085'], fit=['Object_1082'],
                   drop=['Icosphere', 'Skybox', 'Aim'], rear=None, top=None, ref=20, pitch=20.0, shift=[-0.02, 0.0, 0.02],
                   # _fix.glb: the pack's gun vertices were not in the skin's bind space (~1e4 x, flipped); tools/patch_glb_gun.py put
                   # them back with the similarity solved from the gun's own part bones (trigger / hammer / slide / mag pivots)
                   credit="Desert Eagle | First Person Animations — Matzh (CC-BY 4.0)",
                   sections={'draw': {'anim': 'rig|Equip'}, 'idle': {'anim': 'rig|Idle'}, 'fire': {'anim': 'rig|Fire'},
                             'reload': {'anim': 'rig|Reload'}, 'reload_empty': {'anim': 'rig|Reload_Empty'},
                             'inspect': {'anim': 'rig|Inspect'}, 'walk': {'anim': 'rig|Walk'}, 'sprint': {'anim': 'rig|Run'},
                             'holster': {'anim': 'rig|Unequip'}}),
    # v4.17: Matzh "9mm Pistol | First Person Animations" (CC-BY 4.0, pistol model by Urpo), 4K
    'glock': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_9mm_matzh4k.glb', guess=False,
                  gun=['Object_938', 'Object_939', 'Object_940'], fit=['Object_940'],
                  drop=['Icosphere', 'Object_942', 'Object_944', 'Object_946'], rear=None, top=None, ref=20,
                  shift=[-0.045, 0.0, 0.035],   # v4.18: one-handed idle sat in the corner: bring it toward the centre
                  credit="9mm Pistol | First Person Animations — Matzh, pistol model by Urpo (CC-BY 4.0)",
                  sections={'draw': {'anim': 'Equip'}, 'idle': {'anim': 'Idle'}, 'fire': {'anim': 'Fire'},
                            'reload': {'anim': 'Reload'}, 'reload_empty': {'anim': 'Reload_Empty'},
                            'inspect': {'anim': 'Inspect'}, 'walk': {'anim': 'Walk'}, 'sprint': {'anim': 'Run'},
                            'holster': {'anim': 'Unequip'}}),
    # v4.17: Matzh "UZI | First Person Animations (2026 Remake)" (CC-BY 4.0), built from the pack's own .blend + 4K textures
    # by tools/packs/matzh_src_to_glb.py (13 clips: equip / idle / walk / run / aim / fire / firemode / reload x2 / inspect)
    'uzi': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_uzi_matzh_src.glb', guess=False,
                gun=['UZI'], drop=['Icosphere'], rear=None, top=None, ref=20, scale=1.0,
                cam={'hip': [0.17, -0.2, -0.49], 'fov_k': 1.55, 'off': (0.03, 0.025, -0.09)}, meta={'near_cut': 0.05},
                credit="UZI | First Person Animations (2026 Remake) — Matzh (CC-BY 4.0)",
                sections={'draw': {'anim': 'Equip'}, 'idle': {'anim': 'Idle'}, 'fire': {'anim': 'Fire'},
                          'reload': {'anim': 'Reload'}, 'reload_empty': {'anim': 'Reload_Empty'},
                          'inspect': {'anim': 'Inspect'}, 'walk': {'anim': 'Walk'}, 'sprint': {'anim': 'Run'},
                          'ads_in': {'anim': 'Aim_In'}, 'ads_out': {'anim': 'Aim_Out'}, 'firemode': {'anim': 'Firemode'},
                          'holster': {'anim': 'Unequip'}}),
    # v4.17: teenjust500 "Animated Shotgun" (CC-BY 4.0) Remington 870 built from its FBX source + textures by
    # tools/packs/fbx_pack_to_glb.py; kept in the pack's own camera framing
    'r870': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_r870_teenjust_src.glb', guess=False,
                 gun=['Remington870', 'Cylinder'], fit=['Remington870'], drop=[], rear=None, top=None, ref=2,
                 cam={'hip': [0.14, -0.165, -0.36]},
                 credit="Animated Shotgun — teenjust500 (CC-BY 4.0)",
                 sections={'draw': {'anim': 'Take'}, 'idle': {'anim': 'Take', 's': -0.04}, 'fire': {'anim': 'Shoot'},
                           'shell': {'anim': 'Reload'}, 'reload_start': {'anim': 'ReloadStart'}, 'reload_end': {'anim': 'ReloadEnd'},
                           'inspect': {'anim': 'Watch'}, 'holster': {'anim': 'Hide'}}),
    # v4.17: ccransh "FPS AK-74m animations" (CC-BY 4.0; AK-74M by creationwasteland, FP arms by DJMaesen), 4K, with the
    # inspect of ccransh's rifle pack (same rig) copied in by tools/packs/ccransh_add_inspect.py; pack camera = Head_Cam bone
    'ak47': dict(glb='/home/claude/sokak/assets_src/sketchfab/sk_fp_ak74m_ccransh_insp.glb', guess=False,
                 gun=['Object_97', 'Object_99'], fit=['Object_97'], drop=['Icosphere'], rear=None, top=None, ref=5,
                 credit="FPS AK-74m animations — ccransh; AK-74M by creationwasteland, FP arms by DJMaesen (CC-BY 4.0)",
                 sections={'draw': {'anim': 'Rig|AK_Draw'}, 'idle': {'anim': 'Rig|AK_Idle'}, 'fire': {'anim': 'Rig|AK_Shot'},
                           'reload': {'anim': 'Rig|AK_Reload'}, 'reload_empty': {'anim': 'Rig|AK_Reload_full'},
                           'inspect': {'anim': 'Rig|AK_Inspect'}, 'walk': {'anim': 'Rig|AK_Walk'}, 'sprint': {'anim': 'Rig|AK_Run'}}),
    # v3.4: one shared knife rig for every melee weapon (the game's own knife model is attached to its 'knife' node)
    'melee': dict(usd='/home/claude/usdz/7516b757-knife_Animated/scene.usdc', gun=['knife_knife'], wref='knife', step=2,
                  native=True, rear=None, top=None, ref=80, credit="knife Animated — DJMaesen (CC-BY 4.0)",
                  sections={'idle': (0, 160), 'slash': (160, 240), 'slash2': (240, 320), 'stab': (320, 408), 'stab2': (408, 496), 'draw': (532, 580)}),
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
        bpy.ops.import_scene.gltf(filepath=sp['glb'], guess_original_bind_pose=sp.get('guess', True))
        for o in list(bpy.data.objects):
            if any(d in o.name for d in sp.get('drop', ())):
                bpy.data.objects.remove(o)
        frames = [0, 1]
        if sp.get('vfix'):
            Xg = np.array(json.load(open(sp['vfix'][0])))
            Cg = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1.0]])   # glTF Y-up -> Blender Z-up
            XB = Matrix((Cg @ Xg @ np.linalg.inv(Cg)).tolist())
            for n in sp['vfix'][1]:
                bpy.data.objects[n].data.transform(XB)
        # v4.16: packs whose gun has its own armature (UE5 style): hang it on the arms' weapon bone so it follows the hands
        att = sp.get('attach')
        if att:
            gob, arm_name, bone = att
            arm = bpy.data.objects[arm_name]
            act0 = bpy.data.actions.get(sp['sections']['idle']['anim'])
            if arm.animation_data is None:
                arm.animation_data_create()
            arm.animation_data.action = act0
            try:
                sl = arm.animation_data.action_suitable_slots
                if sl: arm.animation_data.action_slot = sl[0]
            except Exception:
                pass
            bpy.context.scene.frame_set(sp.get('ref', 0))
            bpy.context.view_layer.update()
            g = bpy.data.objects[gob]
            # the gun armature's grip bone must sit exactly on the arms' weapon bone (UE5 socket): snap it there
            wa = [o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not arm and (o.parent is g or o is g)]
            wa = wa[0] if wa else None
            if wa is not None and wa.animation_data:
                own = [a for a in bpy.data.actions if a.name.endswith('-' + wa.name)]
                wa.animation_data.action = own[0] if own else None
                bpy.context.view_layer.update()
                M_bone = arm.matrix_world @ arm.pose.bones[bone].matrix
            M_bone = arm.matrix_world @ arm.pose.bones[bone].matrix
            if wa is not None and sp.get('grip') in wa.pose.bones:
                M_grip = wa.matrix_world @ wa.pose.bones[sp['grip']].matrix
                R = Matrix(sp['rel']) if sp.get('rel') else Matrix.Identity(4)
                target = M_bone @ R @ (g.matrix_world.inverted() @ M_grip).inverted()
            else:
                target = g.matrix_world.copy()
            g.parent = arm; g.parent_type = 'BONE'; g.parent_bone = bone
            bpy.context.view_layer.update()
            g.matrix_world = target
        # play the reference action on every animated object
        act = bpy.data.actions.get(sp['sections']['idle']['anim'])
        keep_own = set()
        if sp.get('attach'):
            # the gun armature keeps its own (mag / bolt) action; the arms' action would also drive its _rootJoint
            keep_own = {o.name for o in bpy.data.objects if o.type == 'ARMATURE' and o.name != sp['attach'][1]}
        for o in bpy.data.objects:
            ad = o.animation_data
            if ad and act and o.name not in keep_own:
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
    bpy.ops.import_scene.gltf(filepath=M + 'w_%s.glb' % sp.get('wref', wid))
    wobj = [o for o in bpy.data.objects if o not in keep]
    WP = evpts([o for o in wobj if o.type == 'MESH'])
    wlo, whi = WP.min(0), WP.max(0)
    for o in wobj:
        bpy.data.objects.remove(o)
    s = (whi[1] - wlo[1]) / (hi[1] - lo[1])
    if sp.get('scale'):
        s = sp['scale']           # real-size pack whose gun is bigger than the game's model: keep the arms real-size
    acen = (lo + hi) / 2 * s
    wcen = (wlo + whi) / 2
    if sp.get('align') == 'muzzle':
        # line the muzzles up (flash / tracer markers live on the game model) instead of the box centres
        acen[1] = hi[1] * s; wcen = wcen.copy(); wcen[1] = whi[1]
    if sp.get('shift'):
        wcen = wcen + np.array(sp['shift'])     # game-weapon space nudge (x right, y forward, z up)
    Rm = Matrix(R.tolist()).to_4x4()
    T = Matrix.Translation(Vector(wcen - acen)) @ Matrix.Scale(s, 4) @ Rm @ Matrix.Translation(Vector(-c))
    sock = None
    if sp.get('native'):
        # keep the pack's own first-person camera framing (camera at the origin), only real-size it;
        # the game puts its knife model in the 'knife' socket: grip = socket origin, blade = y, flat = z
        T = Matrix.Scale(s, 4)
        ke = bpy.data.objects['knife']
        mi = ke.matrix_world.inverted()
        o = mi @ ke.matrix_world.translation
        L = Vector(long.tolist()); V1 = Vector(np.linalg.eigh(np.cov((P - c).T))[1][:, 1].tolist())
        # blade = the thin end, far from the grip
        proj = (P - c) @ long
        tip = -L if np.mean(proj < 0) and abs(proj.min()) > abs(proj.max()) else L
        yl = (mi.to_3x3() @ tip).normalized(); zl = (mi.to_3x3() @ V1).normalized()
        cv = lambda v: [v.x, v.z, -v.y]
        sock = {"o": cv(o), "y": cv(yl), "z": cv(zl)}
    if sp.get('pitch'):
        # v4.18: tilt the whole rig about the gun centre (x right, y forward, z up): + = muzzle up
        T = Matrix.Translation(Vector(wcen)) @ Matrix.Rotation(math.radians(sp['pitch']), 4, 'X') @ Matrix.Translation(-Vector(wcen)) @ T
    wfix = None
    vm_fov = 56.0
    if sp.get('cam'):
        # v4.17: the pack's own first-person framing. Put the rig where its camera matches the game's viewmodel camera
        # (vm_off sits at the weapon's hip offset, the camera at -hip in its space), keep the arms real-size, and tell the
        # game where the rig gun ended up so the hidden static weapon (muzzle / sight / shell markers) moves there too
        sc.frame_set(sp['ref']); bpy.context.view_layer.update()
        if sp['cam'].get('bone'):
            # camera = a head/camera bone of the rig, looking along a given world axis
            ab = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
            hb = [b for b in ab.pose.bones if b.name.startswith(sp['cam']['bone']) and 'end' not in b.name][0]
            hp0 = ab.matrix_world @ hb.head
            fw = Vector(sp['cam'].get('fwd', (0, -1, 0))); up0 = Vector(sp['cam'].get('up', (0, 0, 1)))
            zc = -fw.normalized(); xc = up0.cross(zc).normalized(); yc = zc.cross(xc)
            Cw = Matrix(((xc.x, yc.x, zc.x, hp0.x), (xc.y, yc.y, zc.y, hp0.y), (xc.z, yc.z, zc.z, hp0.z), (0, 0, 0, 1)))
            class _C: pass
            cam = _C(); cam.data = _C(); cam.data.sensor_fit = 'VERTICAL'; cam.data.angle_y = math.radians(sp['cam'].get('vfov', 56.0))
        else:
            cam = [o for o in bpy.data.objects if o.type == 'CAMERA'][0]
            Cw = cam.matrix_world.copy()
        scl = float(sp['cam'].get('scale', s))
        cvv = lambda v: Vector((v.x, v.z, -v.y))
        p_g = cvv(Cw.translation * scl)
        f_g = cvv(Cw.to_3x3() @ Vector((0, 0, -1))).normalized()
        u_g = cvv(Cw.to_3x3() @ Vector((0, 1, 0))).normalized()
        z_g = -f_g; x_g = u_g.cross(z_g).normalized(); y_g = z_g.cross(x_g)
        Mc = Matrix(((x_g.x, y_g.x, z_g.x, p_g.x), (x_g.y, y_g.y, z_g.y, p_g.y), (x_g.z, y_g.z, z_g.z, p_g.z), (0, 0, 0, 1)))
        hp = sp['cam']['hip']
        pitch = Matrix.Rotation(math.radians(sp['cam'].get('pitch', 0.0)), 4, 'X')
        Mg = Matrix.Translation(Vector((-hp[0], -hp[1], -hp[2]))) @ pitch @ Matrix.Translation(Vector(sp['cam'].get('off', (0, 0, 0))))
        G = Mg @ Mc.inverted() @ Matrix.Scale(scl, 4)
        Cv = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
        Tcam = Cv.inverted() @ G @ Cv
        W = Cv @ Tcam @ T.inverted() @ Cv.inverted()
        wfix = [W[0][0], W[1][0], W[2][0], W[0][1], W[1][1], W[2][1], W[0][2], W[1][2], W[2][2], W[0][3], W[1][3], W[2][3]]
        T = Tcam
        cd = cam.data
        vfov = 2 * math.atan(math.tan(cd.angle_x / 2) * 9 / 16) if cd.sensor_fit != 'VERTICAL' else cd.angle_y
        vm_fov = round(math.degrees(vfov) * float(sp['cam'].get('fov_k', 1.0)), 2)
        print("CAM", p_g, f_g, "wfix scale", W.to_scale(), "vm_fov", vm_fov)
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
    # v4.17 texture budget: the gun keeps its 4K colour + normal maps, its other maps and the arms go to 2K, the
    # rest (watch, body ...) to 1K. A whole 4K pack (Matzh Deagle: 22 x 4K) was ~460 MB of VRAM for one viewmodel.
    seen = set()
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        isgun = m.name.startswith('gun_paint')
        arms = any(k in m.name.lower() for k in ('glove', 'arm', 'hand', 'sleeve', 'cloth', 'uniform', 'skin'))
        for n in m.node_tree.nodes:
            if n.type != 'TEX_IMAGE' or n.image is None or n.image.name in seen:
                continue
            im = n.image; seen.add(im.name)
            w, h = im.size[:]
            if w == 0:
                continue
            col = any(l.to_socket.name in ('Base Color', 'Color') and l.to_node.type in ('BSDF_PRINCIPLED', 'NORMAL_MAP') for l in n.outputs[0].links)
            lim = (4096 if col else 2048) if isgun else (2048 if arms else 1024)
            if max(w, h) > lim:
                f = lim / max(w, h)
                im.scale(max(1, int(w * f)), max(1, int(h * f)))
    out = M + 'fp_%s.glb' % wid
    if sp.get('glb'):
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_anim_slide_to_zero=True,
                                  export_force_sampling=True, export_yup=True, export_apply=False)
        meta = {"rig": 1, "credit": sp['credit'], "sections": sp['sections'], "sight_dy": sp.get('sight_dy', 0.0)}
        meta.update(sp.get('meta', {}))
        if wfix:
            meta["wfix"] = wfix
            meta["vm_fov"] = vm_fov
    else:
        sc.frame_start, sc.frame_end = min(frames), max(frames)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='SCENE', export_anim_scene_split_object=False,
                                  export_force_sampling=False, export_yup=True, export_apply=False)
        fps = 120.0
        meta = {"rig": 1, "credit": sp['credit'], "sections": {k: [a / fps, b / fps] for k, (a, b) in sp['sections'].items()}}
        if sock:
            meta["socket"] = sock; meta["native"] = 1; meta["melee_ref"] = sp['ref'] / fps
            # where the pack's viewer camera sits (native units, found by test renders), real-sized
            meta["cam"] = [0.0, 0.62 * s, -1.95 * s]; meta["cam_pitch"] = 16.0
            meta["sections"]["inspect"] = meta["sections"]["idle"]
    json.dump(meta, open(M + 'fp_%s.json' % wid, 'w'), indent=1)
    print("WROTE", out)

run(sys.argv[sys.argv.index('--') + 1])
