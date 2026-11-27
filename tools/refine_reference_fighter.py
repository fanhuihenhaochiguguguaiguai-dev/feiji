"""Shape the existing studio airframe from cached multiview constraints.

The rows measure leading and trailing edges as fractions of the aircraft
length at normalized half-span stations. Aircraft/02 provides the planform.
Aircraft/01 and /04 constrain the canopy and fin treatment; /03 checks the
same assignments in the carrier lighting. Only this airframe uses the fit.
"""
import argparse
from pathlib import Path

import numpy as np

from airframe_glb import AirframeGLB
from bake_j20_breakup import write_model
from derive_reference_combat import GEAR


# Leading/trailing edge measurements captured once from the isolated top view.
SPAN = np.array([.14, .28, .40, .52, .65, .77, .88, .95, 1.0])
SOURCE = np.array([
    [.365, .905], [.433, .854], [.492, .833], [.551, .820], [.618, .812],
    [.669, .809], [.718, .806], [.740, .802], [.765, .792],
])
REFERENCE = np.array([
    [.365, .905], [.309, .994], [.354, .975], [.396, .965], [.612, .900],
    [.648, .896], [.681, .890], [.700, .886], [.735, .853],
])
FIT_STRENGTH = .61
NOSE = -11.35
LENGTH = 22.18
HALF_SPAN = 7.25
SURFACES = {
    "Carbon graphite · satin radar finish": ((.025, .028, .032), .63, .28, .33, .22),
    "Wing ceramic composite": ((.065, .074, .086), .61, .35, .22, .28),
    "Silver-grey wing edge": ((.32, .348, .389), .74, .26, .20, .24),
    "Blue-green optical multilayer": ((.035, .168, .156), .13, .135, .79, .12),
}


def smooth(low, high, values):
    t = np.clip((values - low) / (high - low), 0., 1.)
    return t*t*(3. - 2.*t)


def span_curve(points, values):
    span = np.clip(points, SPAN[0], SPAN[-1])
    segment = np.clip(np.searchsorted(SPAN, span) - 1, 0, len(SPAN) - 2)
    derivative = np.gradient(values, SPAN, axis=0)
    spacing = (SPAN[segment + 1] - SPAN[segment])[:, None]
    t = (span - SPAN[segment])[:, None] / spacing
    return ((2*t**3 - 3*t**2 + 1)*values[segment]
            + (t**3 - 2*t**2 + t)*spacing*derivative[segment]
            + (-2*t**3 + 3*t**2)*values[segment + 1]
            + (t**3 - t**2)*spacing*derivative[segment + 1])


def deform(points):
    x, y, z = points.T
    width = np.abs(x)
    span = width / HALF_SPAN
    extents = span_curve(span, SOURCE)
    residuals = span_curve(span, REFERENCE - SOURCE)
    chord = np.clip(((z - NOSE) / LENGTH - extents[:, 0]) / (extents[:, 1] - extents[:, 0]), 0., 1.)
    wing = smooth(1.25, 2.05, width) * (1. - smooth(.38, .82, np.abs(y)))
    wing *= 1. - smooth(8.9, 12.0, z)
    wing_delta = LENGTH * FIT_STRENGTH * wing * ((1.-chord)*residuals[:, 0] + chord*residuals[:, 1])

    cabin = np.exp(-((z + 3.85) / 2.04)**4) * (1. - smooth(.64, 1.88, width))
    crown = cabin * smooth(.45, 1.15, y)
    aft = smooth(5.1, 7.7, z) * smooth(.43, 2.62, y)
    return np.column_stack((
        x * (1. + crown*.19) + np.sign(x)*aft*.21,
        y + crown*.083 - aft*.18,
        z + wing_delta - crown*.18 + aft*.34,
    ))


def sculpt(points):
    x, y, z = points.T
    width = np.abs(x)
    fore = 1. - smooth(-6.1, -3.9, z)
    nose_width = np.interp(z, [-11.35, -10.7, -8.9, -6.8, -5.0, -2.7], [.026, .15, .47, .91, 1.22, 1.56])
    nose_depth = np.interp(z, [-11.35, -10.7, -8.9, -6.8, -5.0, -2.7], [.022, .10, .27, .47, .65, .78])
    height = y - .10
    edge = np.sqrt((x / nose_width)**2 + .002) + np.sqrt((height / nose_depth)**2 + .002)
    facet = 1. - (.63 * fore) * (1. - 1. / np.maximum(1., edge))
    body = (1. - smooth(1.08, 2.12, width)) * (1. - smooth(8.15, 10.4, z))
    cabin = (1. - smooth(.51, .83, width)) * smooth(-6.05, -5.05, z) * (1. - smooth(-2.43, -1.64, z))
    crown = cabin * smooth(.59, 1.12, y)
    intake = smooth(1.03, 1.92, width) * (1. - smooth(2.75, 3.8, width))
    intake *= smooth(-2.87, -1.53, z) * (1. - smooth(1.65, 4.8, z)) * (1. - smooth(-.12, .25, y))
    shoulder = smooth(1.12, 2.1, width) * (1. - smooth(2.9, 4.2, width)) * (1. - smooth(.29, .78, np.abs(y)))
    shoulder *= smooth(-4.1, -.72, z) * (1. - smooth(4.0, 8.7, z))
    wing = smooth(2.0, 3.75, width) * (1. - smooth(.42, .91, np.abs(y)))
    fold = .104 * (smooth(2.7, 4.9, width) - 1.62 * smooth(5.08, 6.96, width))
    return np.column_stack((
        x * facet * (1. - .075*fore + .16*crown) + np.sign(x)*(.17*intake + .10*shoulder),
        .10 + height*facet*(1. - .24*body*(1. - .62*cabin)) + .13*crown - .10*intake + .14*shoulder + wing*fold,
        z - .21*crown - .19*shoulder,
    ))


