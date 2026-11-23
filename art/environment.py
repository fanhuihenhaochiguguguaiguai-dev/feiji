"""Bake the two backends' shared water-mist sprite."""
from pathlib import Path
import math
from PIL import Image

root=Path(__file__).resolve().parents[1]/'public'
tiles=root/'surface'
tiles.mkdir(exist_ok=True)
N=128
image=Image.new('RGBA',(N,N))
for y in range(N):
    for x in range(N):
        u=(x+.5)/N*2-1
        v=(y+.5)/N*2-1
        radius=u*u+v*v+.085*math.sin(u*14+v*11)*math.sin(v*19-u*8)
        alpha=int(max(0,1-radius)**1.9*244)
        image.putpixel((x,y),(199,236,243,max(0,min(255,alpha))))
image.save(tiles/'water.png')
