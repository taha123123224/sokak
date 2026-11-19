import json,struct,numpy as np,sys
src,dst,xf=sys.argv[1],sys.argv[2],sys.argv[3]; nodes=[int(x) for x in sys.argv[4].split(',')]
X=np.load(xf); L=X[:3,:3]; t=X[:3,3]; Rn=L/np.cbrt(abs(np.linalg.det(L)))
raw=open(src,'rb').read(); n=struct.unpack('<I',raw[12:16])[0]; j=json.loads(raw[20:20+n]); boff=20+n+8
B=bytearray(raw)
done=set()
for nd in nodes:
    for p in j['meshes'][j['nodes'][nd]['mesh']]['primitives']:
        for key in ('POSITION','NORMAL','TANGENT'):
            if key not in p['attributes']: continue
            ai=p['attributes'][key]
            if ai in done: continue
            done.add(ai); a=j['accessors'][ai]; bv=j['bufferViews'][a['bufferView']]
            nc=3 if key!='TANGENT' else 4; st=bv.get('byteStride',4*nc); o=boff+bv.get('byteOffset',0)+a.get('byteOffset',0)
            for i in range(a['count']):
                v=np.frombuffer(B[o+i*st:o+i*st+12],'<f4').astype(float)
                if key=='POSITION': w=L@v+t
                else: w=Rn@v; w/=np.linalg.norm(w)+1e-12
                B[o+i*st:o+i*st+12]=w.astype('<f4').tobytes()
            if key=='POSITION':
                P=None
                mn=a['min'];mx=a['max']; c=np.array([[mn[0],mn[1],mn[2]],[mx[0],mx[1],mx[2]]])
                cc=(c@L.T)+t; a['min']=cc.min(0).tolist(); a['max']=cc.max(0).tolist()
js=json.dumps(j).encode(); js+=b' '*((4-len(js)%4)%4)
out=raw[:12]+struct.pack('<I',len(js))+b'JSON'+js+bytes(B[20+n:])
out=out[:8]+struct.pack('<I',len(out))+out[12:]
open(dst,'wb').write(out); print('patched',len(done))
