"""Build the V18.3 carrier and the single approved exhibition airframe in Blender.

Run blender -b -t 4 -P tools/build_carrier_studio.py -- OUTPUT_DIR.
The optional --master file saves the editable modeled scene and --calibration file
renders the calibration camera. Both are excluded from the mobile export.
Coordinates use metres in Blender with the nose pointing along +Y.
"""
import argparse
from bisect import bisect_right
from collections import defaultdict
import gzip
from math import acos, cos, pi, sin, tau
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--master", type=Path)
parser.add_argument("--calibration", type=Path)
options = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
root = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root / "tools"))
from airframe_glb import AirframeGLB
from bake_j20_breakup import write_model
bpy.ops.wm.read_factory_settings(use_empty=True)
options.output.mkdir(parents=True, exist_ok=True)


def material(name, rgb, roughness, metallic=0.0, light=0.0):
    item = bpy.data.materials.new(name)
    item.use_nodes = True
    item.diffuse_color = (*rgb, 1.0)
    principled = item.node_tree.nodes.get("Principled BSDF")
    for slot, value in {"Base Color": (*rgb, 1.0), "Roughness": roughness, "Metallic": metallic,
                        "Emission Color": (*rgb, 1.0), "Emission Strength": light}.items():
        principled.inputs[slot].default_value = value
    return item


def mesh(name, verts, faces, mat, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    if smooth:
        for poly in data.polygons:
            poly.use_smooth = True
    return obj


def solid(name, profile, a, b, axis, mat):
    verts = []
    for end in (a, b):
        for u, v in profile:
            p = [u, v]
            p.insert(axis, end)
            verts.append(p)
    n = len(profile)
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat)


def box(name, pos, size, mat):
    x, y, z = pos
    w, d, h = [p * 0.5 for p in size]
    return solid(name, [(x-w, y-d), (x+w, y-d), (x+w, y+d), (x-w, y+d)], z-h, z+h, 2, mat)


def cylinder(name, a, b, radius, mat, sides=16, tip=None):
    start, end = Vector(a), Vector(b)
    normal = (end - start).normalized()
    tangent = normal.cross(Vector((0, 0, 1)))
    if tangent.length < 0.01:
        tangent = normal.cross(Vector((1, 0, 0)))
    tangent.normalize()
    bitangent = normal.cross(tangent)
    verts = [p + r * (cos(tau*i/sides) * tangent + sin(tau*i/sides) * bitangent)
             for p, r in ((start, radius), (end, radius if tip is None else tip)) for i in range(sides)]
    faces = [tuple(reversed(range(sides))), tuple(range(sides, 2 * sides))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    return mesh(name, verts, faces, mat, True)


def bevel(obj, amount, steps=2):
    edge = obj.modifiers.new("Manufactured edges", "BEVEL")
    edge.width, edge.segments = amount, steps
    edge.limit_method = "ANGLE"
    normals = obj.modifiers.new("Area-weighted highlights", "WEIGHTED_NORMAL")
    normals.keep_sharp = True
    return obj


def around(name, x, y, radius, width, z, mat, lo=0.0, hi=tau):
    segments = max(8, round((hi-lo)*22))
    verts = [(x + cos(t) * r, y + sin(t) * r, z)
             for i in range(segments + 1) for t in [lo+(hi-lo)*i/segments]
             for r in (radius-width*0.5, radius+width*0.5)]
    return mesh(name, verts, [(2*i, 2*i+1, 2*i+3, 2*i+2) for i in range(segments)], mat)


def join(objects, name):
    if len(objects) == 1:
        return objects[0]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def trace(name, points, width, mat):
    verts = [(x, y, z+d) for x, y, z in points for d in (-width*.5, width*.5)]
    return mesh(name, verts, [(2*i, 2*i+1, 2*i+3, 2*i+2) for i in range(len(points)-1)], mat)


def parent_to(name, objects):
    root_node = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root_node)
    for item in objects:
        item.parent = root_node
    return root_node


