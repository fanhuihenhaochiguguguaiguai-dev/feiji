"""Author the fictional J-20 exterior from the four supplied game art views."""
import argparse
from collections import defaultdict
from copy import deepcopy
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.interpolate import PchipInterpolator

from airframe_glb import AirframeGLB
from bake_j20_breakup import write_model
from derive_reference_combat import prune_nodes

NOSE = -11.35
LENGTH = 22.18
NORMAL_FILE = "j20-reference-normal.png"
ORM_FILE = "j20-reference-orm.png"
REPLACED = (
    "Continuous centrebody", "Curved mainplane", "Aileron", "Flush ", "Low-observable",
    "Low optical canopy", "Cockpit glazing", "Cockpit sill", "Cockpit seat",
    "Intake lip", "Recessed intake", "Canted tail leading", "Swept canted tail",
    "Titanium nozzle outer sleeve", "Machined nozzle lip", "Engine core recessed", "Shared physical assembly",
)
SKIN = "Carbon graphite · satin radar finish"
WING = "Wing ceramic composite"
EDGE = "Silver-grey wing edge"
METAL = "Brushed titanium and steel"
CHINE = "Faceted graphite chine"
BELLY = "Brushed belly panels"
BURNER = "Heat-treated nozzle"
HARDWARE = "Dark recessed hardware"
LINER = "Warm ceramic exhaust liner"
SEAL = "Dielectric edge and seal"
GLASS = "Blue-green optical multilayer"
INTERIOR = "Cockpit anthracite and fabric"
DISPLAY = "Cockpit cyan display"
COMBINER = "Cockpit optical combiner"
FILAMENT = "Canopy embedded filament"
FUSELAGE_X = np.array([0., .18, .36, .53, .68, .80, .90, 1.])
RADOME_SECTION = np.array([1., .958, .875, .77, .68, .46, .25, 0.])
CENTREBODY_SECTION = np.array([1., .988, .952, .84, .66, .44, .232, .12])
LOWER_SECTION = np.array([1., 1., .94, .81, .65, .42, .20, .12])


def spline(rows):
    entries = np.asarray(rows)
    return PchipInterpolator(entries[:, 0], entries[:, 1:], axis=0)


# Original shell stations also locate the unchanged inlet and canopy fixtures.
PLANFORM = np.array([
    (0, .006), (.075, .217), (.14, .48), (.215, .75), (.294, 1.03),
    (.338, 1.31), (.365, 1.62), (.405, 2.60), (.448, 3.17), (.461, 3.13),
    (.466, 2.27), (.479, 1.97), (.525, 2.19), (.584, 2.94), (.623, 3.49),
    (.682, 4.62), (.732, 5.54), (.762, 6.13), (.813, 7.02),
    (.829, 7.25), (.865, 7.19), (.881, 6.97), (.883, 6.31),
    (.894, 5.12), (.903, 4.34), (.912, 3.31), (.927, 2.27), (.961, 1.75), (.985, 1.64),
])
# Aircraft 02 top view. Retain the fuselage stations and replace the outboard
# silhouette, including the two rear-edge slopes and the clipped tip.
WING_OUTLINE = np.array([
    (.338, 1.31), (.365, 1.60), (.405, 2.21), (.448, 2.39), (.461, 2.35),
    (.466, 2.30), (.479, 2.23), (.525, 2.44), (.584, 2.98), (.623, 3.48),
    (.682, 4.10), (.732, 4.72), (.762, 5.08), (.813, 5.50), (.829, 5.62),
    (.865, 5.58), (.881, 5.36), (.883, 5.20), (.894, 4.21), (.903, 3.71),
    (.912, 3.20), (.927, 2.36), (.961, 1.75), (.985, 1.64),
])
FOIL_CHORD = np.array([0., .055, .15, .31, .48, .65, .82, .95, 1.])
FOIL_THICKNESS = np.array([0., .32, .77, 1., .91, .70, .40, .13, 0.])
# Width at the chine, height of the crown above it, and underside depth.
BODY = spline([
    (0, .005, .005, .006), (.075, .186, .089, .071),
    (.155, .49, .197, .15), (.242, .79, .295, .208),
    (.327, 1.08, .40, .31), (.41, 1.29, .455, .436),
    (.50, 1.46, .465, .48), (.61, 1.62, .457, .46),
    (.735, 1.73, .448, .43), (.855, 1.69, .418, .40),
    (.938, 1.57, .366, .38), (.981, 1.53, .284, .31), (1, 1.40, .22, .28),
])
# Canopy footprint and rise above the sill. The rear tapers into the spine.
CANOPY = spline([
    (.168, .014, .012), (.204, .225, .154), (.248, .456, .336),
    (.280, .526, .413), (.315, .566, .393), (.357, .530, .309),
    (.401, .337, .144), (.447, .021, .012),
])
HATCH_START, HATCH_END = .199, .433
DECK_OFFSET = np.array([.074, .085, .113, .147, .171, .042, -.028, 0.])
SPINE_OFFSET = np.array([.155, .137, .070, .021, 0., 0., 0., 0.])
BELLY_OFFSET = np.array([-.045, -.051, -.059, -.035, .050, .127, .095, 0.])


def clampstep(low, high, value):
    a = np.clip((value - low) / (high - low), 0, 1)
    return a * a * (3 - 2 * a)


def span_at(q):
    return np.interp(q, PLANFORM[:, 0], PLANFORM[:, 1])


def wing_span_at(q):
    return np.where(q < WING_OUTLINE[0, 0], span_at(q),
                    np.interp(q, WING_OUTLINE[:, 0], WING_OUTLINE[:, 1]))


