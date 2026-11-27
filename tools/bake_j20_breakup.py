"""Cut aircraft wreck components offline without re-encoding paint or animations."""

import json
import math
from pathlib import Path
from struct import pack, unpack_from


MODEL = Path(__file__).resolve().parents[1] / "assets/fleet/j20.glb"


def read_model(path):
    raw = path.read_bytes()
    size = unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + size]), bytearray(raw[28 + size:])


def cut(poly, axis, limit, direction):
    output = []
    for a, b in zip(poly[-1:] + poly[:-1], poly):
        da = (a[axis] - limit) * direction
        db = (b[axis] - limit) * direction
        if (da < 0.0) != (db < 0.0):
            t = da / (da - db)
            output.append(tuple(p + (q - p) * t for p, q in zip(a, b)))
        if db >= 0.0:
            output.append(b)
    return output


def bake(model=MODEL, *, shell_name="Airframe shell", dimensions=None):
    doc, buffer = read_model(model)
    scene = doc["scenes"][doc["scene"]]["nodes"]
    if any(doc["nodes"][node].get("name") == "Breakup" for node in scene):
        return
    source = next(node for node in doc["nodes"] if node.get("name") == f"{shell_name} mesh")

    def read(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        schema = {5123: "H", 5125: "I", 5126: "f"}[accessor["componentType"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[accessor["type"]]
        stride = view.get("byteStride", count * (2 if schema == "H" else 4))
        origin = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return [unpack_from("<" + schema * count, buffer, origin + i * stride) for i in range(accessor["count"])]

    def add(values, semantic, bounds=False):
        origin = len(buffer)
        rows = len(values[0])
        if semantic == "SCALAR":
            schema = "H" if dimensions and max(x[0] for x in values) < 65536 else "I"
        else:
            schema = "f"
        for value in values:
            buffer.extend(pack("<" + schema * rows, *value))
        byte_length = len(buffer) - origin
        buffer.extend(b"\0" * (-len(buffer) % 4))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": origin, "byteLength": byte_length})
        accessor = {"bufferView": view, "componentType": {"H": 5123, "I": 5125, "f": 5126}[schema],
                    "count": len(values), "type": semantic}
        if bounds:
            accessor.update(min=[min(axis) for axis in zip(*values)], max=[max(axis) for axis in zip(*values)])
        doc["accessors"].append(accessor)
        return len(doc["accessors"]) - 1

    surfaces = []

    def collect(node, offset, scale):
        if "rotation" in node or "matrix" in node:
            raise ValueError(f"{node['name']} must use unrotated rest coordinates")
        offset = tuple(a + b * c for a, b, c in zip(offset, scale, node.get("translation", (0, 0, 0))))
        scale = tuple(a * b for a, b in zip(scale, node.get("scale", (1, 1, 1))))
        if "mesh" in node:
            for part in doc["meshes"][node["mesh"]]["primitives"]:
                attrs = part["attributes"]
                positions = read(attrs["POSITION"])
                normals = read(attrs["NORMAL"])
                texcoords = read(attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else [(0.0, 0.0)] * len(positions)
                points = [tuple((x * s + o - t) / k for x, s, o, t, k in zip(p, scale, offset,
                                                                                source["translation"], source["scale"]))
                          for p in positions]
                corners = [p + n + uv for p, n, uv in zip(points, normals, texcoords)]
                indices = [i[0] for i in read(part["indices"])] if "indices" in part else list(range(len(corners)))
                triangles = [[corners[i] for i in indices[s:s + 3]] for s in range(0, len(indices), 3)]
                surfaces.append((part["material"], triangles))
        for child in node.get("children", []):
            collect(doc["nodes"][child], offset, scale)

    shell = next(node for node in doc["nodes"] if node.get("name") == shell_name)
    collect(shell, (0, 0, 0), (1, 1, 1))
    if dimensions:
        combat = next(doc["nodes"][index] for index in scene if doc["nodes"][index]["name"] == "Combat")
        for index in combat.get("children", ()):
            component = doc["nodes"][index]
            if component["name"].startswith(("Drive nacelle", "Spinner", "Prop_", "RadarSpin", "Jammer pod")):
                collect(component, (0, 0, 0), (1, 1, 1))

    interior = next(i for i, entry in enumerate(doc["materials"]) if entry.get("name") == "dark")

    def seal(points, axis, limit, direction):
        u, v = ((1, 2) if axis == 0 else (0, 1))
        flat = sorted({(round(point[u], 5), round(point[v], 5))
                       for point in points if abs(point[axis] - limit) < 0.00001})
        if len(flat) < 3:
            return []
        def chain(items):
            result = []
            for point in items:
                while len(result) >= 2:
                    a, b = result[-2:]
                    if (b[0] - a[0]) * (point[1] - a[1]) > (b[1] - a[1]) * (point[0] - a[0]):
                        break
                    result.pop()
                result.append(point)
            return result[:-1]
        outline = chain(flat) + chain(reversed(flat))
        if direction > 0:
            outline.reverse()
        return [(limit, a, b) if axis == 0 else (a, b, limit) for a, b in outline]

    def piece(name, planes):
        output, boundary = [], []
        for material, triangles in surfaces:
            coordinates, indices, index_map = [], [], {}
            for triangle in triangles:
                poly = triangle
                for axis, limit, direction in planes:
                    poly = cut(poly, axis, limit, direction)
                    if not poly:
                        break
                for i in range(1, len(poly) - 1):
                    for vertex in (poly[0], poly[i], poly[i + 1]):
                        vertex = tuple(round(component, 6) for component in vertex)
                        if vertex not in index_map:
                            index_map[vertex] = len(coordinates)
                            coordinates.append(vertex)
                        indices.append((index_map[vertex],))
            if not indices:
                continue
            boundary.extend(coordinates)
            normals = []
            for vertex in coordinates:
                normal = vertex[3:6]
                length = max(0.0001, math.sqrt(sum(v * v for v in normal)))
                normals.append(tuple(v / length for v in normal))
            output.append({"material": material, "attributes": {
                "POSITION": add([v[:3] for v in coordinates], "VEC3", bounds=True),
                "NORMAL": add(normals, "VEC3"),
                "TEXCOORD_0": add([v[6:] for v in coordinates], "VEC2"),
            }, "indices": add(indices, "SCALAR")})
        for axis, limit, direction in planes:
            points = seal(boundary, axis, limit, direction)
            if len(points) >= 3:
                normal = tuple(-direction if n == axis else 0.0 for n in range(3))
                output.append({"material": interior, "attributes": {
                    "POSITION": add(points, "VEC3", bounds=True),
                    "NORMAL": add([normal] * len(points), "VEC3"),
                }, "indices": add([(i,) for s in range(1, len(points) - 1) for i in (0, s, s + 1)], "SCALAR")})
        doc["meshes"].append({"name": name, "primitives": output})
        node = {"name": name, "mesh": len(doc["meshes"]) - 1}
        for param in ("translation", "rotation", "scale"):
            if param in source:
                node[param] = source[param]
        doc["nodes"].append(node)
        return len(doc["nodes"]) - 1

    left, right, front, aft = -0.245, 0.245, -0.46, 0.31
    if dimensions:
        span, length = dimensions
        x, _, z = source["translation"]
        sx, _, sz = source["scale"]
        left, right = (-span * 0.17 - x) / sx, (span * 0.17 - x) / sx
        front, aft = (-length * 0.22 - z) / sz, (length * 0.22 - z) / sz
    centre = [(0, left, 1), (0, right, -1)]
    parts = [
        piece("Central fuselage", centre + [(2, front, 1), (2, aft, -1)]),
        piece("Port wing", [(0, left, -1)]),
        piece("Starboard wing", [(0, right, 1)]),
        piece("Aft nacelles", centre + [(2, aft, 1)]),
        piece("Forward fuselage", centre + [(2, front, -1)]),
    ]
    scene.append(len(doc["nodes"]))
    doc["nodes"].append({"name": "Breakup", "children": parts})
    write_model(model, doc, buffer)


def write_model(model, doc, buffer):
    doc["buffers"][0]["byteLength"] = len(buffer)
    text = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    model.write_bytes(pack("<4sII", b"glTF", 2, 28 + len(text) + len(buffer))
                      + pack("<I4s", len(text), b"JSON") + text
                      + pack("<I4s", len(buffer), b"BIN\0") + buffer)


if __name__ == "__main__":
    bake()