def shade(asset):
    for material in asset.materials:
        if material["name"] not in SURFACES:
            continue
        color, metal, roughness, coat, coat_roughness = SURFACES[material["name"]]
        material["pbrMetallicRoughness"].update(
            baseColorFactor=[*color, 1.], metallicFactor=metal, roughnessFactor=roughness,
        )
        material.setdefault("extensions", {})["KHR_materials_clearcoat"] = {
            "clearcoatFactor": coat, "clearcoatRoughnessFactor": coat_roughness,
        }
        if "normalTexture" in material:
            material["normalTexture"]["scale"] = .34
        if material["name"] == "Blue-green optical multilayer":
            material["alphaMode"] = "BLEND"
            material["doubleSided"] = True
            material["pbrMetallicRoughness"]["baseColorFactor"][3] = .42


def add_shell(asset, name, points, triangles, material):
    points = np.asarray(points, dtype=float)
    triangles = np.asarray(triangles)
    edges = points[triangles[:, 1:]] - points[triangles[:, :1]]
    products = np.cross(edges[:, 0], edges[:, 1])
    normal = np.zeros_like(points)
    for i in range(3):
        np.add.at(normal, triangles[:, i], products)
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
    # The root is the existing presentation body. The runtime builder will
    # batch these surfaces by material with the other aircraft parts.
    asset.nodes[asset.scene[0]]["children"].append(len(asset.nodes))
    asset.nodes.append({"name": name, "mesh": len(asset.meshes)})
    asset.meshes.append({"name": name, "primitives": [{
        "material": asset.names[material],
        "attributes": {"POSITION": asset.append(points, "VEC3"), "NORMAL": asset.append(normal, "VEC3")},
        "indices": asset.append(triangles.reshape(-1, 1), "SCALAR"),
    }]})


def add_cockpit(asset, shape):
    # A coaming and seat are actual surfaces in the volume beneath the glass.
    # These outlines sit inside the window and share the aircraft's calibrated
    # ordinate map, so they follow the same fairing in both camera views.
    metal = "Brushed titanium and steel"
    graphite = "Cockpit anthracite and fabric"
    asset.names[graphite] = len(asset.materials)
    asset.materials.append({"name": graphite, "doubleSided": True, "pbrMetallicRoughness": {
        "baseColorFactor": [.083, .105, .102, 1.0], "metallicFactor": .15, "roughnessFactor": .66,
    }})
    canopy = next(n for n in asset.nodes if n["name"] == "Low optical canopy")
    skin = asset.meshes[canopy["mesh"]]["primitives"][0]["attributes"]["POSITION"]
    shell = np.asarray(asset.read(skin))
    mid_z = -.5 * (abs(shell[:, 2].min()) + abs(shell[:, 2].max()))
    ring = shell[(abs(shell[:, 2] - mid_z - .41) < .075) & (shell[:, 1] > .67)]
    angle = np.arctan2(ring[:, 1] - .67, ring[:, 0])
    ring = ring[np.argsort(angle)]
    picks = np.linspace(0, len(ring) - 1, min(26, len(ring)), dtype=int)
    ring = ring[picks].copy()
    ring[:, 2] = mid_z + .41
    ring[:, :2] = ring[:, :2] * .99 + [0., .0067]
    strap = np.column_stack((ring[:, 0], ring[:, 1] - .014, ring[:, 2] + .048))
    arch = np.vstack((ring + [0, .005, -.024], strap))
    n = len(ring)
    indices = []
    for i in range(n - 1):
        indices.extend([(i, i + 1, n + i), (i + 1, n + i + 1, n + i)])
    if indices:
        add_shell(asset, "Cockpit glazing arch", arch, indices, metal)

    rim = []
    for side in (-1, 1):
        for z, width, y in [(-5.54, .105, .586), (-5.14, .27, .607), (-4.37, .43, .665),
                            (-3.65, .50, .721), (-2.95, .45, .760), (-2.28, .28, .786), (-1.9, .075, .79)]:
            rim.extend([(side*width, y, z), (side*(width + .037), y - .01, z)])
    faces = []
    for start in (0, 14):
        for i in range(start, start + 12, 2):
            faces.extend([(i, i + 2, i + 1), (i + 1, i + 2, i + 3)] if start == 0 else
                         [(i, i + 1, i + 2), (i + 1, i + 3, i + 2)])
    add_shell(asset, "Cockpit sill rails", shape(np.asarray(rim)), faces, metal)

    inset = [(-.24, .74, -4.53), (.24, .74, -4.53), (-.27, .87, -4.12), (.27, .87, -4.12),
             (-.26, .81, -3.32), (.26, .81, -3.32), (-.17, .97, -2.98), (.17, .97, -2.98),
             (-.14, .975, -2.78), (.14, .975, -2.78), (-.19, .78, -2.63), (.19, .78, -2.63)]
    faces = [(i, i + 2, i + 1) for i in (0, 4, 6, 8)] + [(i + 1, i + 2, i + 3) for i in (0, 4, 6, 8)]
    add_shell(asset, "Cockpit seat and instrument coaming", shape(np.asarray(inset)), faces, graphite)