def cross_section(q, w):
    b, crown, belly = BODY(q)
    chine = .065 - .11 * clampstep(.79, .966, q)
    axial = clampstep(.19, .49, q)
    profile = RADOME_SECTION * (1 - axial) + CENTREBODY_SECTION * axial
    return min(b, .94 * w), chine, crown, belly, profile


def wing_fold(x):
    return np.interp(x, (0., 1.9, 3.81, 4.94, 6.23, 7.25),
                     (0., 0., .095, .058, -.033, -.085))


def skin_uv(points):
    return np.column_stack((points[:, 0] / 14.8 + .5, (points[:, 2] - NOSE) / LENGTH))


def patch_indices(rows, columns, reverse=False):
    a = np.arange(rows * columns).reshape(rows, columns)[:-1, :-1].reshape(-1)
    b = a + 1
    c = a + columns
    d = c + 1
    tris = np.column_stack((a, c, b, b, c, d)).reshape(-1, 3)
    return tris[:, ::-1] if reverse else tris


def put_mesh(asset, name, points, triangles, material, origin=None, normals=None, texcoords=None, colors=None):
    points = np.asarray(points)
    if not len(triangles):
        return
    attributes = {"POSITION": asset.append(points if origin is None else points - origin, "VEC3")}
    attributes["NORMAL"] = asset.append(normals_for(points, triangles) if normals is None else normals, "VEC3")
    if texcoords is not None:
        attributes["TEXCOORD_0"] = asset.append(texcoords, "VEC2")
    if colors is not None:
        attributes["COLOR_0"] = asset.append(colors, "VEC4")
    primitive = {"material": asset.names[material], "attributes": attributes,
                 "indices": asset.append(triangles.reshape(-1, 1), "SCALAR")}
    root = asset.nodes[asset.scene[0]]
    existing = next((asset.nodes[i] for i in root["children"] if asset.nodes[i]["name"] == name), None)
    if existing:
        asset.meshes[existing["mesh"]]["primitives"].append(primitive)
        return
    root["children"].append(len(asset.nodes))
    node = {"name": name, "mesh": len(asset.meshes)}
    if origin is not None:
        node["translation"] = list(origin)
    asset.nodes.append(node)
    asset.meshes.append({"name": name, "primitives": [primitive]})


def normals_for(points, triangles):
    edges = points[triangles[:, 1:]] - points[triangles[:, :1]]
    products = np.cross(edges[:, 0], edges[:, 1])
    normals = np.zeros_like(points, dtype=float)
    for i in range(3):
        np.add.at(normals, triangles[:, i], products)
    return normals / np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)


def skin_section(q, b, chine, crown, belly, profile, top):
    x = b * FUSELAGE_X
    weights = profile if top else (profile + LOWER_SECTION) * .5
    y = chine + (crown if top else -belly) * weights
    original = y.copy()
    shoulder = clampstep(.168, .31, q) * (1.0 - clampstep(.65, .87, q))
    if top:
        # Fit the inner strips to the opening while keeping the wing join fixed.
        aperture = clampstep(.168, HATCH_START, q) * (1.0 - clampstep(HATCH_END, .472, q))
        inner = .78 * CANOPY(np.clip(q, .168, .447))[0]
        lip = x[2] + aperture * (inner - x[2])
        x[:4] = np.interp(x[:4], [0., x[2], x[4]], [0., lip, x[4]])
        spine = clampstep(.351, .444, q) * (1.0 - clampstep(.466, .601, q))
        y = np.interp(x, b * FUSELAGE_X, y) + shoulder * DECK_OFFSET + spine * SPINE_OFFSET
    else:
        # Keep the gear panels and the inlet aperture on their original plane.
        shoulder *= 1.0 - clampstep(.31, .36, q) + clampstep(.50, .58, q)
        y += shoulder * BELLY_OFFSET
    return x, y, original


def skin_point(q, lateral, top=True):
    b, chine, crown, belly, profile = cross_section(q, span_at(q))
    x, y, _ = skin_section(q, b, chine, crown, belly, profile, top)
    return np.array([lateral, np.interp(lateral, x, y), NOSE + q * LENGTH])


