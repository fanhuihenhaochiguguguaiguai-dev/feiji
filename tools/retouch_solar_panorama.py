"""Remove the compact photographic disc from the flight panorama.

Input is the original day.png. The surrounding sky is kept pixel-identical.
"""

import argparse

import numpy as np
from PIL import Image


def retouch(source, destination):
    image = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
    # The compact daylight hotspot occupies x=606..612, y=119..122 in the source.
    row, column = slice(107, 135), slice(591, 629)
    crop = image[row, column].copy()
    y, x = np.mgrid[row, column]
    radius = np.sqrt(((x - 609.2) / 16.4) ** 2 + ((y - 120.1) / 9.7) ** 2)
    inside = radius < 1.0
    field = crop.copy()
    field[inside] = crop[(radius >= 1.0) & (radius < 1.25)].mean(axis=0)
    for _ in range(180):
        neighbour = sum(np.roll(field, i, axis=j) for i in (-1, 1) for j in (0, 1)) * 0.25
        field[inside] = neighbour[inside]
    feather = np.clip((1.0 - radius) * 5.0, 0.0, 1.0)[..., None]
    image[row, column] = crop + (field - crop) * feather
    Image.fromarray(np.rint(image).astype(np.uint8)).save(destination, optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original")
    parser.add_argument("destination")
    args = parser.parse_args()
    retouch(args.original, args.destination)
