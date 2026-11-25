"""Pack the licensed fireball frames for the existing short impact animation."""

import io
import sys
from pathlib import Path
from zipfile import ZipFile

import numpy as np
from PIL import Image

DESTINATION = Path(__file__).resolve().parents[1] / "assets/surface/combustion.webp"
CELL = 96

with ZipFile(sys.argv[1]) as source:
    paths = sorted(name for name in source.namelist() if name.startswith("Lave Blob/") and name.endswith(".png"))
    if len(paths) < 16:
        raise ValueError("Expected the Lave Blob sequence from fscopel's Explosions.zip")
    atlas = Image.new("RGBA", (CELL * 4, CELL * 4))
    for i, index in enumerate(np.rint(np.linspace(0, len(paths) - 1, 16)).astype(int)):
        frame = Image.open(io.BytesIO(source.read(paths[index]))).convert("RGB")
        frame.thumbnail((CELL - 8, CELL - 8), Image.Resampling.LANCZOS)
        color = np.asarray(frame, dtype=np.float32) / 255.0
        # Recover coverage from the black-backed source without carrying dark pixels into the edge.
        peak = np.max(color, axis=-1)
        coverage = np.clip((peak - 0.041) / 0.46, 0.0, 1.0)
        color /= np.maximum(coverage[..., None] ** 0.42, 0.23)
        color *= (1.0, 0.99 - 0.18 * i / 15, 0.91 - 0.21 * i / 15)
        rgba = np.dstack((np.minimum(color, 1), coverage))
        tile = Image.fromarray(np.rint(rgba * 255).astype(np.uint8))
        atlas.paste(tile, (CELL * (i % 4) + (CELL - tile.width) // 2, CELL * (i // 4) + (CELL - tile.height) // 2))
    atlas.save(DESTINATION, lossless=True, method=5)
