"""Extract the HUD art from HUD/01.webp in the supplied visual masters."""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw


# Coordinates are in the 1774 x 887 source and in the exported atlas.
REGIONS = (
    (40, 88, 456, 292), (558, 86, 1213, 160),
    (1410, 79, 1641, 288), (1611, 73, 1697, 157),
    (73, 376, 343, 503), (73, 500, 343, 610), (73, 606, 343, 734),
    (1455, 350, 1642, 512), (1385, 510, 1700, 757),
    (605, 666, 1142, 784), (480, 191, 703, 586), (1064, 190, 1287, 586),
)


def bake(source: Path, output: Path) -> None:
    rgb = Image.open(source).convert("RGB")
    if rgb.size != (1774, 887):
        raise ValueError(f"Unexpected HUD master dimensions: {rgb.size}")
    paint = ImageDraw.Draw(rgb)
    # Fill only the dynamic fields. The borders, pictograms and labels remain
    # the original pixels. The game draws the real readings over these fields.
    for bounds, color in [
        ((157, 105, 402, 136), (9, 22, 37)),
        ((318, 135, 427, 155), (11, 26, 43)),
        ((208, 165, 348, 192), (10, 27, 43)),
        ((218, 194, 348, 223), (12, 29, 45)),
        ((218, 225, 343, 249), (11, 31, 46)),
        ((94, 144, 317, 157), (14, 39, 57)),
        ((607, 103, 771, 129), (12, 24, 31)),
        ((816, 103, 985, 130), (12, 24, 32)),
        ((1090, 103, 1170, 128), (8, 15, 24)),
    ]:
        paint.rectangle(bounds, fill=color)
    for y in range(106, 177):
        for x in range(1475, 1605):
            r, g, b = rgb.getpixel((x, y))
            if r > max(g, b) * 1.43 and r > 40:
                rgb.putpixel((x, y), (8, 30, 47))
    atlas = Image.new("RGBA", rgb.size)
    for x0, y0, x1, y1 in REGIONS:
        crop = rgb.crop((x0, y0, x1, y1))
        pixels = []
        for r, g, b in crop.getdata():
            # Remove the black matte, softening only the near-black edge.
            alpha = min(255, max(0, (max(r, g, b) - 6) * 14))
            if alpha:
                pixels.append(tuple(min(255, round(c * 255 / alpha)) for c in (r, g, b)) + (alpha,))
            else:
                pixels.append((0, 0, 0, 0))
        sprite = Image.new("RGBA", crop.size)
        sprite.putdata(pixels)
        atlas.paste(sprite, (x0, y0))
    atlas.save(output, lossless=True, method=6)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    bake(args.source, args.output)
