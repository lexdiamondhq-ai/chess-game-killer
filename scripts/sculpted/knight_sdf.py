import numpy as np
from skimage import measure
def L(v): return np.sqrt((v**2).sum(0))
def smin(a,b,k):
    h=np.clip(0.5+0.5*(b-a)/k,0,1); return b*(1-h)+a*h-k*h*(1-h)
def smax(a,b,k): return -smin(-a,-b,k)
def ell(P,c,r):
    q=[(P[i]-c[i])/r[i] for i in range(3)]; k0=np.sqrt(sum(x*x for x in q)); k1=np.sqrt(sum((x/r[i])**2 for i,x in enumerate(q)))
    return k0*(k0-1)/np.maximum(k1,1e-6)
def rcone(P,a,b,r1,r2):
    a=np.array(a)[:,None,None,None]; b=np.array(b)[:,None,None,None]; ba=b-a; pa=P-a
    h=np.clip((pa*ba).sum(0)/(ba*ba).sum(),0,1); r=r1+(r2-r1)*h
    return L(pa-ba*h)-r
def sph(P,c,r): return L(P-np.array(c)[:,None,None,None])-r
def build(res=0.0035):
    xs=np.arange(-0.42,0.46,res); ys=np.arange(-0.26,0.26,res); zs=np.arange(0.14,1.02,res)
    X,Y,Z=np.meshgrid(xs,ys,zs,indexing='ij'); P=np.stack([X,Y,Z])
    Ps=P.copy(); Ps[1]=P[1]/0.78   # flatten sides
    Pn=P.copy(); Pn[1]=P[1]/0.7
    neck=rcone(Pn,(0.05,0,0.2),(0.0,0,0.64),0.175,0.125)
    head=rcone(Ps,(-0.01,0,0.765),(-0.255,0,0.535),0.112,0.066)
    d=smin(neck,head,0.06)
    jaw=ell(P,(-0.05,0,0.6),(0.12,0.095,0.1)); d=smin(d,jaw,0.04)
    muz=ell(P,(-0.262,0,0.532),(0.072,0.06,0.068)); d=smin(d,muz,0.03)
    # chest swell at front of neck
    chest=ell(P,(-0.06,0,0.34),(0.11,0.12,0.16)); d=smin(d,chest,0.07)
    # flare into the base
    disc=np.maximum(L(P[[0,1]])-0.215,np.abs(P[2]-0.19)-0.03); d=smin(d,disc,0.05)
    # ears
    for s in (-1,1):
        ear=rcone(P,(0.0,s*0.05,0.79),(0.035,s*0.06,0.94),0.04,0.008); d=smin(d,ear,0.02)
        # ear cup (hollow front)
        cup=ell(P,(-0.005,s*0.055,0.86),(0.018,0.022,0.05)); d=smax(d,-cup,0.008)
        # eye socket and eyeball
        eye=ell(P,(-0.085,s*0.08,0.708),(0.03,0.022,0.019)); d=smax(d,-eye,0.01)
        ball=ell(P,(-0.087,s*0.066,0.707),(0.021,0.018,0.014)); d=smin(d,ball,0.003)
        # brow ridge
        brow=ell(P,(-0.07,s*0.075,0.735),(0.05,0.025,0.015)); d=smin(d,brow,0.015)
        # nostril
        nos=ell(P,(-0.312,s*0.036,0.55),(0.014,0.016,0.019)); d=smax(d,-nos,0.007)
        # cheek muscle
        ch=ell(P,(-0.01,s*0.07,0.6),(0.075,0.04,0.07)); d=smin(d,ch,0.03)
    # mouth line
    for s in (-1,1):
        mouth=rcone(P,(-0.32,s*0.045,0.495),(-0.22,s*0.06,0.5),0.008,0.004); d=smax(d,-mouth,0.005)
    # mane: crest along the back of the neck with strand grooves
    t=np.clip((P[2]-0.24)/(0.83-0.24),0,1)
    cx=0.19-0.15*t**1.3; cz=0.24+(0.83-0.24)*t
    crest=np.sqrt(((P[0]-cx)/0.05)**2+(P[1]/0.058)**2)*0.05-0.05
    crest=np.maximum(crest,np.abs(P[2]-0.53)-0.31)
    strands=0.006*np.sin(P[1]*140+6*np.sin(P[2]*13))*(np.abs(P[1])<0.08)*(P[0]>cx-0.035)
    d=smin(d,crest+strands,0.03)
    # forelock
    fl=ell(P,(-0.02,0,0.8),(0.05,0.03,0.03)); d=smin(d,fl,0.02)
    # flat bottom
    d=np.maximum(d,0.17-P[2])
    v,f,n,_=measure.marching_cubes(d,0.0,spacing=(res,res,res))
    v+=np.array([xs[0],ys[0],zs[0]])
    return v,f
if __name__=='__main__':
    import time;t=time.time();v,f=build();print(len(v),len(f),time.time()-t)
    np.save('scripts/sculpted/kv.npy',v);np.save('scripts/sculpted/kf.npy',f)
