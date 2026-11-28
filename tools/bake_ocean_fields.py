"""Bake periodic capillary slopes and two independently varying sea-state fields."""
from pathlib import Path

import numpy as np
from PIL import Image


size = 128
rng = np.random.default_rng(8193)
x, z = np.meshgrid(np.fft.rfftfreq(size) * size, np.fft.fftfreq(size) * size)
along = x * .86 - z * .51
across = x * .51 + z * .86
frequency = np.hypot(along, across * 1.65)
capillary = np.fft.rfft2(rng.standard_normal((size, size))) * (
    np.exp(-.5 * ((frequency - 12.0) / 6.0) ** 2) / np.maximum(frequency, 1.0)
)


def slope(axis):
    gradient = np.fft.irfft2(capillary * (2j * np.pi * axis), s=(size, size), axes=(0, 1))
    return .5 + gradient * (.155 / gradient.std())


def group(peak, stretch):
    frequency = np.hypot(along, across * stretch)
    field = np.fft.rfft2(rng.standard_normal((size, size)))
    band = np.exp(-.5 * ((frequency - peak) / max(1., peak * .37)) ** 2)
    state = np.fft.irfft2(field * band, s=(size, size), axes=(0, 1))
    state -= state.mean()
    return .5 + state * (.192 / state.std())


packed = np.stack((slope(x), slope(z), group(2.8, 2.1), group(4.9, .78)), axis=-1)
data = np.uint8(np.rint(np.clip(packed, 0.0, 1.0) * 255))
target = Path(__file__).resolve().parents[1] / "assets/environment/ocean-fields.png"
Image.fromarray(data).save(target, optimize=True)
