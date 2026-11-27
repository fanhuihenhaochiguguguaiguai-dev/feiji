"""Measure screenshots from qa/reference_ui.gd against the supplied immutable masters.

Dependencies: Pillow, numpy, scipy, scikit-image, torch/torchvision (CPU), lpips.
The first run uses the standard LPIPS AlexNet weights from the PyTorch model cache.
"""
import argparse
from hashlib import sha256
import json
from pathlib import Path

import lpips
import numpy as np
import torch
from PIL import Image, ImageDraw
from skimage.color import deltaE_ciede2000, rgb2lab
from skimage.metrics import structural_similarity


SCREENS = ("01_splash", "02_battle_loading", "03_lobby")
SIZE = (1672, 941)
MASTERS = {
    "01_splash": "678091087ce4cf766e19a505e404625aa0dc678694fd0293508ae73c1f4c9fd1",
    "02_battle_loading": "4c029e4ed1304d3598ebdeeb4f412a6681667bcf9166f794abe0232fecc42d18",
    "03_lobby": "0de153cdbedeb28a598f2dbe2c19c351fb936e51833c1d8ed588b3433859e406",
}
# The only exclusion in the static gate is the authored footprint of the moving aircraft,
# its reflection and its contact shadow. It is also measured as an independent region.
AIRCRAFT = [(247, 441), (268, 347), (319, 338), (323, 229), (378, 229), (491, 320),
            (532, 308), (755, 300), (801, 293), (850, 286), (895, 294), (928, 308),
            (1054, 310), (1056, 339), (973, 354), (919, 390), (908, 442),
            (847, 483), (738, 515), (606, 538), (455, 537), (335, 529), (245, 500), (218, 472)]
BUTTONS = {"lobby": [29, 128, 226, 64], "hangar": [28, 206, 228, 63], "campaign": [28, 283, 228, 63],
           "pilot": [745, 13, 197, 42], "settings": [1165, 10, 105, 45], "start": [846, 483, 431, 90],
           "training": [737, 591, 242, 52], "free": [982, 591, 255, 52]}
REGIONS = {
    "01_splash": {"airscape": (0, 0, 1280, 380), "emblem_and_title": (340, 375, 940, 615),
                  "progress_track": (438, 654, 842, 691)},
    "02_battle_loading": {"airscape": (0, 0, 1280, 389), "mission_panel": (218, 392, 1057, 646),
                           "progress_track": (287, 555, 979, 607)},
    "03_lobby": {"header": (0, 0, 1280, 76), "navigation": (0, 112, 260, 351),
                 "carrier": (275, 80, 1280, 491), "sortie_controls": (734, 477, 1280, 651),
                 "aircraft_card": (15, 538, 444, 657)},
}


def aircraft_mask():
    mask = Image.new("L", SIZE)
    ImageDraw.Draw(mask).polygon([(round(x * SIZE[0] / 1280), round(y * SIZE[1] / 720))
                                  for x, y in AIRCRAFT], fill=255)
    return np.asarray(mask) != 0


def compare(master, frame, net):
    assert master.size == frame.size == SIZE, "Capture must match the unmodified master resolution"
    source = np.asarray(master.convert("RGB"), dtype=np.float32) / 255
    actual = np.asarray(frame.convert("RGB"), dtype=np.float32) / 255
    _, ssim = structural_similarity(source, actual, data_range=1, channel_axis=-1, gaussian_weights=True, full=True)
    lab = deltaE_ciede2000(rgb2lab(source), rgb2lab(actual))
    # A weight map on the computed features keeps the unchanged reference pixels as input.
    tensors = [torch.from_numpy(a.transpose((2, 0, 1))).unsqueeze(0) * 2 - 1 for a in (source, actual)]
    with torch.no_grad():
        distances = net(*tensors).squeeze().numpy()
    return ssim.mean(axis=-1), lab, distances, np.max(abs(source - actual), axis=-1)


def measurements(metrics, mask):
    ssim, lab, lp, rgb = [m[mask] for m in metrics]
    return {"ssim": round(float(ssim.mean()), 5), "lpips_alex": round(float(lp.mean()), 5),
            "mean_delta_e_2000": round(float(lab.mean()), 4), "p95_delta_e_2000": round(float(np.quantile(lab, 0.95)), 4),
            "exact_rgb_fraction": round(float(np.mean(rgb == 0)), 5)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("masters", type=Path)
    parser.add_argument("screenshots", type=Path)
    options = parser.parse_args()
    torch.set_num_threads(4)
    for screen, digest in MASTERS.items():
        path = options.masters / f"{screen}.png"
        if sha256(path.read_bytes()).hexdigest() != digest:
            parser.error(f"{path.name} differs from the supplied master")
    net = lpips.LPIPS(net="alex", spatial=True, verbose=False).eval()
    static = np.ones(SIZE[::-1], dtype=bool)
    dynamic = aircraft_mask()
    results = {}
    for screen in SCREENS:
        with Image.open(options.masters / f"{screen}.png") as master, Image.open(options.screenshots / f"{screen}.png") as frame:
            maps = compare(master, frame, net)
        foreground = screen == "03_lobby"
        mask = ~dynamic if foreground else static
        result = measurements(maps, mask)
        result["pass"] = result["ssim"] >= 0.97 and result["lpips_alex"] <= 0.03
        if foreground:
            result["static_fraction"] = round(float(np.mean(~dynamic)), 5)
            result["live_aircraft_region"] = measurements(maps, dynamic)
            result["full_frame"] = measurements(maps, static)
        regions = {}
        for name, (left, top, right, bottom) in REGIONS[screen].items():
            x0, x1 = (round(x * SIZE[0] / 1280) for x in (left, right))
            y0, y1 = (round(y * SIZE[1] / 720) for y in (top, bottom))
            area = np.s_[y0:y1, x0:x1]
            regions[name] = measurements([m[area] for m in maps], mask[area])
        result["regions"] = regions
        results[screen] = result
    layout = json.loads((options.screenshots / "layout.json").read_text())
    deviations = {name: max(abs(got - ref) / axis for got, ref, axis in zip(layout[name], target, (1280, 720, 1280, 720)))
                  for name, target in BUTTONS.items()}
    report = {"screens": results, "button_worst_deviation_percent": 100 * max(deviations.values()),
              "static_gate_pass": all(x["pass"] for x in results.values()) and max(deviations.values()) <= 0.005}
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return not report["static_gate_pass"]


if __name__ == "__main__":
    raise SystemExit(main())
