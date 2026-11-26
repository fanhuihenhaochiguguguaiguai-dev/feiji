"""Bake the J-20 imaging model and its LODs from the same dimensioned surface.

Use the inherited V18.3 J-20 GLB as the input rig. It supplies the cockpit
interior, controls, landing gear, nozzle and shared material textures.
"""
import argparse
from collections import defaultdict
from copy import deepcopy
from io import BytesIO
from math import cos, radians, sin
from pathlib import Path
from struct import pack, unpack_from

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.interpolate import CubicSpline

from bake_j20_breakup import bake, read_model, write_model


# Game coordinates in metres. Each frame specifies Z, width, upper height,
# lower height and chine elevation. The stations can be edited independently
# of the tessellation, UVs and exported levels.
STATIONS = [
    (-10.608, 0.026, 0.021, 0.022, 0.038),
    (-9.86, 0.226, 0.129, 0.117, 0.037),
    (-8.35, 0.476, 0.314, 0.276, 0.061),
    (-6.75, 0.730, 0.486, 0.424, 0.034),
    (-5.50, 0.957, 0.624, 0.525, 0.007),
    (-4.33, 1.086, 0.679, 0.578, -0.013),
    (-2.55, 1.254, 0.761, 0.632, -0.042),
    (-1.29, 1.458, 0.754, 0.678, -0.060),
    (0.62, 1.510, 0.773, 0.648, -0.081),
    (2.48, 1.505, 0.773, 0.635, -0.092),
    (4.56, 1.486, 0.759, 0.630, -0.108),
    (6.41, 1.304, 0.649, 0.602, -0.130),
    (7.65, 1.139, 0.482, 0.520, -0.138),
    (8.73, 0.801, 0.328, 0.394, -0.149),
    (9.63, 0.317, 0.153, 0.226, -0.159),
    (9.996, 0.139, 0.076, 0.116, -0.158),
]
BODY = CubicSpline(np.array(STATIONS)[:, 0], np.array(STATIONS)[:, 1:], bc_type="natural")
CANOPY_FRAMES = np.array([
    (-6.13, 0.022, 0.012), (-5.82, 0.215, 0.065), (-5.39, 0.425, 0.244),
    (-4.76, 0.557, 0.458), (-4.08, 0.532, 0.456), (-3.30, 0.361, 0.273),
    (-2.72, 0.173, 0.086), (-2.43, 0.025, 0.013),
])
CANOPY = CubicSpline(CANOPY_FRAMES[:, 0], CANOPY_FRAMES[:, 1:], bc_type="natural")


def body_point(z, angle):
    width, top, bottom, chine = BODY(z)
    s, c = np.sin(angle), np.cos(angle)
    # Exact differentiable sections around the chine. A narrow interpolation
    # on the underside preserves the edge break without creating faceted rings.
    shoulder = 0.68 + 0.32 * s * s
    blend = (1.0 + np.tanh(s / 0.13)) * 0.5
    height = bottom + (top - bottom) * blend
    return np.array((width * c * (1.0 + 0.24 * s * s),
                     chine + height * s * shoulder, z))


def canopy_point(z, angle):
    width, height = CANOPY(z)
    x = width * np.cos(angle)
    # Seat each glazing section on the actual chine profile. Invert the
    # cross-section's x coordinate to meet the fuselage at both edges.
    ratio = x / BODY(z)[0]
    c = ratio
    for _ in range(3):
        c -= (1.24 * c - 0.24 * c ** 3 - ratio) / (1.24 - 0.72 * c * c)
    shoulder = body_point(z, np.arccos(c))[1]
    return np.array((x, shoulder + height * np.sin(angle) + 0.009, z))