steel = material("Marine paint · graphite", (0.042, 0.061, 0.079), 0.47, 0.55)
edge_steel = material("Exposed rolled steel", (0.092, 0.118, 0.143), 0.36, 0.71)
dark = material("Recessed structural steel", (0.016, 0.026, 0.036), 0.64, 0.38)
paint = material("Worn nonskid yellow", (0.49, 0.23, 0.036), 0.72)
chalk = material("Muted deck markings", (0.43, 0.48, 0.51), 0.73)
sole = material("Wet flight deck", (0.078, 0.104, 0.128), 0.25, 0.35)
window = material("Bridge glazing", (0.027, 0.067, 0.077), 0.22, 0.37)
amber = material("Amber deck fixtures", (1.0, 0.40, 0.095), 0.22, light=3.3)
cyan = material("Cyan landing strip fixtures", (0.095, 0.74, 0.97), 0.22, light=2.4)
banner = material("Weathered signal maroon", (0.195, 0.039, 0.036), 0.73)
canvas = material("Dark equipment canvas", (0.041, 0.072, 0.077), 0.78)


def carrier():
    previous = set(bpy.data.objects)
    deck = [(-42, -96), (-35, -113), (25, -113), (36, -94),
            (36, 91), (23, 109), (-27, 109), (-42, 83)]
    outline = [(-40, -96), (-32, -108), (22, -108), (32, -94),
               (32, 90), (20, 105), (-24, 105), (-39, 80)]
    solid("Flight deck", deck, -0.16, 0.0, 2, sole)
    bevel(solid("Continuous aviation deck rim", deck, -1.02, -0.17, 2, edge_steel), 0.11)
    bevel(solid("Carrier hull above waterline", outline, -15.1, -0.95, 2, steel), 0.31)
    island, small, lit, yellow, rails = [], [], [], [], []
    island.extend([bevel(box("Island foundation", (-37, -17, 2.8), (8, 69, 5.6), steel), 0.27),
                   bevel(box("Hangar aft bulkhead", (-33, -43, 5.45), (9, 21, 10.9), steel), 0.16),
                   bevel(box("Hangar forward bulkhead", (-32.5, 9, 4.95), (10, 22, 9.9), steel), 0.17),
                   bevel(box("Hangar roof", (-32.2, -17, 10.1), (13, 57, 1.5), edge_steel), 0.18),
                   bevel(box("Command island lower storey", (-34, -19, 13.1), (10, 58, 4), steel), 0.38),
                   bevel(box("Command island upper storey", (-34.2, -24, 16.3), (9, 43, 3.1), steel), 0.27),
                   bevel(box("Bridge cantilever", (-33.5, -9, 18.2), (12, 21, 3.1), edge_steel), 0.38)])
    # The hangar mouth opens on the deck with a chamfered steel frame and actual depth.
    p = [(-33.5, 0), (-33.5, 6.4), (-31.1, 9.0), (-6, 9.0), (-3.6, 6.4), (-3.6, 0),
         (-5.05, 0), (-5.05, 5.9), (-6.7, 7.6), (-30.45, 7.6), (-32.05, 5.9), (-32.05, 0)]
    bevel(solid("Chamfered hangar door frame", p, -27.1, -25.9, 0, edge_steel), 0.09)
    box("Hangar recessed rear wall", (-39.3, -18.55, 4.2), (0.48, 27.1, 8.4), dark)
    for y in (-31, -24, -17, -10, -6):
        small.append(box("Hangar roof beam", (-33.7, y, 7.4), (12, 0.40, 0.33), edge_steel))
        lit.append(box("Hangar internal light", (-32.7, y, 7.19), (4.25, 0.10, 0.06), cyan))
    for z, lower, upper in ((5.2, -51, 17), (11.9, -45, 16), (15.1, -43, 0), (18.7, -18, 1)):
        small.append(box("Catwalk", (-27.7, (lower+upper)/2, z), (2.1, upper-lower, 0.20), edge_steel))
        rails.append(box("Catwalk guardrail", (-26.62, (lower+upper)/2, z+0.86), (0.067, upper-lower, 0.076), edge_steel))
        for y in range(lower, upper, 2):
            rails.append(box("Catwalk stanchion", (-26.66, y, z+0.46), (0.092, 0.084, 0.95), edge_steel))
    for y in range(-43, 14, 3):
        for z in (12.9, 16.1):
            small.append(box("External window recess", (-28.92, y, z), (0.16, 1.92, 0.64), dark))
            lit.append(box("Deckhouse window", (-28.81, y, z), (0.09, 1.69, 0.47), amber if y % 4 else window))
        small.append(box("Side casing joint", (-28.60, y+1.4, 5.6), (0.07, 0.06, 7.5), edge_steel)) if y < -33 or y > -4 else None
    for y in range(-17, 2, 2):
        small.append(box("Slanted bridge window", (-27.43, y, 18.18), (0.15, 1.49, 0.96), window))
        lit.append(box("Bridge instrument strip", (-27.33, y, 17.83), (0.055, 1.12, 0.12), cyan))
    for y in (-43.1, 2.7):
        solid("Tapered naval signal banner", [(y-1.8, 9.9), (y+1.8, 9.9), (y+1.8, 5.75), (y, 5.16), (y-1.8, 5.75)], -27.0, -26.92, 0, banner)
        for sign in (-1, 1):
            solid("Banner wing insignia", [(y, 8.3), (y+sign*1.11, 8.86), (y+sign*.83, 8.22),
                  (y+sign*.34, 7.97), (y, 7.84)], -26.91, -26.875, 0, paint)
    for x, y in [(-26.5, -34), (-26.5, -3.6), (-26.5, 12), (-26.5, -53)]:
        for z in (2.7, 4.4, 6.0):
            small.append(box("Heavy lamp enclosure", (x, y, z), (.31, .45, .26), dark))
            lit.append(box("Hangar door warm light", (x+.19, y, z), (.075, .25, .15), amber))
    for y in (-39.3, 3.8, 8.1):
        small.append(bevel(box("Louvred service panel",(-27.43,y,3.31),(.22,2.9,2.17),dark),.055))
        for j in range(9):
            small.append(box("Steel ventilation blade",(-27.27,y,2.55+j*.19),(.138,2.55,.055),edge_steel))
    for y in (-40.4, 8.4):
        for dy,dz,w,h in ((0,0,.32,2.93),(1.24,0,.32,2.93),(.62,1.31,1.24,.31),(.62,-1.31,1.24,.31),
                          (2.10,0,.35,2.93),(2.38,1.30,.78,.34),(2.39,-1.31,.83,.31)):
            small.append(box("Flight deck island number",(-27.228,y+dy,5.45+dz),(.065,w,h),chalk))
    for side, start, stop in ((35.1, -88, 86), (-41.25, -86, 83)):
        for y in range(start, stop, 3):
            rails.append(box("Perimeter stanchion", (side, y, 0.67), (.105, .115, 1.35), edge_steel))
            if y % 4 == 0:
                lit.append(box("Perimeter marker", (side, y+0.24, 0.28), (.21, .25, .16), amber))
        for z in (0.38, 0.84, 1.24):
            rails.append(box("Continuous guardrail", (side, (start+stop)/2, z), (.07, stop-start, .060), edge_steel))
    for x in (-17.8, 20.8):
        for y in range(-87, 93, 8):
            lit.append(box("Flush landing strip marker", (x, y, 0.019), (.78, .17, .035), cyan))
    yellow.append(around("Deck parking arc", 9.3, 3, 19.3, .14, .021, paint, -.37, 4.0))
    for y in range(-100, 102, 8):
        yellow.append(box("Runway dashed center", (10.3, y, .019), (.21, 3.8, .024), chalk))
    for y in (-51.0, 22.0):
        for x in range(-24, 15, 2):
            yellow.append(solid("Painted deck hazard stripe", [(x-.52, y-.22), (x+.22, y-.22), (x+.68, y+.22), (x-.05, y+.22)], .015, .025, 2, paint))
    for index, (x, y) in enumerate([(-20, -47), (-22, 14), (17, -32), (19, -35), (23, 50), (-30, 29), (-14, 24)]):
        for n in range(2 if index % 2 else 3):
            loc = (x+n*1.42, y+n*.41, .53)
            bevel(box("Ribbed deck equipment case", loc, (1.46, 2.17, 1.04), canvas), .10)
            small.append(box("Metal case lid", (loc[0], loc[1], 1.11), (1.41, 2.17, .10), edge_steel))
            for dx in (-.50, .50):
                small.append(box("Equipment case rib", (loc[0]+dx, loc[1]-.98, .55), (.11, .18, .96), dark))
                yellow.append(box("Case corner marker", (loc[0]+dx, loc[1]-1.08, .53), (.12, .046, .25), paint))
    for x, y, height in [(-33, -16, 12), (-33.8, -39, 8)]:
        z = 19.8 if y > -20 else 17.4
        for dx in (-1.4, 1.4):
            cylinder("Tapered antenna leg", (x+dx,y,z), (x+dx*.18,y,z+height), .17, edge_steel, 8, .064)
        for i in range(3):
            h = z + height * (.24 + i*.23)
            cylinder("Crossed mast bracing", (x-.96+i*.24,y,h), (x+1.05-i*.25,y,h+2.5), .065, steel, 6)
            small.append(box("Antenna crossbar", (x, y, h), (4.4-i*.84, .15, .13), edge_steel))
        lit.append(box("Mast obstruction light", (x, y, z+height), (.15,.14,.14), amber))
    for y, radius in [(-37.6, 1.54), (-11, 1.18)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=(-32.5, y, 20.5 if y>-20 else 18.1))
        ob = bpy.context.object
        ob.name = "Marine radar enclosure"
        ob.data.materials.append(chalk)
        for f in ob.data.polygons:
            f.use_smooth = True
    for group, name in [(small,"Deck fittings and casing joints"), (lit,"Marine practical fixtures"),
                        (yellow,"Deck operational markings"), (rails,"Safety rails and stanchions")]:
        join(group, name)
    return parent_to("Carrier | flight deck and command island", [p for p in bpy.data.objects if p not in previous])


