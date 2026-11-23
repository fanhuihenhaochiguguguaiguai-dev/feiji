"""Author three coastal provinces, simulate drainage, and export one shared height lattice per map."""
from pathlib import Path
import struct

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter, map_coordinates

ROOT = Path(__file__).resolve().parents[1] / "public" / "world"
SIZE, EXTENT = 1025, 48000
STEP = EXTENT / (SIZE - 1)
axis = np.linspace(-EXTENT/2, EXTENT/2, SIZE, dtype=np.float32)
x, z = np.meshgrid(axis, axis)
X, Z = x/1000, z/1000

# The sight line from (18, 2610) follows the strait. Each line defines a sculpted
# spine with elevations on its control points. Width is in kilometres.
COAST = [
    (1.75,[(-5.7,3.9,.30),(-5.2,2.1,.61),(-4.6,.4,1.03),(-5,-1.3,.73),(-6.7,-3.4,1.13)]),
    (2.32,[(-6.8,-1.8,1.09),(-5.8,-3.3,1.39),(-4.7,-4.6,1.19),(-3.5,-5.3,.68),(-2.9,-6.9,.43)]),
    (2.05,[(6.9,3.85,.39),(5.0,2.4,.37),(4.8,.7,.65),(3.45,-.2,.34),(2.6,-1.6,.19)]),
    (1.97,[(6.3,-8.1,1.25),(4.9,-6.9,1.49),(4.4,-5,1.04),(2.9,-4.1,1.37),(2.1,-3.5,.82)]),
    (1.11,[(1.0,-8.9,.48),(.45,-7.4,.38),(-.5,-6.25,.22)]),
    (.60,[(-1.7,-2.8,.21),(-1.46,-1.9,.15),(-1.16,-1.12,.10)]),
    (3.21,[(-14,6,2.6),(-12.5,2.7,2.19),(-11.6,-.5,2.68),(-10.2,-4,2.2),(-12.1,-7.5,2.71),(-11.1,-12.2,2.63)]),
    (3.42,[(-18,-10.1,2.95),(-14.3,-12.7,2.46),(-10.1,-15.1,2.86),(-6.2,-14.6,2.18),(-3.2,-15.1,1.42)]),
    (2.91,[(3.3,-17.7,2.35),(5.8,-14.4,2.48),(8.1,-13.4,1.98),(10.6,-11.5,2.51),(14.7,-11.8,2.03)]),
    (3.04,[(10.4,-3.6,1.3),(13.2,-1.8,2.01),(15.6,1.2,1.71),(15.4,5.9,2.31),(11.4,9.2,1.92),(7.0,11.2,.82)]),
    (2.45,[(-3.9,10.9,1.2),(-1.0,12.5,1.65),(2.9,13.5,1.74),(5.6,14.2,1.02)]),
]
FROST = [
    (1.84,[(-5.8,5,.42),(-4.9,2.5,.92),(-5.0,.3,1.45),(-6.8,-2.6,1.8),(-5.7,-5.8,2.30),(-4.4,-7,1.83)]),
    (1.99,[(5.3,4.0,.53),(4.4,2.2,.52),(4.9,-.6,1.13),(3.7,-3,1.62),(4.4,-6.2,1.44),(3.4,-8.1,2.53)]),
    (1.20,[(-.8,-9.1,1.03),(-.4,-7.7,.51),(.85,-6.8,.29)]),
    (2.81,[(-13,7.8,2.17),(-12,4,2.9),(-10,-.8,3.13),(-10.4,-4.2,2.8),(-9.4,-9,3.28),(-11.2,-14.2,2.74)]),
    (2.47,[(-7.8,-13.7,3.17),(-4.5,-14.7,3.28),(-1.6,-14.2,2.95),(2.5,-15.5,2.91),(5.2,-13.8,2.27)]),
    (2.83,[(9.9,-13.3,3.27),(11.7,-10.8,2.4),(11.1,-7.4,3.29),(11.9,-2.2,2.85),(14.7,1.8,2.88),(14.2,8.7,2.11)]),
    (2.89,[(1.2,12,1.92),(4.5,11.6,1.89),(7.7,13.4,2.19),(10.8,11,1.94)]),
]
STORM = [
    (2.08,[(-6.1,5.4,.29),(-4.6,3,.37),(-4.8,.77,.41),(-5.5,-1.8,.69),(-4.4,-3.7,.45)]),
    (1.68,[(5.2,3.3,.27),(4.7,1.8,.64),(3.4,.1,.51),(3.2,-1.9,.58),(4.3,-3.0,.55)]),
    (1.73,[(-4.2,-6.9,.88),(-2.1,-7.6,.46),(-.9,-9.9,.88),(1.1,-11.6,.61),(3.6,-12.1,.77)]),
    (1.01,[(.8,-3.6,.17),(.38,-4.9,.33),(.78,-5.9,.27)]),
    (.59,[(-1.7,-2.6,.22),(-1.0,-1.5,.13)]),
    (2.68,[(-14.7,7,1.36),(-11.3,5.7,1.52),(-10.8,3.3,1.12),(-9.7,-.4,1.7),(-11.2,-7.3,1.72),(-10.2,-10.9,1.25)]),
    (3.16,[(14.2,9.4,2.05),(12.5,5.4,1.52),(10.9,-.4,1.04),(12.1,-5,1.57),(9.4,-9.4,1.92),(11.2,-13.9,2.24)]),
    (2.86,[(-13,-15.2,2.21),(-9.3,-14.5,1.64),(-5.6,-16.8,1.77),(-2.3,-16.4,1.35),(2,-17.6,1.92),(7.3,-16.5,1.76)]),
    (2.15,[(-1.8,11.2,1.06),(2.1,12.2,1.21),(3.9,13.6,1.78),(6.1,11.8,1.05)])
]

