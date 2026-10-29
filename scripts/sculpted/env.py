# A studio "light tent" as an equirectangular image for SceneKit's lighting environment.
# Symmetric under quarter turns and mirrors, so it reads the same whichever way the engine maps it.
import os, sys
import numpy as np
from PIL import Image
W,H=2048,1024
u=(np.arange(W)+0.5)/W; v=(np.arange(H)+0.5)/H
az=(u*2*np.pi)[None,:]           # azimuth
el=(np.pi/2 - v*np.pi)[:,None]   # elevation, +90 top
x=np.cos(el)*np.cos(az); z=np.cos(el)*np.sin(az); y=np.sin(el)*np.ones_like(az)
img=np.zeros((H,W),np.float32)
# dark floor, soft dome rising to a bright top
dome=np.clip((y+0.05)/1.05,0,1)
img+=0.015+0.30*dome**1.6
def box(c_az,c_el,w,h,b,soft=0.25):
    # soft-edged rectangle on the sphere, in angles (degrees)
    da=np.angle(np.exp(1j*(az-np.radians(c_az))))
    de=el-np.radians(c_el)
    ax=np.abs(da)*np.cos(el)/np.radians(w/2); ay=np.abs(de)/np.radians(h/2)
    f=np.clip((1-np.maximum(ax,ay))/soft,0,1)
    return b*f*f*(3-2*f)
# overhead soft box (big), four corner boxes, a thin bright strip ring low down for rim light
img+=np.where(y>0, 1.0*np.clip((y-0.82)/0.08,0,1), 0)
for a in (45,135,225,315):
    img+=box(a,32,34,26,1.0,0.3)
    img+=box(a+45,12,10,24,0.55,0.4)
img=np.clip(img,0,1)
# --above: the same tent for the flat view, seen from straight above (env_above.py).
args=[a for a in sys.argv[1:] if a!='--above']
if '--above' in sys.argv:
    sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
    from env_above import above
    img=above(img,el*np.ones_like(az))
rgb=np.stack([img*0.985,img*0.99,img],-1)   # very slightly cool
out=args[0] if args else 'build/sculpted/out/sculpted-env%s.png'%('-above' if '--above' in sys.argv else '')
Image.fromarray((np.clip(rgb,0,1)**(1/2.2)*255+0.5).astype(np.uint8)).save(out,optimize=True)
print('ok')
