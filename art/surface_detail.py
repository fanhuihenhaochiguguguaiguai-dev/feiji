"""Bake original 2K cliff albedo, relief and material response maps."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

root=Path(sys.argv[1])
root.mkdir(parents=True,exist_ok=True)
size=2048
random=np.random.default_rng(28618)
axis=np.linspace(0,1,size,endpoint=False,dtype=np.float32)
x,y=np.meshgrid(axis,axis)
def noise(n):
    grid=random.uniform(-1,1,(n,n)).astype(np.float32)
    return map_coordinates(grid,[(y*n)%n,(x*n)%n],order=3,mode='grid-wrap')
wide=noise(19)
chip=noise(123)
grain=noise(400)
shear=y+.12*x+.013*wide+.005*chip
seam=np.maximum(0,np.cos(shear*176+wide*2.1))**13
relief=(wide*.37+chip*.16+grain*.05-seam*.13)*.48
up=(np.roll(relief,1,0)-np.roll(relief,-1,0))*4.1
side=(np.roll(relief,1,1)-np.roll(relief,-1,1))*4.1
norm=np.sqrt(1+up*up+side*side)
light=.70+wide*.10+chip*.055+grain*.025-seam*.08
color=np.stack((light*.995,light*.978+.014,light*.932+.044),axis=-1)
normal=np.stack((.5+.5*side/norm,.5+.5*up/norm,.5+.5/norm),axis=-1)
orm=np.stack((.95-np.maximum(0,.1-relief)*.86,.81+seam*.12-chip*.11,np.zeros_like(x)),axis=-1)
for name,array in [('stone-color',color),('stone-relief',normal),('stone-response',orm)]:
    Image.fromarray(np.rint(np.clip(array,0,1)*255).astype(np.uint8)).save(root/(name+'.png'))
