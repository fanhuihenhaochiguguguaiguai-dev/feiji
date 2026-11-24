"""Bake original smoke and fire flipbooks and the secondary spark sprite."""
from pathlib import Path
import numpy as np
from PIL import Image

output=Path(__file__).resolve().parents[1]/'public/surface'
n=128
steps=8
grid=(np.arange(n,dtype=np.float32)+.5)/n*2-1
x,y=np.meshgrid(grid,grid)
a=np.arctan2(y,x)
r=np.hypot(x,y)
def image(array):return Image.fromarray(np.uint8(np.rint(np.clip(array,0,255))))

for material in ('smoke','fire'):
    frames=[]
    for t in np.linspace(0,1,steps):
        folds=.11*np.sin(7*a+8*r-t*3)+.062*np.cos(13*y+19*x+t*4)+.023*np.sin(13*a-r*11)
        mass=np.clip(1-(r*1.12+folds)**2,0,1)
        edge=np.clip(1-r**8,0,1)
        density=mass**(1.24+t*.73)*edge
        shade=np.clip(.58-y*.33+(folds+.06*np.sin(26*x+28*y-t*4))*.91,0,1)
        if material=='smoke':
            channels=(89+shade*119,96+shade*117,103+shade*115,238*density)
        else:
            core=np.exp(-(3.5+5.3*t)*(r+folds*.6)**2)
            heat=core*(1-.74*t)
            channels=(168+87*core,42+207*heat,12+236*heat**1.76,248*density)
        frames.append(np.stack(channels,axis=-1))
    image(np.concatenate(frames,axis=1)).save(output/(material+'-frames.webp'),quality=92,method=6,exact=True)

plume=np.exp(-(x*(3.8+2.3*y))**2-3.2*y*y)*np.clip(1-r*r,0,1)
image(np.stack((np.full_like(x,255),162+93*plume,94+161*plume,255*plume),axis=-1)).save(output/'spark.webp',lossless=True,method=6,exact=True)

edge=np.clip(1-(r+.09*np.sin(9*a+5*r)+.038*np.cos(16*a))**2,0,1)**2.1
metal=np.exp(-((r-.30)*12)**2)*np.clip(np.cos(12*a+6*r),0,1)
image(np.stack((18+65*metal,14+54*metal,14+38*metal,227*edge),axis=-1)).save(output/'impact-mark.webp',quality=93,method=6,exact=True)
