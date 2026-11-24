"""Bake soft smoke, plasma, sparks and optical shock rings for instanced effects."""
from pathlib import Path
from math import atan2, cos, exp, hypot, sin
from PIL import Image

output=Path(__file__).resolve().parents[1]/'public/surface'
n=128
sprites={name:Image.new('RGBA',(n,n)) for name in ['pressure','spark']}
unit=lambda x:min(1,max(0,x))
for y in range(n):
    for x in range(n):
        u=(x+.5)/n*2-1
        v=(y+.5)/n*2-1
        a=atan2(v,u)
        r=hypot(u,v)
        folds=.06*sin(9*a+12*r)+.045*cos(13*v+20*u)+.065*sin(5*a-7*r)
        arc=exp(-((r-(.70+.012*sin(13*a)))/.042)**2)*unit(1-(r/.94)**8)
        sprites['pressure'].putpixel((x,y),(174,216,236,int(136*arc)))
        plume=exp(-(u*(3.8+2.3*v))**2-3.2*v*v)*unit(1-r*r)
        sprites['spark'].putpixel((x,y),(255,int(162+93*plume),int(94+161*plume),int(255*plume)))
for name,image in sprites.items():
    image.save(output/(name+'.webp'),lossless=True,method=6,exact=True)

# Each strip stores the full lifecycle in contiguous 128-pixel cells.
for kind in ('smoke','fire'):
    frames=8
    atlas=Image.new('RGBA',(n*frames,n))
    for frame in range(frames):
        age=frame/(frames-1)
        for y in range(n):
            for x in range(n):
                u=(x+.5)/n*2-1
                v=(y+.5)/n*2-1
                a=atan2(v,u)
                r=hypot(u,v)
                folds=.09*sin(8*a+10*r-age*5)+.058*cos(13*v+20*u+age*4)+.047*sin(5*a-8*r+age*8)
                edge=unit(1-(r*1.08+folds)**2)
                light=unit(.68-.34*v+.36*folds+.12*cos(u*14-v*18+age*3))
                if kind=='smoke':
                    pixel=(int(109+91*light),int(120+87*light),int(132+79*light),int(244*edge**(1.14+age*.6)))
                else:
                    core=exp(-(4+age*5)*(r+folds*.7)**2)*(1-age*.72)
                    pixel=(255,int(63+192*core),int(18+229*core),int(246*edge**(1.5+age*.7)))
                atlas.putpixel((frame*n+x,y),pixel)
    atlas.save(output/(kind+'-flipbook.webp'),quality=91,method=6,exact=True)