def ship_skin(asset):
    stations = np.unique(np.round(np.concatenate((
        np.linspace(0., .984, 75), PLANFORM[:, 0], BODY.x,
        [.077, .124, .168, .211, .263, .315, .357, .406, .447, HATCH_START, HATCH_END,
         .687, .829, .865, .881, .912, .926]
    )), 6))
    stations = stations[stations <= .984]
    surfaces = defaultdict(list)
    # Piecewise cross-section keeps the radome's chine sharp and allows the
    # rear shoulder to turn continuously into a thin airfoil.
    beyond = np.array([.05, .13, .24, .38, .51, .64, .76, .86, .93, .97, 1.])
    columns = len(FUSELAGE_X) + len(beyond)
    panel = np.tile(np.repeat(np.arange(columns - 1), 2), len(stations) - 1)
    for sign in (-1, 1):
        for top in (True, False):
            eps = 1. if top else -1.
            rows = []
            refined_rows = []
            for q in stations:
                w = span_at(q)
                b, root_chine, crown, belly, center = cross_section(q, w)
                core_x, core_y, original_y = skin_section(q, b, root_chine, crown, belly, center, top)
                local_span = wing_span_at(q) - b
                outside_x = b + local_span * beyond
                # Grow the inner wing from the shell shoulder, then taper its
                # thickness continuously toward the outer bevel.
                main = clampstep(.479, .60, q) * (1.0 - clampstep(.847, .940, q))
                inner = np.interp(beyond, [0., .09, .20, .34, .53, .72, .90, 1.],
                                  [0., .23, .74, .93, .70, .39, .10, 0.])
                prior = np.interp(beyond, [0., .13, .40, .64, .86, 1.], [0., .45, .91, .69, .28, 0.])
                thickness = clampstep(.026, 1.0, local_span)
                thickness *= (.175 if top else .19) * prior * (1.0 - main) + (.29 if top else .26) * inner * main
                root_blend = (core_y[-1] - root_chine) * (1.0 - beyond) ** (3.0 - main)
                wing_y = root_chine + wing_fold(outside_x) - wing_fold(b) + root_blend + eps * thickness
                z = np.full(columns, NOSE + q*LENGTH)
                rows.extend(zip(sign * np.concatenate((b * FUSELAGE_X, outside_x)),
                                np.concatenate((original_y, wing_y)), z))
                refined_rows.extend(zip(sign * np.concatenate((core_x, outside_x)),
                                        np.concatenate((core_y, wing_y)), z))
            original = np.asarray(rows)
            vertices = np.asarray(refined_rows)
            triangles = patch_indices(len(stations), columns, (sign == 1) != top)
            centers = original[triangles].mean(axis=1)
            w = abs(centers[:, 0])
            q = (centers[:, 2] - NOSE) / LENGTH
            normals = normals_for(vertices, triangles)
            vertex_q = (vertices[:, 2] - NOSE) / LENGTH
            vertex_panel = np.tile(np.arange(columns), len(stations))
            soften = clampstep(.24, .54, vertex_q)[:, None]
            # Preserve the authored longitudinal shoulder through the
            # midbody. Blend it out before the unmodified aft shell.
            crease = (clampstep(.168, .31, vertex_q) *
                      (1.0 - clampstep(.66, .865, vertex_q)))[:, None]
            core_soften = soften * (1.0 - .72 * crease)
            original_normals = normals_for(original, triangles)
            pinned = (vertex_panel >= len(FUSELAGE_X) - 1) | (vertex_q >= .87)
            smoothing = []
            for cheek, blend in ((panel < 4, core_soften),
                                 ((panel >= 4) & (panel < 7), core_soften),
                                 (panel >= 7, soften)):
                angled = normals_for(vertices, triangles[cheek]) * (1.0 - blend) + normals * blend
                original_angled = normals_for(original, triangles[cheek]) * (1.0 - soften) + original_normals * soften
                angled[pinned] = original_angled[pinned]
                angled /= np.maximum(np.linalg.norm(angled, axis=1, keepdims=True), 1e-12)
                smoothing.append((cheek, angled))
            # Material and moving panel borders follow whole rows and columns.
            # Classifying triangle centers by distance left half-panel teeth.
            wing = panel >= len(FUSELAGE_X) - 1
            flap = (panel >= 11) & (panel < 15) & (q > .829) & (q < .926)
            bright = ((panel >= 15) & (q > .687) & (q < .926))
            bright |= ((panel >= 12) & (q > .865) & (q < .926))
            bright |= ((q > .077) & (q < .124))
            opening = (q > HATCH_START) & (q < HATCH_END) & (panel < 2) & top
            inlet = (q > .369) & (q < .496) & (w > 1.36) & (w < 2.47) & (not top)
            # Skin faces inside the recessed throats show as dark bars from
            # the rear. Terminate the skin at the twin engine housings.
            exhaust = (q > .940) & ((w - .92) ** 2 + (centers[:, 1] - .02) ** 2 < .59 ** 2)
            core = np.where((panel >= 4) & (q < .62), CHINE, SKIN) if top else BELLY
            marks = np.where(bright, EDGE, np.where(wing, WING, core))
            for mat in (EDGE, SKIN, WING, CHINE, BELLY):
                for mobile in (False, True):
                    name = ("Aileron left" if sign < 0 else "Aileron right") if mobile else "Fused airframe skin"
                    origin = np.array([sign*4.92, -.04, NOSE+.829*LENGTH]) if mobile else None
                    mask = (marks == mat) & (flap == mobile) & ~opening & ~inlet & ~exhaust
                    for cheek, normal in smoothing:
                        section = mask & cheek
                        if section.any():
                            surfaces[name, mat].append((vertices, triangles[section], normal, origin))
    for (name, material), pieces in surfaces.items():
        points, indices, ns = [], [], []
        offset = 0
        for vertices, tris, normals, origin in pieces:
            ids, remap = np.unique(tris.reshape(-1), return_inverse=True)
            points.extend(vertices[ids])
            ns.extend(normals[ids])
            indices.extend((remap+offset).reshape(-1, 3))
            offset += len(ids)
        p = np.asarray(points)
        texture = skin_uv(p)
        put_mesh(asset, name, p, np.asarray(indices), material, origin, np.asarray(ns), texture)


def canopy_point(q, width, rise, across):
    base = skin_point(q, width)[1] + .023
    return np.array([width * across, base + rise * (1.0 - across ** 2) ** .68, NOSE + q * LENGTH])


