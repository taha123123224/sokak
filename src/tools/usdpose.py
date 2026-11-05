from pxr import Usd, UsdSkel, Vt, Gf
import numpy as np
class Poser:
    def __init__(self, f):
        self.st=st=Usd.Stage.Open(f)
        sk=[p for p in st.Traverse() if p.GetTypeName()=="Skeleton"][0]
        an=[p for p in st.Traverse() if p.GetTypeName()=="SkelAnimation"][0]
        self.skel=UsdSkel.Skeleton(sk)
        self.joints=[str(j) for j in self.skel.GetJointsAttr().Get()]
        self.names=[j.split('/')[-1] for j in self.joints]
        self.topo=UsdSkel.Topology(self.skel.GetJointsAttr().Get())
        self.rest=self.skel.GetRestTransformsAttr().Get()
        self.bind=self.skel.GetBindTransformsAttr().Get()
        c=UsdSkel.Cache()
        self.aq=c.GetAnimQuery(UsdSkel.Animation(an))
        aj=[str(j) for j in self.aq.GetJointOrder()]
        self.map=[(self.joints.index(j), i) for i,j in enumerate(aj) if j in self.joints]
        self.times=list(self.aq.GetJointTransformTimeSamples())
        self.anim_name=an.GetName()
    def skel_xforms(self,t):
        loc=list(self.rest)
        al=self.aq.ComputeJointLocalTransforms(Usd.TimeCode(t))
        for si,ai in self.map: loc[si]=al[ai]
        return UsdSkel.ConcatJointTransforms(self.topo, Vt.Matrix4dArray(loc))
if __name__=="__main__":
    import sys
    for n in sys.argv[1:]:
        P=Poser(f"/home/claude/ext3d/usdz/{n}/scene.usdc")
        print("==",n,P.anim_name,len(P.joints),len(P.map),len(P.times))
        prev=None; out=[]
        for t in P.times:
            X=np.array([list(m.ExtractTranslation()) for m in P.skel_xforms(t)])
            if prev is not None: out.append("%d:%.0f"%(t,np.abs(X-prev).sum()))
            prev=X
        print(" ".join(out))