def mark_wing_panels(asset):
    edge = asset.names["Silver-grey wing edge"]
    for node in asset.nodes:
        if not node["name"].startswith("Curved mainplane"):
            continue
        mesh = asset.meshes[node["mesh"]]
        for primitive in mesh["primitives"][:]:
            if primitive["material"] != asset.names["Wing ceramic composite"]:
                continue
            vertices = np.asarray(asset.read(primitive["attributes"]["POSITION"]))
            triangles = np.asarray(asset.read(primitive["indices"])).reshape(-1, 3)
            points = vertices[triangles].mean(axis=1)
            x, y, z = points.T
            width = np.abs(x)
            leading = np.interp(width, [2.3, 3.8, 4.55, 6.5, 7.25], [-.65, .30, 2.47, 4.27, 5.35])
            band = (width > 2.45) & (width < 7.24) & (y > -.285)
            band &= (z > leading -.14) & (z < leading + (.90 - .46*smooth(4.5, 7.25, width)))
            if band.any() and not band.all():
                primitive["indices"] = asset.append(triangles[~band].reshape(-1, 1), "SCALAR")
                mesh["primitives"].append({
                    "material": edge, "attributes": dict(primitive["attributes"]),
                    "indices": asset.append(triangles[band].reshape(-1, 1), "SCALAR"),
                })


def refine(source: Path, destination: Path):
    asset = AirframeGLB(source)
    metadata = asset.doc["asset"].setdefault("extras", {})
    if metadata.get("reference_fighter_fit_version", 0) >= 2:
        raise ValueError("These refinements have already been applied to the source.")
    already_fit = bool(metadata.get("reference_fighter_fit"))

    def shape(points):
        return sculpt(points if already_fit else deform(points))

    for node in asset.nodes:
        name = node["name"]
        if "mesh" not in node or name.startswith(GEAR):
            continue
        assert not {"matrix", "rotation", "scale"} & node.keys()
        origin = np.asarray(node.get("translation", [0., 0., 0.]))
        next_origin = np.zeros(3)
        if "translation" in node:
            next_origin = shape(origin[None, :])[0]
            node["translation"] = next_origin.tolist()
        for primitive in asset.meshes[node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            points = np.asarray(asset.read(attrs["POSITION"])) + origin
            refined = shape(points)
            epsilon = np.eye(3) * .0015
            jacobian = np.stack([(shape(points + step) - shape(points - step)) / .003 for step in epsilon], axis=2)
            assert np.min(np.linalg.det(jacobian)) > .10, name
            existing = np.asarray(asset.read(attrs["NORMAL"]))
            new_normals = np.linalg.solve(jacobian.transpose(0, 2, 1), existing[:, :, None])[:, :, 0]
            new_normals /= np.maximum(np.linalg.norm(new_normals, axis=1, keepdims=True), 1e-10)
            attrs["POSITION"] = asset.append(refined - next_origin, "VEC3")
            attrs["NORMAL"] = asset.append(new_normals, "VEC3")
            if "TANGENT" in attrs:
                tangents = np.asarray(asset.read(attrs["TANGENT"]))
                axes = np.einsum("nij,nj->ni", jacobian, tangents[:, :3])
                axes -= (axes * new_normals).sum(axis=1, keepdims=True) * new_normals
                axes /= np.maximum(np.linalg.norm(axes, axis=1, keepdims=True), 1e-10)
                attrs["TANGENT"] = asset.append(np.column_stack((axes, tangents[:, 3])), "VEC4")
    mark_wing_panels(asset)
    add_cockpit(asset, shape)
    shade(asset)
    metadata["reference_fighter_fit"] = "Aircraft/01–04, sculpted loft with cockpit detail"
    metadata["reference_fighter_fit_version"] = 2
    write_model(destination, asset.doc, asset.compact())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    refine(args.source, args.destination)