def coastal_relief():
    """Use surveyed elevation already shipped with the coastal battle theatre."""
    raw = gzip.decompress((root / "assets/environment/bay.height").read_bytes())
    materials = [material("Coastal slate", (.064,.098,.131), .91),
                 material("Exposed cliff facets", (.109,.135,.154), .87),
                 material("Distant coastal scree", (.152,.168,.189), .84)]
    parts = []
    areas = [(-3240,1100,224,64,.56,.65),(-4650,3870,864,224,.58,1.20),
             (3590,-2100,64,64,.96,-.38),(2200,4320,864,384,.54,-.43),
             (-3100,-3930,64,224,.69,.42)]
    n = 57
    for index,(x,y,sx,sy,scale,heading) in enumerate(areas):
        verts, faces = [], []
        for j in range(n):
            for i in range(n):
                source = (sy+2*j)*1025 + sx+2*i
                h = struct.unpack_from("<h",raw,source*2)[0]/4.0
                border = min(i,j,n-1-i,n-1-j)
                trim_edge = min(1.0,border/12.0)
                p,q = (i-(n-1)*.5)*43.0,(j-(n-1)*.5)*41.0
                verts.append((x+p*cos(heading)-q*sin(heading),y+p*sin(heading)+q*cos(heading),-18+max(0,h)*trim_edge*scale))
        for j in range(n-1):
            for i in range(n-1):
                p = j*n+i
                if max(verts[k][2] for k in (p,p+1,p+n,p+n+1)) < -4:
                    continue
                faces.append((p,p+1,p+n+1,p+n))
        item = mesh(f"Surveyed coastal section {index+1}",verts,faces,materials[0],True)
        for shade in materials[1:]:
            item.data.materials.append(shade)
        for face in item.data.polygons:
            if face.normal.z < .78:
                face.material_index=1
            if sum(verts[k][2] for k in face.vertices)/4.0 > 279.0:
                face.material_index=2
        parts.append(item)
    return parent_to("SurveyedCoastline",parts)


