"""Bake the far mountain matte from the existing Frost terrain and dusk panorama."""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

root=Path(__file__).resolve().parents[1]/'public'
height=np.fromfile(root/'world/frost.height',dtype='<i2',offset=12).reshape(1025,1025)*.25
panorama=np.asarray(Image.open(root/'surface/dusk-panorama.webp').convert('RGB'),dtype=float)/255
width,rows=1536,208
angle=(np.arange(width)+.5)/width*2*np.pi
elevation=.23-(np.arange(rows)+.5)/rows*.31
# The rear of the hangar looks into the northern ridges. Sample front to back
# so nearer ridges occlude distant faces at equal viewing elevations.
relative=(angle-2.48+np.pi)%(2*np.pi)-np.pi
direction=np.stack([np.sin(relative),-np.cos(relative)])
distance=np.linspace(6400,25000,440)[:,None]
x=440+direction[0]*distance/46.875
z=641+direction[1]*distance/46.875
land=map_coordinates(height,[z,x],order=1,mode='constant',cval=-240,prefilter=False)
slope_z,slope_x=np.gradient(height,46.875)
light=np.clip(.64+.4*map_coordinates(slope_x,[z,x],order=1,prefilter=False)
                 -.25*map_coordinates(slope_z,[z,x],order=1,prefilter=False),.22,.98)
silhouette=(np.maximum(0,land)*.74-185)/distance
coverage=np.clip((1.24-np.abs(relative))*2.4,0,1)
image=np.zeros((rows,width,4),dtype=np.uint8)
columns=np.arange(width)
for row,ray in enumerate(elevation):
    hit=(silhouette>=np.tan(ray))&(land>25)
    first=hit.argmax(axis=0)
    rock=light[first,columns]
    snow=np.clip((land[first,columns]-2300)/1400,0,1)*(.53+.47*rock)
    fog=np.clip(.24+distance[first,0]/48000,0,.76)
    sky=panorama[round((.5-ray/np.pi)*(panorama.shape[0]-1)),:]
    ground=np.array([.22,.255,.33])+rock[:,None]*np.array([.22,.18,.15])
    ground=ground*(1-snow[:,None])+snow[:,None]*np.array([.78,.79,.81])
    color=ground*(1-fog[:,None])+sky*fog[:,None]
    opacity=coverage*hit.any(axis=0)*np.clip((ray+.08)/.045,0,1)
    image[row,:,:3]=(np.clip(color,0,1)*255).astype(np.uint8)
    image[row,:,3]=(opacity*255).astype(np.uint8)
Image.fromarray(image).save(root/'surface/lobby-mountains.webp',quality=92,method=6,exact=True)