def glazing(asset):
    rows = np.unique(np.round(np.r_[np.linspace(.168, .447, 38), CANOPY.x], 6))
    across = np.cos(np.linspace(0., np.pi, 21))
    glass, rim, well = [], [], []
    for q in rows:
        w, rise = CANOPY(q)
        glass.extend(canopy_point(q, w, rise, u) for u in across)
        sill = skin_point(q, w)
        rim.append([sill + offset for offset in (
            (-min(.018, w * .27), .030, 0.),
            (.022, .031, 0.), (.043, .010, 0.), (.036, -.028, 0.),
        )])
    for q in np.unique(np.r_[np.linspace(HATCH_START, HATCH_END, 21), .223, .410]):
        w = float(CANOPY(q)[0])
        sill = skin_point(q, w * .84)
        floor = skin_point(q, 0., False)[1] + .09
        depth = (sill[1] - floor) * clampstep(HATCH_START, .227, q) * (1.0 - clampstep(.407, HATCH_END, q))
        x, y, z = sill
        well.append([(x, y+.014, z), (x*.88, y-.027, z),
                     (x*.67, y-depth-.026, z), (-x*.67, y-depth-.026, z),
                     (-x*.88, y-.027, z), (-x, y+.014, z)])
    normal_tint = np.tile(abs(across) ** 3.4, len(rows))
    colors = np.column_stack((1.0 - .31 * normal_tint, 1.0 - .16 * normal_tint,
                              1.0 - .08 * normal_tint, .33 + .58 * normal_tint))
    put_mesh(asset, "Canopy single pane", glass, patch_indices(len(rows), len(across), True), GLASS, colors=colors)
    rim = np.asarray(rim)
    for side in (-1., 1.):
        shell = rim * [side, 1., 1.]
        loft(asset, "Canopy inset sill", shell[:, 1:], CHINE, side < 0, True)
        loft(asset, "Canopy corner seal", shell[:, :2], SEAL, side < 0)
    loft(asset, "Cockpit recessed tub", np.asarray(well), INTERIOR, True)

    # A shallow amber strip follows the glazing and remains purely decorative.
    strip = []
    for wave in np.linspace(0., 1., 32):
        along = .218 + .193 * wave
        lateral = .55 + .22 * np.sin(2.6 * np.pi * wave)
        w, rise = CANOPY(along)
        half_width = .005 / w
        strip.append([canopy_point(along, w, rise, u) + [0., .003, 0.]
                      for u in (lateral - half_width, lateral + half_width)])
    loft(asset, "Canopy curved filament", np.asarray(strip), FILAMENT)
    cockpit_fittings(asset)


def cockpit_block(asset, name, rows, material, lateral=0.):
    # Fixed-width chamfers give the fittings readable edges at game distance.
    sections = []
    for z, width, bottom, top in rows:
        bevel = min(.032, width * .25, (top-bottom) * .22)
        ring = [
            (-width+bevel, bottom), (width-bevel, bottom),
            (width, bottom+bevel), (width, top-bevel),
            (width-bevel, top), (-width+bevel, top),
            (-width, top-bevel), (-width, bottom+bevel),
        ]
        sections.append([(x + lateral, y, z) for x, y in ring])
    points = np.asarray(sections).reshape(-1, 3)
    side = patch_indices(len(rows), 9, True)
    ring_ids = np.r_[np.arange(8), 0] + (8 * np.arange(len(rows)))[:, None]
    front = np.array([(0, n+1, n) for n in range(1, 7)])
    back = front[:, ::-1] + (len(rows)-1) * 8
    put_mesh(asset, name, points, np.vstack((ring_ids.flat[side], front, back)), material)


def cockpit_fittings(asset):
    deck = []
    for q in np.linspace(.168, .278, 11):
        edge = skin_point(q, .85 * CANOPY(q)[0]) - [0., .013, 0.]
        deck.append([edge * [-1., 1., 1.], edge])
    loft(asset, "Cockpit forward deck", np.asarray(deck), SEAL)
    cockpit_block(asset, "Cockpit seat rails", [(-4.13, .19, -.04, .10), (-3.07, .18, -.05, .09)], SEAL)
    cockpit_block(asset, "Cockpit inclined seat", [
        (-4.11, .193, .065, .163), (-3.72, .206, .063, .172), (-3.49, .215, .075, .325),
        (-3.36, .202, .09, .518), (-3.23, .197, .21, .627), (-3.12, .174, .45, .632),
    ], INTERIOR)
    cockpit_block(asset, "Cockpit headrest", [(-3.26, .100, .543, .638), (-3.14, .12, .570, .687),
                                             (-3.04, .10, .573, .673)], SEAL)
    for side in (-1., 1.):
        cockpit_block(asset, "Cockpit seat guards", [
            (-3.98, .045, .104, .164), (-3.60, .050, .095, .279), (-3.29, .061, .151, .405),
        ], SEAL, side * .212)
        cockpit_block(asset, "Cockpit detail side consoles", [
            (-5.14, .070, .15, .243), (-4.8, .080, .123, .278), (-3.99, .073, .068, .233),
            (-3.60, .056, .065, .162),
        ], HARDWARE, side * .317)
    cockpit_block(asset, "Cockpit detail side stick", [(-4.65, .029, .207, .274),
                  (-4.57, .037, .202, .338), (-4.49, .028, .220, .325)], SEAL, .340)
    cockpit_block(asset, "Cockpit instrument coaming", [
        (-5.69, .17, .19, .34), (-5.43, .294, .074, .465), (-5.11, .327, .022, .443),
    ], SEAL)
    display = np.array([[-.269,.082,-5.084], [.269,.082,-5.084],
                        [-.288,.404,-5.105], [.288,.404,-5.105]])
    put_mesh(asset, "Cockpit panoramic display", display, np.array([(0, 1, 2), (2, 1, 3)]), DISPLAY)
    combiner = np.array([[-.167,.458,-5.29], [.167,.458,-5.29],
                         [-.142,.631,-5.46], [.142,.631,-5.46]])
    put_mesh(asset, "Cockpit combiner glass", combiner, np.array([(0, 1, 2), (2, 1, 3)]), COMBINER)
    # Sparse angular marks on the large display and the glass.
    for y, z, w, h in ((.26, -5.088, .138, .0016), (.33, -5.097, .094, .0016),
                        (.53, -5.358, .073, .0015), (.571, -5.398, .045, .0014)):
        rules = np.array([[-w, y-h, z], [w,y-h,z], [-w,y+h,z], [w,y+h,z]])
        put_mesh(asset, "Cockpit detail cyan marks", rules, np.array([(0, 1, 2), (2, 1, 3)]), COMBINER)


