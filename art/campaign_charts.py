"""Render tactical relief from the same signed elevation lattice used in flight."""
from pathlib import Path
from struct import unpack
from subprocess import run
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import distance_transform_edt

PUBLIC = Path(__file__).resolve().parents[1] / 'public'
CHARTS = PUBLIC / 'charts'
CHARTS.mkdir(exist_ok=True)


def relief(sector):
    data = (PUBLIC / 'world' / (sector + '.height')).read_bytes()
    magic, size, units, extent = unpack('<4sHHI', data[:12])
    assert magic == b'WF09' and extent > 0
    h = np.frombuffer(data, dtype='<i2', offset=12).reshape(size, size).astype(np.float32) / units
    x, y = np.meshgrid(np.arange(size), np.arange(size))
    grain = (np.sin(x*.55 + y*.48)*np.sin(y*.32-x*.39) + np.cos(x*.81+y*.25))*.014
    dz, dx = np.gradient(h, extent/(size-1))
    slope = np.hypot(dx, dz)
    light = np.clip((.64+dx*.53+dz*.56)/np.sqrt(1+slope*slope), .03, 1)
    snow = np.clip((h-730)/760, 0, 1) * (1-np.clip(slope-.22,0,.75)) if sector == 'frost' else np.clip((h-1800)/1000,0,.38)
    rock = np.clip(slope*1.34 + h/4100, 0, 1)
    coast = np.exp(-np.abs(h)/38)
    shallow = np.exp(np.minimum(0, h)/196)
    bands = np.exp(-np.abs((h+65)%130-65)/9)
    paint = []
    for sea, shoal, grass, stone, ice, sand in [(10,27,41,104,199,131),(24,64,72,113,217,149),(41,78,71,123,226,136)]:
        land = ((grass*(1-rock)+stone*rock)*(1-snow)+ice*snow)*(.57+.72*light)
        land = land*(1-.63*coast) + sand*coast*.63
        water = sea + (shoal-sea)*shallow + coast*(shoal-sea)*.27
        paint.append(np.where(h>=0,land,water)*(1+grain-bands*.047))
    image = Image.fromarray(np.clip(np.stack(paint, axis=-1), 0, 255).astype('uint8'))
    image.save(CHARTS / (sector + '.webp'), quality=92, method=6)
    return image


for theatre in ('sundown', 'frost', 'storm'):
    relief(theatre)

# WGS84, Pacific-centred at 150°E. The same projection is used for mission overlays.
width, height = 2880, 1440
with TemporaryDirectory() as directory:
    land = Path(directory) / 'land.tif'
    bitmap = Path(directory) / 'land.pgm'
    run(['gdal_rasterize', '-q', '-of','GTiff','-ot','Byte','-burn','255','-init','0',
         '-te','-180','-90','180','90','-ts',str(width),str(height),'-l','land',
         str(PUBLIC.parent/'art'/'geodata'/'natural-earth.gpkg'),str(land)], check=True)
    run(['gdal_translate','-q','-of','PNM',str(land),str(bitmap)],check=True)
    land_mask = np.asarray(Image.open(bitmap)) > 127
    assert .30 < land_mask.mean() < .40, 'Invalid global land coverage'
    mask = np.roll(land_mask, -width * 5 // 12, axis=1)

surface = Image.open(PUBLIC.parent/'art'/'geodata'/'natural-earth-relief.jpg').convert('RGB')
assert surface.size == (width,height)
lit = surface.convert('L')
source = np.roll(np.asarray(surface, dtype=np.float32)/255, -width * 5 // 12, axis=1)
detailed = np.asarray(lit, dtype=np.float32) - np.asarray(lit.filter(ImageFilter.GaussianBlur(5)),dtype=np.float32)
hillshade = np.roll(detailed, -width * 5 // 12, axis=1)
shore = distance_transform_edt(~mask) - distance_transform_edt(mask)
x, y = np.meshgrid(np.linspace(-np.pi,np.pi,width),np.linspace(-np.pi/2,np.pi/2,height))
continental = (1-np.exp(np.minimum(shore,0)/58))
shelf = np.exp(-np.maximum(shore,0)/17)
polar = abs(np.sin(y))**2.6
lum = .84 + .16*np.cos(y*.72) + .07*np.cos(x*1.6+y*1.7)
grain = .6*np.sin(x*683+y*433)+.7*np.cos(x*931-y*353)
world = []
terrain_gray=source.mean(axis=-1)
for channel,(sea,shoal,land,high,ice) in enumerate([(8,34,43,47,21),(21,62,70,71,16),(39,93,78,84,17)]):
    water = sea + (shoal-sea)*shelf*.75
    ground = (land+(high-land)*continental+ice*polar)*lum+45*(terrain_gray-.46)+.52*hillshade+29*(source[:,:,channel]-.48)
    edge = np.exp(-abs(shore)/2.4)*10
    world.append(np.where(mask,ground,water)+edge+grain)
world = Image.fromarray(np.clip(np.stack(world,axis=-1),0,255).astype('uint8'))
world.save(CHARTS/'world.webp',quality=93,method=6)
