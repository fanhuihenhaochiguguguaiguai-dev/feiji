"""Bake broad, irregular light from the hangar entrance and overhead fixtures."""
from pathlib import Path
import numpy as np
from PIL import Image

width, height = 768, 1024
x,z=np.meshgrid(np.linspace(-70,70,width),np.linspace(118.5,-72.5,height))
ripple=.62+.12*np.sin(x*5.17+np.sin(z*.45)*2)+.08*np.cos(z*.93-x*2.36)
streak=.34+.66*ripple
entrance=np.exp(-((x+7+z*.22)/22)**2-((z-32)/45)**2)*streak
warm=np.zeros_like(x)
cool=np.zeros_like(x)
for side in (-1,1):
    for bay in (-32,-10,23):
        warm+=np.exp(-((x-side*22.0)/3.8)**2-((z-bay)/6.7)**2)*ripple
    for bay in (-32,-21,-10,1,12,23,34):
        cool+=np.exp(-((x-side*8.0)/4.9)**2-((z-bay)/4.3)**2)*ripple
light=entrance*.40+warm*.21
cool*=.18
color=np.stack([light*.93+cool*.46,light*.64+cool*.70,light*.41+cool],axis=-1)
Image.fromarray(np.uint8(np.clip(color,0,1)**.52*255)).save(Path(__file__).resolve().parents[1]/'public/studio/apron-light.webp',quality=90,method=6)
