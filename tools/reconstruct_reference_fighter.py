"""Replace the J-20 exterior skin from the existing four-view authoring asset.

The 02 top-view aircraft mask established the longitudinal stations. Separate
maxima preserve the forward strake and broad rear wing. The side and front
views constrain the chine, radome, canopy and intake depths. Tail, engines and
undercarriage stay in their existing reference-space coordinates.
"""
import argparse
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.interpolate import PchipInterpolator

from airframe_glb import AirframeGLB
from bake_j20_breakup import write_model
from derive_reference_combat import prune_nodes

NOSE = -11.35
LENGTH = 22.18
WIDTH = 7.25
NORMAL_FILE = "j20-reference-normal.png"
REPLACED = (
    "Continuous centrebody", "Curved mainplane", "Aileron", "Flush ", "Low-observable",
    "Low optical canopy", "Cockpit glazing", "Cockpit sill", "Cockpit seat",
    "Intake lip", "Recessed intake",
)
SKIN = "Carbon graphite · satin radar finish"
WING = "Wing ceramic composite"
EDGE = "Silver-grey wing edge"
METAL = "Brushed titanium and steel"
SEAL = "Dielectric edge and seal"
GLASS = "Blue-green optical multilayer"
INTERIOR = "Cockpit anthracite and fabric"


def spline(rows):
    entries = np.asarray(rows)
    return PchipInterpolator(entries[:, 0], entries[:, 1:], axis=0)


# Width in the transverse direction, sampled against the design top view.
# The low plateau after the forward strake is the gap before the main wing.
PLANFORM = spline([
    (0, .015), (.06, .21), (.13, .49), (.21, .82), (.29, 1.12),
    (.34, 1.48), (.371, 1.83), (.427, 2.98), (.459, 3.14),
    (.469, 2.21), (.492, 2.01), (.526, 2.26), (.574, 2.87),
    (.63, 3.76), (.69, 4.77), (.748, 5.83), (.794, 6.68),
    (.831, 7.22), (.850, 7.25), (.871, 7.13), (.881, 6.53),
    (.895, 4.74), (.909, 3.10), (.927, 1.99), (.954, 1.77), (.984, 1.66), (1, 1.49),
])
# Width at the chine, height of the crown above it, and underside depth.
BODY = spline([
    (0, .014, .011, .012), (.075, .25, .12, .093),
    (.155, .55, .24, .17), (.242, .89, .37, .23),
    (.327, 1.21, .47, .31), (.41, 1.47, .51, .42),
    (.50, 1.62, .53, .48), (.61, 1.75, .489, .46),
    (.735, 1.81, .45, .43), (.855, 1.72, .441, .40),
    (.938, 1.60, .43, .42), (.981, 1.59, .40, .36), (1, 1.40, .32, .31),
])
# The glass starts well ahead of the wing root, as in Aircraft 01 and 04.
CANOPY = spline([
    (.18, .021, .03, .324), (.22, .32, .184, .402),
    (.269, .503, .354, .47), (.319, .58, .405, .521),
    (.365, .557, .328, .561), (.411, .333, .161, .591),
    (.446, .029, .016, .603),
])


def clampstep(low, high, value):
    a = np.clip((value - low) / (high - low), 0, 1)
    return a * a * (3 - 2 * a)


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


