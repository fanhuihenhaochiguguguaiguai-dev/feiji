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
    "Carbon graphite · satin radar finish": ((.019, .020, .023), .62, .26, .30, .26),
    "Wing ceramic composite": ((.081, .084, .091), .57, .33, .18, .32),
    "Silver-grey wing edge": ((.29, .303, .325), .81, .24, .16, .25),
    "Blue-green optical multilayer": ((.036, .246, .214), .55, .13, .73, .13),
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
            material["normalTexture"]["scale"] = .30


def refine(source: Path, destination: Path):
    asset = AirframeGLB(source)
    metadata = asset.doc["asset"].setdefault("extras", {})
    if metadata.get("reference_fighter_fit"):
        raise ValueError("Start from the unrefined studio mesh to apply the cached fit once.")
    for node in asset.nodes:
        name = node["name"]
        if "mesh" not in node or name.startswith(GEAR):
            continue
        assert not {"matrix", "rotation", "scale"} & node.keys()
        origin = np.asarray(node.get("translation", [0., 0., 0.]))
        next_origin = deform(origin[None, :])[0]
        if "translation" in node:
            node["translation"] = next_origin.tolist()
        else:
            assert np.max(np.abs(next_origin)) < 1e-8
        for primitive in asset.meshes[node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            points = np.asarray(asset.read(attrs["POSITION"])) + origin
            refined = deform(points)
            epsilon = np.eye(3) * .0015
            jacobian = np.stack([(deform(points + step) - deform(points - step)) / .003 for step in epsilon], axis=2)
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
    shade(asset)
    metadata["reference_fighter_fit"] = "Aircraft/01–04, existing topology"
    write_model(destination, asset.doc, asset.compact())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    refine(args.source, args.destination)
