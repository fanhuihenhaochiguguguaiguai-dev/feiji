"""Compare the stock release, custom release and the template embedded in it."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
from zipfile import ZipFile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("stock", type=Path)
parser.add_argument("built", type=Path)
parser.add_argument("template", type=Path)
args = parser.parse_args()
godot_library = "lib/arm64-v8a/libgodot_android.so"

with ZipFile(args.stock) as stock, ZipFile(args.built) as built, ZipFile(args.template) as template:
    assert built.testzip() is None
    assert len(set(built.namelist())) == len(built.namelist())
    elf = built.read(godot_library)
    assert elf == template.read(godot_library), "export did not embed the custom engine"
    assert len(elf) < stock.getinfo(godot_library).file_size, "custom ELF is not smaller"
    assert args.built.stat().st_size < args.stock.stat().st_size, "custom APK is not smaller"
    assert "assets/assets/boot/splash.png" in built.namelist()
    assert {"lib/arm64-v8a/libskyterrain.android.arm64.so",
            "lib/arm64-v8a/libterrain.android.release.arm64.so"}.issubset(built.namelist())
    for entry in ("assets/assets/environment/world-116.res", "assets/assets/environment/world-413.res",
                  "assets/assets/environment/world-704.res"):
        if entry in stock.namelist():
            assert entry in built.namelist()
    print(json.dumps({
        "stock_release_bytes":args.stock.stat().st_size,
        "custom_release_bytes":args.built.stat().st_size,
        "stock_engine_bytes":stock.getinfo(godot_library).file_size,
        "custom_engine_bytes":len(elf),
        "custom_engine_sha256":sha256(elf).hexdigest()
    }, indent=2))