def ship_skin(asset):
    stations = np.unique(np.round(np.concatenate((
        np.linspace(0., .982, 75), PLANFORM.x, BODY.x, CANOPY.x, [.125, .141, .815, .865, .902]
    )), 6))
    stations = stations[stations <= .984]
    surfaces = defaultdict(list)
    # Piecewise cross-section keeps the radome's chine sharp and allows the
    # rear shoulder to turn continuously into a thin airfoil.
    fuselage_x = np.array([0., .18, .36, .53, .68, .80, .90, 1.])
    forward = np.array([1., .94, .77, .57, .38, .23, .11, 0.])
    aft = np.array([1., .978, .884, .720, .54, .35, .17, 0.])
    beyond = np.array([.05, .13, .24, .38, .51, .64, .76, .86, .93, .97, 1.])
    columns = len(fuselage_x) + len(beyond)
    for sign in (-1, 1):
        for top in (True, False):
            eps = 1. if top else -1.
            rows = []
            for q in stations:
                w = PLANFORM(q)[0]
                b, crown, belly = BODY(q)
                b = min(b, .94*w)
                root_chine = .065 - .11 * clampstep(.79, .966, q)
                axial = clampstep(.13, .44, q)
                center = forward*(1-axial)+aft*axial
                # Lower centerbody carries the avionics and inlet shoulders,
                # then narrows into the engine nacelles.
                core_y = root_chine + eps*(crown if top else belly)*center
                outside_x = b + (w-b)*beyond
                wave = np.sin(np.pi*beyond)**.8
                fold = (.087*clampstep(2., 3.94, outside_x) - .121*clampstep(4.1, 6.6, outside_x))
                wing_y = root_chine + fold + eps * wave * (.16 if top else .19)
                x = sign * np.concatenate((b*fuselage_x, outside_x))
                y = np.concatenate((core_y, wing_y))
                rows.extend(zip(x, y, np.full(columns, NOSE + q*LENGTH)))
            vertices = np.asarray(rows)
            triangles = patch_indices(len(stations), columns, (sign == 1) != top)
            centers = vertices[triangles].mean(axis=1)
            w = abs(centers[:, 0])
            q = (centers[:, 2] - NOSE) / LENGTH
            width = PLANFORM(q)[:, 0]
            body = BODY(q)[:, 0]
            normals = normals_for(vertices, triangles)
            wing = w > body * .94
            flap = wing & (q > .815) & (q < .914) & (w > 3.22)
            bright = ((w > width * .86) & (q > .723) & wing)
            bright |= ((q > .865) & (w > 2.5) & wing)
            bright |= ((q > .094) & (q < .129) & (w > body*.28))
            hole_width = CANOPY(np.clip(q, .18, .446))[:, 0]
            opening = (q > .202) & (q < .425) & (w < hole_width*.78) & top
            marks = np.where(bright, EDGE, np.where(wing, WING, SKIN))
            for mat in (EDGE, SKIN, WING):
                for mobile in (False, True):
                    mask = (marks == mat) & (flap == mobile) & ~opening
                    if mask.any():
                        name = ("Aileron left" if sign < 0 else "Aileron right") if mobile else "Fused airframe skin"
                        origin = np.array([sign*4.92, -.04, NOSE+.815*LENGTH]) if mobile else None
                        surfaces[name, mat].append((vertices, triangles[mask], normals, origin))
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
        texture = np.column_stack((p[:, 0] / 14.8+.5, (p[:, 2]-NOSE)/LENGTH))
        put_mesh(asset, name, p, np.asarray(indices), material, origin, np.asarray(ns), texture)


def glazing(asset):
    rows = np.unique(np.round(np.concatenate((np.linspace(.18,.446,44),
                     [.205, .262, .270, .401, .408, .428])), 6))
    columns = 25
    theta = np.linspace(0, np.pi, columns)
    points, well = [], []
    for q in rows:
        w, rise, floor = CANOPY(q)
        z = NOSE + q*LENGTH
        points.extend(zip(w*np.cos(theta), floor+rise*np.sin(theta)**.83, np.full(columns,z)))
        well.extend([(w*.98, floor-.008,z), (.62*w, floor-.24,z),
                     (-.62*w, floor-.24,z), (-w*.98,floor-.008,z)])
    points = np.asarray(points)
    faces = patch_indices(len(rows), columns, True)
    center = points[faces].mean(axis=1)
    q = (center[:,2]-NOSE)/LENGTH
    rim = abs(center[:,0]) > .966*CANOPY(q)[:,0]
    band = rim | ((q>.262)&(q<.270)) | ((q>.401)&(q<.408))
    normals = normals_for(points,faces)
    for mask, name, material in [(~band,"Canopy clear panes",GLASS), (band,"Canopy alloy frames",METAL)]:
        picked, mapped = np.unique(faces[mask].reshape(-1),return_inverse=True)
        put_mesh(asset,name,points[picked],mapped.reshape(-1,3),material,normals=normals[picked])
    put_mesh(asset,"Cockpit well",np.asarray(well),patch_indices(len(rows),4,True),INTERIOR)

    # Dark seat and coaming sit inside the glass. Displays face the seat.
    coaming = np.array([
        [-.27,.53,-5.64],[.27,.53,-5.64],[-.30,.65,-5.20],[.30,.65,-5.20],
        [-.235,.59,-4.18],[.235,.59,-4.18],[-.16,.86,-3.71],[.16,.86,-3.71],
        [-.14,.88,-3.45],[.14,.88,-3.45],[-.20,.61,-3.19],[.20,.61,-3.19],
    ])
    faces = np.array([(i,i+2,i+1) for i in range(0,10,2)]+[(i+1,i+2,i+3) for i in range(0,10,2)])
    put_mesh(asset,"Cockpit instrument coaming and seat",coaming,faces,INTERIOR)