skin = material("Carbon graphite · satin radar finish", (0.016, 0.016, 0.016), 0.33, 0.47)
trim = material("Dielectric edge and seal", (0.010, 0.010, 0.010), 0.50, 0.19)
slate = material("Wing ceramic composite", (0.022, 0.022, 0.022), 0.31, 0.53)
metal = material("Brushed titanium and steel", (0.23, 0.265, 0.29), 0.29, 0.86)
heat = material("Heat-treated nozzle", (0.141, 0.10, 0.08), 0.38, 0.79)
glass = material("Blue-green optical multilayer", (0.068, 0.29, 0.28), 0.15, 0.65)
glass.node_tree.nodes.get("Principled BSDF").inputs["Coat Weight"].default_value = 0.6
rubber = material("Aircraft tyre", (0.017, 0.021, 0.027), 0.86)

# y, half-breadth, crown above chine, lower contour and chine height.
FUSELAGE = [(-10.5, .83, .34, .34, .08), (-9.1, 1.39, .57, .50, .07),
            (-6.5, 1.83, .72, .59, .06), (-3.4, 1.93, .79, .64, .04),
            (-.1, 1.81, .82, .63, .02), (2.7, 1.56, .78, .56, .04),
            (5.0, 1.22, .65, .48, .08), (6.8, .91, .47, .38, .12),
            (8.9, .47, .27, .23, .11), (10.7, .13, .075, .09, .10), (11.35, .02, .018, .019, .10)]


