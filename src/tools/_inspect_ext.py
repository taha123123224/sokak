import bpy, sys, os, mathutils
from mathutils import Vector
E='/home/claude/ext3d'
files={'ak':E+'/3dexport_dx02_ak_47_staobj_lowpol_exp_v2_1674068658/DX02_AK_47_StaObj_LowPol_Exp_v2/Dx00_1_ak47_export_v1.0.3.fbx',
 'sniper':E+'/3dexport_sniper_1722149628/3dexport_sniper_1722149628/finalized_lowpoly.fbx',
 'fn502':E+'/12f9a100-3dexport_fn502_1687540411/fn502/fn502.fbx',
 'r870':E+'/1c24b91b-3dexport_remington870_1661021571/remington870.blend'}
for k,f in [(sys.argv[-1], files[sys.argv[-1]])]:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    if f.endswith('.blend'):
        bpy.ops.wm.open_mainfile(filepath=f, load_ui=False, use_scripts=False)
    else:
        bpy.ops.import_scene.fbx(filepath=f)
    ms=[o for o in bpy.data.objects if o.type=='MESH']
    pts=[o.matrix_world@Vector(c) for o in ms for c in o.bound_box]
    mn=Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))); mx=Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
    tris=sum(len(o.data.polygons) for o in ms)
    print('==',k,'objs',len(ms),'polys',tris,'size',tuple(round(v,3) for v in (mx-mn)),'min',tuple(round(v,3) for v in mn))
    print('   objects', [o.name for o in ms][:25])
    print('   mats', [m.name for m in bpy.data.materials][:20])
    print('   images', [i.name for i in bpy.data.images][:10])
