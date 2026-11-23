"""Bake broad illumination and irregular specular streaks into the wet apron."""
from pathlib import Path
import numpy as np
from PIL import Image

width, height = 512, 768
x,z=np.meshgrid(np.linspace(-70,70,width),np.linspace(118.5,-72.5,height))
ripple=(.54+.22*np.sin(x*5.17+np.sin(z*.45)*2)+.16*np.cos(z*.93-x*2.36))
sun=np.exp(-((x+5+z*.23)/24)**2-((z-29)/43)**2)*(.24+ripple*.76)
lamps=np.zeros_like(sun)
for side in (-1,1):
    for hangar_bay in (-32,-21,-10,1,12,23,34):
        lamps+=np.exp(-((x-side*22.0)/3.4)**2-((z-hangar_bay)/7.4)**2)*ripple
for lamp_x,lamp_z in [(-8,3.6),(9.1,-1.9),(15.3,12),(-7,16.2)]:
    lamps+=np.exp(-((x-lamp_x)/.92)**2-((z-lamp_z)/4.9)**2)*ripple*.92
cool=np.exp(-((x-6)/13)**2-((z+4)/36)**2)*ripple*.27
light=sun*.59+lamps*.48
image=np.stack([light*.94+cool*.32,light*.58+cool*.61,light*.29+cool],axis=-1)
Image.fromarray(np.uint8(np.clip(image,0,1)**.52*255)).save(Path(__file__).resolve().parents[1]/'public/studio/apron-light.webp',quality=90,method=6)