def profile(frames, y):
    index = min(len(frames)-2, max(0, bisect_right([f[0] for f in frames], y)-1))
    a, b = frames[index:index+2]
    before, after = frames[max(index-1, 0)], frames[min(len(frames)-1, index+2)]
    h = b[0]-a[0]
    t = (y-a[0])/h
    u = t*t
    v = u*t
    result = []
    for x0, x1, pa, pb in zip(a[1:], b[1:], before[1:], after[1:]):
        m0 = (x1-pa)*h/(b[0]-before[0])
        m1 = (pb-x0)*h/(after[0]-a[0])
        result.append((2*v-3*u+1)*x0 + (v-2*u+t)*m0 + (-2*v+3*u)*x1 + (v-u)*m1)
    return result


def loft(name, frames, point, mat, regions, rings, closed=True):
    start, stop = frames[0][0], frames[-1][0]
    verts, faces = [], []
    for i in range(regions+1):
        y = start + (stop-start)*i/regions
        shape = profile(frames, y)
        verts.extend(point(y, tau*j/rings if closed else pi*j/rings, shape) for j in range(rings if closed else rings+1))
    n = rings if closed else rings+1
    for i in range(regions):
        for j in range(rings):
            a, b = i*n+j, i*n+(j+1)%n
            faces.append((a,a+n,b+n,b))
    if closed:
        faces.extend((tuple(reversed(range(rings))), tuple(range(regions*n, (regions+1)*n))))
    return mesh(name, verts, faces, mat, True)


def body(y, angle, shape):
    w, upper, lower, centre = shape
    s, c = sin(angle), cos(angle)
    return (w*c*(1+.12*s*s), y, centre+s*(upper if s>=0 else lower)*(.77+.23*s*s))


def canopy(y, angle, shape):
    width, height, floor = shape
    return (width*cos(angle), y, floor+sin(angle)*height)


