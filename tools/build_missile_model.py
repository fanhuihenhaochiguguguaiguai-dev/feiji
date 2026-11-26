"""Bake the original Skyblade projectile mesh with Blender's glTF exporter."""

from math import cos, pi, sin, tau
from pathlib import Path

import bpy


def material(name, rgb, metallic, roughness):
    part = bpy.data.materials.new(name)
    part.diffuse_color = (*rgb, 1.0)
    part.use_nodes = True
    shader = part.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = part.diffuse_color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return part


def bake():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = [
        material("Ceramic radome", (0.44, 0.48, 0.48), 0.14, 0.38),
        material("Painted skin", (0.63, 0.67, 0.66), 0.30, 0.31),
        material("Joint collars", (0.29, 0.33, 0.36), 0.72, 0.33),
        material("Graphite nozzle", (0.065, 0.074, 0.077), 0.68, 0.37),
        material("Markings", (0.64, 0.22, 0.075), 0.18, 0.40),
    ]
    vertices, faces, assignments = [], [], []

    def face(indices, surface, smooth=False):
        faces.append(indices)
        assignments.append((surface, smooth))

    # The local +Z axis is the nose and becomes Godot +Y at export.
    rings = [
        (-1.60, 0.022, 3), (-1.77, 0.089, 3), (-1.77, 0.126, 2),
        (-1.69, 0.144, 2), (-1.54, 0.148, 3), (-1.51, 0.163, 2),
        (-1.21, 0.166, 1), (-1.16, 0.173, 2), (-1.10, 0.173, 2),
        (-1.06, 0.169, 1), (-0.62, 0.170, 1), (-0.60, 0.170, 4),
        (-0.49, 0.170, 4), (-0.47, 0.169, 1), (0.72, 0.166, 1),
        (0.75, 0.168, 2), (0.81, 0.168, 2), (0.84, 0.164, 0),
        (1.17, 0.147, 0), (1.43, 0.113, 0), (1.61, 0.072, 0),
        (1.73, 0.035, 0), (1.76, 0.009, 0),
    ]
    sides = 24
    for z, radius, unused in rings:
        vertices.extend((radius * cos(tau * i / sides), radius * sin(tau * i / sides), z) for i in range(sides))
    for ring, (_, _, surface) in enumerate(rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            face((ring * sides + i, ring * sides + j, (ring + 1) * sides + j, (ring + 1) * sides + i), surface, True)
    face(tuple(reversed(range(sides))), 3)
    face(tuple(range((len(rings) - 1) * sides, len(rings) * sides)), 0)

    def fin(angle, outline, gauge):
        base = len(vertices)
        for side in (-1, 1):
            for radius, z in outline:
                thickness = gauge * side * (0.30 if radius > 0.35 else 1.0)
                vertices.append((radius * cos(angle) - thickness * sin(angle),
                                 radius * sin(angle) + thickness * cos(angle), z))
        n = len(outline)
        face(tuple(base + i for i in reversed(range(n))), 1)
        face(tuple(base + n + i for i in range(n)), 1)
        for i in range(n):
            j = (i + 1) % n
            face((base + i, base + j, base + n + j, base + n + i), 2)

    for i in range(4):
        angle = pi * 0.25 + i * pi * 0.5
        fin(angle, [(0.152, -1.58), (0.432, -1.52), (0.428, -1.32), (0.33, -1.20), (0.152, -0.90)], 0.017)
        fin(angle, [(0.155, 0.15), (0.319, 0.21), (0.319, 0.37), (0.16, 0.62)], 0.012)
    mesh = bpy.data.meshes.new("Skyblade projectile")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    body = bpy.data.objects.new("FlightBody", mesh)
    bpy.context.collection.objects.link(body)
    for item in materials:
        mesh.materials.append(item)
    for polygon, (surface, smooth) in zip(mesh.polygons, assignments):
        polygon.material_index = surface
        polygon.use_smooth = smooth
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.export_scene.gltf(
        filepath=str(Path(__file__).resolve().parents[1] / "assets" / "surface" / "projectile.glb"),
        export_format="GLB",
        export_cameras=False,
        export_lights=False,
    )


if __name__ == "__main__":
    bake()