def surface(point, stations, angles, material, *, closed=True, atlas=False):
    rows = defaultdict(list)
    ring = len(angles)
    vertices = {}
    for i, z in enumerate(stations):
        for j, angle in enumerate(angles):
            p = point(z, angle)
            t = point(z, angle + 0.0002) - point(z, angle - 0.0002)
            dz = point(z + 0.0002, angle) - point(z - 0.0002, angle)
            n = np.cross(t, dz)
            n /= np.linalg.norm(n)
            uv = (angle / (2 * np.pi), (z - STATIONS[0][0]) / 20.604) if atlas else (angle / np.pi, z * 0.19)
            vertices[i, j] = (*p, *n, *uv)
    for i in range(len(stations) - 1):
        for j in range(ring - 1):
            a, b = vertices[i, j], vertices[i, j + 1]
            c, d = vertices[i + 1, j + 1], vertices[i + 1, j]
            tint = material((stations[i] + stations[i + 1]) * 0.5, (angles[j] + angles[j + 1]) * 0.5)
            rows[tint].extend([(a, b, c), (a, c, d)])
    if closed:
        for side in (0, len(stations) - 1):
            direction = -1 if side == 0 else 1
            z = stations[side]
            p = np.mean([vertices[side, j][:3] for j in range(ring - 1)], axis=0)
            center = (*p, 0.0, 0.0, direction, 0.5, z * 0.19)
            for j in range(ring - 1):
                a, b = vertices[side, j], vertices[side, j + 1]
                a, b = (a, b) if direction > 0 else (b, a)
                face = [(v[0], v[1], v[2], 0.0, 0.0, direction, v[0] * 0.4, v[1] * 0.4)
                        for v in (a, b)]
                rows[material(z, 1.0)].append((center, *face))
    return rows


def airframe(regions, segments):
    start, stop = STATIONS[0][0], STATIONS[-1][0]
    # The radome joint stays at the same station in all detail levels.
    nose = np.linspace(start, -7.76, max(5, regions // 6))
    airframe_z = np.r_[nose[:-1], np.linspace(-7.76, stop, regions - len(nose) + 1)]

    def skin(z, angle):
        if z < -7.76:
            return "J20 dielectric radome"
        return "J20 coated belly" if np.sin(angle) < 0 else "J20 coated skin"

    return surface(body_point, airframe_z, np.linspace(0, 2 * np.pi, segments + 1), skin, atlas=True)


def clear_canopy(regions, segments):
    z = np.linspace(CANOPY_FRAMES[0, 0], CANOPY_FRAMES[-1, 0], regions)
    curved = surface(canopy_point, z, np.linspace(0.16, np.pi - 0.16, segments + 1),
                     lambda _z, _a: "J20 optical glass", closed=False)
    # Fit a narrow gasket to the same surface curve as the glazing.
    for lo, hi in ((0.0, 0.16), (np.pi - 0.16, np.pi)):
        gasket = surface(canopy_point, z, [lo, hi], lambda _z, _a: "J20 composite trim", closed=False)
        curved["J20 composite trim"].extend(gasket["J20 composite trim"])
    return curved


# Loft rings are specified outside-to-inside. The asymmetric swept mouth
# opens into a genuine recessed duct with a dark terminus.
INTAKE_RINGS = (
    # z, half-width, half-height, centre-x, centre-y, edge sweep
    (-0.96, 0.363, 0.259, 1.20, -0.236, 0.022),
    (-1.89, 0.481, 0.381, 1.21, -0.221, 0.121),
    (-3.73, 0.548, 0.472, 1.19, -0.182, 0.177),
    (-4.13, 0.493, 0.426, 1.185, -0.177, 0.207),
    (-4.16, 0.453, 0.385, 1.193, -0.181, 0.209),
    (-4.06, 0.405, 0.343, 1.201, -0.187, 0.191),
    (-3.68, 0.379, 0.303, 1.212, -0.218, 0.149),
    (-2.87, 0.339, 0.265, 1.192, -0.246, 0.051),
    (-2.04, 0.248, 0.188, 1.083, -0.251, 0.005),
    (-1.96, 0.024, 0.026, 1.047, -0.242, 0.0),
)


def intakes(samples, full_shell):
    rows = defaultdict(list)
    rings = INTAKE_RINGS if full_shell else tuple(INTAKE_RINGS[i] for i in (0, 2, 3, 5, 8, 9))
    for side in (-1, 1):
        vectors = []
        for z, width, height, cx, cy, sweep in rings:
            ring = []
            for a in np.linspace(0.0, 2.0 * np.pi, samples + 1):
                c, s = np.cos(a), np.sin(a)
                x = np.copysign(abs(c) ** 0.63, c)
                y = np.copysign(abs(s) ** 0.66, s)
                ring.append(np.array((side * (cx + width * (x + y * 0.17)), cy + height * y,
                                      z + sweep * (0.5 * x + y * 0.62))))
            vectors.append(ring)
        for i in range(len(vectors) - 1):
            for j in range(samples):
                z = rings[i][0]
                tint = "skin" if z > -4.1 and i < 3 else "J20 composite trim" if i < len(rings) - 3 else "intake"
                if i >= (5 if full_shell else 3):
                    tint = "intake"
                verts = []
                for r, k in ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)):
                    left, right = (k - 1) % samples, (k + 1) % samples
                    along = vectors[i + 1][k] - vectors[i][k]
                    n = side * np.cross(along, vectors[r][right] - vectors[r][left])
                    n /= np.linalg.norm(n)
                    p = vectors[r][k]
                    verts.append((*p, *n, k / samples, p[2] * 0.29))
                a, b, c, d = verts if side < 0 else verts[::-1]
                rows[tint].extend([(a, b, c), (a, c, d)])
    return rows


