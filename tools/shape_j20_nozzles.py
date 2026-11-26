"""Replace the rear nozzle trim of the existing J-20 exterior with modeled petals."""
import argparse
import io
import json
from math import cos, pi, sin
import struct
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
raw = args.source.read_bytes()
header_size = struct.unpack_from("<I", raw, 12)[0]
model = json.loads(raw[20:20 + header_size])
data = bytearray(raw[28 + header_size:])
name = "Nozzle alloy and ceramic"
if any(material.get("name") == name for material in model["materials"]):
    raise ValueError("Provide the original exterior geometry")

def view(blob, target=None):
    data.extend(b"\0" * (-len(data) % 4))
    location = len(data)
    data.extend(blob)
    index = len(model["bufferViews"])
    model["bufferViews"].append({"buffer": 0, "byteOffset": location, "byteLength": len(blob)})
    if target:
        model["bufferViews"][-1]["target"] = target
    return index


def floats(values):
    values = np.asarray(values, dtype="<f4")
    index = len(model["accessors"])
    model["accessors"].append({"bufferView": view(values.tobytes(), 34962), "componentType": 5126,
        "count": len(values), "type": {2:"VEC2", 3:"VEC3"}[values.shape[1]],
        "min": values.min(axis=0).tolist(), "max": values.max(axis=0).tolist()})
    return index


def read(accessor_number, dtype, width):
    accessor = model["accessors"][accessor_number]
    buffer_view = model["bufferViews"][accessor["bufferView"]]
    offset = buffer_view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = buffer_view.get("byteStride", dtype.itemsize * width)
    values = np.ndarray((accessor["count"], width), dtype=dtype, buffer=data,
                        offset=offset, strides=(stride, dtype.itemsize))
    return accessor, values.copy(), offset

exterior = next(node for node in model["nodes"] if node.get("name") == "Airframe shell mesh")
primitives = model["meshes"][exterior["mesh"]]["primitives"]
for original in primitives:
    label = model["materials"][original["material"]]["name"]
    if label not in {"titanium", "dark"}:
        continue
    _, positions, _ = read(original["attributes"]["POSITION"], np.dtype("<f4"), 3)
    index_type = {5123: np.dtype("<u2"), 5125: np.dtype("<u4")}[model["accessors"][original["indices"]]["componentType"]]
    index, indices, offset = read(original["indices"], index_type, 1)
    triangles = indices.reshape(-1, 3)
    points = positions[triangles]
    rear_ring = ((points[..., 2] > 0.895) & (abs(points[..., 0]) < 0.183)).all(axis=1)
    output = triangles[~rear_ring].tobytes()
    data[offset:offset + indices.nbytes] = output + b"\0" * (indices.nbytes - len(output))
    index["count"] -= int(rear_ring.sum()) * 3
    if "max" in index:
        index["max"] = [int(triangles[~rear_ring].max())]
    if "min" in index:
        index["min"] = [int(triangles[~rear_ring].min())]

positions, normals, uv = [], [], []
petals = 14
step = 2 * pi / petals

def quad(corners, texcoords, outward):
    n = np.cross(np.subtract(corners[1], corners[0]), np.subtract(corners[2], corners[0]))
    if np.dot(n, outward) < 0.0:
        corners = corners[::-1]
        texcoords = texcoords[::-1]
        n = -n
    n /= np.linalg.norm(n)
    for k in (0, 1, 2, 0, 2, 3):
        positions.append(corners[k])
        normals.append(n)
        uv.append(texcoords[k])


for centre in (-0.08911, 0.08911):
    for petal in range(petals):
        angle = step * petal

        def point(a, radius, z):
            phi = angle + step * a
            return centre + radius * cos(phi), -0.11988 + radius * sin(phi), z

        axis = np.array([cos(angle), sin(angle), 0.0])
        # Each petal has folded sides, a stiffened centre, a lip and a recessed ceramic lining.
        outer = [(0.078, 0.899), (0.080, 0.920), (0.073, 0.948), (0.067, 0.971)]
        for strip in range(3):
            r0, z0 = outer[strip]
            r1, z1 = outer[strip + 1]
            for a0, a1 in [(-0.475, -0.22), (-0.22, 0.22), (0.22, 0.475)]:
                def formed(a, radius, z):
                    flange = 0.0016 if abs(a) < 0.3 else -0.0010
                    tip = -0.0060 * abs(a) if z > 0.95 else 0.0
                    return point(a, radius + flange, z + tip)
                y0, y1 = 0.12 + strip * 0.14, 0.26 + strip * 0.14
                quad([formed(a0,r0,z0), formed(a1,r0,z0), formed(a1,r1,z1), formed(a0,r1,z1)],
                     [(a0+.5,y0),(a1+.5,y0),(a1+.5,y1),(a0+.5,y1)], axis)
        a0, a1 = -0.475, 0.475
        quad([point(a0, .067, .968), point(a1, .067, .968), point(a1, .054, .966), point(a0, .054, .966)],
             [(0,.54),(1,.54),(1,.64),(0,.64)], (0,0,1))
        quad([point(a0, .054, .966), point(a1, .054, .966), point(a1, .048, .895), point(a0, .048, .895)],
             [(0,.65),(1,.65),(1,.96),(0,.96)], -axis)

y, x = np.mgrid[:64, :64] / 63.0
inner = np.clip((y - 0.56) * 7.0, 0, 1)
flange = 1.0 - np.clip(np.minimum(x, 1 - x) * 14, 0, 1)
packed = np.stack((0.98 - inner * 0.47 - flange * 0.12, 0.38 + inner * 0.38 + flange * 0.055,
                  0.88 - inner * 0.70), axis=-1)
png = io.BytesIO()
Image.fromarray(np.uint8(np.rint(np.clip(packed, 0, 1) * 255))).save(png, format="PNG", optimize=True)
model["images"].append({"bufferView": view(png.getvalue()), "mimeType": "image/png", "name": "Nozzle material mask"})
texture = len(model["textures"])
model["textures"].append({"source": len(model["images"]) - 1})
material = len(model["materials"])
model["materials"].append({"name": name,
    "pbrMetallicRoughness": {"baseColorFactor": [0.205, 0.235, 0.258, 1],
        "metallicRoughnessTexture": {"index": texture}}, "occlusionTexture": {"index": texture}})
primitives.append({"attributes":{"POSITION":floats(positions), "NORMAL":floats(normals), "TEXCOORD_0":floats(uv)},
                   "material":material, "mode":4})
data.extend(b"\0" * (-len(data) % 4))
model["buffers"][0]["byteLength"] = len(data)
header = json.dumps(model, separators=(",", ":")).encode()
header += b" " * (-len(header) % 4)
args.output.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(data))
    + struct.pack("<I4s", len(header), b"JSON") + header + struct.pack("<I4s", len(data), b"BIN\0") + data)
