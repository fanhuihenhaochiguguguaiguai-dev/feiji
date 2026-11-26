"""Bake the game's turbulent wreck smoke to a two-channel volume atlas.

Run with NumPy, SciPy and Pillow. Rendering only samples the baked density
and visibility. The flow field and the advection solver run offline.
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, maximum_filter, minimum_filter, zoom

SIZE = 48
FRAMES = 11
FRAME_STEPS = 8
DT = 0.035
TILE_COLUMNS = 12
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "surface" / "wreck-smoke.png"
GRID = np.indices((SIZE, SIZE, SIZE), dtype=np.float32)
Z, Y, X = GRID / (SIZE - 1) - 0.5


def noise(rng, cells):
    lattice = rng.standard_normal((cells, cells, cells)).astype(np.float32)
    return zoom(lattice, SIZE / cells, order=3, mode="reflect")


def curl_field(rng):
    az, ay, ax = (noise(rng, 7) for _ in range(3))
    return 0.10 * np.stack((
        np.gradient(ay, axis=2) - np.gradient(ax, axis=1),
        np.gradient(ax, axis=0) - np.gradient(az, axis=2),
        np.gradient(az, axis=1) - np.gradient(ay, axis=0),
    ))


def wind(age, curl):
    # Upward flow bends outward at the head, rolls over the rim and folds back into the plume.
    centre_x = 0.035 * np.sin(age * 2.0) - 0.011
    centre_z = 0.028 * np.sin(age * 2.75 + 0.7)
    dx, dz = X - centre_x, Z - centre_z
    radius = np.maximum(0.001, np.sqrt(dx * dx + dz * dz))
    heading = np.arctan2(dz, dx)
    rise = Y - (-0.255 + age * 0.169 + 0.037 * np.sin(2 * heading + age * 1.6))
    rim = radius - (0.093 + age * 0.047 + 0.027 * np.cos(3 * heading - age * 1.3))
    roll = 3.20 * np.exp(-((rim / 0.115) ** 2 + (rise / 0.128) ** 2)) * np.exp(-age * 0.30)
    throat = np.exp(-(radius / (0.21 + age * 0.038)) ** 2)
    spread = 0.18 * np.exp(-age * 0.58)
    twist = 0.34 * np.sin(Y * 11.0 + age * 1.6) * throat
    return np.stack((
        dz * spread + dz / radius * rise * roll + dx * twist - age * 0.008,
        0.128 + 0.068 * throat - rim * roll,
        dx * spread + dx / radius * rise * roll - dz * twist + age * 0.011,
    )) + curl


def advect(field, velocity):
    delta = velocity * (DT * (SIZE - 1))
    carried = map_coordinates(field, GRID - delta, order=1, prefilter=False)
    returned = map_coordinates(carried, GRID + delta, order=1, prefilter=False)
    # Compensate interpolation diffusion without letting it create new extrema.
    corrected = carried + (field - returned) * 0.5
    return np.clip(corrected, minimum_filter(field, size=3), maximum_filter(field, size=3))


def build_billows(rng):
    # Vary the entrainment cells around the updraft so one regular rim never dominates.
    billows = []
    for i in range(13):
        heading = i * 2.399963 + rng.uniform(-0.27, 0.25)
        rising = i < 9
        lift = rng.uniform(0.34, 0.58) if rising else rng.uniform(0.08, 0.26)
        spread = rng.uniform(0.13, 0.265) if rising else rng.uniform(0.07, 0.18)
        width = rng.uniform(0.103, 0.169) if rising else rng.uniform(0.086, 0.137)
        onset = rng.uniform(0.01, 0.23) if i < 6 else rng.uniform(0.13, 0.66)
        billows.append((heading, lift, spread, width, onset, rng.uniform(-1.20, 1.22), rng.uniform(0.0, 6.28)))
    return billows


def billow_density(age, billows, detail):
    smoke = np.zeros_like(X)
    for heading, lift, spread, width, onset, rotation, phase in billows:
        born = age - onset
        if born <= 0.0:
            continue
        growth = 1.0 - np.exp(-born * 1.38)
        expansion = 1.0 - np.exp(-born * 1.08)
        heading += rotation * growth
        drift = 0.04 + spread * expansion
        cx = np.cos(heading) * drift + 0.029 * np.sin(born * 3.2 + phase)
        cy = -0.335 + lift * (1.0 - np.exp(-born * 1.21)) + 0.023 * np.sin(born * 4.1 + phase)
        cz = np.sin(heading) * drift * 0.78 + 0.031 * np.cos(born * 2.5 + phase)
        radius = 0.034 + width * growth
        dx = (X - cx) / radius
        dy = (Y - cy) / (radius * (0.77 + 0.20 * np.sin(phase) + 0.20 * growth))
        dz = (Z - cz) / (radius * (0.89 + 0.14 * np.cos(phase)))
        rotor = 1.23 * born + phase
        u = dx * np.cos(rotor) + dy * np.sin(rotor)
        v = dy * np.cos(rotor) - dx * np.sin(rotor)
        warp = np.sin(u * 4.7 + dz * 2.9 + phase) * np.cos(v * 4.1 - dz * 3.5)
        warp += 0.36 * np.sin(v * 9.9 + u * 7.5 - dz * 7.0 - phase)
        distance = np.sqrt(dx * dx + dy * dy + dz * dz) + warp * 0.17
        weight = np.clip((1.13 - distance) * 1.55, 0.0, 1.0) ** 1.25
        weight *= min(1.0, born * 3.1) * np.exp(-born * 0.22)
        smoke = np.maximum(smoke, weight * detail)
    return smoke


def visibility(field):
    # One upper side of each billow catches light, while overlapping pockets absorb it.
    depth = np.zeros_like(field)
    for step in range(1, 19):
        sunlight = np.array([0.27, 0.89, 0.37], dtype=np.float32)[:, None, None, None] * step
        depth += map_coordinates(field, GRID + sunlight, order=1, prefilter=False)
    return np.exp(-depth * 0.165)


def bake():
    rng = np.random.default_rng(183073)
    curl = curl_field(rng)
    billows = build_billows(rng)
    texture = np.clip(noise(rng, 16) * 0.30 + noise(rng, 27) * 0.13 + 0.80, 0.19, 1.22)
    source = np.zeros_like(X)
    for cx, cy, cz, sx, sy, sz, density in [
        (-0.02, -0.323, 0.005, 0.088, 0.069, 0.079, 1.0),
        (0.073, -0.304, 0.043, 0.070, 0.062, 0.057, 0.78),
        (-0.085, -0.278, -0.043, 0.065, 0.068, 0.060, 0.89),
        (0.007, -0.226, -0.039, 0.057, 0.062, 0.055, 0.64),
    ]:
        distance = ((X - cx) / sx) ** 2 + ((Y - cy) / sy) ** 2 + ((Z - cz) / sz) ** 2
        source = np.maximum(source, np.maximum(1.0 - distance * 0.40, 0.0) ** 1.45 * density)
    source *= texture
    wall = np.clip(np.minimum.reduce([0.49 - np.abs(X), 0.49 - np.abs(Y), 0.49 - np.abs(Z)]) * 16.0, 0, 1)
    field = source * 0.43
    all_tiles = FRAMES * SIZE
    atlas = np.zeros(((all_tiles + TILE_COLUMNS - 1) // TILE_COLUMNS * SIZE, TILE_COLUMNS * SIZE, 3), dtype=np.uint8)

    for step in range((FRAMES - 1) * FRAME_STEPS + 1):
        age = step * DT
        if step > 0:
            field = advect(field, wind(age, curl)) * (wall * 0.995)
            if age < 0.58:
                field += source * (0.19 * np.exp(-age * 2.4))
        if step % FRAME_STEPS:
            continue
        frame = step // FRAME_STEPS
        smoke = (field * 0.57 + billow_density(age, billows, texture) * 0.88) * wall
        density = np.clip((smoke - 0.043) * 1.72, 0.0, 1.0)
        shade = visibility(smoke)
        for layer in range(SIZE):
            tile = frame * SIZE + layer
            row, column = divmod(tile, TILE_COLUMNS)
            target = atlas[row * SIZE:(row + 1) * SIZE, column * SIZE:(column + 1) * SIZE]
            target[..., 0] = np.rint(density[layer] * 255).astype(np.uint8)
            target[..., 1] = np.rint(shade[layer] * 255).astype(np.uint8)
        print(f"{age:.2f}s: {int((density > 0.15).sum())} dense cells")
    Image.fromarray(atlas).save(OUTPUT, optimize=True)


if __name__ == "__main__":
    bake()
