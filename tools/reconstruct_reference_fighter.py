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
FUSELAGE_X = np.array([0., .18, .36, .53, .68, .80, .90, 1.])
RADOME_SECTION = np.array([1., .958, .875, .77, .68, .46, .25, 0.])
CENTREBODY_SECTION = np.array([1., .988, .952, .84, .66, .44, .232, .12])
LOWER_SECTION = np.array([1., 1., .94, .81, .65, .42, .20, .12])


def spline(rows):
    entries = np.asarray(rows)
    return PchipInterpolator(entries[:, 0], entries[:, 1:], axis=0)


# Width in the transverse direction, sampled against the design top view.
# The low plateau after the forward strake is the gap before the main wing.
PLANFORM = np.array([
    (0, .006), (.075, .217), (.14, .48), (.215, .75), (.294, 1.03),
    (.338, 1.31), (.365, 1.62), (.405, 2.60), (.448, 3.17), (.461, 3.13),
    (.466, 2.27), (.479, 1.97), (.525, 2.19), (.584, 2.94), (.623, 3.49),
    (.682, 4.62), (.732, 5.54), (.762, 6.13), (.813, 7.02),
    (.829, 7.25), (.865, 7.19), (.881, 6.97), (.883, 6.31),
    (.894, 5.12), (.903, 4.34), (.912, 3.31), (.927, 2.27), (.961, 1.75), (.985, 1.64),
])
# Width at the chine, height of the crown above it, and underside depth.
BODY = spline([
    (0, .005, .005, .006), (.075, .186, .089, .071),
    (.155, .49, .197, .15), (.242, .79, .295, .208),
    (.327, 1.08, .40, .31), (.41, 1.29, .455, .436),
    (.50, 1.46, .465, .48), (.61, 1.62, .457, .46),
    (.735, 1.73, .448, .43), (.855, 1.69, .418, .40),
    (.938, 1.57, .366, .38), (.981, 1.53, .284, .31), (1, 1.40, .22, .28),
])
# The glass starts well ahead of the wing root, as in Aircraft 01 and 04.
CANOPY = spline([
    (.168, .014, .009), (.211, .27, .153), (.263, .485, .371),
    (.315, .567, .472), (.357, .541, .398), (.406, .329, .176),
    (.447, .021, .012),
])
# Aircraft 04: the slim radome grows into an upper deck and a recessed
# lower bevel. The side elevation fixes the extent of each transition.
NOSE_REFINEMENT = spline([
    (0., 1., 0.), (.036, .88, .67), (.079, .83, 1.),
    (.125, .90, .90), (.168, 1., .52), (.234, 1., 0.), (1., 1., 0.),
])
# Section offsets in metres, measured inboard from the unchanged wing join.
# Keep the outermost station fixed so the original airfoils still fit.
NOSE_CROWN_OFFSET = np.array([-.045, -.041, -.027, -.005, .017, .005, -.008, 0.])
NOSE_BELLY_OFFSET = np.array([-.011, -.012, -.019, -.031, -.027, -.008, .003, 0.])
DECK_OFFSET = np.array([.028, .039, .067, .120, .130, .036, -.013, 0.])
BELLY_OFFSET = np.array([-.036, -.050, -.070, -.105, -.056, .004, .017, 0.])


def clampstep(low, high, value):
    a = np.clip((value - low) / (high - low), 0, 1)
    return a * a * (3 - 2 * a)


def span_at(q):
    return np.interp(q, PLANFORM[:, 0], PLANFORM[:, 1])


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


def put_mesh(asset, name, points, triangles, material, origin=None, normals=None, texcoords=None):
    points = np.asarray(points)
    if not len(triangles):
        return
    attributes = {"POSITION": asset.append(points if origin is None else points - origin, "VEC3")}
    attributes["NORMAL"] = asset.append(normals_for(points, triangles) if normals is None else normals, "VEC3")
    if texcoords is not None:
        attributes["TEXCOORD_0"] = asset.append(texcoords, "VEC2")
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


