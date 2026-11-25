"""Bake the two V18.3 environment samples from the sources in assets/licenses/scenery.txt."""

import gzip
import json
import struct
import subprocess
import tempfile
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter, map_coordinates, median_filter

ROOT = Path(__file__).resolve().parent.parent
SOURCES = Path(sys.argv[1])
OUTPUT = ROOT / "assets/environment"
EDGE = 1025


def survey_heights(name, smoothing):
    dataset = SOURCES / name
    width, height = Image.open(dataset).size
    with tempfile.TemporaryDirectory() as folder:
        raw = Path(folder) / "survey.f32"
        subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-ot", "Float32", str(dataset), str(raw)], check=True)
        source = np.fromfile(raw, dtype="<f4").reshape(height, width)
    source = np.where(np.isfinite(source) & (np.abs(source) < 8000), source, 0.0)
    median = median_filter(source, size=5)
    source = np.where(np.abs(source - median) < 380, source, median)
    source = np.clip(source, 0, 3400)
    source = gaussian_filter(source, smoothing)
    rows, cols = np.meshgrid(np.linspace(0, height - 1, EDGE), np.linspace(0, width - 1, EDGE), indexing="ij")
    return map_coordinates(source, (rows, cols), order=3)


def relief():
    ground = survey_heights("glacier-bay.tif", 1.05)
    # Preserve the coastline. Water depth here is an authored approximation.
    land = ground >= 2.0
    ground = np.where(land, np.maximum(ground - 1.5, 0) * 0.48, -np.minimum(88, distance_transform_edt(~land) * 2.4))
    # Bring the main ridges up while retaining the surveyed shoreline and low islands.
    ranged = np.clip((ground - 125) / 420, 0, 1)
    battle = ground + np.maximum(ground, 0) * 0.17 * ranged * ranged * (3 - 2 * ranged)
    (OUTPUT / "bay.height").write_bytes(gzip.compress(np.rint(battle * 4).astype("<i2").tobytes(), mtime=0))
    relief_colors(battle, "bay")
    # Use the inland massif for the alpine route. The valley floor remains open at the entry.
    massif = survey_heights("alpine-relief.tif", .56)
    ridge_detail = gaussian_filter(massif, 1.15) - gaussian_filter(massif, 8.5)
    frost = 50 + np.maximum(massif * 0.72 + ridge_detail * 1.16, 0)
    world_z, world_x = np.meshgrid(np.arange(EDGE) * 24 - 6200, np.arange(EDGE) * 24 - 6250, indexing="ij")
    along = 5250 - world_z
    centre = 11450 - along * .15
    bank = np.clip((765 - np.abs(world_x - centre)) / 540, 0, 1)
    approach = np.clip((along + 1050) / 810, 0, 1) * np.clip((3100 - along) / 1580, 0, 1)
    floor = 190 + np.maximum(massif, 0) * .14 + ridge_detail * .20
    frost -= np.maximum(frost - floor, 0) * (bank * bank * (3 - 2 * bank)) * approach
    (OUTPUT / "frost.height").write_bytes(gzip.compress(np.rint(frost * 4).astype("<i2").tobytes(), mtime=0))
    relief_colors(frost, "frost")
    return ground


