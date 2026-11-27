"""Bake space-filling cumulus density and three theatre sunlight fields."""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter, map_coordinates, maximum_filter

ASSET = Path(__file__).resolve().parents[1] / "assets/environment/battle-clouds.png"
WIDTH, DEPTH, SLICES = 128, 96, 48
PERIOD_X, PERIOD_Z = 24.0, 18.0  # kilometres
SUN = ((-.88, .31, -.36), (-.74, .59, .33), (.50, .218, -.84))
RNG = np.random.default_rng(18314)

layer, row, column = np.mgrid[:SLICES, :DEPTH, :WIDTH].astype(np.float32)
x = (column + .5) / WIDTH * PERIOD_X
z = (row + .5) / DEPTH * PERIOD_Z
y = layer / (SLICES - 1)
# Preserve empty space as well as the occupied lobes. Starting at the
# surface value would turn positive detail noise into a map-wide fog layer.
bank = np.full_like(x, -1.0)


def noise(size):
    """Smooth, periodically tiled detail at a particular spatial frequency."""
    grid = RNG.random(size).astype(np.float32) - .5
    coordinates = (y * (size[0] - 1), z / PERIOD_Z * size[1], x / PERIOD_X * size[2])
    return map_coordinates(grid, coordinates, order=3, mode="grid-wrap")


def bubble(cx, cz, cy, rx, rz, ry):
    dx = (x - cx + PERIOD_X * .5) % PERIOD_X - PERIOD_X * .5
    dz = (z - cz + PERIOD_Z * .5) % PERIOD_Z - PERIOD_Z * .5
    radius = np.sqrt((dx / rx) ** 2 + (dz / rz) ** 2 + ((y - cy) / ry) ** 2)
    np.maximum(bank, 1.0 - radius, out=bank)


# Designed breaks between cloud groups leave open blue sky and clear flight
# corridors. Each family's lobes share a base and taper into separate towers.
centres = [
    (10.1, .8, 1.6, 1.0), (14.3, 2.3, 1.0, .8),
    (6.8, 15.7, 2.0, 1.4), (13.8, 12.3, 1.7, 1.8),
    (2.7, 4.3, 1.3, .9), (6.1, 7.6, 1.0, .85),
    (18.8, 6.1, 2.0, 1.4), (21.7, 14.5, 1.4, 1.05),
    (3.5, 12.3, 1.4, 1.0), (21.4, 2.3, 1.7, 1.1),
    (15.9, 8.2, 1.1, .85), (9.9, 9.6, 1.7, .8),
]
for cx, cz, rx, rz in centres:
    bubble(cx, cz, .23, rx, rz, RNG.uniform(.19, .30))
    for _ in range(9):
        dx, dz = RNG.uniform(-.76, .76, 2)
        cy = RNG.uniform(.24, .63) - .11 * min(1.0, abs(dx) + abs(dz))
        bubble(cx + dx * rx, cz + dz * rz, cy, rx * RNG.uniform(.28, .55),
               rz * RNG.uniform(.32, .64), RNG.uniform(.10, .25))

edge = .27 * noise((9, 22, 28)) + .13 * noise((19, 48, 64)) + .07 * noise((29, 76, 108))
density = np.clip((bank + edge) / .44, 0.0, 1.0)
density = gaussian_filter(density * density * (3.0 - 2.0 * density),
                          (.42, .28, .28), mode=("nearest", "wrap", "wrap"))
density *= np.clip(y / .083, 0.0, 1.0) * np.clip((1.0 - y) / .13, 0.0, 1.0)


def sunlight(direction, thickness):
    """Integrate the density along a theatre light direction before export."""
    v = np.asarray(direction)
    v /= np.linalg.norm(v)
    optical_depth = np.zeros_like(density)
    distance = 0.0
    for step in (.08, .11, .14, .18, .23, .29, .36, .48, .65, .88, 1.18):
        mid = distance + step * .5
        altitude = layer + v[1] * mid * (SLICES - 1) / thickness
        grid = (np.clip(altitude, 0, SLICES - 1),
                row + v[2] * mid * DEPTH / PERIOD_Z,
                column + v[0] * mid * WIDTH / PERIOD_X)
        optical_depth += map_coordinates(density, grid, order=1, mode="grid-wrap") * step
        distance += step
    return np.exp(-optical_depth * 3.35)


channels = [density, *(sunlight(v, thickness) for v, thickness in zip(SUN, (2.16, 2.27, 2.50)))]
voxels = np.rint(np.stack(channels, axis=-1) * 255).astype(np.uint8)
atlas = voxels.reshape(6, 8, DEPTH, WIDTH, 4).transpose(0, 2, 1, 3, 4).reshape(6 * DEPTH, 8 * WIDTH, 4)
image = Image.new("RGBA", (atlas.shape[1], atlas.shape[0] + DEPTH))
image.paste(Image.fromarray(atlas, "RGBA"))

# Conservative horizontal free distance for ray skipping. Periodic padding
# keeps jumps consistent across tiled weather cells and floating origins.
occupied = density > .004
empty = np.tile(~occupied.any(axis=0), (3, 3))
spacing = (PERIOD_Z / DEPTH, PERIOD_X / WIDTH)
distance = distance_transform_edt(empty, sampling=spacing)[DEPTH:2 * DEPTH, WIDTH:2 * WIDTH]
distance = np.clip((distance - 1.65 * np.hypot(*spacing)) / 4.0, 0.0, 1.0)
# Expand the height envelope horizontally and vertically so an empty-height
# jump cannot cross a nearby bank, even after trilinear density filtering.
envelope = maximum_filter(occupied, size=(5, 5, 5), mode=("nearest", "wrap", "wrap"))
base = np.min(np.where(envelope, y, 1.0), axis=0)
top = np.max(np.where(envelope, y, 0.0), axis=0)
bounds = np.stack((np.floor(distance * 255), np.floor(base * 255), np.ceil(top * 255)), axis=-1)
image.paste(Image.fromarray(np.uint8(bounds)).convert("RGBA"), (0, atlas.shape[0]))
image.save(ASSET, optimize=True)
