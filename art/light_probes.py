"""Bake compact, linear HDR lighting probes for the shared real-time rig."""
from pathlib import Path
import math

root=Path(__file__).resolve().parents[1]/'public/surface'
profiles={
    'day': ((-.40,.57,-.74),(.21,.38,.67),(.45,.57,.68),(4.1,3.9,3.5)),
    'dusk': ((.69,.14,-.73),(.19,.27,.53),(.81,.34,.16),(4.4,2.35,.76)),
    'storm': ((.39,.22,-.84),(.16,.22,.32),(.37,.43,.51),(1.61,1.79,2.03)),
    'night': ((.44,.28,-.85),(.055,.091,.18),(.12,.16,.26),(.31,.55,.94)),
}
for name,(sun,top,line,solar) in profiles.items():
    length=math.sqrt(sum(value*value for value in sun))
    sun=tuple(value/length for value in sun)
    w,h=128,64
    with (root/f'probe-{name}.hdr').open('wb') as f:
        f.write(f'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {h} +X {w}\n'.encode())
        for y in range(h):
            phi=(.5-(y+.5)/h)*math.pi
            vertical=math.sin(phi)
            zenith=max(0,vertical)**.52
            for x in range(w):
                theta=(x+.5)/w*math.tau
                direction=(math.cos(theta)*math.cos(phi),vertical,math.sin(theta)*math.cos(phi))
                focus=max(0,sum(a*b for a,b in zip(sun,direction)))
                sp=focus**33*.34+focus**480*1.65
                below=(1+min(0,vertical)*.76)
                color=[((a*zenith+b*(1-zenith))*.78+sp*c)*below for a,b,c in zip(top,line,solar)]
                maximum=max(color)
                scale,ex=math.frexp(maximum)
                f.write(bytes([int(c/maximum*scale*256) for c in color]+[ex+128]))
