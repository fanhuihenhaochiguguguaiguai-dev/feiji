"""Compare the stock release, custom release and the template embedded in it."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZIP_STORED, ZipFile


def referenced_resources(root):
    """Include literal runtime references that a selected-resource export can omit."""
    suffixes = {".gd", ".tscn", ".gdshader", ".gdshaderinc"}
    for relative in ("game", "scenes", "shaders", "addons/harfang_pilot", "addons/ocean_waves"):
        for source in (root / relative).rglob("*"):
            if source.suffix not in suffixes or not source.is_file():
                continue
            text = source.read_text(encoding="utf-8")
            for resource in re.findall(r"""["']res://([^"'\r\n]+)["']""", text):
                if "%" not in resource and not resource.endswith("/") and not (root / resource).is_dir():
                    yield resource, str(source.relative_to(root))
            if source.suffix in {".gdshader", ".gdshaderinc"}:
                for include in re.findall(r'^\s*#include\s+"([^"]+)"', text, re.M):
                    if not include.startswith("res://"):
                        resource = source.with_name(include).relative_to(root).as_posix()
                        yield resource, str(source.relative_to(root))


def check_packed_resource(package, entries, resource, origin):
    asset = f"assets/{resource}"
    candidates = (asset, f"{asset}.import", f"{asset}.remap")
    if resource.endswith(".gd"):
        candidates += (f"{asset}c",)
    assert any(path in entries for path in candidates), f"Missing {resource} (required by {origin})"
    for alias in candidates[1:3]:
        if alias not in entries:
            continue
        targets = re.findall(r'^path(?:\.\w+)?="res://([^"]+)"', package.read(alias).decode(), re.M)
        assert targets, f"Missing import target in {alias}"
        assert all(f"assets/{target}" in entries for target in targets), f"Broken import/remap: {alias} → {targets}"


def check_exported_startup(package, root, vulkan=False):
    # Run the APK's assets without the source tree as a fallback. Only the
    # native libraries use desktop builds so this can run on the Linux runner.
    with TemporaryDirectory(prefix="skyblade-startup-") as directory:
        work = Path(directory)
        runtime = work / "runtime"
        game_pack = work / "exported-assets.zip"
        for folder in ("addons/terrain_3d/bin", "native/bin"):
            (runtime / folder).mkdir(parents=True)
            for library in (root / folder).glob("*linux*x86_64.so"):
                (runtime / folder / library.name).symlink_to(library)
        with ZipFile(game_pack, "w", ZIP_STORED) as pack:
            for entry in package.infolist():
                if entry.filename.startswith("assets/") and not entry.is_dir():
                    pack.writestr(entry.filename.removeprefix("assets/"), package.read(entry))
        boot = ["--path", str(runtime), "--main-pack", str(game_pack), "--script", str(root / "qa/reference_ui.gd")]
        modes = [["--headless", *boot]]
        if vulkan:
            modes.append(["--render-thread", "safe", "--rendering-method", "mobile", "--rendering-driver", "vulkan",
                          "--audio-driver", "Dummy", "--fixed-fps", "90", "--resolution", "480x270", *boot, "--", "--vulkan-launch"])
        for i, mode in enumerate(modes):
            renderer = "headless" if i == 0 else "Mobile Vulkan"
            print(f"Checking the exported game with {renderer}", file=sys.stderr, flush=True)
            try:
                result = subprocess.run(
                    ["godot", *mode],
                    env={**os.environ, "XDG_DATA_HOME": str(work / f"user-data-{i}"), "XDG_CACHE_HOME": str(work / f"cache-{i}")},
                    capture_output=True, text=True, timeout=360 if i else 100,
                )
            except subprocess.TimeoutExpired as error:
                output = ((error.stdout or b"") + (error.stderr or b"")).decode(errors="replace")
                raise AssertionError(f"Exported game timed out with {renderer}:\n{output[-6000:]}") from None
            output = result.stdout + result.stderr
            passed = result.returncode == 0 and '{"failures":[]}' in result.stdout and "ERROR:" not in output
            assert passed, f"Exported startup failed with {renderer} (exit {result.returncode}):\n{output[-6000:]}"
            print(f"Passed the exported lobby, sortie and return test with {renderer}", file=sys.stderr, flush=True)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("stock", type=Path)
parser.add_argument("built", type=Path)
parser.add_argument("template", type=Path)
parser.add_argument("--startup-test", action="store_true")
parser.add_argument("--vulkan-startup-test", action="store_true")
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
    root = Path(__file__).resolve().parents[2]
    preset = root / "export_presets.cfg"
    selected = re.search(r"^export_files=(.+)$", preset.read_text(), re.M)
    assert selected
    for resource, origin in referenced_resources(root):
        check_packed_resource(built, entries, resource, origin)
    for resource in re.findall(r'"res://([^"]+)"', selected[1]):
        check_packed_resource(built, entries, resource, preset.name)
    if args.startup_test or args.vulkan_startup_test:
        check_exported_startup(built, root, args.vulkan_startup_test)
    print(json.dumps({
        "stock_release_bytes":args.stock.stat().st_size,
        "custom_release_bytes":args.built.stat().st_size,
        "stock_engine_bytes":stock.getinfo(godot_library).file_size,
        "custom_engine_bytes":len(elf),
        "custom_engine_sha256":sha256(elf).hexdigest(),
        "exported_startup_tested":args.startup_test or args.vulkan_startup_test,
        "exported_vulkan_startup_tested":args.vulkan_startup_test,
    }, indent=2))