def wing(sign):
    sections = [(1.04, 3.20, -8.72, .03, .28), (2.15, 1.63, -7.54, .09, .32),
                (4.0, -1.26, -6.77, .01, .23), (6.61, -4.83, -6.51, -.22, .11),
                (7.08, -5.28, -6.31, -.25, .075), (7.25, -5.61, -6.22, -.23, .025)]
    verts = []
    marks = 56
    for i in range(31):
        x = sections[0][0]+(sections[-1][0]-sections[0][0])*i/30
        front,rear,datum,thickness = profile(sections, x)
        for j in range(marks):
            angle = tau*j/marks
            chord = .5-.5*cos(angle)
            verts.append((sign*x,front+(rear-front)*chord,datum+thickness*sin(angle)*(1-.30*chord)))
    faces = []
    for i in range(30):
        for j in range(marks):
            a,b = i*marks+j,i*marks+(j+1)%marks
            face = (a,b,b+marks,a+marks)
            faces.append(face if sign>0 else face[::-1])
    obj = mesh("Curved mainplane · %s" % ("P" if sign>0 else "S"), verts, faces, slate, True)
    obj.data.materials.append(skin)
    obj.data.materials.append(metal)
    for face in obj.data.polygons:
        chord_segment = face.index%marks
        if chord_segment < 3 or chord_segment > marks-4:
            face.material_index=1
        if face.index//marks > 15 and chord_segment in (3, 4, marks-5, marks-4):
            face.material_index=2
    # Aileron split and the breaks between the composite skin panels.
    for t in (.59,.83):
        verts = []
        for i in range(37):
            x = 2.05 + i * 4.97 / 36
            front,rear,datum,height = profile(sections,x)
            for chord in (t-.0023,t+.0023):
                thickness = (4*chord*(1-chord))**.5
                verts.append((sign*x,front+(rear-front)*chord,datum+height*thickness*(1-.30*chord)+.022))
        mesh("Flush composite panel seam",verts, [(2*i,2*i+1,2*i+3,2*i+2) for i in range(36)],trim)
    return obj


