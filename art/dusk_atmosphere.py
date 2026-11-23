"""Bake the airbase's HDR radiance and display panorama from one twilight lighting model."""
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

ROOT = Path(__file__).resolve().parents[1] / 'public' / 'surface'
W,H=1536,768
rng=np.random.default_rng(72138)
noise=rng.random((512,512), dtype=np.float32)
phi=(.5-(np.arange(H,dtype=np.float32)+.5)/H)*np.pi
theta=(np.arange(W,dtype=np.float32)+.5)/W*2*np.pi
y=np.sin(phi)[:,None]
x=np.cos(phi)[:,None]*np.cos(theta)[None,:]
z=np.cos(phi)[:,None]*np.sin(theta)[None,:]
sun=np.array([-.93,.19,.37],dtype=np.float32)
sun/=np.linalg.norm(sun)
angle=np.clip(x*sun[0]+y*sun[1]+z*sun[2],0,1)
source=np.array([1,.59,.31],dtype=np.float32)
fade=np.exp(-np.maximum(y,0)*5.6)
sunset=np.exp(-np.maximum(y,0)*11)*(.15+.85*angle**7)
blue=np.array([.023,.069,.155],dtype=np.float32)
warm=np.array([.26,.117,.073],dtype=np.float32)
air=blue+(warm-blue)*fade[:,:,None]
air=(air+sunset[:,:,None]*np.array([.55,.196,.046],dtype=np.float32)+angle[:,:,None]**28*source*.072)
air*=np.clip((y+.42)*4.2,.11,1)[:,:,None]

def noise_at(a,b):
    return map_coordinates(noise,[np.remainder(b,512),np.remainder(a,512)],order=1,mode='grid-wrap',prefilter=False)

# Each cloud deck intersects the appropriate world-space ray at its own altitude.
for altitude,frequency,base,tint in [(2900,1,.455,.86),(1400,1,.478,1),(790,.76,.504,1.1)]:
    h=np.maximum(.016,y)
    ray=np.minimum(55000,altitude/h)
    a=x*ray*(.0028*frequency)+85+altitude*.021
    b=z*ray*(.0016*frequency)+220-altitude*.018
    stretch=np.sin(a*.023)*3.7
    coarse=noise_at(a*.23+stretch,b*.72)
    density=(coarse*.55+noise_at(a*.63+13,b*1.4)*.27+noise_at(a*1.8,b*3.5)*.126+noise_at(a*4.53,b*8.11)*.054)
    low=noise_at(a*.23+stretch-1.23*sun[0],b*.72-1.6*sun[2])
    edge=np.clip((coarse-low)*1.62+.21,0,1)
    optical=np.clip((density-base)*4.85,0,.93)*(np.clip((y-.027)/.072,0,1)**2)
    fadeCloud=(1-np.exp(-np.maximum(0,density-base)*7.3))
    dust=np.exp(-np.maximum(0,y)*4.9)*(.29+.71*angle**4)
    dark=np.stack(np.broadcast_arrays(.035+dust*.033,.050+dust*.031,.087+dust*.021),axis=-1)
    lit=(edge*(1-.45*fadeCloud))[:,:,None]*(np.array([.46,.49,.57])+.62*dust[:,:,None]*source)
    cloud=dark+lit*tint
    air=air*(1-optical[:,:,None])+cloud*optical[:,:,None]

disk=np.clip((angle-.99993)/.000018,0,1)
air+=disk[:,:,None]*source*7
scale=lambda a:np.clip((a*(2.51*a+.03))/(a*(2.43*a+.59)+.14),0,1)
encoded=scale(air)**.454545
Image.fromarray(np.uint8(np.round(encoded*255))).save(ROOT/'dusk-panorama.webp',quality=92,method=6)

# Downsample in linear light before writing RGBE for reflection and ambient probes.
linear=air.reshape(64,12,128,12,3).mean(axis=(1,3))
scale,exp=np.frexp(linear.max(axis=-1))
bytes_=np.dstack((np.uint8(np.clip(linear/np.exp2(exp[:,:,None])*256,0,255)),np.uint8(exp+128)))
(ROOT/'probe-airbase-atlas.hdr').write_bytes(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 64 +X 128\n'+bytes_.tobytes())
