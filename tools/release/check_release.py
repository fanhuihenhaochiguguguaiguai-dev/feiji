"""Compare the stock release, custom release and the template embedded in it."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
from zipfile import ZipFile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("stock", type=Path)
parser.add_argument("built", type=Path)
parser.add_argument("template", type=Path)
args = parser.parse_args()
godot_library = "lib/arm64-v8a/libgodot_android.so"

with ZipFile(args.stock) as stock, ZipFile(args.built) as built, ZipFile(args.template) as template:
    assert built.testzip() is None
    entries = set(built.namelist())
    assert len(entries) == len(built.namelist())
    elf = built.read(godot_library)
    assert elf == template.read(godot_library), "export did not embed the custom engine"
    assert len(elf) < stock.getinfo(godot_library).file_size, "custom ELF is not smaller"
    assert args.built.stat().st_size < args.stock.stat().st_size, "custom APK is not smaller"
    assert "assets/assets/boot/splash.png" in entries
    assert "assets/assets/environment/frost.snow" in entries
    assert {"lib/arm64-v8a/libskyterrain.android.arm64.so",
            "lib/arm64-v8a/libterrain.android.release.arm64.so"}.issubset(entries)
    campaign = json.loads(built.read("assets/assets/campaign.json"))
    for aircraft in campaign["fleet"]:
        assert f'assets/assets/fleet/{aircraft["id"]}.glb.import' in entries, aircraft["id"]
    for theatre in campaign["theatres"]:
        seed = theatre["seed"]
        assert f"assets/assets/environment/world-{seed}.scn" in entries, seed
        assert f"assets/assets/environment/detail-{seed}.terrainpack" in entries, seed
    for shader in ("fft_butterfly", "fft_compute", "fft_unpack", "spectrum_compute", "spectrum_modulate", "transpose"):
        assert f"assets/addons/ocean_waves/compute/{shader}.glsl.import" in entries, shader
    assert not any(path.startswith(("assets/qa/", "assets/tools/")) for path in entries)
    preset = Path(__file__).resolve().parents[2] / "export_presets.cfg"
    selected = re.search(r"^export_files=(.+)$", preset.read_text(), re.M)
    assert selected
    for resource in re.findall(r'"res://([^"]+)"', selected[1]):
        asset = f"assets/{resource}"
        if resource.endswith(".gd"):
            assert f"{asset}c" in entries or asset in entries, resource
        else:
            assert any(f"{asset}{suffix}" in entries for suffix in ("", ".import", ".remap")), resource
    print(json.dumps({
        "stock_release_bytes":args.stock.stat().st_size,
        "custom_release_bytes":args.built.stat().st_size,
        "stock_engine_bytes":stock.getinfo(godot_library).file_size,
        "custom_engine_bytes":len(elf),
        "custom_engine_sha256":sha256(elf).hexdigest()
    }, indent=2))
