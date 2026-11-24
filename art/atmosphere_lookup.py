"""Bake transmittance and directional scattering terms used by sky and sea."""
from pathlib import Path
import numpy as np
from PIL import Image

height=128
width=256
angle=np.linspace(-1,1,width,dtype=np.float32)[None,:]
elevation=np.linspace(0,1,height,dtype=np.float32)[:,None]
mass=1/(elevation+.134+np.sqrt(elevation+.022)*.31)
slant=1-np.exp(-mass*.24)
rayleigh=.75*(1+angle*angle)
mie=.039/np.maximum(.016,1+.7225-1.7*angle)**1.5
glow=mie*(.16+.035*mass)
data=np.stack(np.broadcast_arrays(slant,rayleigh/1.5,np.sqrt(np.clip(glow/.90,0,1))),axis=-1)
root=Path(__file__).resolve().parents[1]/'public/surface'
Image.fromarray(np.rint(data*255).astype(np.uint8)).save(root/'air-scattering.png',optimize=True)
