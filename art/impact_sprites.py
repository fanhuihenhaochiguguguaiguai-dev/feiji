"""Bake soft smoke, plasma, sparks and optical shock rings for instanced effects."""
from pathlib import Path
from math import atan2, cos, exp, hypot, sin
from PIL import Image

output=Path(__file__).resolve().parents[1]/'public/surface'
n=128
sprites={name:Image.new('RGBA',(n,n)) for name in ['combustion','soot','pressure','spark']}
unit=lambda x:min(1,max(0,x))
for y in range(n):
    for x in range(n):
        u=(x+.5)/n*2-1
        v=(y+.5)/n*2-1
        a=atan2(v,u)
        r=hypot(u,v)
        folds=.06*sin(9*a+12*r)+.045*cos(13*v+20*u)+.065*sin(5*a-7*r)
        smoke=unit(1-(r+folds)**2)**1.3
        light=unit(.71-.38*v+.24*folds+.11*cos(u*14-v*18))
        sprites['soot'].putpixel((x,y),(int(113+76*light),int(126+70*light),int(131+74*light),int(248*smoke)))
        core=exp(-5*r**2)
        sprites['combustion'].putpixel((x,y),(255,int(69+186*core),int(20+228*core),int(245*unit(1-(r+folds)**2)**2)))
        arc=exp(-((r-(.70+.012*sin(13*a)))/.042)**2)*unit(1-(r/.94)**8)
        sprites['pressure'].putpixel((x,y),(174,216,236,int(136*arc)))
        plume=exp(-(u*(3.8+2.3*v))**2-3.2*v*v)*unit(1-r*r)
        sprites['spark'].putpixel((x,y),(255,int(162+93*plume),int(94+161*plume),int(255*plume)))
for name,image in sprites.items():
    image.save(output/(name+'.webp'),lossless=True,method=6,exact=True)
