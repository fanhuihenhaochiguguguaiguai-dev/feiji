"""Split the supplied Skyblade masters into clean plates and a lossless UI atlas."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("masters", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / "assets"
canvas = 1280, 720
boot, battle, lobby = [Image.open(args.masters / name).convert("RGB") for name in
                       ("01_splash.png", "02_battle_loading.png", "03_lobby.png")]
width, height = boot.size
if any(image.size != (1672, 941) for image in (boot, battle, lobby)):
    raise SystemExit("All three masters must have their original 1672 × 941 pixels")


def point(x, y):
    return round(x * width / canvas[0]), round(y * height / canvas[1])


def box(x, y, right, bottom):
    return (*point(x, y), *point(right, bottom))


def save_lossless(image, path):
    image.save(path, lossless=True, method=6, exact=True)


def erase(image, area):
    """Interpolate between uninterrupted plate pixels at the top and bottom of text."""
    x0, y0, x1, y1 = area
    surrounding = np.asarray(image.crop((x0 - 3, y0 - 3, x1 + 3, y1 + 3))).astype(float)
    top = surrounding[:3, 3:-3].mean(axis=0)
    bottom = surrounding[-3:, 3:-3].mean(axis=0)
    t = np.linspace(0, 1, y1 - y0)[:, None, None]
    patch = Image.fromarray(np.rint(top * (1 - t) + bottom * t).astype(np.uint8))
    feather = Image.new("L", patch.size)
    ImageDraw.Draw(feather).rectangle((2, 2, patch.width - 3, patch.height - 3), fill=255)
    image.paste(patch, (x0, y0), feather.filter(ImageFilter.GaussianBlur(1.0)))


def neutralize_bar(image, area, empty_x):
    """Continue the original empty track across the reference's pre-filled part."""
    x0, y0, x1, y1 = box(*area)
    sx, _ = point(empty_x, 0)
    strip = image.crop((sx, y0, sx + 1, y1)).resize((x1 - x0, y1 - y0))
    image.paste(strip, (x0, y0))


atlas = Image.new("RGBA", (704, 224))
entries = [
    (boot, (443, 667, 618, 680), (0, 0), (350, 26)),
    (battle, (300, 562, 806, 597), (0, 28), (704, 49)),
    (battle, (358, 466, 575, 517), (0, 83), (217, 51)),
    (battle, (359, 523, 515, 550), (218, 83), (156, 27)),
    (lobby, (910, 18, 930, 46), (376, 83), (20, 28)),
    (lobby, (1073, 16, 1130, 47), (397, 83), (57, 31)),
    (lobby, (157, 557, 355, 598), (0, 135), (198, 41)),
    (lobby, (161, 605, 269, 633), (198, 135), (108, 28)),
]
for image, area, origin, size in entries:
    atlas.paste(image.crop(box(*area)).resize(size, Image.Resampling.LANCZOS), origin)

neutralize_bar(boot, (443, 665, 640, 683), 663)
boot.save(root / "boot/splash.png", optimize=True)
empty_cap = battle.crop(box(951, 563, 972, 597)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
neutralize_bar(battle, (299, 563, 819, 597), 836)
battle.paste(empty_cap, point(298, 563))
for area in ((354, 463, 579, 519), (354, 520, 521, 553)):
    erase(battle, box(*area))
save_lossless(battle, root / "loading/alpine.webp")

save_lossless(atlas, root / "ui/reference-atlas.webp")
