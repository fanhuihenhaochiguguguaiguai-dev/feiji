"""Convert transparent render masters to production WebP and the small wallet mark."""
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]/"public"/"items"
for path in sorted(root.glob("*.render.png")):
    key=path.name.removesuffix(".render.png")
    with Image.open(path) as source:
        frame=source.convert("RGBA")
        frame.save(root/(key+".webp"),quality=91,method=6)
        if key=="credits":
            frame=frame.crop(frame.getchannel("A").getbbox())
            frame.thumbnail((52,40),Image.Resampling.LANCZOS)
            frame.save(root/"credits-wallet.webp",quality=96,method=6)
    path.unlink()