def smooth(a, b, v):
    t = np.clip((v-a)/(b-a), 0, 1)
    return t*t*(3-2*t)

def field(rng, n):
    coarse = rng.normal(0, 1, (n,n)).astype("float32")
    coords = np.broadcast_to(np.linspace(1,n-2,SIZE,dtype=np.float32)[None,:], x.shape)
    return map_coordinates(coarse, [coords.T,coords], order=3, mode="reflect", prefilter=True)

def erode(height, solid, repetitions):
    """Route rain downhill. Accumulated drainage cuts coherent channels into convex slopes."""
    h = height.copy()
    for epoch in range(repetitions):
        head = np.pad(h,1,constant_values=-170)
        adjacent = [head[dy:dy+SIZE,dx:dx+SIZE] for dy,dx in ((0,1),(1,0),(1,2),(2,1))]
        slopes = np.maximum(0, h - np.minimum.reduce(adjacent))
        direction = np.argmin(adjacent,axis=0)
        flow = np.float32(.45) + solid.astype("float32")*.58
        for _ in range(25):
            moving = np.minimum(flow,150)*(slopes>.24)
            flow = np.float32(.7)+(np.roll(moving*(direction==0),-1,axis=0)
                +np.roll(moving*(direction==1),-1,axis=1)
                +np.roll(moving*(direction==2),1,axis=1)+np.roll(moving*(direction==3),1,axis=0))
        incise = np.clip(np.log1p(flow)*np.sqrt(slopes)*(.88+epoch*.07),0,28)
        transport = (gaussian_filter(h,.82)-h)*.63
        h += np.where(solid,transport-incise*(h>1),0)
    return h

def forge(name, seed, spines):
    rng = np.random.default_rng(seed)
    small = field(rng,89); broad = field(rng,16); mids = field(rng,42)
    shift_x = X + broad*.31 + mids*.085
    shift_z = Z + field(rng,17)*.32 + small*.036
    mass = np.full_like(x, -150)
    for width,line in spines:
        width *= 1.0 + broad*.084 + mids*.13
        closest = np.full_like(x,1000)
        crest = np.zeros_like(x)
        for (ax,az,ha),(bx,bz,hb) in zip(line,line[1:]):
            dx,dz = bx-ax,bz-az
            t = np.clip(((shift_x-ax)*dx+(shift_z-az)*dz)/(dx*dx+dz*dz),0,1)
            dist = np.hypot(shift_x-ax-t*dx,shift_z-az-t*dz)
            w = dist/width
            closest = np.minimum(w,closest)
            shoulders = np.exp(-1.65*w*w)*smooth(1.35,.14,w)
            height = (ha+(hb-ha)*t)*1000 * shoulders
            crest = np.maximum(crest,height)
        foot = (1-closest)*110 - 14 + mids*10
        smooth_hill = 1.0 + mids*.16 + small*.045
        plateau = (crest * smooth_hill) * smooth(1.05,.31,closest) + foot
        mass = np.maximum(mass,np.where(closest<1.7,plateau,-160))
    solid=mass>-15
    peak = erode(mass,solid,5)
    slope = np.hypot(*np.gradient(peak))/STEP
    carving = small*(7+np.clip(peak/70,0,25))
    slates = np.sin((X*.20+Z*.11+peak*.0008+mids*.051)*47)*np.minimum(slope,1.4)*4.2
    h = peak + (carving+slates)*smooth(0,110,peak)
    # Local civil works raises the apron and feathers to the original slope.
    tx = x + 2970; tz=z-1250
    earthworks = smooth(395,305,abs(tx-70))*smooth(1220,975,abs(tz))
    berm = smooth(640,375,abs(tx-35))*smooth(1530,1160,abs(tz))
    h = h*(1-berm)+np.maximum(h,22+small*3)*berm
    h = h*(1-earthworks)+31*earthworks
    underwater = h<0
    # Distance units are also used by the animated breakers.
    distance = np.where(underwater,-distance_transform_edt(underwater),distance_transform_edt(~underwater))*STEP
    h = np.where(underwater, np.maximum(h, -200) - np.minimum(96,np.maximum(0,-distance-95)*.012),h)
    # Edge samples follow the same coarse chord at every LOD. This preserves
    # continuity without artificial vertical skirts at chunk boundaries.
    for seam in range(0,SIZE,64):
        h[:,seam]=np.interp(np.arange(SIZE),np.arange(0,SIZE,4),h[::4,seam])
        h[seam,:]=np.interp(np.arange(SIZE),np.arange(0,SIZE,4),h[seam,::4])
    underwater = h<0
    distance = np.where(underwater,-distance_transform_edt(underwater),distance_transform_edt(~underwater))*STEP
    # Store actual elevation samples in quarter-metres. The atlas packs the same sample into RG.
    packed = np.clip(np.rint(h*4),-32767,32767).astype("<i2")
    # Z-major image rows. The runtime samples texel centres and never flips the texture.
    u = (packed.astype(np.int32) + 32768)
    atlas = np.stack((u>>8,u&255,np.rint(np.clip(distance/520+.5,0,1)*255)),axis=-1).astype(np.uint8)
    (ROOT/f"{name}.height").write_bytes(struct.pack("<4sHHI",b"WF09",SIZE,4,EXTENT)+packed.tobytes())
    Image.fromarray(atlas,"RGB").save(ROOT/f"{name}-surface.png",compress_level=8)
    print(name, "heights", int(h.min()), int(h.max()), "cells", SIZE**2,flush=True)

if __name__ == "__main__":
    ROOT.mkdir(exist_ok=True,parents=True)
    for name,seed,design in [("sundown",413,COAST),("frost",704,FROST),("storm",116,STORM)]:
        forge(name,seed,design)