class Asset:
    def __init__(self, source, atlas_path):
        self.doc, self.buffer = read_model(source)
        self.access = self.doc["accessors"]
        self.views = self.doc["bufferViews"]
        self.nodes = self.doc["nodes"]
        self.meshes = self.doc["meshes"]
        self.materials = self.doc["materials"]
        self.scene = self.doc["scenes"][self.doc["scene"]]["nodes"]
        self.names = {entry["name"]: i for i, entry in enumerate(self.materials)}
        self.add_material("J20 dielectric radome", "skin", (0.115, 0.133, 0.151), 0.58, 0.04)
        self.add_material("J20 composite trim", "dark", (0.072, 0.083, 0.096), 0.51, 0.19)
        self.add_material("J20 optical glass", "glass", (0.18, 0.197, 0.21, 0.61), 0.16, 0.07)
        skin_texture = self.bake_skin_atlas(atlas_path)
        for name, color in (("J20 coated skin", (0.142, 0.155, 0.166)), ("J20 coated belly", (0.119, 0.129, 0.142))):
            self.add_material(name, "skin", color, 1.0, 1.0)
            coating = self.materials[self.names[name]]
            coating.pop("normalTexture", None)
            coating["occlusionTexture"] = {"index": skin_texture, "strength": 0.55}
            coating["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": skin_texture}
            coat = coating.get("extensions", {}).get("KHR_materials_clearcoat")
            if coat:
                coat.update(clearcoatFactor=0.09, clearcoatRoughnessFactor=0.51)
        self.materials[self.names["skin"]]["pbrMetallicRoughness"]["baseColorFactor"] = [0.152, 0.170, 0.188, 1.0]
        self.materials[self.names["belly"]]["pbrMetallicRoughness"]["baseColorFactor"] = [0.109, 0.123, 0.142, 1.0]
        self.materials[self.names["panel"]]["pbrMetallicRoughness"]["baseColorFactor"] = [0.127, 0.145, 0.163, 1.0]
        self.materials[self.names["trim"]]["pbrMetallicRoughness"]["baseColorFactor"] = [0.227, 0.247, 0.266, 1.0]
        coat = self.materials[self.names["skin"]].get("extensions", {}).get("KHR_materials_clearcoat")
        if coat:
            coat.update(clearcoatFactor=0.11, clearcoatRoughnessFactor=0.48)

    def bake_skin_atlas(self, path):
        # The seam layout is authored in fuselage space and baked once.
        # Use one ORM atlas across all airframe levels, without tiling.
        existing = next((i for i, t in enumerate(self.doc["textures"]) if t.get("name") == "J20 fuselage ORM"), None)
        width, height = 512, 1024
        mask = Image.new("L", (width, height))
        draw = ImageDraw.Draw(mask)
        sections = [
            ((0.045, -6.12), (0.096, -5.73), (0.111, -4.66), (0.102, -3.81), (0.066, -3.44)),
            ((0.034, -2.29), (0.063, -2.02), (0.067, -0.66), (0.038, -0.21), (0.034, -2.29)),
            ((0.089, 0.46), (0.194, 0.69), (0.191, 2.38), (0.164, 2.69), (0.094, 2.57), (0.089, 0.46)),
            ((0.079, 4.34), (0.157, 4.48), (0.146, 6.16), (0.097, 6.39), (0.079, 4.34)),
            ((0.018, 7.28), (0.088, 7.60), (0.138, 8.12), (0.19, 8.78)),
        ]
        for outline in sections:
            for side in (False, True):
                for coords in (outline, tuple((0.56 + a, z + 0.34) for a, z in outline[1:-1])):
                    points = [((0.5 - a if side else a) % 1.0 * width,
                               (z - STATIONS[0][0]) / 20.604 * height) for a, z in coords]
                    draw.line(points, fill=215 if coords is outline else 165, width=2)
        seam = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.48)), dtype=np.float32) / 255.0
        noise = np.random.default_rng(20).normal(128.0, 2.8, (height // 8, width // 8))
        grain = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((width, height), Image.Resampling.BILINEAR),
                           dtype=np.float32) - 128.0
        texels = np.dstack((255.0 - 43.0 * seam, 157.0 + 39.0 * seam + grain, 37.0 - 17.0 * seam))
        encoded = BytesIO()
        Image.fromarray(texels.clip(0, 255).astype(np.uint8)).save(encoded, format="PNG", optimize=True)
        data = encoded.getvalue()
        textures = self.doc["textures"]
        images = self.doc["images"]
        image = {"name": "J20 fuselage ORM"}
        if path:
            path.write_bytes(data)
            image["uri"] = path.name
        else:
            self.views.append({"buffer": 0, "byteOffset": len(self.buffer), "byteLength": len(data)})
            self.buffer.extend(data + b"\0" * (-len(data) % 4))
            image.update(bufferView=len(self.views) - 1, mimeType="image/png")
        if existing is not None:
            images[textures[existing]["source"]] = image
            return existing
        textures.append({"name": "J20 fuselage ORM", "source": len(images)})
        images.append(image)
        return len(textures) - 1

    def add_material(self, name, original, color, roughness, metallic):
        if name not in self.names:
            copy = deepcopy(self.materials[self.names[original]])
            self.names[name] = len(self.materials)
            copy["name"] = name
            self.materials.append(copy)
        entry = self.materials[self.names[name]]
        pbr = entry["pbrMetallicRoughness"]
        pbr.pop("metallicRoughnessTexture", None)
        pbr.update(baseColorFactor=[*color, *([1.0] if len(color) == 3 else [])],
                   roughnessFactor=roughness, metallicFactor=metallic)

    def read(self, index):
        a = self.access[index]
        view = self.views[a["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        schema = {5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
        stride = view.get("byteStride", width * (2 if schema == "H" else 4))
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [unpack_from("<" + schema * width, self.buffer, start + i * stride) for i in range(a["count"])]

    def append(self, rows, kind):
        start = len(self.buffer)
        scalar = kind == "SCALAR"
        schema = "H" if scalar and max(v[0] for v in rows) < 65536 else "I" if scalar else "f"
        for row in rows:
            self.buffer.extend(pack("<" + schema * len(row), *row))
        end = len(self.buffer)
        self.buffer.extend(b"\0" * (-end % 4))
        self.views.append({"buffer": 0, "byteOffset": start, "byteLength": end - start})
        a = {"bufferView": len(self.views) - 1, "componentType": {"H": 5123, "I": 5125, "f": 5126}[schema],
             "count": len(rows), "type": kind}
        if kind == "VEC3":
            a.update(min=list(map(min, zip(*rows))), max=list(map(max, zip(*rows))))
        self.access.append(a)
        return len(self.access) - 1

    def pack_surfaces(self, groups, node):
        translation = np.asarray(node.get("translation", [0, 0, 0]))
        scale = np.asarray(node.get("scale", [1, 1, 1]))
        output = []
        for material, faces in groups.items():
            indexed = {}
            indices = []
            for face in faces:
                for corner in face:
                    key = tuple(round(float(v), 7) for v in corner)
                    indices.append((indexed.setdefault(key, len(indexed)),))
            if not indices:
                continue
            positions = [tuple((v[:3] - translation) / scale) for v in indexed]
            attributes = {"POSITION": self.append(positions, "VEC3"),
                          "NORMAL": self.append([v[3:6] for v in indexed], "VEC3"),
                          "TEXCOORD_0": self.append([v[6:] for v in indexed], "VEC2")}
            output.append({"material": self.names[material], "attributes": attributes,
                           "indices": self.append(indices, "SCALAR")})
        return output

    def retain_rig_surfaces(self, node):
        parts = self.meshes[node["mesh"]]["primitives"]
        parents = {}
        triangles = []
        translation = np.asarray(node["translation"])
        scale = np.asarray(node["scale"])

        def root(p):
            while parents[p] != p:
                parents[p] = parents[parents[p]]
                p = parents[p]
            return p

        for part_index, part in enumerate(parts):
            positions = self.read(part["attributes"]["POSITION"])
            keys = [tuple(round(x, 6) for x in p) for p in positions]
            indices = [i[0] for i in self.read(part["indices"])] if "indices" in part else list(range(len(keys)))
            for j in range(0, len(indices), 3):
                corners = indices[j:j + 3]
                a, b, c = (keys[i] for i in corners)
                for key in (a, b, c):
                    parents.setdefault(key, key)
                main = root(a)
                parents[root(b)] = main
                parents[root(c)] = main
                triangles.append((part_index, corners, (a, b, c)))
        components = defaultdict(list)
        for part_index, corners, points in triangles:
            components[root(points[0])].append((part_index, corners, points))
        kept = defaultdict(list)
        for faces in components.values():
            points = np.array([p for _, _, triangle in faces for p in triangle]) * scale + translation
            low, high = np.min(points, axis=0), np.max(points, axis=0)
            replaced_body = low[2] < -10.5 and high[2] > 9.8 and max(abs(low[0]), abs(high[0])) < 1.7
            replaced_duct = (-4.24 < low[2] < -3.64 and -3.99 < high[2] < -0.83
                             and (low[0] > 0.45 or high[0] < -0.45) and max(abs(low[0]), abs(high[0])) < 1.83
                             and low[1] < -0.40)
            canopy_bows = (max(abs(low[0]), abs(high[0])) < 0.60 and low[1] > 0.43
                           and -5.58 < low[2] < -3.69 and high[2] - low[2] < 0.10)
            faces_are_new = all(parts[i].get("extras", {}).get("j20_surface") for i, _, _ in faces)
            if replaced_body or replaced_duct or canopy_bows or faces_are_new:
                continue
            for part_index, indices, _ in faces:
                kept[part_index].extend(indices)
        if len(kept) == len(parts) and all(len(kept[i]) == self.access[p["indices"]]["count"]
                                           for i, p in enumerate(parts) if "indices" in p):
            raise ValueError("No inherited J-20 surfaces were identified for replacement")
        for part_index, indices in kept.items():
            old = parts[part_index]
            if old.get("extras", {}).get("j20_surface"):
                continue
            remap = {original: i for i, original in enumerate(dict.fromkeys(indices))}
            attrs = {}
            for semantic, accessor in old["attributes"].items():
                all_rows = self.read(accessor)
                attrs[semantic] = self.append([all_rows[original] for original in remap], self.access[accessor]["type"])
            yield {**old, "attributes": attrs, "indices": self.append([(remap[i],) for i in indices], "SCALAR")}

    def replace(self, node_by_name, canopy_by_name, detail):
        node = next(entry for entry in self.nodes if entry.get("name") == node_by_name)
        mesh = self.meshes[node["mesh"]]
        hull = airframe(*detail[:2])
        for material, triangles in intakes(detail[2], detail[2] >= 16).items():
            hull[material].extend(triangles)
        inherited = list(self.retain_rig_surfaces(node))
        rebuilt = self.pack_surfaces(hull, node)
        for primitive in rebuilt:
            primitive["extras"] = {"j20_surface": True}
        mesh["primitives"] = inherited + rebuilt
        mesh["extras"] = {"airframe_id": "j20", "master_space": "airframe_metres"}
        canopy = next(entry for entry in self.nodes if entry.get("name") == canopy_by_name)
        self.meshes[canopy["mesh"]]["primitives"] = self.pack_surfaces(
            clear_canopy(detail[3], detail[4]), canopy)

    def add_game_anchors(self):
        # Hit proxies are in the same metre space as the loft and nozzles.
        # Sections overlap so a sweep can cross joints without missing a hit.
        proxies = [
            ("CenterRadome", (0.0, 0.035, -7.72), (0.72, 0.56, 3.07), 0),
            ("CenterForebody", (0.0, 0.060, -4.62), (1.13, 0.83, 3.32), 0),
            ("CenterCanopy", (0.0, 0.64, -4.37), (0.59, 0.53, 1.65), 0),
            ("CenterAirframe", (0.0, -0.08, 1.10), (1.63, 0.87, 5.50), 0),
            ("CenterTail", (0.0, -0.12, 6.31), (1.53, 0.73, 4.00), 0),
        ]
        mounts = []
        for side, label in ((-1, "Port"), (1, "Starboard")):
            mounts.append({"name": label, "translation": [side * 0.92, -0.16, 9.66]})
            proxies.extend([
                (label + "Canard", (side * 1.81, 0.19, -2.94), (1.49, 0.22, 0.73), side * -25),
                (label + "Intake", (side * 1.19, -0.18, -2.67), (0.63, 0.55, 1.85), 0),
                (label + "InboardWing", (side * 2.51, -0.13, 3.09), (1.77, 0.31, 3.87), side * 20),
                (label + "OutboardWing", (side * 4.97, -0.11, 4.87), (2.07, 0.24, 1.70), side * -31),
                (label + "FinBase", (side * 1.80, 0.68, 6.74), (0.50, 0.99, 2.18), 0),
                (label + "FinTip", (side * 2.63, 1.97, 7.62), (0.57, 1.23, 1.46), 0),
                (label + "Nozzle", (side * 0.92, -0.16, 8.89), (0.86, 0.83, 1.18), 0),
            ])
        entries = []
        for name, position, extent, yaw in proxies:
            turn = radians(yaw) * 0.5
            entries.append({"name": name, "translation": position, "scale": extent,
                            "rotation": [0.0, sin(turn), 0.0, cos(turn)]})
        for name, nodes in (("J20HitProxies", entries), ("J20Exhausts", mounts)):
            children = list(range(len(self.nodes), len(self.nodes) + len(nodes)))
            self.nodes.extend(nodes)
            self.scene.append(len(self.nodes))
            self.nodes.append({"name": name, "children": children})

    def compact(self):
        # Drop superseded accessor payloads, including the previous breakup,
        # without re-encoding any preserved textures or animation channels.
        used_meshes = sorted({n["mesh"] for n in self.nodes if "mesh" in n})
        mesh_map = {old: i for i, old in enumerate(used_meshes)}
        self.doc["meshes"] = [self.meshes[i] for i in used_meshes]
        for n in self.nodes:
            if "mesh" in n:
                n["mesh"] = mesh_map[n["mesh"]]
        bindings = []
        for mesh in self.doc["meshes"]:
            for p in mesh["primitives"]:
                bindings.extend((p["attributes"], key) for key in p["attributes"])
                if "indices" in p:
                    bindings.append((p, "indices"))
        for clip in self.doc.get("animations", []):
            for sampler in clip["samplers"]:
                bindings.extend(((sampler, "input"), (sampler, "output")))
        accessors = sorted({section[key] for section, key in bindings})
        mapping = {ix: i for i, ix in enumerate(accessors)}
        for section, key in bindings:
            section[key] = mapping[section[key]]
        self.doc["accessors"] = [self.access[ix] for ix in accessors]
        bound_views = self.doc["accessors"] + [im for im in self.doc.get("images", []) if "bufferView" in im]
        views = sorted({view["bufferView"] for view in bound_views})
        mapping = {ix: i for i, ix in enumerate(views)}
        for view in bound_views:
            view["bufferView"] = mapping[view["bufferView"]]
        compact = bytearray()
        self.doc["bufferViews"] = []
        for ix in views:
            view = self.views[ix]
            start = view.get("byteOffset", 0)
            compact.extend(b"\0" * (-len(compact) % 4))
            self.doc["bufferViews"].append({**view, "byteOffset": len(compact)})
            compact.extend(self.buffer[start:start + view["byteLength"]])
        compact.extend(b"\0" * (-len(compact) % 4))
        return compact


def build(source, output, master):
    atlas = None if master else output.with_name(f"{output.stem}_skin_orm.png")
    asset = Asset(source, atlas)
    # The existing offline breakup tool bakes the updated shell with the
    # same five IDs. Other nodes, their animation indices and mounts survive.
    breakup = next((i for i in asset.scene if asset.nodes[i]["name"] == "Breakup"), None)
    if breakup is not None:
        group = asset.nodes[breakup]
        assert set(group["children"] + [breakup]) == set(range(min(group["children"]), len(asset.nodes)))
        asset.scene.remove(breakup)
        del asset.nodes[min(group["children"]):]
    authored = [i for i in asset.scene if asset.nodes[i]["name"] in {"J20HitProxies", "J20Exhausts"}]
    if authored:
        first = min(child for i in authored for child in asset.nodes[i]["children"])
        asset.scene[:] = [i for i in asset.scene if i not in authored]
        del asset.nodes[first:]
    asset.replace("Airframe shell mesh", "Canopy glass",
                  (148, 96, 42, 72, 48) if master else (34, 32, 20, 23, 18))
    asset.replace("Airframe shell.001 mesh", "Canopy glass.001", (18, 20, 12, 13, 12))
    asset.replace("Airframe shell.002 mesh", "Canopy glass.002", (10, 10, 8, 7, 6))
    asset.add_game_anchors()
    write_model(output, asset.doc, asset.compact())
    if not master:
        bake(output)
    print(f"{output}: {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("source", type=Path)
    args.add_argument("output", type=Path)
    args.add_argument("--master", action="store_true", help="write the high-density authoring mesh")
    settings = args.parse_args()
    build(settings.source, settings.output, settings.master)
