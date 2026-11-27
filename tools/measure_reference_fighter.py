"""Isolate the aircraft in the four supplied contact sheets for offline fitting.

Requires Pillow, NumPy, SciPy and torchvision. Run once on the Aircraft folder
and keep the measurements as authoring inputs for refine_reference_fighter.py.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
import torch
from torchvision.models.segmentation import (
    LRASPP_MobileNet_V3_Large_Weights,
    lraspp_mobilenet_v3_large,
)


VIEWS = {
    "quarter": ("01", (100, 0, 1620, 345)),
    "side": ("02", (22, 298, 833, 584)),
    "front": ("02", (846, 0, 1663, 285)),
    "rear": ("02", (852, 312, 1656, 592)),
    "top": ("02", (8, 598, 835, 916)),
    "carrier": ("03", (0, 89, 884, 517)),
    "surface": ("04", (60, 5, 1605, 376)),
}
LUMA = np.array([.2126, .7152, .0722])


def measure(source: Path, output: Path):
    weights = LRASPP_MobileNet_V3_Large_Weights.COCO_WITH_VOC_LABELS_V1
    preprocess = weights.transforms()
    model = lraspp_mobilenet_v3_large(weights=weights).eval()
    output.mkdir(parents=True, exist_ok=True)
    for view, (file, box) in VIEWS.items():
        with Image.open(source / f"{file}.webp") as image:
            crop = image.convert("RGB").crop(box)
        preview = crop.copy()
        preview.thumbnail((475, 143))
        with torch.inference_mode():
            probability = model(preprocess(preview)[None])["out"].softmax(1)[0, 1].numpy()
        heatmap = Image.fromarray((probability * 255).astype("uint8"))
        confidence = np.array(heatmap.resize(crop.size, Image.Resampling.BILINEAR))
        components, found = ndimage.label(confidence > 88)
        if found == 0:
            raise ValueError(f"{view}: no aircraft detected")
        counts = np.bincount(components.ravel())
        counts[0] = 0
        core = components == counts.argmax()
        tone = np.asarray(crop) @ LUMA / 255.
        neighborhood = ndimage.binary_dilation(core, iterations=16)
        edges = ndimage.binary_propagation(core & (tone < .46), mask=(tone < .54) & neighborhood)
        mask = ndimage.binary_fill_holes(core | edges)
        np.savez_compressed(output / f"{view}.npz", mask=mask, probability=confidence)
        crop.save(output / f"{view}.png")


if __name__ == "__main__":
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("source", type=Path)
    args.add_argument("output", type=Path)
    options = args.parse_args()
    measure(options.source, options.output)