def refine_core(q, core_x, core_y, nose, top):
    # The glass sill and the inlet and gear openings are inherited fixtures.
    shoulder = clampstep(.155, .31, q) * (1.0 - clampstep(.67, .87, q))
    if top:
        sill = CANOPY(np.clip(q, .168, .447))[0]
        sill_blend = 1.0 - clampstep(.447, .49, q)
        shoulder *= 1.0 - sill_blend * (1.0 - clampstep(sill + .04, sill + .22, core_x))
        nose *= 1.0 - clampstep(.145, .168, q) * (1.0 - clampstep(sill + .04, sill + .18, core_x))
    else:
        shoulder *= 1.0 - clampstep(.31, .36, q) + clampstep(.50, .58, q)
    return core_y + nose * (NOSE_CROWN_OFFSET if top else NOSE_BELLY_OFFSET) + shoulder * (
        DECK_OFFSET if top else BELLY_OFFSET)


def ship_skin(asset):
    stations = np.unique(np.round(np.concatenate((
        np.linspace(0., .984, 75), PLANFORM[:, 0], BODY.x, CANOPY.x,
        [.077, .124, .687, .829, .865, .881, .912, .926]
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
                profile = center if top else (center + LOWER_SECTION) * .5
                core_y = root_chine + eps * (crown if top else belly) * profile
                local_span = w - b
                outside_x = b + local_span * beyond
                # The inner blend shares the chine height, then tapers into
                # the wing wedge while distinct span stations carry camber.
                wave = np.interp(beyond, [0., .13, .40, .64, .86, 1.], [0., .45, .91, .69, .28, 0.])
                thickness = clampstep(.026, 1.0, local_span) * (.175 if top else .19)
                root_blend = (core_y[-1] - root_chine) * (1.0 - beyond) ** 3
                wing_y = root_chine + wing_fold(outside_x) - wing_fold(b) + root_blend + eps * wave * thickness
                core_x = b * FUSELAGE_X
                x = sign * np.concatenate((core_x, outside_x))
                y = np.concatenate((core_y, wing_y))
                z = np.full(columns, NOSE + q*LENGTH)
                rows.extend(zip(x, y, z))
                width_scale, nose = NOSE_REFINEMENT(q)
                refined_y = np.concatenate((refine_core(q, core_x, core_y, nose, top), wing_y))
                refined_rows.extend(zip(x * width_scale, refined_y, z))
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
            crease = (clampstep(.14, .31, vertex_q) *
                      (1.0 - clampstep(.66, .865, vertex_q)))[:, None]
            core_soften = soften * (1.0 - .72 * crease)
            original_normals = normals_for(original, triangles)
            pinned = ((vertex_q >= .168) & (vertex_panel >= len(FUSELAGE_X) - 1)) | (vertex_q >= .87)
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
            hole_width = CANOPY(np.clip(q, .168, .447))[:, 0]
            opening = (q > .207) & (q < .430) & (w < hole_width * .78) & top
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


def glazing(asset):
    rows = np.unique(np.round(np.concatenate((np.linspace(.168,.447,44),
                     [.205, .259, .267, .402, .408, .428])), 6))
    columns = 25
    theta = np.linspace(0, np.pi, columns)
    points, well = [], []
    for q in rows:
        w, rise = CANOPY(q)
        b, chine, crown, _, center = cross_section(q, span_at(q))
        floor = chine + crown * np.interp(w / b, FUSELAGE_X, center) - .012
        z = NOSE + q*LENGTH
        points.extend(zip(w*np.cos(theta), floor+rise*np.sin(theta)**.83, np.full(columns,z)))
        well.extend([(w*.98, floor-.008,z), (.62*w, floor-.24,z),
                     (-.62*w, floor-.24,z), (-w*.98,floor-.008,z)])
    points = np.asarray(points)
    faces = patch_indices(len(rows), columns, True)
    center = points[faces].mean(axis=1)
    q = (center[:,2]-NOSE)/LENGTH
    rim = abs(center[:,0]) > .966*CANOPY(q)[:,0]
    band = rim | ((q>.259)&(q<.267)) | ((q>.402)&(q<.408))
    normals = normals_for(points,faces)
    for mask, name, material in [(~band,"Canopy clear panes",GLASS), (band,"Canopy alloy frames",SEAL)]:
        picked, mapped = np.unique(faces[mask].reshape(-1),return_inverse=True)
        put_mesh(asset,name,points[picked],mapped.reshape(-1,3),material,normals=normals[picked])
    put_mesh(asset,"Cockpit well",np.asarray(well),patch_indices(len(rows),4,True),INTERIOR)

    # Dark seat and coaming sit inside the glass. Displays face the seat.
    coaming = np.array([
        [-.27,.43,-5.64],[.27,.43,-5.64],[-.30,.57,-5.20],[.30,.57,-5.20],
        [-.235,.46,-4.18],[.235,.46,-4.18],[-.16,.76,-3.71],[.16,.76,-3.71],
        [-.14,.79,-3.45],[.14,.79,-3.45],[-.20,.48,-3.19],[.20,.48,-3.19],
    ])
    faces = np.array([(i,i+2,i+1) for i in range(0,10,2)]+[(i+1,i+2,i+3) for i in range(0,10,2)])
    put_mesh(asset,"Cockpit instrument coaming and seat",coaming,faces,INTERIOR)


def fit_navigation_lights(asset):
    lamp = next(n for n in asset.nodes if n["name"] == "Shared physical assembly.001")
    for primitive in asset.meshes[lamp["mesh"]]["primitives"]:
        attributes = primitive["attributes"]
        points = np.array(asset.read(attributes["POSITION"]))
        # Refit the retained airframe lamps to the new wing tip, using the same
        # edge geometry as the wing instead of the previous asset's coordinates.
        q = .841 + (points[:, 2] - 6.19) / LENGTH * .62
        width = span_at(q)
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


def tail_fins(asset):
    chord_t = np.array([0., .07, .21, .43, .65, .87, .97, 1.])
    cross = np.array([.07, .63, .95, 1., .86, .51, .26, .07])
    rows = [(0., 1.30, .27, 4.84, 10.25, .22),
            (.30, 1.45, 1.08, 5.76, 10.16, .207),
            (.67, 1.66, 2.16, 7.20, 9.94, .14),
            (.87, 1.78, 2.72, 7.97, 9.86, .098),
            (1., 1.87, 3.02, 8.54, 9.71, .071)]
    for sign in (-1, 1):
        for side in (-1, 1):
            verts = np.concatenate([
                np.column_stack((sign * (x + side * thick * cross), np.full(len(chord_t), y),
                                 z0 + (z1 - z0) * chord_t))
                for _, x, y, z0, z1, thick in rows
            ])
            faces = patch_indices(len(rows), len(chord_t), sign * side < 0)
            coords = verts[faces].mean(axis=1)
            q = np.tile(np.repeat(chord_t[:-1], 2), len(rows) - 1)
            bright = (coords[:, 1] > 2.15) | (q < .06)
            n = normals_for(verts, faces)
            for wanted, color in [(~bright, SKIN), (bright, EDGE)]:
                put_mesh(asset, "Canted clipped fins", verts, faces[wanted], color, normals=n,
                         texcoords=skin_uv(verts))
        # Close the cap and two narrow bevels, so the fin still reads from the nose.
        edges = []
        for _, x, y, z0, z1, thick in rows:
            edges.append(np.array([[sign*(x - thick*.07), y, z0], [sign*(x + thick*.07), y, z0],
                                   [sign*(x + thick*.07), y, z1], [sign*(x - thick*.07), y, z1]]))
        for left, right in [(0, 1), (2, 3)]:
            loft(asset, "Fin edge bevels", [edge[[left, right]] for edge in edges], METAL, sign < 0)
        loft(asset, "Fin edge bevels", [edges[-1][[0, 1]], edges[-1][[3, 2]]], METAL, sign > 0)


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
    ]:
        mat = deepcopy(asset.materials[asset.names[template]])
        mat["name"] = name
        mat["pbrMetallicRoughness"].update(baseColorFactor=color, metallicFactor=metal, roughnessFactor=rough)
        asset.names[name] = len(asset.materials)
        asset.materials.append(mat)
    asset.materials[asset.names[LINER]]["emissiveFactor"] = [.27,.073,.013]
    ship_skin(asset)
    glazing(asset)
    intakes(asset)
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
    glass = asset.materials[asset.names[GLASS]]["pbrMetallicRoughness"]
    glass["baseColorFactor"] = [.055, .226, .198, .39]
    glass["roughnessFactor"] = .105
    metadata["reference_fighter_fit_version"] = 5
    metadata["reference_fighter_fit"] = "Aircraft/01–04; faceted radome and shouldered centrebody"
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