def fighter():
    previous = set(bpy.data.objects)
    loft("Continuous centrebody and pointed radome", FUSELAGE, body, skin, 112, 80)
    frames = [(1.42,.042,.016,.797),(1.92,.29,.24,.787),(2.63,.48,.44,.72),
              (3.36,.51,.49,.693),(4.02,.42,.43,.653),(4.77,.26,.23,.60),(5.23,.025,.011,.564)]
    loft("Low optical canopy", frames, canopy, glass, 46, 40, False)
    for side in (-1,1):
        chine = []
        for i in range(69):
            y = -9.38 + i * 19.58 / 68
            point = body(y,.145,profile(FUSELAGE,y))
            chine.append((side*(point[0]+.009),point[1],point[2]+.002))
        trace("Low-observable longitudinal chine insert",chine,.032,metal)
    for y in (-6.5,-4.8,-1.75,6.92):
        shape = profile(FUSELAGE,y)
        points = [body(y+edge,tau*j/80,shape) for edge in (-.013,.013) for j in range(80)]
        points = [(x*1.004,z_y,shape[3]+(z-shape[3])*1.006) for x,z_y,z in points]
        mesh("Flush transverse skin joint",points,[(j,(j+1)%80,(j+1)%80+80,j+80) for j in range(80)],trim)
    combine = defaultdict(list)
    for s in (-1,1):
        wing(s)
        tail = [(-10.04,.23),(-9.88,3.04),(-7.92,3.16),(-6.19,1.93),(-4.95,.87),(-5.95,.16)]
        tail_obj = solid("Swept canted tail",tail,1.2,1.39,0,skin)
        for p in tail_obj.data.vertices:
            p.co.x = s*(p.co.x+p.co.z*.270)
        bevel(tail_obj,.045,3)
        silver = solid("Canted tail leading insert",[(-9.82,2.82),(-9.81,3.04),(-7.95,3.156),(-6.34,2.00),(-6.52,2.02),(-8.04,2.94)],1.192,1.401,0,metal)
        for p in silver.data.vertices:
            p.co.x=s*(p.co.x+p.co.z*.270)
        # Two recessed intake contours and a real dark duct terminus.
        outer=[(1.35,-.23),(1.61,.17),(2.21,.10),(2.58,-.16),(2.36,-.50),(1.64,-.53)]
        inner=[(1.48,-.22),(1.67,.067),(2.15,.019),(2.37,-.17),(2.22,-.39),(1.70,-.42)]
        mouth=[(s*x,1.48+.22*(x-1.63),z) for x,z in outer]
        inset=[(s*x,1.41+.19*(x-1.63),z) for x,z in inner]
        duct=[(s*(x*.89),.16,z*.72) for x,z in inner]
        back=[(s*x,-6.4,z*.80) for x,z in outer]
        all_points = mouth+inset+duct+back
        n = len(outer)
        for start,end,mat in [(0,n,metal),(n,2*n,trim),(3*n,0,skin)]:
            faces=[(start+j,start+(j+1)%n,end+(j+1)%n,end+j) for j in range(n)]
            if s<0:
                faces=[f[::-1] for f in faces]
            mesh("Intake lip / duct / integrated fairing",all_points,faces,mat,mat==skin)
        mesh("Recessed intake end",duct,[tuple(range(n))],trim)
        nozzle_x = s * .92
        cylinder("Titanium nozzle outer sleeve",(nozzle_x,-9.1,.02),(nozzle_x,-10.50,.02),.77,heat,40,.68)
        rings=[(-10.42,.697),(-10.55,.694),(-10.78,.659),(-10.83,.606),(-10.70,.566),(-10.20,.435),(-9.89,.37)]
        verts=[(nozzle_x+r*cos(tau*i/48),y,.02+r*sin(tau*i/48)) for y,r in rings for i in range(48)]
        faces=[(i*48+j,i*48+(j+1)%48,(i+1)*48+(j+1)%48,(i+1)*48+j) for i in range(len(rings)-1) for j in range(48)]
        mesh("Machined nozzle lip and hollow throat",verts,faces,metal,True)
        for i in range(18):
            t=tau*i/18
            combine[metal].append(cylinder("Nozzle petal rib",(nozzle_x+.744*cos(t),-9.74,.02+.744*sin(t)),
                (nozzle_x+.665*cos(t),-10.60,.02+.665*sin(t)),.033,metal,6,.024))
        cylinder("Engine core recessed behind throat",(nozzle_x,-9.86,.02),(nozzle_x,-9.75,.02),.36,trim,32)
        strut=(s*1.9,-2.27,-.48); hub=(s*2.42,-2.10,-1.38)
        door = bevel(box("Main landing gear bay door",(s*2.18,-2.63,-.61),(.27,1.29,.12),skin),.060)
        door.rotation_euler.y = s * .35
        combine[metal].extend([cylinder("Main gear oleo",strut,hub,.103,metal,14,.084),
            cylinder("Trailing gear link",(s*2.31,-2.92,-.58),hub,.067,metal,12)])
        cylinder("Main tyre",(hub[0]-.16,hub[1],hub[2]),(hub[0]+.16,hub[1],hub[2]),.37,rubber,32)
        combine[metal].append(cylinder("Wheel hub",(hub[0]-.182,hub[1],hub[2]),(hub[0]+.182,hub[1],hub[2]),.175,metal,24))
        combine[cyan].append(box("Navigation light strip",(s*7.12,-5.9,-.175),(.085,.40,.052),cyan))
    combine[metal].append(cylinder("Nose gear oleo",(0,5.14,-.38),(0,5.14,-1.48),.075,metal,14,.06))
    for x in (-.13,.13):
        cylinder("Nose wheel",(x-.063,5.14,-1.49),(x+.065,5.14,-1.49),.26,rubber,28)
    for group in combine.values():
        join(group,"Shared physical assembly")
    parts = [p for p in bpy.data.objects if p not in previous]
    normal = bpy.data.images.load(str(root / "assets/fleet/shared-panel-normal.png"))
    normal.colorspace_settings.name = "Non-Color"
    for coat in (skin,slate):
        nodes = coat.node_tree.nodes
        src = nodes.new("ShaderNodeTexImage")
        src.image = normal
        relief = nodes.new("ShaderNodeNormalMap")
        relief.inputs["Strength"].default_value = .23
        coat.node_tree.links.new(src.outputs["Color"],relief.inputs["Color"])
        coat.node_tree.links.new(relief.outputs["Normal"],nodes.get("Principled BSDF").inputs["Normal"])
    for part in parts:
        if part.type != "MESH" or not any(m in (skin,slate) for m in part.data.materials):
            continue
        uvs = part.data.uv_layers.new(name="Surface atlas")
        for idx, loop in enumerate(part.data.loops):
            local = part.data.vertices[loop.vertex_index].co
            uvs.data[idx].uv = ((local.x+7.5)/15.0,(local.y+10.9)/22.5)
    return parent_to("Reference specimen | fairings, aerofoils and gear", parts)


