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


def relief():
    dataset = SOURCES / "glacier-bay.tif"
    width, height = Image.open(dataset).size
    with tempfile.TemporaryDirectory() as folder:
        raw = Path(folder) / "survey.f32"
        subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-ot", "Float32", str(dataset), str(raw)], check=True)
        source = np.fromfile(raw, dtype="<f4").reshape(height, width)
    source = np.where(np.isfinite(source) & (np.abs(source) < 8000), source, 0.0)
    median = median_filter(source, size=5)
    source = np.where(np.abs(source - median) < 380, source, median)
    source = np.clip(source, 0, 3400)
    source = gaussian_filter(source, 1.05)
    rows, cols = np.meshgrid(*(np.linspace(0, source.shape[0] - 1, EDGE),) * 2, indexing="ij")
    ground = map_coordinates(source, (rows, cols), order=3)
    # Preserve the coastline. Water depth here is an authored approximation.
    land = ground >= 2.0
    ground = np.where(land, np.maximum(ground - 1.5, 0) * 0.48, -np.minimum(88, distance_transform_edt(~land) * 2.4))
    (OUTPUT / "bay.height").write_bytes(gzip.compress(np.rint(ground * 4).astype("<i2").tobytes(), mtime=0))
    return ground


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
    lit = np.clip((.55 * dx + .43 - .63 * dz) / strength, -.25, 1)
    cliff = 1 - 1 / strength
    colors = np.stack((.064 + cliff * .066, .10 + cliff * .067, .144 + cliff * .069), axis=-1)
    snow = np.clip((y - 470) / 155, 0, 1) * np.clip(1 - cliff * 2.75, 0, 1)
    colors = colors * (1 - snow[..., None]) + np.array((.39, .46, .51)) * snow[..., None]
    colors *= (.76 + .62 * lit[..., None])
    haze = (.17 + np.clip(radius / 12500, 0, .72))[..., None]
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


OUTPUT.mkdir(parents=True, exist_ok=True)
hangar_ridges(relief())
atmosphere_lut()
pack_surfaces()
