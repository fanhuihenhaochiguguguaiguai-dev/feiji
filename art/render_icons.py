"""Render the inventory icon identity set under a common photographic rig."""
from pathlib import Path
from tempfile import TemporaryDirectory
from xml.etree import ElementTree as ET
import sys
import math

import addon_utils
import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
RAW=HERE.parent/"public"/"items"
RAW.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
addon_utils.enable("io_curve_svg")
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=20
scene.cycles.use_denoising=False
scene.render.resolution_x=192
scene.render.resolution_y=144
scene.render.resolution_percentage=100
scene.render.film_transparent=True
scene.render.image_settings.file_format="PNG"
scene.render.image_settings.color_mode="RGBA"
scene.world=bpy.data.worlds.new("Neutral navy studio")
scene.world.color=(.24,.28,.36)
scene.view_settings.view_transform="AgX"

def pbr(name,rgb,metal,rough):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    node=mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value=(*rgb,1)
    node.inputs["Metallic"].default_value=metal
    node.inputs["Roughness"].default_value=rough
    return mat

def aim(o,target):
    o.rotation_euler=(Vector(target)-o.location).to_track_quat("-Z","Y").to_euler()

for name,pos,w,power,color in [
    ("Warm fabric softbox",(-3.9,4.4,6.0),4.8,315,(1,.82,.65)),
    ("Sky bounce",(3.2,-2.1,4.6),3.7,170,(.57,.78,1)),
    ("Outline kicker",(2.7,4.6,1.8),3.2,115,(.71,.88,1))]:
    light=bpy.data.lights.new(name,"AREA");light.energy=power;light.color=color;light.shape="DISK";light.size=w
    lamp=bpy.data.objects.new(name,light);scene.collection.objects.link(lamp);lamp.location=pos;aim(lamp,(0,0,0))
cam=bpy.data.objects.new("Ortho asset camera",bpy.data.cameras.new("Lens"))
scene.collection.objects.link(cam);cam.location=(2.0,-1.8,7.6);aim(cam,(0,0,0));cam.data.type="ORTHO";cam.data.ortho_scale=4.03
scene.camera=cam
warm=pbr("Brass emblem",(.52,.27,.075),.79,.29)
cool=pbr("Cast titanium",(.24,.36,.43),.66,.33)
core=pbr("Nickel inlay",(.49,.57,.61),.72,.28)
body=pbr("Gunmetal enamel",(.059,.082,.115),.61,.36)
color_by_asset={
    "shorebolt":(.57,.42,.12),"xp":(.23,.43,.63),"flarewing":(.56,.14,.084),"skylance":(.29,.51,.60),"interceptor":(.39,.43,.50),
    "night":(.14,.19,.30),"navy":(.19,.33,.47),"factory":(.36,.39,.41),"sand":(.46,.37,.24),
    "bronze-sky":(.53,.23,.10),"reserve":(.22,.40,.34),"survey":(.13,.38,.39),"veil":(.20,.30,.49),
    "tech-signal":(.18,.45,.47),"tech-horizon":(.37,.31,.54),"tech-power":(.54,.30,.11),
    "tech-vectoring":(.22,.41,.58),"up-maneuver":(.25,.39,.59),"up-armor":(.36,.39,.44),
    "up-radar":(.20,.42,.41),"up-engine":(.57,.27,.12),"circuit":(.25,.41,.31)
}

def plate(name,outline,depth,offset,mat):
    count=len(outline)
    points=[(x,y,offset+z) for z in (-depth/2,depth/2) for x,y in outline]
    faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
    faces.extend((i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count))
    geo=bpy.data.meshes.new(name);geo.from_pydata(points,[],faces);geo.update()
    ob=bpy.data.objects.new(name,geo);scene.collection.objects.link(ob);ob.data.materials.append(mat)
    edge=ob.modifiers.new("Machined edge","BEVEL");edge.width=.044;edge.segments=3
    normal=ob.modifiers.new("Weighted normals","WEIGHTED_NORMAL");normal.keep_sharp=True
    return ob