def intakes(asset):
    # A recessed trapezoid, with a chamfered lip that opens into a dark duct.
    for sign in (-1,1):
        mouth = np.array([
            [1.30,.105,-2.81],[1.87,.15,-2.70],[2.54,.057,-2.48],
            [2.32,-.42,-2.58],[1.62,-.50,-2.74],[1.26,-.30,-2.84],
        ])
        center = mouth.mean(axis=0)
        inset = center+(mouth-center)*.84+[0,0,.105]
        inside = center+(mouth-center)*.70+[-.06,-.03,.73]
        fairing = center+(mouth-center)*[1.09, .91, .2]+[-.034,.035,3.0]
        for a,b,name,mat in [
            (mouth,inset,"Intake chamfer",METAL), (inset,inside,"Intake recessed liner",SEAL),
            (fairing,mouth,"Intake shoulder skin",SKIN),
        ]:
            p=np.vstack((a,b))
            p[:,0]*=sign
            f = np.array([(i,(i+1)%6,i+6) for i in range(6)]+[((i+1)%6,(i+1)%6+6,i+6) for i in range(6)])
            uv = np.column_stack((p[:, 0] / 14.8+.5, (p[:, 2]-NOSE)/LENGTH)) if mat == SKIN else None
            put_mesh(asset,name,p,f[:,::1 if sign>0 else -1],mat,texcoords=uv)
        inside[:,0]*=sign
        put_mesh(asset,"Intake inner wall",inside,np.array([(0,i+1,i) for i in range(1,5)]),SEAL)


def reference_normal(path):
    # Panel breaks follow the projected chine and swept wing sections. The
    # tiny height texture is baked offline and occupies a single GPU texture.
    resolution = 1024
    channel = Image.new("L", (resolution, resolution), 128)
    paint = ImageDraw.Draw(channel)
    def seam(points, strength=104):
        xy=[(round(x*(resolution-1)),round(z*(resolution-1))) for x,z in points]
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
    height = np.array(channel.filter(ImageFilter.GaussianBlur(.70)),dtype=float)/255.
    noise = np.random.default_rng(20).normal(0,.0014,height.shape)
    gy,gx = np.gradient(height+noise)
    normals = np.dstack((-gx*9.,-gy*9.,np.ones_like(gx)))
    normals /= np.linalg.norm(normals,axis=2,keepdims=True)
    Image.fromarray(np.round((normals*.5+.5)*255).astype(np.uint8)).save(path,optimize=True)


def reconstruct(source, output, texture):
    asset = AirframeGLB(source)
    metadata = asset.doc["asset"].setdefault("extras", {})
    if metadata.get("reference_fighter_fit_version") != 2:
        raise ValueError("Use the v2 refined J-20 authoring mesh as the retained rig source.")
    root = asset.nodes[asset.scene[0]]
    root["children"] = [i for i in root["children"] if not asset.nodes[i]["name"].startswith(REPLACED)]
    ship_skin(asset)
    glazing(asset)
    intakes(asset)
    # A single J-20-only normal map, with clean linear tangent-space channels.
    images, textures = asset.doc["images"], asset.doc["textures"]
    images.append({"name": "J-20 measured panel detail", "uri": "../fleet/"+NORMAL_FILE})
    textures.append({"source":len(images)-1,"sampler":0})
    for key in (SKIN,WING,EDGE):
        mat=asset.materials[asset.names[key]]
        mat["normalTexture"]={"index":len(textures)-1,"scale":.44}
    asset.materials[asset.names[GLASS]]["pbrMetallicRoughness"]["baseColorFactor"][3]=.34
    metadata["reference_fighter_fit_version"] = 3
    metadata["reference_fighter_fit"] = "Aircraft/01–04; independently lofted fuselage and wings"
    prune_nodes(asset)
    write_model(output, asset.doc, asset.compact())
    reference_normal(texture)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source",type=Path)
    cli.add_argument("output",type=Path)
    cli.add_argument("normal_map",type=Path)
    a=cli.parse_args()
    reconstruct(a.source,a.output,a.normal_map)