def relief_colors(ground, name):
    # Align this map to the clipmap lattice, using one sample every 24 meters.
    axes = np.arange(EDGE) * 24 - 6144
    x, z = np.meshgrid(axes, axes)
    height = map_coordinates(ground, ((z + 6200) / 24, (x + 6250) / 24), order=1, mode="nearest")
    shoulder = gaussian_filter(height, 5.1)
    cut = gaussian_filter(height, 1.25) - shoulder
    dz, dx = np.gradient(gaussian_filter(height, 1.25), 24)
    slope = np.clip(np.hypot(dx, dz), 0, 1)
    # An offline four-direction horizon estimate keeps recesses legible at a distance.
    padded = np.pad(height, 24, mode="edge")
    occlusion = np.zeros_like(height)
    for vx, vz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        horizon = np.zeros_like(height)
        for step in (3, 8, 24):
            col, row = 24 + vx * step, 24 + vz * step
            neighbour = padded[row:row+EDGE, col:col+EDGE]
            horizon = np.maximum(horizon, (neighbour - height) / (step * 24))
        occlusion += np.arctan(horizon)
    occlusion /= 4
    source = Image.open(SOURCES / "rock-color.jpg").convert("L").resize((192, 192), Image.Resampling.LANCZOS)
    grain = np.asarray(source, dtype=np.float32) / 255
    stratum = map_coordinates(grain, ((z / 54 + x / 290) % 192, (x / 88 - z / 218) % 192), order=1, mode="grid-wrap")
    crest = np.clip((height - 85) / 215, 0, 1) * np.clip(cut / 33 + .42, 0, 1)
    crease = np.clip(-cut / 26, 0, 1)
    sea_cliff = np.clip((height - 5) / 34, 0, 1) * np.clip((140 - height) / 90, 0, 1)
    neutral = .97 - crease * .13 - slope * (.06 + stratum * .09) + crest * .065 - occlusion * .31
    color = np.stack((neutral - crest * .05, neutral - sea_cliff * .023, neutral + crest * .049 - sea_cliff * .095), axis=-1)
    if name == "frost":
        # Broad rock exposures sit on steep faces and concave gullies. Broad slopes hold snow.
        exposed = np.clip((slope + crease * .42 + (stratum - .5) * .17 - .16) / .45, 0, 1)
        exposed = (exposed * exposed * (3 - 2 * exposed))[..., None]
        fluting = np.clip(cut / 24, -.8, .8)
        powder = np.array((.98, .99, 1.0)) * (.98 - crease * .15 + fluting * .03 - occlusion * .29)[..., None]
        # Terrain3D multiplies this map with the scan's albedo. Keep the rock tint
        # near neutral so the same albedo is not applied twice in shadow.
        schist = np.array((.89, .88, .87)) * (.82 + stratum * .17 + fluting * .09 - occlusion * .19)[..., None]
        color = powder + (schist - powder) * exposed
    boundary = np.minimum.reduce((x + 6144, 18432 - x, z + 6144, 18432 - z))
    weight = (np.clip((boundary - 1536) / 1700, 0, 1) * np.clip(height / 16, 0, 1))[..., None]
    rgb = 1 + (color - 1) * weight
    rgba = np.concatenate((rgb, np.full_like(height[..., None], .5)), axis=-1)
    pixels = np.rint(np.clip(rgba, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(pixels).save(OUTPUT / f"{name}-color.png", optimize=True)


def hangar_ridges(ground):
    axes = np.linspace(-7400, 7400, 133)
    x, z = np.meshgrid(axes, axes)
    radius = np.hypot(x, z)
    u = .68 + (.24 * x - .94 * z) / 16800
    v = .43 + (-.94 * x - .24 * z) / 16800
    source = map_coordinates(ground, (np.clip(v, 0, 1) * (EDGE - 1), np.clip(u, 0, 1) * (EDGE - 1)), order=1)
    y = np.maximum(source, -25) * 0.96 - 105
    flatten = np.clip((radius - 235) / 480, 0, 1)
    y = -1.4 * (1 - flatten) + y * flatten
    y -= np.clip((radius - 6500) / 1300, 0, 1) * 180
    dz, dx = np.gradient(y, axes, axes)
    strength = np.sqrt(1 + dx * dx + dz * dz)
    # Match the runway key light and bake the occlusion of the opposite side of each ridge.
    lit = np.maximum(0, (-.47 * dx + .11 - .876 * dz) / strength)
    oy, ox = np.indices(y.shape)
    horizon = np.zeros_like(y)
    for distance in (120, 315, 650, 1150, 2200):
        stride = distance / (axes[1] - axes[0])
        towards_sun = map_coordinates(y, (oy + .876 * stride, ox + .47 * stride), order=1, mode="nearest")
        horizon = np.maximum(horizon, (towards_sun - y) / distance)
    sun_visibility = np.clip((0.18 - horizon) / .12, 0, 1)
    cliff = 1 - 1 / strength
    colors = np.stack((.064 + cliff * .066, .10 + cliff * .067, .144 + cliff * .069), axis=-1)
    snow = np.clip((y - 470) / 155, 0, 1) * np.clip(1 - cliff * 2.75, 0, 1)
    colors = colors * (1 - snow[..., None]) + np.array((.39, .46, .51)) * snow[..., None]
    colors *= .72 + (lit * sun_visibility)[..., None] * np.array((.91, .70, .46))
    haze = (1 - .85 * np.exp(-radius / 9300))[..., None]
    colors = colors * (1 - haze) + np.array((.19, .237, .28)) * haze
    colors = np.where((source < 0)[..., None], np.array((.092, .135, .165)), colors)
    positions = np.stack((x, y, z), axis=-1).astype("<f4").reshape(-1, 3)
    rgba = np.concatenate((colors, np.ones_like(x)[..., None]), axis=-1)
    rgba = np.rint(np.clip(rgba, 0, 1) * 255).astype(np.uint8).reshape(-1, 4)
    # The proxy needs no runtime terrain or lightmap generation.
    i = np.arange(len(axes) ** 2, dtype=np.uint16).reshape(x.shape)
    a, b, c, d = i[:-1, :-1], i[:-1, 1:], i[1:, :-1], i[1:, 1:]
    indices = np.stack((a, c, b, b, c, d), axis=-1).astype("<u2").flatten()
    chunks = [positions.tobytes(), rgba.tobytes(), indices.tobytes()]
    mesh = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0, "name": "Baked airfield ridges"}],
            "extensionsUsed": ["KHR_materials_unlit"],
            "materials": [{"extensions": {"KHR_materials_unlit": {}}, "doubleSided": True}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}, "indices": 2, "material": 0}]}],
            "buffers": [{"byteLength": sum(map(len, chunks))}],
            "bufferViews": [{"buffer": 0, "byteOffset": sum(map(len, chunks[:k])), "byteLength": len(c)} for k, c in enumerate(chunks)],
            "accessors": [
                {"bufferView": 0, "componentType": 5126, "count": len(positions), "type": "VEC3", "min": positions.min(axis=0).tolist(), "max": positions.max(axis=0).tolist()},
                {"bufferView": 1, "componentType": 5121, "count": len(rgba), "type": "VEC4", "normalized": True},
                {"bufferView": 2, "componentType": 5123, "count": len(indices), "type": "SCALAR"}]}
    header = json.dumps(mesh, separators=(",", ":")).encode()
    header += b" " * ((-len(header)) % 4)
    binary = b"".join(chunks)
    binary += b"\0" * ((-len(binary)) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(binary))
    glb += struct.pack("<I4s", len(header), b"JSON") + header + struct.pack("<I4s", len(binary), b"BIN\0") + binary
    (OUTPUT / "airfield-ridges.glb").write_bytes(glb)


