"""Refine the authored fleet surfaces and derive the shared native airframe assets."""

import argparse
from collections import defaultdict
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from airframe_glb import AirframeGLB
from bake_j20_breakup import bake, write_model


LEVELS = ("Exterior", "Combat", "LOD")
CURVED_MATERIALS = {"skin", "belly", "panel", "radome", "glass", "intake", "titanium"}
LEVEL_EDGE_BUDGET = (290, 112, 42)


def unit(vector):
    return vector / max(np.linalg.norm(vector), 1e-12)


def branch(asset, root):
    yield asset.nodes[root]
    for child in asset.nodes[root].get("children", ()):
        yield from branch(asset, child)


def read_primitive(asset, primitive):
    values = {key: np.asarray(asset.read(index)) for key, index in primitive["attributes"].items()}
    corners = values["POSITION"]
    indices = (np.asarray(asset.read(primitive["indices"])).ravel() if "indices" in primitive
               else np.arange(len(corners)))
    return values, indices.reshape((-1, 3))


def edge_key(a, b):
    return (a, b) if a < b else (b, a)


def patches(corners, mids):
    """Split a triangle without creating mismatched edges at paint seams."""
    a, b, c = corners
    u, v, w = mids
    count = sum(mid is not None for mid in mids)
    if count == 0:
        return ((a, b, c),)
    if count == 3:
        return ((a, u, w), (u, b, v), (w, v, c), (u, v, w))
    if count == 1:
        i = next(i for i, mid in enumerate(mids) if mid is not None)
        a, b, c = corners[i:] + corners[:i]
        u = mids[i]
        return ((a, u, c), (u, b, c))
    i = next(i for i, mid in enumerate(mids) if mid is None)
    a, b, c = corners[i:] + corners[:i]
    _, v, w = mids[i:] + mids[:i]
    return ((a, b, v), (a, v, w), (w, v, c))