def export(assembly, path):
    bpy.ops.object.select_all(action="DESELECT")
    for item in [assembly, *assembly.children_recursive]:
        item.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
                             export_apply=True, export_animations=False, export_cameras=False, export_lights=False)


stage = carrier()
coast = coastal_relief()
coast.parent = stage
sample = fighter()
export(stage, options.output / "carrier-stage.glb")
specimen = options.output / "reference-fighter.glb"
export(sample, specimen)
asset = AirframeGLB(specimen)
for image in asset.doc.get("images", []):
    if image.get("name") == "shared-panel-normal":
        image.pop("bufferView")
        image.pop("mimeType")
        image["uri"] = "../fleet/shared-panel-normal.png"
write_model(specimen, asset.doc, asset.compact())
if options.master or options.calibration:
    sample.location.z = 1.75
    scene = bpy.context.scene
    scene.world = bpy.data.worlds.new("Sunset environment")
    scene.world.use_nodes = True
    nodes = scene.world.node_tree.nodes
    panorama = nodes.new("ShaderNodeTexEnvironment")
    panorama.image = bpy.data.images.load(str(root / "assets/studio/carrier-sunset.hdr"))
    scene.world.node_tree.links.new(panorama.outputs["Color"], nodes.get("Background").inputs["Color"])
    nodes.get("Background").inputs["Strength"].default_value = .54
    key = bpy.data.lights.new("Raking dusk sunlight", type="SUN")
    key.energy, key.angle, key.color = 1.9, .036, (1.0,.69,.45)
    light = bpy.data.objects.new(key.name,key)
    bpy.context.collection.objects.link(light)
    light.rotation_euler = Vector((.70, -.70, -.081)).to_track_quat("-Z","Y").to_euler()
    camera = bpy.data.cameras.new("Reference camera")
    camera.sensor_fit = "VERTICAL"
    camera.angle = 34.0 * pi / 180.0
    cam = bpy.data.objects.new(camera.name,camera)
    bpy.context.collection.objects.link(cam)
    cam.location = (26.17,-10.12,6.12)
    cam.rotation_euler = (Vector((0,0,2.85))-cam.location).to_track_quat("-Z","Y").to_euler()
    scene.camera=cam
    wet = sole.node_tree.nodes
    scan = wet.new("ShaderNodeTexImage")
    scan.image = bpy.data.images.load(str(root / "assets/studio/tarmac.webp"))
    tex_coord = wet.new("ShaderNodeTexCoord")
    scale = wet.new("ShaderNodeVectorMath")
    scale.operation="SCALE"
    scale.inputs[3].default_value=.12
    sole.node_tree.links.new(tex_coord.outputs["Object"], scale.inputs[0])
    sole.node_tree.links.new(scale.outputs[0],scan.inputs["Vector"])
    sole.node_tree.links.new(scan.outputs[0],wet.get("Principled BSDF").inputs["Base Color"])
    if options.master:
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=str(options.master),compress=True)
    if options.calibration:
        scene.render.engine="CYCLES"
        scene.cycles.samples=40
        scene.cycles.use_denoising=False
        scene.render.resolution_x=800
        scene.render.resolution_y=450
        scene.render.resolution_percentage=100
        scene.render.filepath=str(options.calibration)
        bpy.ops.render.render(write_still=True)
