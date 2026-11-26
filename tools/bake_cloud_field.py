"""Bake the battle cloud density and vertical profile into a compact volume atlas."""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

assets = Path(__file__).resolve().parents[1] / "assets"
width, length, layers = 96, 64, 32
source = Image.open(Path(__file__).resolve().parent / "scenery/cloud-source.png").convert("RGB").resize((width, length))
source = np.asarray(source, dtype=np.float32) / 255.0
height, z, x = np.meshgrid(np.linspace(0, 1, layers), np.arange(length), np.arange(width), indexing="ij")
rng = np.random.default_rng(184)
turbulence = map_coordinates(rng.random((8, 8, 12)),
    (height * 6 + 0.5, z * 8 / length, x * 12 / width), order=3, mode="grid-wrap")
cover = source[..., 0] * 0.73 + source[..., 1] * 0.27
cover = map_coordinates(cover, (z + height * 8, x - height * 14), order=1, mode="grid-wrap")
profile = np.sin(np.pi * height) ** 0.76
cloud = np.clip((cover + 0.21 * (turbulence - 0.5) - 0.43) / 0.31, 0, 1)
field = np.uint8(np.rint(cloud * cloud * (3 - 2 * cloud) * profile * 255))
atlas = Image.new("L", (width * 8, length * 4))
for layer in range(layers):
    atlas.paste(Image.fromarray(field[layer]), (layer % 8 * width, layer // 8 * length))
atlas.save(assets / "environment/cloud-volume.png", optimize=True)
