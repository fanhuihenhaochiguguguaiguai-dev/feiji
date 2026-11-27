"""Extract interface artwork. The two new masters are used only for their assigned UI.

The original lobby art is the already registered V18.3 lobby master, with
variable labels cleared by the preceding bake. No background pixels are used
outside the bounded metal, glass and icon shapes.
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFilter


root = Path(__file__).resolve().parents[1]
refs = Path(sys.argv[1])
atlas = Image.new("RGBA", (1024, 590))
lobby = Image.open(sys.argv[2]).convert("RGB").resize((1280, 720), Image.Resampling.LANCZOS)
hangar = Image.open(next(refs.glob("01_*"))).convert("RGB").resize((1040, 468), Image.Resampling.LANCZOS)
training = Image.open(next(refs.glob("02_*"))).convert("RGB").resize((1040, 468), Image.Resampling.LANCZOS)


def stamp(source, rect, dest, shape=None):
    tile = source.crop(rect).convert("RGBA")
    if shape:
        alpha = Image.new("L", tile.size)
        ImageDraw.Draw(alpha).polygon(shape, fill=255)
        tile.putalpha(alpha.filter(ImageFilter.GaussianBlur(.60)))
    atlas.paste(tile, dest)


stamp(lobby, (0, 0, 741, 76), (0, 0), [(0,0),(740,0),(707,69),(378,69),(352,75),(35,75),(0,62)])
stamp(lobby, (744, 11, 944, 58), (0, 79), [(0,14),(14,0),(196,0),(199,43),(194,46),(0,46)])
stamp(lobby, (969, 10, 1142, 56), (202, 79), [(0,10),(13,0),(169,0),(172,44),(2,45)])
stamp(lobby, (1164, 8, 1273, 58), (378, 79), [(0,10),(12,0),(101,0),(108,6),(108,44),(100,49),(0,49)])
for i, (y, h) in enumerate(((126, 70), (204, 68), (282, 68))):
    stamp(lobby, (26, y, 259, y+h), (i*235, 130), [(0,16),(14,0),(232,0),(212,h-12),(203,h-1),(0,h-1)])
stamp(lobby, (832, 479, 1280, 576), (0, 202), [(0,96),(64,5),(430,0),(447,24),(409,96)])
for i, (x0,x1) in enumerate(((734,982),(979,1240))):
    w = x1-x0
    stamp(lobby, (x0,588,x1,646), (450+i*268,202), [(0,57),(26,2),(w-8,0),(w-1,8),(w-29,57)])
stamp(lobby, (13,539,441,652), (0, 302), [(0,19),(21,0),(398,0),(427,35),(388,112),(11,112),(0,99)])
stamp(lobby, (518,663,762,720), (433, 302), [(103,0),(126,0),(147,19),(243,23),(210,45),(126,56),(23,49),(0,22),(86,19)])

# Equipment card art from the hangar master and glyphs from the training master.
for i,x in enumerate((198, 349, 501, 654)):
    stamp(hangar, (x, 379, x+120, 414), (i*122, 419), [(7,0),(119,0),(111,34),(0,34)])
stamp(hangar, (180, 318, 224, 362), (505, 419), [(0,0),(43,0),(43,43),(0,43)])
for i, y in enumerate((105,153,198,247,295)):
    stamp(training, (744,y,829,y+40), (i*87, 460), [(10,1),(84,1),(72,39),(0,39)])
stamp(training, (744,61,1024,99), (0, 505), [(13,0),(269,0),(279,11),(279,37),(0,37),(0,12)])

# Nine-slice corners carry the blues and warm edge values sampled from the
# hangar design. The flexible centre is intentionally translucent over 3D.
draw = ImageDraw.Draw(atlas)
draw.rounded_rectangle((712,300,799,387), radius=11, fill=(8,46,68,232), outline=(79,171,206,255), width=2)
draw.rounded_rectangle((717,305,794,382), radius=8, outline=(23,102,133,255), width=1)
draw.line((722,300,741,300), fill=(241,185,96,255), width=2)
draw.line((765,387,787,387), fill=(243,190,103,255), width=2)
draw.rounded_rectangle((809,300,896,387), radius=10, fill=(83,57,25,245), outline=(247,192,99,255), width=2)
draw.rounded_rectangle((814,305,891,382), radius=7, outline=(164,103,49,255), width=1)
draw.line((826,301,874,301), fill=(255,233,176,255), width=2)
draw.line((827,386,875,386), fill=(255,224,156,255), width=2)
atlas.save(root / "assets/ui/studio-chrome.webp", lossless=True, method=6, exact=True)