def credit():
    blank=[(-1.63,-.36),(-1.28,-.75),(.88,-.75),(1.59,-.30),(1.59,.36),(1.24,.73),(-.93,.73),(-1.63,.29)]
    plate("Pressed flight-credit blank",blank,.24,0,warm)
    plate("Blue-grey enamel bed",[(x*.88,y*.82) for x,y in blank],.072,.155,body)
    wedge=[(-.73,-.41),(.05,-.14),(.82,-.41),(.67,-.17),(.055,.32),(-.58,-.18)]
    plate("Raised flight chevron",[(x-.025,y+.115) for x,y in wedge],.064,.230,warm)
    plate("Runway inlay",[(-.090,-.48),(.10,-.48),(.127,-.27),(-.119,-.27)],.042,.220,core)
    for s in (-1,1):
        for j in range(3):
            x=s*(.92+j*.146);y=(j-1)*.074
            plate("Reeded rim",[(x-.04,y-.139),(x+.035,y-.12),(x+.035,y+.12),(x-.040,y+.108)],.031,.215,core)

def machined_box(name,center,size,mat,depth=None):
    x,y,z=center;w,h,d=size
    return plate(name,[(x-w/2,y-h/2),(x+w/2,y-h/2),(x+w/2,y+h/2),(x-w/2,y+h/2)],depth or d,z,mat)

def axis_cylinder(name,a,b,left,right,mat):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=left,radius2=right,depth=(a-b).length, location=(a+b)/2)
    ob=bpy.context.object;ob.name=name
    ob.rotation_euler=(b-a).to_track_quat("Z","Y").to_euler()
    ob.data.materials.append(mat)
    for f in ob.data.polygons:
        f.use_smooth=len(f.vertices)==4
    return ob

def ordnance(key,shape):
    paint=pbr(key+" protective finish",color_by_asset.get(key,(.29,.35,.29)),.34,.42)
    shell=pbr(key+" external shell",(.41,.46,.49),.51,.32)
    n=(-1.50,0,.16);a=(.97,0,.16);b=(1.64,0,.16)
    width=(.20,.16,.15,.26)[shape]
    axis_cylinder("Rocket motor",n,a,width,width,shell)
    axis_cylinder("Ogive",a,b,width,.013,paint)
    axis_cylinder("Nozzle",(-1.62,0,.16),(-1.43,0,.16),width*.68,width*.84,body)
    for x in [-1.18,-.45,.64]:
        axis_cylinder("Identifier collar",(x,0,.16),(x+.083,0,.16),width*1.03,width*1.03,paint)
    for sign in (-1,1):
        plate("Tail control",[(n[0],sign*width*.90),(-.68,sign*width*.90),
             (-1.21,sign*(width+.34)),(-1.51,sign*(width+.31))],.080,.12,paint)
        if shape!=3:
            plate("Forward fin",[(.28,sign*width*.82),(.77,sign*width*.82),
                 (.27,sign*(width+.17+shape*.08)),(.10,sign*(width+.17))],.054,.14,shell)

def gun(key,barrels):
    y0=-(barrels-1)*.082
    box=pbr(key+" parked mechanism",(.31,.36,.41),.66,.44)
    machined_box("Receiver",(-.85,0,.01),(1.06,barrels*.18+.34,.49),box)
    machined_box("Feeder",(-.88,-.42,.06),(.81,.31,.26),warm)
    for i in range(barrels):
        y=y0+i*.164
        z=.12+math.sin(i*1.7)*.085
        axis_cylinder("Barrel",(-.43,y,z),(1.12,y,z),.088,.061,cool)
        axis_cylinder("Muzzle nut",(1.04,y,z),(1.31,y,z),.105,.091,body)
    axis_cylinder("Gas guide",(-.31,.14,.22),(.95,.14,.22),.11,.074,core)

def box_asset(key):
    col=color_by_asset.get(key,(.29,.37,.44))
    mat=pbr(key+" painted case",col,.35,.45)
    machined_box("Cast enclosure",(0,0,.04),(2.53,1.60,.37),mat)
    machined_box("Recessed face",(0,0,.247),(2.32,1.34,.075),body)
    if key=="reserve":
        for x in (-.91,.91):
            machined_box("Raised tie-down",(x,0,.28),(.23,1.69,.05),core)
        machined_box("Redundant cartridge",(0,0,.31),(.88,.64,.09),mat)
        machined_box("Supply crest",(0,0,.388),(.22,.57,.055),warm)
        machined_box("Supply crest",(0,0,.389),(.53,.20,.055),warm)
    else:
        for x in (-.68,0,.67):
            machined_box("Chip package",(x,.10,.34),(.49,.51,.15),mat)
            for q in range(4):
                machined_box("Edge contact",(x-.18+q*.12,-.39,.31),(.044,.21,.06),warm)
        for y in (-.54,.57):
            machined_box("Machined lug",(0,y,.290),(2.19,.065,.071),core)