def refine(asset, node, level, master):
    """Tessellate curved Hermite edges while retaining the original paint UV charts."""
    mesh = asset.meshes[node["mesh"]]
    scale = float(max(node.get("scale", (1.0, 1.0, 1.0))))
    budget = LEVEL_EDGE_BUDGET[level]
    if node["name"].startswith("Canopy"):
        budget = max(12, budget // 8)
    if master and level == 0:
        budget *= 10
    edges = defaultdict(list)
    sources = []
    for primitive in mesh["primitives"]:
        vertices, faces = read_primitive(asset, primitive)
        positions = vertices["POSITION"]
        normals = vertices["NORMAL"]
        keys = [tuple(p) for p in np.round(positions, 6)]
        sources.append((primitive, vertices, faces, keys))
        smooth = asset.materials[primitive["material"]]["name"] in CURVED_MATERIALS
        for triangle in faces:
            p, q, r = positions[triangle]
            face_normal = unit(np.cross(q - p, r - p))
            for i in range(3):
                a, b, opposite = triangle[i], triangle[(i + 1) % 3], triangle[(i + 2) % 3]
                if keys[b] < keys[a]:
                    a, b = b, a
                pa, pb = positions[a], positions[b]
                extent = np.linalg.norm(pb - pa)
                threshold = (0.087, 0.15, 0.27)[level] / scale
                if master and level == 0:
                    threshold *= 0.42
                if extent < threshold or extent < 1e-10:
                    continue
                normal_a, normal_b = normals[a], normals[b]
                altitude = np.linalg.norm(np.cross(pb - pa, positions[opposite] - pa)) / extent
                valid = smooth and min(np.dot(normal_a, face_normal), np.dot(normal_b, face_normal)) > 0.18
                edges[(keys[a], keys[b])].append((pa, pb, normal_a, normal_b, face_normal, altitude, valid))

    choices = []
    for edge, samples in edges.items():
        # Exclude seams between rigid parts and fixed feature edges. Seam
        # occurrences used by two paints still share one generated position.
        if len(samples) != 2 or not all(s[-1] for s in samples):
            continue
        a, b = samples
        if min(np.dot(a[2], b[2]), np.dot(a[3], b[3]), np.dot(a[4], b[4])) < 0.67:
            continue
        pa, pb = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        na, nb = unit(a[2] + b[2]), unit(a[3] + b[3])
        bend = np.dot(na, nb)
        if not 0.22 < bend < 0.996:
            continue
        tangent = pb - pa
        shift = 0.20 * (nb * np.dot(tangent, nb) - na * np.dot(tangent, na))
        error = np.linalg.norm(shift)
        if error * scale < (0.0012, 0.0035, 0.008)[level]:
            continue
        limit = min(min(a[5], b[5]) * 0.14, 0.045 / scale)
        center = (pa + pb) * 0.5 + shift * min(1.0, limit / error)
        choices.append((error, edge, center, unit(na + nb)))
    selected = {key: (center, normal)
                for _, key, center, normal in sorted(choices, key=lambda item: (-item[0], item[1]))[:budget]}
    if not selected:
        return 0

    for primitive, vertices, faces, keys in sources:
        matching = {}
        output = []
        additions = defaultdict(list)
        for i, j, k in faces:
            mids = []
            for a, b in ((i, j), (j, k), (k, i)):
                value = selected.get(edge_key(keys[a], keys[b]))
                if value is None:
                    mids.append(None)
                    continue
                key = (min(a, b), max(a, b))
                if key not in matching:
                    matching[key] = len(keys) + len(matching)
                    additions["POSITION"].append(value[0])
                    additions["NORMAL"].append(value[1])
                    if "TEXCOORD_0" in vertices:
                        uv = vertices["TEXCOORD_0"]
                        additions["TEXCOORD_0"].append((uv[a] + uv[b]) * 0.5)
                mids.append(matching[key])
            output.extend(patches((i, j, k), tuple(mids)))
        if matching:
            for name, rows in additions.items():
                schema = asset.access[primitive["attributes"][name]]["type"]
                primitive["attributes"][name] = asset.append(np.vstack((vertices[name], rows)), schema)
            indices = np.asarray(output).reshape(-1, 1)
            primitive["indices"] = asset.append(indices, "SCALAR")
    return len(selected)


def meshes_in_space(asset, root):
    """Collect resting meshes in aircraft coordinates, including detached nacelles."""
    def visit(index, transform):
        node = asset.nodes[index]
        basis = Rotation.from_quat(node.get("rotation", (0, 0, 0, 1))).as_matrix()
        local = np.eye(4)
        local[:3, :3] = basis * node.get("scale", (1, 1, 1))
        local[:3, 3] = node.get("translation", (0, 0, 0))
        placement = transform @ local
        if "mesh" in node:
            yield node["name"], asset.meshes[node["mesh"]], placement
        for child in node.get("children", ()):
            if not asset.nodes[child]["name"].startswith(("Gear_", "Prop_", "Store_", "Bay_")):
                yield from visit(child, placement)

    yield from visit(root, np.eye(4))


def components(asset, mesh, placement):
    """Find connected parts even when painted surface groups split their indices."""
    parents = {}
    points = {}

    def root(point):
        while parents[point] != point:
            parents[point] = parents[parents[point]]
            point = parents[point]
        return point

    for primitive in mesh["primitives"]:
        values, faces = read_primitive(asset, primitive)
        vertices = values["POSITION"] @ placement[:3, :3].T + placement[:3, 3]
        keys = list(map(tuple, np.round(vertices, 4)))
        for key, vertex in zip(keys, vertices):
            parents.setdefault(key, key)
            points[key] = vertex
        for i, j, k in faces:
            a, b, c = map(root, (keys[i], keys[j], keys[k]))
            parents[b] = a
            parents[c] = a
    groups = defaultdict(list)
    for key, point in points.items():
        groups[root(key)].append(point)
    return [np.asarray(group) for group in groups.values()]


def coordinates(points):
    horizontal = points[:, [0, 2]] - points[:, [0, 2]].mean(axis=0)
    _, _, principal = np.linalg.svd(horizontal, full_matrices=False)
    direction = principal[0]
    if direction[1] < 0.0:
        direction = -direction
    a, b = direction
    basis = np.array(((b, 0.0, a), (0.0, 1.0, 0.0), (-a, 0.0, b)))
    return basis, points @ basis


def proxy(points, label):
    basis, box = coordinates(points)
    lower, upper = box.min(axis=0), box.max(axis=0)
    scale = np.maximum((upper - lower) * (0.59, 0.64, 0.59), (0.12, 0.13, 0.20))
    center = basis @ ((lower + upper) * 0.5)
    return {"name": label, "scale": scale.tolist(), "translation": center.tolist(),
            "rotation": Rotation.from_matrix(basis).as_quat().tolist()}


def add_nodes(asset, label, entries):
    first = len(asset.nodes)
    asset.nodes.extend(entries)
    asset.scene.append(len(asset.nodes))
    asset.nodes.append({"name": label, "children": list(range(first, len(asset.nodes)))})


def derive_attachments(asset, exterior, spec):
    candidates = []
    for name, mesh, placement in meshes_in_space(asset, exterior):
        for points in components(asset, mesh, placement):
            if len(points) < 18:
                continue
            lower, upper = points.min(axis=0), points.max(axis=0)
            span, height, length = upper - lower
            center = (lower + upper) * 0.5
            if max(span, height, length) < spec["length"] * 0.09 or sorted((span, height, length))[-2] < 0.11:
                continue
            if "Canopy" in name:
                label = "Canopy"
            elif name.startswith(("Drive nacelle", "Spinner")):
                label = "Engine"
            elif abs(center[0]) > spec["span"] * 0.09 and span > spec["span"] * 0.12:
                label = "Wing"
            elif length > spec["length"] * 0.64 and abs(center[0]) < spec["span"] * 0.05:
                label = "Fuselage"
            elif height > spec["length"] * 0.09 and center[1] > 0.25:
                label = "Fin"
            elif name.startswith("Radar"):
                label = "Radar"
            else:
                label = "Shell"
            score = max(span * length, height * length, span * height)
            candidates.append((score, label, points))
    entries = []
    count_by_label = defaultdict(int)
    for _, label, points in sorted(candidates, key=lambda row: -row[0])[:18]:
        _, chart = coordinates(points)
        fractions = (0.22, 0.48, 0.73) if label == "Fuselage" else (0.52,) if label == "Wing" else ()
        first, last = chart[:, 2].min(), chart[:, 2].max()
        boundaries = [first + (last - first) * f for f in fractions]
        bands = [points]
        if boundaries:
            pad = (last - first) * 0.075
            provisional = [points[(chart[:, 2] >= a - pad) & (chart[:, 2] <= b + pad)]
                           for a, b in zip([first, *boundaries], [*boundaries, last])]
            if all(len(part) >= 10 for part in provisional):
                bands = provisional
        for band in bands:
            if len(entries) == 25:
                break
            side = "Port" if band[:, 0].mean() < -0.3 else "Starboard" if band[:, 0].mean() > 0.3 else "Centre"
            name = side + label
            count_by_label[name] += 1
            entries.append(proxy(band, f"{name}{count_by_label[name]}"))
    if not entries:
        raise ValueError(f"{spec['id']}: no fitted collision sections")
    add_nodes(asset, "HitProxies", entries)
    if spec["engine"] and not spec["props"]:
        # Preserve the catalog's per-engine attachment points on the inherited
        # engine geometry. The artists can now inspect them with the same rig.
        mounts = [{"name": f"Nozzle{i + 1}", "translation": mount[:3]}
                  for i, mount in enumerate(spec["engine"])]
        add_nodes(asset, "Exhausts", mounts)
    return len(entries)


def triangle_count(asset, root):
    return sum((asset.access[part["indices"]]["count"] if "indices" in part
                else asset.access[part["attributes"]["POSITION"]]["count"]) // 3
               for node in branch(asset, root) if "mesh" in node
               for part in asset.meshes[node["mesh"]]["primitives"])


def build(source, output, spec, master):
    asset = AirframeGLB(source)
    if any(asset.nodes[index]["name"] in {"HitProxies", "Breakup"} for index in asset.scene):
        raise ValueError(f"{spec['id']}: choose the original source rig for a repeatable bake")
    roots = {asset.nodes[index]["name"]: index for index in asset.scene}
    baseline = [triangle_count(asset, roots[level]) for level in LEVELS]
    edits = []
    for level, name in enumerate(LEVELS):
        root = roots[name]
        edits.append(sum(refine(asset, mesh, level, master) for mesh in branch(asset, root)
                         if "mesh" in mesh and mesh["name"].startswith(("Airframe shell", "Canopy glass"))))
    upgraded = [triangle_count(asset, roots[name]) for name in LEVELS]
    if not all(edits) or not upgraded[0] > upgraded[1] > upgraded[2]:
        raise ValueError(f"{spec['id']}: incomplete or misordered detail levels {edits} {upgraded}")
    nproxies = derive_attachments(asset, roots["Exterior"], spec)
    write_model(output, asset.doc, asset.compact())
    if not master:
        bake(output, shell_name="Airframe shell.001", dimensions=(spec["span"], spec["length"]))
    return {"id": spec["id"], "before": baseline, "after": upgraded, "curved_edges": edits,
            "collision_proxies": nproxies, "before_bytes": source.stat().st_size,
            "after_bytes": output.stat().st_size}


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="directory containing the original GLBs")
    parser.add_argument("output", type=Path)
    parser.add_argument("--only", nargs="+")
    parser.add_argument("--master", action="store_true", help="output dense source meshes for offline art tools")
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error("Use a separate output directory to retain the authored source rigs.")
    catalogue = Path(__file__).resolve().parents[1] / "assets/campaign.json"
    aircraft = json.loads(catalogue.read_text())["fleet"]
    args.output.mkdir(parents=True, exist_ok=True)
    for spec in aircraft:
        identity = spec["id"]
        if identity == "j20" or (args.only and identity not in args.only):
            continue
        name = f"{identity}.glb"
        print(json.dumps(build(args.source / name, args.output / name, spec, args.master)), flush=True)


if __name__ == "__main__":
    run()
