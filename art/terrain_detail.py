"""Encode an eroded 4097² lattice while preserving the V18 coast and runway."""
import gzip
import struct

import numpy as np
from scipy.ndimage import gaussian_filter, map_coordinates

COARSE = 1025
DETAIL = 4097
EXTENT = 48000
DETAIL_POWER = 4
PATCH = 64
PRIORITY = {413: (1600, 2048), 704: (1664, 1792), 116: (1536, 1792)}


def remap(layer, size, order):
    axis = np.linspace(0, layer.shape[0]-1, size, dtype=np.float32)
    grid = np.broadcast_to(axis[None, :], (size, size))
    return map_coordinates(layer, (grid.T, grid), order=order, mode='reflect', prefilter=order>1)


def refinement(samples, seed):
    rng = np.random.default_rng(seed)
    coarse = samples.astype(np.float32)*.25
    # The original sheltering mountains stay in place. Route water down the
    # finer sub-grid and soften close ridges through talus transport.
    height = remap(coarse, 2049, 1)
    ridges = remap(rng.normal(0,1,(210,210)).astype(np.float32), 2049, 3)
    fine = remap(rng.normal(0,1,(512,512)).astype(np.float32), 2049, 1)
    slope = np.hypot(*np.gradient(height)) / (EXTENT/2048)
    land = np.clip((height-25)/175, 0, 1)
    relief = (ridges*4.2 + fine*1.4)*np.clip(.45+slope, .45, 2.25)
    ground = height+relief*land
    p = np.pad(ground,1,mode='edge')
    around = [p[:-2,1:-1],p[2:,1:-1],p[1:-1,:-2],p[1:-1,2:]]
    lower = np.minimum.reduce(around)
    route = np.argmin(around,axis=0)
    fall = np.maximum(0,ground-lower)
    accumulation = np.ones_like(ground)
    for _ in range(18):
        moving = np.minimum(accumulation,130)*(fall>.42)
        accumulation = 1+np.roll(moving*(route==0),-1,0)+np.roll(moving*(route==1),1,0) \
            +np.roll(moving*(route==2),-1,1)+np.roll(moving*(route==3),1,1)
    channels = np.log1p(accumulation)*np.minimum(np.sqrt(fall),4.6)*.49
    talus = (gaussian_filter(ground,.78)-ground)*np.clip(slope-.51,0,.77)
    detail = remap((relief+talus-channels)*land,DETAIL,1)

    # Fade the new relief near old knots and along the streaming tile seams.
    # The base plane is also made of the original V18 mesh triangles.
    i=np.arange(DETAIL,dtype=np.float32)
    fraction=i%DETAIL_POWER
    knot=np.minimum(fraction,DETAIL_POWER-fraction)/2
    between_knots=np.maximum(knot[:,None],knot[None,:])
    tile=i%256
    edge=np.clip(np.minimum(tile,256-tile)/8,0,1)
    x=i*(EXTENT/(DETAIL-1))-EXTENT*.5
    airfield=np.maximum(np.clip((abs(x+2970)-630)/490,0,1)[None,:],
                        np.clip((abs(x-1250)-1550)/515,0,1)[:,None])
    detail*=between_knots*edge[:,None]*edge[None,:]*airfield
    return np.rint(np.clip(detail*4,-100,100)).astype(np.int8)


def micro_detail(seed):
    i,j=PRIORITY[seed]
    size=PATCH*2+1
    rng=np.random.default_rng(seed*317)
    axis=np.arange(size,dtype=np.float32)
    source=remap(rng.normal(0,1,(19,19)).astype(np.float32),size,3)
    ridge=remap(rng.normal(0,1,(44,44)).astype(np.float32),size,3)
    crack=np.maximum(0,np.cos(axis[None,:]*.29+axis[:,None]*.17+source*.74))**7
    apron=np.clip(np.minimum(axis,size-1-axis)/10,0,1)
    values=np.rint(np.clip((source*2.3+ridge*.85-crack*.88)*apron[:,None]*apron[None,:]*4,-22,22)).astype(np.int8)
    values[::2,::2]=0
    return struct.pack('<HHH',i,j,PATCH)+values.tobytes()


def with_microdata(packet, seed):
    base_length=12+COARSE*COARSE*2+DETAIL*DETAIL
    return packet[:base_length]+micro_detail(seed)


def encode(samples, seed):
    assert samples.shape == (COARSE,COARSE)
    delta=refinement(samples,seed)
    assert not np.any(delta[::4,::4])
    packet=struct.pack('<4sHHI',b'WF18',DETAIL,4,EXTENT)+samples.astype('<i2').tobytes()+delta.tobytes()
    return gzip.compress(with_microdata(packet,seed),compresslevel=6,mtime=0)


if __name__=='__main__':
    import sys
    from pathlib import Path
    source,destination,seed=sys.argv[1:]
    data=Path(source).read_bytes()
    assert data[:4]==b'WF09' and len(data)==12+COARSE*COARSE*2
    old=np.frombuffer(data,dtype='<i2',offset=12).reshape(COARSE,COARSE)
    dst=Path(destination)
    dst.write_bytes(encode(old,int(seed)))
    print(dst, dst.stat().st_size)
