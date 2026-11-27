"""Derive the J-20 game rig from the shared studio GLB and its existing game rig.

The previous J-20 supplies its cockpit, gear tracks, deployment nodes and
collision contract. The studio source supplies the exterior and moving panels.
"""
import argparse
from collections import defaultdict
from copy import deepcopy
from math import sqrt
from pathlib import Path

from airframe_glb import AirframeGLB
from bake_j20_breakup import bake, write_model


GEAR = ("Main landing gear", "Main gear", "Main tyre", "Trailing gear", "Nose gear", "Nose wheel", "Wheel hub")
DETAIL = ("Flush ", "Low-observable ", "Canted tail leading", "Recessed intake", "Shared physical")


def transfer_materials(target, source):
    mapping = {}
    for i, material in enumerate(source.materials):
        new = deepcopy(material)
        if "normalTexture" in new:
            tex = source.doc["textures"][new["normalTexture"]["index"]]
            normal = source.doc["images"][tex["source"]]
            dst = target.doc["images"]
            uri = Path(normal["uri"]).name
            image = next((j for j, entry in enumerate(dst) if entry.get("uri") == uri), None)
            if image is None:
                image = len(dst)
                dst.append({"uri": uri, "name": normal["name"]})
            textures = target.doc["textures"]
            texture = next((j for j, entry in enumerate(textures) if entry["source"] == image), None)
            if texture is None:
                texture = len(textures)
                textures.append({"source": image, "sampler": 0})
            new["normalTexture"]["index"] = texture
        mapping[i] = len(target.materials)
        target.materials.append(new)
    target.doc["extensionsUsed"] = sorted(set(target.doc.get("extensionsUsed", [])) | set(source.doc.get("extensionsUsed", [])))
    return mapping


def append_mesh(target, source, nodes, materials, scale, name, local=False):
    groups = defaultdict(lambda: ([], [], [], []))
    for node in nodes:
        if "rotation" in node or "matrix" in node or "scale" in node:
            raise ValueError(f"{node['name']} should be baked in airframe coordinates")
        origin = (0, 0, 0) if local else node.get("translation", (0, 0, 0))
        for component in source.meshes[node["mesh"]]["primitives"]:
            pos, normal, uv, indices = groups[materials[component["material"]]]
            attr = component["attributes"]
            offset = len(pos)
            points = source.read(attr["POSITION"])
            pos.extend(tuple((v + b) * s for v, b, s in zip(p, origin, scale)) for p in points)
            for n in source.read(attr["NORMAL"]):
                vector = tuple(v / s for v, s in zip(n, scale))
                length = max(1e-8, sqrt(sum(v*v for v in vector)))
                normal.append(tuple(v / length for v in vector))
            uv.extend(source.read(attr["TEXCOORD_0"]) if "TEXCOORD_0" in attr else [(0, 0)] * len(points))
            indices.extend((i+offset,) for i, in source.read(component["indices"]))
    primitives = []
    for material, (pos, normal, uv, indices) in groups.items():
        primitives.append({"material": material, "attributes": {
            "POSITION": target.append(pos, "VEC3"), "NORMAL": target.append(normal, "VEC3"),
            "TEXCOORD_0": target.append(uv, "VEC2")}, "indices": target.append(indices, "SCALAR")})
    index = len(target.meshes)
    target.meshes.append({"name": name, "primitives": primitives})
    return index


def prune_nodes(asset):
    seen = set()
    def visit(ident):
        if ident not in seen:
            seen.add(ident)
            for child in asset.nodes[ident].get("children", []):
                visit(child)
    for node in asset.scene:
        visit(node)
    ordered = sorted(seen)
    mapping = {old: new for new, old in enumerate(ordered)}
    asset.nodes[:] = [asset.nodes[i] for i in ordered]
    for node in asset.nodes:
        if "children" in node:
            node["children"] = [mapping[i] for i in node["children"]]
    asset.scene[:] = [mapping[i] for i in asset.scene]
    for clip in asset.doc.get("animations", []):
        for channel in clip["channels"]:
            binding = channel["target"]
            binding["node"] = mapping[binding["node"]]


def derive(sample, inherited, output):
    src, dst = AirframeGLB(sample), AirframeGLB(inherited)
    materials = transfer_materials(dst, src)
    # The original declared 21.2 m length and 13.4 m span set the visual scale.
    scale = (13.4 / 14.5, 1.0, 21.2 / 21.85)
    surfaces = [n for n in src.nodes if "mesh" in n and not n["name"].startswith(GEAR)]
    flaps = [n for n in surfaces if n["name"].startswith("Aileron")]
    hull = [n for n in surfaces if n not in flaps]
    base = [n for n in hull if not n["name"].startswith(DETAIL)]
    full_mesh = append_mesh(dst, src, hull, materials, scale, "Reference exterior")
    base_mesh = append_mesh(dst, src, base, materials, scale, "Reference combat")
    flap_meshes = {flap["name"]: append_mesh(dst, src, [flap], materials, scale, flap["name"], local=True)
                   for flap in flaps}
    for i in dst.scene[:]:
        level = dst.nodes[i]
        name = level["name"]
        if name == "Breakup":
            dst.scene.remove(i)
        if name not in ("Exterior", "Combat", "LOD"):
            continue
        keep = [j for j in level["children"] if dst.nodes[j]["name"].startswith(("Gear_", "Bay_"))]
        part = {"name": "Airframe shell mesh" if name == "Exterior" else f"Reference {name} mesh",
                "mesh": full_mesh if name == "Exterior" else base_mesh, "translation": [0, 0, 0], "scale": [1, 1, 1]}
        part_index = len(dst.nodes)
        dst.nodes.append(part)
        shell_children = [part_index]
        for flap in flaps:
            mesh = flap_meshes[flap["name"]]
            shell_children.append(len(dst.nodes))
            dst.nodes.append({"name": flap["name"], "mesh": mesh,
                              "translation": [x * s for x, s in zip(flap.get("translation", (0, 0, 0)), scale)]})
        level["children"] = [len(dst.nodes)] + keep
        dst.nodes.append({"name": "Airframe shell" if name == "Exterior" else f"Reference {name}",
                          "children": shell_children})
    tail = next(dst.nodes[i] for i in dst.scene if dst.nodes[i]["name"] == "J20Exhausts")
    for i in tail["children"]:
        x = dst.nodes[i]["translation"][0]
        dst.nodes[i]["translation"] = [x * scale[0], 0.02, 10.72 * scale[2]]
    prune_nodes(dst)
    write_model(output, dst.doc, dst.compact())
    bake(output, dimensions=(13.4, 21.2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample", type=Path)
    parser.add_argument("rig", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    derive(args.sample, args.rig, args.output)