def fit_navigation_lights(asset):
    lamp = next(n for n in asset.nodes if n["name"] == "Shared physical assembly.001")
    for primitive in asset.meshes[lamp["mesh"]]["primitives"]:
        attributes = primitive["attributes"]
        points = np.array(asset.read(attributes["POSITION"]))
        # Refit the retained airframe lamps to the new wing tip, using the same
        # edge geometry as the wing instead of the previous asset's coordinates.
        q = .841 + (points[:, 2] - 6.19) / LENGTH * .62
        width = wing_span_at(q)
        shift = np.max(abs(points[:, 0])) - abs(points[:, 0])
        points[:, 0] = np.sign(points[:, 0]) * (width - shift - .03)
        points[:, 1] += .241 + .065 - .11 * clampstep(.79, .966, q) + wing_fold(width)
        points[:, 2] = NOSE + LENGTH * q
        attributes["POSITION"] = asset.append(points, "VEC3")
    lamp["name"] = "Refitted wing navigation lights"


def loft(asset, name, sections, material, reverse=False, textured=False):
    points = np.concatenate(sections)
    indices = patch_indices(len(sections), len(sections[0]), reverse)
    put_mesh(asset, name, points, indices, material, texcoords=skin_uv(points) if textured else None)


def access_panels(asset):
    perimeter = np.array([
        (.486, .65), (.519, .52), (.653, .53), (.694, .65), (.669, .81), (.534, .84),
    ])
    inset = perimeter.mean(axis=0) + (perimeter - perimeter.mean(axis=0)) * .88
    shell = []
    for outline, offset in ((perimeter, (-.012, -.027, 0.)), (inset, (.041, .052, 0.))):
        ring = []
        for q, width in outline:
            b = cross_section(q, span_at(q))[0]
            ring.append(skin_point(q, b * width) + offset)
        shell.append(np.r_[ring, ring[:1]])
    for sign in (-1., 1.):
        panel = np.asarray(shell) * [sign, 1., 1.]
        loft(asset, "Raised access cover bevel", panel, CHINE, sign > 0, True)
        top = panel[-1, :-1]
        triangles = np.array([(0, i, i+1) for i in range(1, len(top)-1)])
        if sign < 0:
            triangles = triangles[:, ::-1]
        put_mesh(asset, "Raised access covers", top, triangles, SKIN, texcoords=skin_uv(top))


def intakes(asset):
    # A swept, bevelled opening under the shoulder. The low throat remains
    # clear in head-on camera views, with a dark liner and curved inboard lip.
    mouth = np.array([
        [1.30, .015, -3.55], [1.49, .213, -3.48], [2.59, .135, -3.21],
        [2.88, -.087, -3.13], [2.56, -.602, -3.24], [2.25, -.730, -3.32],
        [1.51, -.689, -3.55], [1.27, -.478, -3.65], [1.30, .015, -3.55],
    ])
    center = np.array([2.03, -.245, -3.37])
    opening = center + (mouth - center) * .825 + [0., 0., .068]
    throat = center + (mouth - center) * [.72, .83, .36] + [-.030, -.020, 1.18]
    shoulder = center + (mouth - center) * [.97, .84, .34] + [-.147, .023, 1.61]
    # Lift and widen the outer housing behind the lip while leaving the aperture alone.
    shoulder[:, 0] += [.00, .04, .098, .124, .078, .026, .00, .00, .00]
    shoulder[:, 1] += [.03, .112, .158, .084, .012, -.016, .00, .00, .03]
    blend = center + (mouth - center) * [.65, .45, .13] + [-.264, .243, 4.13]
    back = center + (mouth - center) * [.69, .59, .09] + [-.186, -.010, 2.18]
    for sign in (-1, 1):
        mirror = np.array([sign, 1., 1.])
        loft(asset, "Intake chamfer", [opening * mirror, mouth * mirror], METAL, sign < 0)
        loft(asset, "Intake shoulder panels", [mouth * mirror, shoulder * mirror, blend * mirror],
             CHINE, sign < 0, True)
        loft(asset, "Recessed intake liner", [opening * mirror, throat * mirror, back * mirror], HARDWARE, sign > 0)
        put_mesh(asset, "Recessed intake backplate", back[:-1] * mirror,
                 np.array([(0, i + 1, i) for i in range(1, 7)])[:, ::sign], HARDWARE)
        # The inboard fairing swells into the duct, then comes back to the
        # body side. It follows the chine and stays distinct from the lip.
        z = np.array([-4.68, -4.30, -4.03, -3.77, -3.45, -3.18, -2.89])
        swell = np.array([.005, .096, .174, .220, .195, .109, .004])
        spread = np.array([.036, .183, .249, .272, .258, .196, .060])
        section = np.linspace(0., np.pi, 15)
        bulge = []
        for at, height, half in zip(z, swell, spread, strict=True):
            q = (at - NOSE) / LENGTH
            b, chine, crown, belly, profile = cross_section(q, span_at(q))
            y = chine - .062 + half * np.cos(section)
            upper = b * np.interp((y - chine) / crown, profile[::-1], FUSELAGE_X[::-1])
            lower_profile = (profile + LOWER_SECTION) * .5
            lower = b * np.interp((chine - y) / belly, lower_profile[::-1], FUSELAGE_X[::-1])
            # Embed the perimeter in the existing side so only the centre
            # of the bulge stands off the skin.
            shell = np.where(y > chine, upper, lower)
            pts = np.column_stack((shell - .012 + height * np.sin(section), y, np.full(len(section), at)))
            bulge.append(pts * mirror)
        loft(asset, "Inboard intake bulge", bulge, CHINE, sign > 0, True)


