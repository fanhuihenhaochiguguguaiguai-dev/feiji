"""Build the coastal cliff mesh from the Poly Haven 1K glTF download.

Run Blender in background mode with this script and pass the glTF path after --.
"""

import sys
from pathlib import Path

import bpy


def bake(source):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    cliff, = (obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    bpy.context.view_layer.objects.active = cliff
    cliff.name = "CoastalCliff"
    cliff.data.calc_loop_triangles()

    # Keep the scanned ledges and silhouette. The retained UVs carry finer fracture detail.
    modifier = cliff.modifiers.new(name="Cliff polygon budget", type="DECIMATE")
    modifier.ratio = min(1.0, 6800.0 / len(cliff.data.loop_triangles))
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    cliff.data.calc_loop_triangles()
    target = Path(__file__).resolve().parents[1] / "assets/environment/coastal-cliff.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB",
                              export_cameras=False, export_lights=False, export_extras=False)
    print(f"Saved {len(cliff.data.loop_triangles)} triangles to {target.name}")


if __name__ == "__main__":
    bake(Path(sys.argv[sys.argv.index("--") + 1]).resolve())