def engine_part(key):
    axis_cylinder("Pump casing",(-1.35,0,.11),(1.32,0,.11),.61,.42,cool)
    axis_cylinder("Rotor barrel",(-1.55,0,.11),(-.96,0,.11),.46,.49,body)
    axis_cylinder("Forward flange",(-1.47,0,.11),(-1.32,0,.11),.48,.48,warm)
    for x in (-.73,-.40,-.09,.22,.53,.82):
        axis_cylinder("Heat collar",(x,0,.11),(x+.063,0,.11),.64-.095*(x+.73),.64-.095*(x+.73),core)
    for y in (-.43,.43):
        axis_cylinder("Hydraulic line",(-.73,y,.42),(1.18,y,.29),.045,.040,warm)

def emblem(svg:Path):
    name=svg.stem
    ET.register_namespace("","http://www.w3.org/2000/svg")
    doc=ET.parse(svg)
    root=doc.getroot()
    ns="{http://www.w3.org/2000/svg}"
    glyph=root.findall(ns+"g")[-1]
    # Keep the original silhouette artwork as editable curves. The background frame
    # and catalog grid belong to the UI, so they are kept out of the render.
    for child in list(root):
        if child is not glyph:root.remove(child)
    glyph.attrib={"fill":"#fff"}
    for part in glyph:
        part.attrib.pop("opacity",None)
        part.set("fill","#fff")
    with TemporaryDirectory(prefix="wforge-svg-") as scratch:
        export=Path(scratch)/svg.name;doc.write(export,encoding="unicode")
        before=set(bpy.data.objects)
        bpy.ops.import_curve.svg(filepath=str(export))
        curves=[o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(p) for o in curves for p in o.bound_box]
    min_x,max_x=min(v.x for v in bounds),max(v.x for v in bounds)
    min_y,max_y=min(v.y for v in bounds),max(v.y for v in bounds)
    size=min(3.02/max(max_x-min_x,.001),2.28/max(max_y-min_y,.001))
    offset=Vector(((min_x+max_x)/2,(min_y+max_y)/2,0))
    mat=pbr(name+" enamel",color_by_asset.get(name,(.55,.39,.22)),.57,.36)
    for i,o in enumerate(curves):
        world=o.matrix_world.copy()
        o.parent=None;o.matrix_world=world
        o.location=(o.location-offset)*size
        o.scale*=size
        o.data.dimensions="2D";o.data.resolution_u=10
        o.data.extrude=.062/max(o.scale.x,1);o.data.bevel_depth=.016/max(o.scale.x,1)
        o.data.bevel_resolution=3;o.data.materials.clear()
        o.data.materials.append(mat if i%3!=2 else core)
    # Aircraft are already rendered from their own separate mesh designs in the hangar.

selection=set(sys.argv[sys.argv.index("--")+1:]) if "--" in sys.argv else set()
permanent=set(bpy.data.objects)
for svg in sorted((HERE/"icon-blueprints").glob("*.svg")):
    if selection and svg.stem not in selection:continue
    key=svg.stem
    if key=="credits":credit()
    elif key in ("interceptor","flarewing","skylance","bomb"):ordnance(key,("interceptor","flarewing","skylance","bomb").index(key))
    elif key=="shorebolt":ordnance(key,2)
    elif key in ("cannon-light","cannon-jet","cannon-heavy","up-weapons"):gun(key,1 if key=="cannon-light" else 3 if key=="cannon-jet" else 5)
    elif key in ("reserve","circuit","veil"):box_asset(key)
    elif key in ("vector","up-engine"):engine_part(key)
    else:emblem(svg)
    scene.render.filepath=str(RAW/(svg.stem+".render.png"))
    bpy.ops.render.render(write_still=True)
    for ob in set(bpy.data.objects)-permanent:bpy.data.objects.remove(ob,do_unlink=True)
    print("Rendered",svg.stem,flush=True)