def foil_shell(asset, name, halves, flip, accent_rows, accent_leading=False, skin=WING):
    # Both sides meet at the chord edges. Only the narrow spanwise tip needs a cap.
    for i, sections in enumerate(halves):
        row_count = len(sections)
        points = np.concatenate(sections)
        faces = patch_indices(row_count, len(FOIL_CHORD), flip != bool(i))
        rows = np.repeat(np.arange(row_count - 1), 2 * (len(FOIL_CHORD) - 1))
        chord = np.tile(np.repeat(FOIL_CHORD[:-1], 2), row_count - 1)
        accent = (rows >= accent_rows) | ((chord < .05) & accent_leading)
        normals = normals_for(points, faces)
        for material, selected in ((skin, ~accent), (EDGE, accent)):
            put_mesh(asset, name, points, faces[selected], material,
                     normals=normals, texcoords=skin_uv(points))
    rim = np.vstack((halves[0][-1], halves[1][-1][-2:0:-1]))
    center = rim.mean(axis=0)
    near_tip = halves[0][-2].mean(axis=0)
    faces = np.array([(len(rim), i, (i + 1) % len(rim)) for i in range(len(rim))])
    if np.dot(np.cross(rim[0] - center, rim[1] - center), center - near_tip) < 0.:
        faces = faces[:, ::-1]
    vertices = np.vstack((rim, center))
    put_mesh(asset, name, vertices, faces, EDGE, texcoords=skin_uv(vertices))


def canards(asset):
    # Aircraft 02 shows a long tapered canard, with the aft edge close to
    # the main-wing shoulder and an upturned, thin tip in the frontal view.
    # Span, axial bounds, leading-edge height, chord twist and half thickness.
    profiles = [
        (1.13, -3.06, -0.94, .212, -.024, .113),
        (1.39, -2.93, -0.96, .229, -.041, .111),
        (1.72, -2.66, -0.97, .239, -.059, .087),
        (2.10, -2.28, -0.99, .248, -.076, .065),
        (2.51, -1.86, -1.04, .264, -.094, .044),
        (2.89, -1.48, -1.09, .292, -.099, .024),
        (3.05, -1.34, -1.13, .309, -.097, .014),
    ]
    camber = np.sin(np.pi * FOIL_CHORD) * .025
    for sign in (-1., 1.):
        halves = [
            [np.column_stack((np.full(len(FOIL_CHORD), x * sign),
                              y + twist * FOIL_CHORD + camber + face * half * FOIL_THICKNESS,
                              start + (end - start) * FOIL_CHORD))
             for x, start, end, y, twist, half in profiles]
            for face in (1., -1.)
        ]
        foil_shell(asset, "Tapered canard surfaces", halves, sign > 0, 4, True)
        # Extend the upper material over the stationary shoulder; embed both
        # edges so the fillet does not become an independent floating plate.
        sections = []
        for z, lift, width in [(-3.42, .008, .18), (-2.97, .071, .32), (-2.48, .136, .43),
                               (-1.96, .153, .45), (-1.45, .131, .39), (-.99, .053, .33), (-.58, .005, .21)]:
            q = (z - NOSE) / LENGTH
            shoulder = cross_section(q, span_at(q))[0]
            coords = []
            for t, loft_height in [(-.90, -.025), (-.39, lift*.63), (.10, lift),
                                    (.52, lift*.74), (1., -.024)]:
                x = shoulder + t * width
                pt = skin_point(q, x) + [0., loft_height, 0.]
                coords.append(pt * [sign, 1., 1.])
            sections.append(coords)
        loft(asset, "Canard shoulder fillets", np.asarray(sections), CHINE, sign < 0, True)


def tail_fins(asset):
    # The side view fixes the swept leading edge and the aft-raked cap;
    # the front view fixes the outward lean independently of the sweep.
    # Height above the attachment, front and rear bounds, half thickness.
    rows = [
        (.00, 5.51, 9.87, .194),
        (.30, 5.83, 9.98, .183),
        (.86, 6.65, 10.12, .144),
        (1.67, 7.71, 10.32, .105),
        (2.18, 8.43, 10.46, .075),
        (2.56, 8.98, 10.55, .051),
        (2.69, 9.17, 10.61, .038),
        (2.78, 9.38, 10.55, .027),
    ]
    for sign in (-1., 1.):
        halves = [
            [np.column_stack((sign * (1.245 + height * .147 + face * half * FOIL_THICKNESS),
                              np.full(len(FOIL_CHORD), .215 + height),
                              start + (end - start) * FOIL_CHORD))
             for height, start, end, half in rows]
            for face in (1., -1.)
        ]
        foil_shell(asset, "Canted clipped fins", halves, sign < 0, 4, True, SKIN)
        blend = []
        for z, width, rise in [(4.76,.125,.006), (5.38,.235,.072), (6.25,.32,.17),
                               (7.58,.34,.232), (8.71,.31,.198), (9.63,.269,.128), (10.05,.19,.016)]:
            q = (z - NOSE) / LENGTH
            row = []
            for f, height in [(-1.,-.019),(-.54,.52),(-.16,1.),(.20,.96),(.59,.53),(1.,-.019)]:
                pt = skin_point(q, 1.245 + width * f)
                pt[1] += height if height < 0 else rise * height
                row.append(pt * [sign, 1., 1.])
            blend.append(row)
        loft(asset, "Swept fin root fairings", np.asarray(blend), CHINE, sign < 0, True)


