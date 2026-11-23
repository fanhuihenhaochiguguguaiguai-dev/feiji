from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]/'public'/'cards'
for path in root.glob('*.render.png'):
    with Image.open(path) as frame:
        frame.save(root/(path.name.removesuffix('.render.png')+'.webp'),quality=89,method=6)
    path.unlink()