def atmosphere_lut():
    # Integrate exponential air and aerosol density along rays at a representative flight altitude.
    elevation = np.linspace(0, 1, 48)
    radius = 6_371_000
    origin = radius + 1300
    ray_end = -origin * elevation + np.sqrt((origin * elevation) ** 2 + (radius + 80000) ** 2 - origin ** 2)
    t = np.linspace(0, 1, 80) ** 1.7
    distance = ray_end[:, None] * t
    height = np.sqrt(origin ** 2 + distance ** 2 + 2 * origin * distance * elevation[:, None]) - radius
    air = np.trapezoid(np.exp(-height / 8000), distance, axis=1)
    mist = np.trapezoid(np.exp(-height / 1400), distance, axis=1)
    extinction = air[:, None] * np.array((5.8, 13.5, 33.1)) * 1e-6 + mist[:, None] * 1.4e-5
    scattering = 1 - np.exp(-extinction)
    angle = np.linspace(-1, 1, 64)
    phase = .72 + .28 * (angle * angle) + .16 * np.clip(angle, 0, 1) ** 7
    rgb = scattering[:, None, :] * phase[None, :, None]
    Image.fromarray(np.rint(np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(OUTPUT / "air-scattering.png", optimize=True)


def pack_surfaces():
    for kind in ("rock", "sand"):
        for color in (True, False):
            path = SOURCES / (f"{kind}-color.jpg" if color else f"{kind}-normal.png")
            texture = Image.open(path).convert("RGBA")
            source = SOURCES / (f"{kind}-displacement.png" if color else f"{kind}-rough.png")
            data = np.array(Image.open(source))
            if color:
                lower, upper = np.percentile(data, (3, 97))
                channel = np.uint8(np.clip((data - lower) / max(1, upper - lower), 0, 1) * 171 + 36)
                alpha = Image.fromarray(channel).convert("L")
            else:
                alpha = Image.open(source).convert("L")
            texture.putalpha(alpha.resize(texture.size, Image.Resampling.LANCZOS))
            texture.save(OUTPUT / f"{kind}-{'height' if color else 'rough'}.webp", lossless=True, method=5)
            if kind == "sand" and color:
                # Powdered gravel gives the snowfield a granular profile without adding a normal map.
                gray = np.array(texture.convert("L").resize((512, 512), Image.Resampling.LANCZOS), dtype=np.float32)
                snow = (.72 + gray / 255 * .25)[..., None] * np.array((.96, .982, 1.0))
                powder = Image.fromarray(np.rint(snow * 255).astype(np.uint8)).convert("RGBA")
                powder.putalpha(alpha.resize(powder.size, Image.Resampling.LANCZOS))
                powder.resize(texture.size, Image.Resampling.LANCZOS).save(OUTPUT / "snow-height.webp", lossless=True, method=5)


OUTPUT.mkdir(parents=True, exist_ok=True)
hangar_ridges(relief())
atmosphere_lut()
pack_surfaces()