def tail_and_nozzles(asset):
    # Faceted root housings connect the shell to the round exhaust assemblies.
    # Their intermediary sections keep the aft corners and aft divider visible.
    ribs = np.array([[-.66, .10], [-.34, .52], [.27, .49], [.67, .17], [.66, -.28],
                     [.29, -.57], [-.29, -.53], [-.66, -.28], [-.66, .10]])
    divider = np.array([[-.46, .07], [-.24, .33], [.24, .33], [.46, .07], [.23, -.19],
                        [-.23, -.19], [-.46, .07]])
    sections = [np.column_stack((divider * [scale, h] + [0., y], np.full(len(divider), z)))
                for z, scale, h, y in [(6.69, .55, .45, .30), (8.39, .86, .73, .23),
                                       (10.04, .76, .98, .03), (10.81, .49, .91, -.05),
                                       (10.93, .36, .74, -.055)]]
    loft(asset, "Swept tail divider", sections, CHINE, textured=True)
    put_mesh(asset, "Tail divider end face", sections[-1][:-1], np.array([(0, i, i + 1) for i in range(1, 5)]), METAL)
    ring_angle = np.linspace(0., 2.0 * np.pi, 41)
    n = len(ring_angle)
    for sign in (-1, 1):
        housing = []
        for z, width, depth, x, y in [(6.58, .78, .69, .90, .049), (7.47, 1.13, .82, .92, .025),
                                      (8.43, 1.19, 1., .95, .006), (9.33, 1.10, 1.11, .94, .016),
                                      (10.05, .91, .91, .92, .021)]:
            xy = (ribs * [width, depth] + [x, y]) * [sign, 1.]
            housing.append(np.column_stack((xy, np.full(len(xy), z))))
        loft(asset, "Faceted aft fairings", housing, CHINE, sign < 0, True)

        def ring(radius, z):
            return np.column_stack((.92 * sign + radius * np.cos(ring_angle),
                                    .02 + radius * np.sin(ring_angle), np.full(n, z)))
        # Contrasting retaining bands and stepped annular throat surfaces.
        sizes = [(.684, 9.68), (.735, 9.82), (.733, 9.95), (.705, 10.02),
                 (.705, 10.52), (.681, 10.83), (.636, 10.93), (.557, 10.93),
                 (.534, 10.81), (.510, 10.64), (.474, 10.52), (.464, 10.17), (.434, 9.96)]
        parts = [ring(r, z) for r, z in sizes]
        for i, mat in enumerate((METAL, METAL, BURNER, SEAL, BURNER, METAL, METAL,
                                 BURNER, HARDWARE, LINER, HARDWARE, HARDWARE)):
            loft(asset, "Machined annular exhaust", parts[i:i+2], mat, True)
        # Narrow gaps between petals remain readable without another texture.
        for j in range(16):
            a = (j + np.array([.09, .36, .63, .91])) * (2 * np.pi / 16.)
            rows = []
            for radius, z in [(.710, 10.03), (.726, 10.23), (.715, 10.51), (.693, 10.71)]:
                rows.append(np.column_stack((.92 * sign + radius*np.cos(a), .02 + radius*np.sin(a),
                                              np.full(len(a), z))))
            loft(asset, "Nozzle petals", rows, METAL if j % 4 == 0 else BURNER, True)
        starter = ring(.435, 10.0)
        core = np.vstack((starter, [[.92 * sign, .02, 9.97]]))
        put_mesh(asset, "Engine core cover", core, np.array([(i, i + 1, n) for i in range(n-1)]), HARDWARE)


def gear_panels(asset):
    # Narrow skin seams flank the original articulated gear. The seams hug
    # the underside and the collision and motion still use the stock rig.
    for x0, x1, q0, q1 in [(-.31, .31, .213, .352), (1.15, 1.61, .518, .617), (-1.61, -1.15, .518, .617)]:
        x = np.array([x0, x0+.037, x1-.037, x1, x1, x1-.037, x0+.037, x0, x0])
        q = np.array([q0+.008, q0, q0, q0+.008, q1-.008, q1, q1, q1-.008, q0+.008])
        middle_x = (x0 + x1) * .5
        middle_q = (q0 + q1) * .5
        rows = []
        for scale in (1.0, .925):
            coords = []
            for a, t in zip(middle_x + (x - middle_x)*scale, middle_q + (q - middle_q)*scale, strict=True):
                b, chine, _, belly, profile = cross_section(t, span_at(t))
                depth = np.interp(abs(a) / b, FUSELAGE_X, (profile + LOWER_SECTION)*.5)
                coords.append((a, chine - belly * depth - .006, NOSE + LENGTH * t))
            rows.append(np.array(coords))
        loft(asset, "Landing bay perimeter seams", rows, SEAL)


