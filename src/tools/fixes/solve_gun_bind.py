exec(open('/tmp/gfix.py').read().split("names={")[0])
names={nd.get('name'):i for i,nd in enumerate(N)}
sk=j['skins'][0]; IBM=acc(sk['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
bindpos={k:np.linalg.inv(IBM[k])[:3,3] for k in range(len(sk['joints']))}
src=[];dst=[];lab=[]
for node in (1082,1083,1084,1085):
    p=j['meshes'][N[node]['mesh']]['primitives'][0]['attributes']
    P=acc(p['POSITION']); W=acc(p['WEIGHTS_0']); J=acc(p['JOINTS_0']).astype(int)
    dom=J[np.arange(len(J)),W.argmax(1)]
    for k in np.unique(dom):
        m=dom==k
        if m.sum()<30: continue
        src.append(P[m].mean(0)); dst.append(bindpos[k]); lab.append((node,N[sk['joints'][k]]['name'],int(m.sum())))
src=np.array(src); dst=np.array(dst)
for l,s,d in zip(lab,src,dst): print(l, s.round(1), d.round(3))
def umeyama(A,Bm):
    ma,mb=A.mean(0),Bm.mean(0); A0,B0=A-ma,Bm-mb; U,S,Vt=np.linalg.svd(B0.T@A0/len(A)); D=np.eye(3)
    if np.linalg.det(U)*np.linalg.det(Vt)<0: D[2,2]=-1
    R=U@D@Vt; s=np.trace(np.diag(S)@D)/((A0**2).sum()/len(A)); t=mb-s*R@ma; return s,R,t
s,R,t=umeyama(src,dst); res=np.linalg.norm((s*(R@src.T)).T+t-dst,axis=1)
print('scale',s,'res',res.round(4)); print('R',R.round(3)); print('t',t.round(4))
np.save('/tmp/deagle_X.npy',np.r_[np.c_[s*R,t],[[0,0,0,1]]])
# gloves bind extent for comparison
p=j['meshes'][N[13]['mesh']]['primitives'][0]['attributes']; P=acc(p['POSITION']); print('glove bind', P.min(0).round(3),P.max(0).round(3))
g=(s*(R@src.T)).T+t; print('gun parts mapped', g.min(0).round(3), g.max(0).round(3))
