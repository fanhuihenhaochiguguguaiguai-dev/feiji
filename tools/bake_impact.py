"""Bake the existing fire and soot flipbooks from a small, animated density volume."""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates


ROOT = Path(__file__).resolve().parent.parent / "assets/surface"
SIZE = 80
axis = np.linspace(-1, 1, SIZE, dtype=np.float32)
z, y, x = np.meshgrid(np.linspace(-1, 1, 30, dtype=np.float32), axis, axis, indexing="ij")
rng = np.random.default_rng(613)
field = rng.random((24, 24, 24), dtype=np.float32)
lobes = rng.uniform(-0.44, 0.44, (11, 3))
lobes[:, 1] += 0.06


def noise(scale, travel):
    return map_coordinates(field, (z * scale + 11, y * scale + 11 - travel, x * scale + 11 + travel * 0.39), order=1, mode="wrap")


def frame(time, fire):
    expanding = 0.78 + time * 0.32
    swirl = noise(6.2, time * 1.6) - 0.5
    fine = noise(11.0, time * 3.2) - 0.5
    shape = np.full_like(x, -2.0)
    for i, (dx, dy, dz) in enumerate(lobes):
        size = (0.35 + (i % 4) * .06) * expanding
        r2 = ((x - dx * expanding + swirl * .18) / size) ** 2
        r2 += ((y - dy * expanding - .13 * time) / (size * 1.05)) ** 2
        r2 += ((z - dz) / (size * .93)) ** 2
        shape = np.maximum(shape, 1 - r2)
    step = np.clip((shape + swirl * .64 + fine * .30) * 1.6, 0, 1)
    extinction = 1 - np.exp(-step * (.42 if fire else .36))
    remaining = np.cumprod(1 - extinction, axis=0)
    visible = extinction * np.concatenate((np.ones_like(remaining[:1]), remaining[:-1]), axis=0)
    coverage = 1 - remaining[-1]

    # Precompute soft directional shading and keep hot cores inside cooler, turbulent edges.
    column = np.cumsum(step, axis=0)
    light = np.exp(-column * .14) * (.70 - x * .18 - y * .12)
    if fire:
        heat = np.clip(.16 + step * .62 + swirl * .34 + fine * .18 - time * .42, 0, 1)
        color = np.stack((.29 + heat * .71, .066 + heat ** 1.46 * .84, .022 + heat ** 3.2 * .80), axis=-1)
        color *= (.69 + light[..., None] * .47)
        hot_core = np.clip((step + swirl * .29 - .14) / .56, 0, 1) * (1.0 - min(1.0, time * 2.35))
        color += (np.array((1.0, .95, .76)) - color) * hot_core[..., None] * .94
    else:
        ash = np.clip((.23 + light * .61 + swirl * .19 + fine * .13), .07, .9)
        color = ash[..., None] * np.array((1.0, .97, .94))
    rgb = (visible[..., None] * color).sum(axis=0) / np.maximum(coverage[..., None], .0001)
    rgba = np.concatenate((rgb, coverage[..., None]), axis=-1)
    return Image.fromarray(np.rint(np.clip(rgba, 0, 1) * 255).astype(np.uint8))


for name, fire in (("combustion", True), ("soot", False)):
    atlas = Image.new("RGBA", (SIZE * 4, SIZE * 4))
    for i in range(16):
        atlas.paste(frame(i / 15, fire), (SIZE * (i % 4), SIZE * (i // 4)))
    atlas.save(ROOT / (name + ".webp"), lossless=True, method=5)