def bake_panel_maps(normal_path, orm_path):
    # Panel breaks follow the projected chine and swept wing sections.
    resolution = 1024
    channel = Image.new("L", (resolution, resolution), 128)
    paint = ImageDraw.Draw(channel)
    def seam(points, strength=94):
        xy = [(round(x*(resolution-1)), round(z*(resolution-1))) for x, z in points]
        paint.line(xy, fill=strength, width=2)
    for side in (-1.,1.):
        for x in (.022, .048, .087):
            offset = side*x
            seam([(.5+offset,.16),(.5+offset,.36),(.5+offset*1.16,.52),
                  (.5+offset*1.19,.78),(.5+offset*.85,.96)])
        for r in (.25,.37,.53,.68,.82):
            base=.5+side*(r*.483)
            seam([(base,.556+ r*.26),(base+side*.046,.654+r*.191),
                  (base+side*.016,.785+r*.097),(base+side*.026,.869+r*.015)])
        for q in [.152,.361,.487,.626,.743,.861,.936]:
            seam([(.5+side*.016,q-.027),(.5+side*.072,q),(.5+side*.109,q+.028)])
            for j in range(8):
                x = round((.5 + side * (.024+j*.010)) * (resolution-1))
                y = round((q-.03+j*.0061) * (resolution-1))
                paint.ellipse((x-1, y-1, x+1, y+1), fill=106)
    height = np.asarray(channel.filter(ImageFilter.GaussianBlur(.74)), dtype=float) / 255.
    rng = np.random.default_rng(20)
    gy, gx = np.gradient(height + rng.normal(0, .0008, height.shape))
    normals = np.dstack((-gx*11., -gy*11., np.ones_like(gx)))
    normals /= np.linalg.norm(normals,axis=2,keepdims=True)
    Image.fromarray(np.rint((normals*.5+.5)*255).astype(np.uint8)).save(normal_path, optimize=True)

    size = 512
    line = np.asarray(channel.resize((size, size), Image.Resampling.BOX), dtype=float) / 255.
    line = np.clip((.501 - line) * 6.0, 0.0, 1.0)
    q, x = np.mgrid[0:1:complex(size), 0:1:complex(size)]
    x = np.abs(x - .5)
    panel_tone = rng.uniform(0.0, 1.0, (12, 9))
    panel = panel_tone[np.clip(np.floor(10. + q*11.5 - 2.2*x).astype(int)-10, 0, 11),
                       np.clip(np.floor(x*15. + .25*q).astype(int), 0, 8)]
    aerowear = clampstep(.804, .949, q) * (1.0 - clampstep(.016, .108, x))
    ao = 1.0 - line * .39
    rough = .28 + panel * .21 + aerowear * .15 + line * .35
    metal = .55 + panel * .24 + aerowear * .14
    packed = np.clip(np.dstack((ao, rough, metal)), 0., 1.)
    Image.fromarray(np.rint(packed*255).astype(np.uint8)).save(orm_path, optimize=True)


def reconstruct(source, output, normal_map, orm_map):
    asset = AirframeGLB(source)
    metadata = asset.doc["asset"].setdefault("extras", {})
    if metadata.get("reference_fighter_fit_version") != 2:
        raise ValueError("Use the v2 refined J-20 authoring mesh as the retained rig source.")
    root = asset.nodes[asset.scene[0]]
    fit_navigation_lights(asset)
    root["children"] = [i for i in root["children"] if not asset.nodes[i]["name"].startswith(REPLACED)]
    for name, template, color, metal, rough in [
        (CHINE, SKIN, [.045,.055,.068,1.], .61, .46),
        (BELLY, WING, [.075,.083,.097,1.], .47, .54),
        (HARDWARE, SEAL, [.013,.019,.025,1.], .32, .63),
        (LINER, BURNER, [.203,.109,.055,1.], .79, .35),
        (DISPLAY, SEAL, [.025,.092,.105,1.], .10, .30),
        (COMBINER, GLASS, [.055,.31,.32,.23], .04, .19),
        (FILAMENT, SEAL, [.29,.17,.09,1.], .38, .38),
    ]:
        mat = deepcopy(asset.materials[asset.names[template]])
        mat["name"] = name
        mat["pbrMetallicRoughness"].update(baseColorFactor=color, metallicFactor=metal, roughnessFactor=rough)
        asset.names[name] = len(asset.materials)
        asset.materials.append(mat)
    asset.materials[asset.names[LINER]]["emissiveFactor"] = [.27,.073,.013]
    asset.materials[asset.names[DISPLAY]]["emissiveFactor"] = [.017,.067,.073]
    asset.materials[asset.names[COMBINER]]["emissiveFactor"] = [.005,.072,.073]
    ship_skin(asset)
    glazing(asset)
    intakes(asset)
    access_panels(asset)
    canards(asset)
    tail_fins(asset)
    tail_and_nozzles(asset)
    gear_panels(asset)
    images, textures = asset.doc["images"], asset.doc["textures"]
    for name, file in (("J-20 panel relief", NORMAL_FILE), ("J-20 panel ORM", ORM_FILE)):
        images.append({"name": name, "uri": "../fleet/" + file})
        textures.append({"source": len(images)-1, "sampler": 0})
    orm = len(textures)-1
    for key in (SKIN,WING,EDGE,CHINE,BELLY):
        mat = asset.materials[asset.names[key]]
        mat["normalTexture"] = {"index": orm-1, "scale": .55}
        mat["occlusionTexture"] = {"index": orm, "strength": .55}
        surface = mat["pbrMetallicRoughness"]
        surface.update(metallicRoughnessTexture={"index": orm}, roughnessFactor=1.0,
                       metallicFactor=.95 if key in (EDGE, CHINE) else .82)
    skin = asset.materials[asset.names[SKIN]]["pbrMetallicRoughness"]
    skin["baseColorFactor"] = [.046, .054, .066, 1.]
    glass = asset.materials[asset.names[GLASS]]
    glass["doubleSided"] = False
    glass["pbrMetallicRoughness"].update(baseColorFactor=[.10, .28, .26, .44], roughnessFactor=.135)
    metadata["reference_fighter_fit_version"] = 7
    metadata["reference_fighter_fit"] = "Aircraft/01–04; tapered canards, clipped mainplane and swept fin roots"
    prune_nodes(asset)
    write_model(output, asset.doc, asset.compact())
    bake_panel_maps(normal_map, orm_map)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source",type=Path)
    cli.add_argument("output",type=Path)
    cli.add_argument("normal_map",type=Path)
    cli.add_argument("orm_map",type=Path)
    a=cli.parse_args()
    reconstruct(a.source,a.output,a.normal_map,a.orm_map)
