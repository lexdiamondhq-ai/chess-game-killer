# A dark studio as an equirectangular image for SceneKit's lighting environment: one big soft box
# overhead, four tall soft boxes on the diagonals and thin low strips, all in a near-black room, so
# polished surfaces show deep color with crisp highlights instead of a grey sheen.
# Symmetric under quarter turns and mirrors, so it reads the same whichever way the engine maps it.
import sys
import numpy as np
from PIL import Image
W,H=2048,1024
u=(np.arange(W)+0.5)/W; v=(np.arange(H)+0.5)/H
az=(u*2*np.pi)[None,:]
el=(np.pi/2 - v*np.pi)[:,None]
y=np.sin(el)*np.ones_like(az)
img=np.zeros((H,W),np.float32)
dome=np.clip(y,0,1)
img+=0.004+0.03*dome**2
def box(c_az,c_el,w,h,b,soft=0.25):
    da=np.angle(np.exp(1j*(az-np.radians(c_az))))
    de=el-np.radians(c_el)
    ax=np.abs(da)*np.cos(el)/np.radians(w/2); ay=np.abs(de)/np.radians(h/2)
    f=np.clip((1-np.maximum(ax,ay))/soft,0,1)
    return b*f*f*(3-2*f)
img+=np.where(y>0, 1.0*np.clip((y-0.86)/0.06,0,1)**2, 0)
for a in (45,135,225,315):
    img+=box(a,30,26,30,0.85,0.35)
    img+=box(a+45,9,5,14,0.6,0.45)
img=np.clip(img,0,1)
rgb=np.stack([img*0.99,img*0.99,img],-1)
Image.fromarray((np.clip(rgb,0,1)**(1/2.2)*255+0.5).astype(np.uint8)).save(sys.argv[1] if len(sys.argv) > 1 else "build/sculpted/out/sculpted-env-studio.png",optimize=True)
