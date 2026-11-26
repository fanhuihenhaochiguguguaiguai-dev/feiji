"""Bake segment air density and unresolved water Fresnel response."""
from pathlib import Path

import numpy as np
from PIL import Image

target = Path(__file__).resolve().parents[1] / "assets/environment"
altitude = np.linspace(0.0, 8000.0, 128)
start, end = np.meshgrid(altitude, altitude)
air = np.zeros((*start.shape, 3))
for channel, scale in enumerate((8000.0, 1400.0)):
    delta = (end - start) / scale
    mean = np.ones_like(delta)
    np.divide(-np.expm1(-delta), delta, out=mean, where=delta != 0.0)
    air[..., channel] = mean * np.exp(-start / scale)
Image.fromarray(np.uint8(np.rint(air * 255))).save(target / "air-column.png", optimize=True)

cosine, slope = np.meshgrid(np.linspace(0.0, 1.0, 96), np.linspace(0.0, 0.32, 48))
view_x = np.sqrt(1.0 - cosine**2)
nodes, weights = np.polynomial.hermite.hermgauss(16)
reflected = np.zeros_like(cosine)
visible = np.zeros_like(cosine)
for x, wx in zip(nodes, weights, strict=True):
    for z, wz in zip(nodes, weights, strict=True):
        dx, dz = x * slope * np.sqrt(2.0), z * slope * np.sqrt(2.0)
        projected = np.maximum(0.0, cosine - view_x * dx)
        incidence = projected / np.sqrt(1.0 + dx**2 + dz**2)
        refracted = np.sqrt(1.0 - (1.0 - incidence**2) / 1.333**2)
        horizontal = (incidence - 1.333 * refracted) / (incidence + 1.333 * refracted)
        vertical = (1.333 * incidence - refracted) / (1.333 * incidence + refracted)
        weight = wx * wz * projected
        reflected += weight * 0.5 * (horizontal**2 + vertical**2)
        visible += weight
fresnel = np.ones_like(reflected)
np.divide(reflected, visible, out=fresnel, where=visible > 0.0)
Image.fromarray(np.uint8(np.rint(fresnel * 255))).save(target / "water-response.png", optimize=True)
