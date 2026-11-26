"""Run in Blender 4.3 with -- <directory of CC0 Small Campfire VDB frames>."""
import sys
from pathlib import Path

import bpy
import numpy as np


def sample_volume(paths, samples=32):
    bpy.ops.object.volume_import(filepath=str(paths[len(paths) // 2]))
    volume = bpy.context.object
    bpy.context.view_layer.update()
    bounds = np.array(volume.bound_box, dtype=np.float32)
    low, high = bounds.min(axis=0), bounds.max(axis=0)
    centre = (low + high) * 0.5
    radius = (high - low).max() * 0.58
    axis = np.linspace(-radius, radius, samples, dtype=np.float32)
    z, y, x = np.meshgrid(axis, axis, axis, indexing="ij")
    # Blender Z-up maps to the game's Y-up.
    points = np.stack((x, -z, y), axis=-1) + centre
    mesh = bpy.data.meshes.new("Volume bake lattice")
    mesh.vertices.add(samples**3)
    mesh.vertices.foreach_set("co", points.flatten())
    lattice = bpy.data.objects.new("Volume bake lattice", mesh)
    bpy.context.collection.objects.link(lattice)
    group = bpy.data.node_groups.new("Sample source grids", "GeometryNodeTree")
    for side in ("INPUT", "OUTPUT"):
        group.interface.new_socket(name="Geometry", in_out=side, socket_type="NodeSocketGeometry")
    mod = lattice.modifiers.new("Sample source grids", "NODES")
    mod.node_group = group
    nodes, links = group.nodes, group.links
    source = nodes.new("GeometryNodeObjectInfo")
    source.inputs["Object"].default_value = volume
    position = nodes.new("GeometryNodeInputPosition")
    geometry = nodes.new("NodeGroupInput").outputs["Geometry"]
    for attribute in ("density", "flames"):
        grid = nodes.new("GeometryNodeGetNamedGrid")
        grid.inputs["Name"].default_value = attribute
        links.new(source.outputs["Geometry"], grid.inputs["Volume"])
        sample = nodes.new("GeometryNodeSampleGrid")
        links.new(grid.outputs["Grid"], sample.inputs["Grid"])
        links.new(position.outputs["Position"], sample.inputs["Position"])
        store = nodes.new("GeometryNodeStoreNamedAttribute")
        store.inputs["Name"].default_value = attribute
        links.new(geometry, store.inputs["Geometry"])
        links.new(sample.outputs["Value"], store.inputs["Value"])
        geometry = store.outputs["Geometry"]
    links.new(geometry, nodes.new("NodeGroupOutput").inputs["Geometry"])
    frames = []
    for path in paths:
        volume.data.filepath = str(path)
        bpy.context.view_layer.update()
        evaluated = lattice.evaluated_get(bpy.context.evaluated_depsgraph_get())
        result = evaluated.to_mesh()
        frame = np.empty((samples, samples, samples, 3), dtype=np.float32)
        for channel, attribute in enumerate(("density", "flames")):
            values = np.empty(samples**3, dtype=np.float32)
            result.attributes[attribute].data.foreach_get("value", values)
            frame[..., channel] = values.reshape((samples,) * 3)
        evaluated.to_mesh_clear()
        # The source extinction is expressed per original VDB world unit.
        frame[..., 0] *= radius * 2.0
        # Hemispherical visibility toward the upper layer, integrated offline.
        above = np.flip(np.cumsum(np.flip(frame[..., 0], axis=1), axis=1), axis=1)
        frame[..., 2] = np.exp(-above * 0.45)
        frames.append(frame)
    return np.array(frames)


source_dir = Path(sys.argv[sys.argv.index("--") + 1])
paths = sorted(source_dir.glob("*.vdb"))
frames = sample_volume([paths[index] for index in np.linspace(0, len(paths) - 1, 6).astype(int)])
assert frames[..., 0].max() > 0.1 and frames[..., 1].max() > 0.05
frames[..., 0] *= 1.25
frames[..., 1] *= 1.7
atlas = frames.reshape(24, 8, 32, 32, 3).transpose(0, 2, 1, 3, 4).reshape(768, 256, 3)
atlas = np.concatenate((atlas, np.ones((768, 256, 1), dtype=np.float32)), axis=2)
image = bpy.data.images.new("Combustion grids", width=256, height=768, alpha=False)
image.colorspace_settings.name = "Non-Color"
image.pixels.foreach_set(np.flip(atlas.clip(0, 1), axis=0).copy().ravel())
image.filepath_raw = str(Path(__file__).resolve().parents[1] / "assets/surface/combustion-volume.png")
image.file_format = "PNG"
image.save()
print("Combustion grids:", frames.shape, frames[..., :2].max(axis=(0, 1, 2, 3)))
