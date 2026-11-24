"""Flagship studio. The editable Blender source and Web GLB share the same meshes."""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from fleet import MAT, block, coating, empty, loft, merge, mesh, rod, tube

bpy.ops.wm.read_factory_settings(use_empty=True)
for name, rgb, metal, rough, glow in [
    ('iron','48525a',.62,.43,0),('edge','727e86',.61,.40,0),
    ('zinc','283240',.53,.60,0),('concrete','535b5d',.06,.78,0),
    ('nightglass','334b68',.37,.24,0),('amber','d28a41',.46,.48,0),
    ('beacon','f4c386',.08,.36,1.38),('strip','cedbe4',.04,.39,1.85),
    ('rubber','21282d',.025,.89,0),('equip','5f645f',.34,.60,0),
    ('scarlet','803846',.36,.57,0),('white','dab994',.12,.49,0),
    ('arm','b17139',.53,.42,0),('piston','9da9b2',.84,.24,0),('teal','40616b',.37,.55,0)]:
    MAT[name]=coating(name,rgb,metal,rough,False,1,glow)

def prism(name,a,b,profile,key,parent):
    start,end=Vector(a),Vector(b)
    axis=(end-start).normalized()
    normal=Vector((0,0,1)) if abs(axis.z)<.82 else Vector((1,0,0))
    side=axis.cross(normal).normalized()
    normal=side.cross(axis).normalized()
    vertices=[tuple(center+u*side+w*normal) for center in (start,end) for u,w in profile]
    n=len(profile)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return mesh(name,vertices,faces,parent,[key],smooth=False)

def girder(name,a,b,width,depth,parent,key='iron'):
    w,h=width*.5,depth*.5
    flange=max(.034,h*.24);web=w*.24
    profile=[(-w,-h),(w,-h),(w,-h+flange),(web,-h+flange),(web,h-flange),(w,h-flange),
             (w,h),(-w,h),(-w,h-flange),(-web,h-flange),(-web,-h+flange),(-w,-h+flange)]
    prism(name,a,b,profile,key,parent)

def lamp(x,y,z,parent,key='beacon'):
    block('Luminaire cast housing',(x,y+.16,z),(2.10,.34,.53),parent,'zinc',.043)
    block('Emitter glass',(x,y-.035,z),(1.89,.102,.26),parent,key,.013)
    for d in (-.77,.77):
        rod('Suspension stud',(x+d,y+.20,z),(x+d,y+.72,z),.027,parent,'edge',6)

def cage(x,z,parent):
    for dx in (-1.38,1.38):
        for dz in (-1.72,1.72):
            block('Machined foot',(x+dx,.17,z+dz),(.38,.34,.37),parent,'zinc',.027)
            girder('Service stand',(x+dx,.34,z+dz),(x+dx,2.62,z+dz),.13,.14,parent,'amber')
        girder('Tool deck sill',(x+dx,2.56,z-1.73),(x+dx,2.56,z+1.73),.17,.18,parent)
    block('Elevated grating',(x,2.58,z),(2.98,.11,3.65),parent,'edge',.02)
    for j in range(8):
        block('Wheel-safe grate',(x,2.65,z-1.55+j*.45),(2.82,.043,.025),parent,'zinc')
    for dx in (-1.39,1.39):
        rod('Safety rail',(x+dx,3.61,z-1.78),(x+dx,3.61,z+1.51),.062,parent,'amber',8)
        for dz in (-1.67,0,1.43):
            rod('Rail mount',(x+dx,2.69,z+dz),(x+dx,3.61,z+dz),.048,parent,'amber',7)
    for j in range(10):
        block('Step plate',(x,.29+j*.212,z-3.73+j*.21),(1.03,.092,.28),parent,'edge',.021)
    for dx in (-.56,.56):
        girder('Ladder rail',(x+dx,.18,z-3.91),(x+dx,2.53,z-1.65),.11,.13,parent,'amber')

root=empty('Hangar')
structure=empty('Foundry frame',root)
service=empty('Work stations',root)
far=empty('Runway annex',root)
truss=[-32,-21,-10,1,12,23,34]
for z in truss:
    for side in (-1,1):
        x=side*29.8
        girder('Tapered steel pier',(x,.3,z),(x,17.8,z),.92,1.25,structure)
        block('Reinforced column footing',(x,.33,z),(2.18,.65,1.66),structure,'concrete',.067)
        for dx in (-.72,.72):
            for dz in (-.54,.54):
                rod('Anchor and nut',(x+dx,.58,z+dz),(x+dx,.79,z+dz),.076,structure,'edge',6)
        block('Inspection marker',(x-side*.48,4.82,z),(.038,.57,1.04),structure,'amber')
        if z in (-32,-10,23):lamp(x-side*1.48,6.83,z+.17,structure,'beacon')
        girder('Upper roof purlin',(x,17.8,z),(0,23.4,z),.46,.69,structure)
    girder('Roof truss lower chord',(-29.8,16.78,z),(29.8,16.78,z),.40,.61,structure)
    for i in range(12):
        xa=-30+i*5;xb=xa+5
        ya=17.8+(1-abs(xa)/30)*5.49;yb=17.8+(1-abs(xb)/30)*5.49
        girder('Continuous roof lattice',(xa,ya if i%2 else 16.78,z),(xb,16.78 if i%2 else yb,z),.22,.29,structure)
        if i in (4,7):lamp(xa+2.5,16.50,z,structure,'strip')
for x in [-29,-23,-16,-9,-3,3,9,16,23,29]:
    y=18+(1-abs(x)/30)*5.59
    girder('Longitudinal purlin',(x,y,-34),(x,y,34),.28,.36,structure)
for side in (-1,1):
    for k in range(10):
        xa=k*3.0*side;xb=(k+1)*3.0*side
        y1=18.3+(1-abs(xa)/30)*5.58;y2=18.3+(1-abs(xb)/30)*5.58
        # The gaps near the ridge form a glazed skylight.
        if k not in (0,1):
            mesh('Standing seam roof',[(xa,y1,-34),(xb,y2,-34),(xb,y2,34),(xa,y1,34)],[(0,1,2,3)],structure,['zinc'],smooth=False,closed=False)
    for z in (-28,-16,-4,8,20):
        gz=z+9.1
        x=side*30.1
        block('Ribbed bay panel',(x,5.45,z+5.1),(.25,10.6,10.16),structure,'zinc')
        for rib in range(12):
            ridge=z+.52+.84*rib
            block('Raised zinc seam',(x-side*.18,5.43,ridge),(.13,10.51,.081),structure,'iron')
        block('Glazed clerestory',(x,13.16,z+5.1),(.34,3.43,10.14),structure,'nightglass',.026)
        for k2 in range(6):
            col=z+(.7+k2*1.74)
            block('Clerestory mullion',(x-side*.18,13.13,col),(.27,3.66,.15),structure,'edge')
        for y in (11.49,13.27,14.8):
            block('Clerestory transom',(x-side*.16,y,z+5.1),(.27,.14,10.19),structure,'iron')
        for y in (8.02,8.34,8.56):
            rod('Hydraulic services',(x-side*.88,y,z-1),(x-side*.88,y+.06,gz+1.4),.077,structure,'iron' if y>8.19 else 'amber',9)
    x=side*26.6
    girder('Catwalk glazing rail',(x,10.64,-32),(x,10.64,23),.23,.26,structure,'edge')
    block('Catwalk grated tread',(x,9.42,-4.5),(2.26,.17,53.0),structure,'iron',.023)
    for z in range(-30,25,3):
        rod('Catwalk railing',(x-side*.99,9.38,z),(x-side*.99,10.64,z),.042,structure,'amber',6)
    for z in (-25,-11,4,19):
        girder('Catwalk console',(side*29.9,7.29,z),(x-side*.58,9.40,z),.27,.33,structure)


for x in (-25.6,25.6):
    girder('Portal machinery', (x,.22,32.2),(x,16.98,32.2),.95,1.32,structure,'edge')
    for z in (29.8,31.1,32.6):
        block('Power door cassette',(x*1.06,8.2,z),(2.59,16.4,.64),structure,'iron',.07)
        block('Door actuation track',(x*.97,8.2,z),(.18,16.38,.41),structure,'amber',.028)
    block('Portal signal',(x,5.11,30.81),(1.16,.30,.29),structure,'beacon',.035)
    for i in range(7):
        block('Door junction box',(x,12.0+i*.45,30.72),(1.65,.16,.42),structure,'zinc',.009)
girder('Portal beam',(-26.4,16.6,32.3),(26.4,16.6,32.3),.86,1.11,structure,'edge')
for i in range(8):
    x=-23+i*6.6
    lamp(x,15.89,31.6,structure,'beacon')
    for z in (43,58,73,89):
        block('Runway recessed light',(x,.049,z),(.45,.08,.22),far,'beacon',.016)
for x,z in [(-23,10),(23,17)]:
    cage(x,z,service)
    for j in range(4):
        p=x+(.58 if j%2 else -.34), .29+(j//2)*.52, z+3.1+(j%2)*.52
        block('Ammunition service crate',p,(1.18,.50,.66),service,'equip',.053)
        block('Crate binding',(p[0],p[1]+.27,p[2]),(1.15,.035,.13),service,'amber')
for x,z in [(-18.2,-5),(24.1,22.0)]:
    block('Calibration trolley body',(x,.8,z),(2.22,1.15,3.12),service,'equip',.09)
    rod('Wrapped service hose',(x-.78,1.37,z),(x+.77,1.37,z),.37,service,'rubber',16)
    for s in (-1,1):
        for e in (-1.13,1.13):
            ico=z+e
            rod('Fork wheel',(x+s*.81,.33,ico),(x+s*1.18,.33,ico),.34,service,'rubber',16)
            rod('Wheel hub',(x+s*1.18,.33,ico),(x+s*1.21,.33,ico),.13,service,'edge',12)
    for i in range(8):
        block('Cooling grille',(x-.89+i*.22,1.01,z-1.604),(.064,.25,.043),service,'iron',.01)
# Near bays have distinct equipment silhouettes and leave a clear taxi corridor.
for x,z,direction in [(-11.8,9.6,1),(14.3,6.4,-1)]:
    block('Tracked lifting base',(x,.28,z),(2.82,.54,2.47),service,'zinc',.13)
    block('Rotary bearing',(x,.69,z),(1.38,.38,1.46),service,'iron',.09)
    anchor=(x,.89,z)
    elbow=(x+direction*.70,3.29,z+.26)
    knuckle=(x+direction*2.08,3.90,z+.30)
    girder('Boxed crane boom',anchor,elbow,.43,.52,service,'arm')
    girder('Adjustable boom',elbow,knuckle,.29,.37,service,'arm')
    rod('Hydraulic cylinder',(x-direction*.29,.82,z-.15),(x+direction*.37,2.23,z+.09),.145,service,'zinc',10)
    rod('Chrome piston',(x+direction*.37,2.17,z+.09),elbow,.082,service,'piston',10)
    rod('Gimbal pin',(elbow[0],elbow[1],elbow[2]-.31),(elbow[0],elbow[1],elbow[2]+.31),.16,service,'piston',12)
    rod('Hoist wire',knuckle,(knuckle[0],knuckle[1]-.78,knuckle[2]),.019,service,'zinc',6)
    block('Hoist hook housing',(knuckle[0],knuckle[1]-.83,knuckle[2]),(.23,.20,.22),service,'arm',.034)
    for dx in (-1.03,1.03):
        block('Tracked pad',(x+dx,.22,z),(.69,.44,2.50),service,'rubber',.118)
        for dz in (-.89,-.44,0,.44,.89):
            block('Track shoe',(x+dx,.39,z+dz),(.72,.07,.19),service,'iron',.018)
    block('Service status lamp',(x-direction*.83,.63,z-.77),(.24,.17,.14),service,'beacon',.02)

for x,z,key in [(10.8,1.3,'scarlet'),(-10.4,3.5,'teal'),(13.6,-8.4,'equip'),(-14.1,14.2,'arm')]:
    block('Torque tool cabinet',(x,.55,z),(1.61,1.03,.78),service,key,.064)
    block('Rubber lined worktop',(x,1.106,z),(1.76,.112,.88),service,'rubber',.036)
    for j in range(4):
        y=.25+j*.185
        block('Drawer fascia',(x,y,z-.405),(1.45,.15,.044),service,key,.014)
        rod('Drawer handle',(x-.32,y,z-.45),(x+.32,y,z-.45),.023,service,'edge',7)
    for dx in (-.61,.61):
        rod('Caster',(x+dx-.08,.105,z-.27),(x+dx+.08,.105,z-.27),.104,service,'rubber',10)
    for j in range(3):
        rod('Calibrated socket',(x-.37+j*.17,1.17,z+.06),(x-.37+j*.17,1.25,z+.06),.041,service,'piston',9)

for x,z in [(-8,3.6),(9.1,-1.9),(15.3,12),(-7,16.2)]:
    block('Recessed apron lamp frame',(x,.018,z),(.73,.072,.16),service,'iron',.015)
    block('Apron lamp lens',(x,.066,z),(.55,.027,.091),service,'beacon',.01)
for x,z in [(-14.8,1.2),(12.8,3.6)]:
    stations=[(x+j*.21,.023,z+math.sin(j*.32)*.59) for j in range(20)]
    for a,b in zip(stations,stations[1:]):
        rod('Power feeder',a,b,.033,service,'rubber',6)
for x in (-10.2,10.2):
    for z in (-9,3,15,26):
        girder('Maintenance rail',(x,11.9,z),(x,11.9,z+11),.24,.35,structure,'edge')
        rod('Rail suspension',(x,11.94,z+5),(x,18,z+5),.072,structure,'iron',7)
        lamp(x,11.63,z+4.7,structure,'strip' if x>0 else 'beacon')

# Hangar frontage lands beyond the left edge of the taxi corridor.
for x in (-28.7,28.7):
    for z in (-33.5,-31.8,-30.1):
        block('External canopy lamp housing',(x,9.10,z),(1.46,.18,.34),structure,'iron',.03)
        block('Canopy lighting lens',(x,8.98,z),(1.20,.07,.24),structure,'beacon',.013)
for x in (-20,-12,-4,4,12,20):
    block('Bay number sign',(x,12.10,-34.15),(4.48,1.14,.24),structure,'zinc',.04)
    block('Backlit bay index',(x-.91,12.1,-34.30),(.84,.19,.075),structure,'beacon',.016)
    for j in range(4):
        block('Bay stencil',(x+j*.25,12.1,-34.272),(.13,.30,.04),structure,'edge',.006)

# Apron-side power unit, coupled tug and a pair of runway service posts.
x,z=-38,29
block('Tow tractor frame',(x,.58,z),(2.11,.58,3.82),far,'iron',.095)
block('Tow tractor counterweight',(x,.85,z+1.23),(1.97,.65,1.15),far,'amber',.09)
block('Tow tractor cab frame',(x,1.63,z-.64),(1.65,1.55,1.44),far,'iron',.063)
block('Tow tractor glazing',(x,1.91,z-1.38),(1.39,.77,.038),far,'nightglass',.024)
for side in (-1,1):
    for dz in (-1.22,1.04):
        rod('Tow tractor tyre',(x+side*.83,.43,z+dz),(x+side*1.11,.43,z+dz),.42,far,'rubber',16)
        rod('Tow tractor hub',(x+side*1.1,.43,z+dz),(x+side*1.14,.43,z+dz),.14,far,'edge',10)
    block('Tow tractor headlight',(x+side*.68,.91,z-1.95),(.29,.21,.11),far,'beacon',.021)

towerX,towerZ=-32,78
for dims,loc,mat in [((8,1,8),(towerX,.44,towerZ),'concrete'),((4.4,14.7,4.9),(towerX,7.3,towerZ),'zinc'),
    ((9.4,2,8.8),(towerX,14.6,towerZ),'iron'),((8.45,2.15,8.35),(towerX,16.48,towerZ),'nightglass'),
    ((9.35,.51,9.02),(towerX,17.59,towerZ),'edge')]:
    block('Operations tower',loc,dims,far,mat,.10)
for i in range(8):
    block('Tower window bow',(towerX-3.8+i*1.08,16.52,towerZ-4.22),(.105,2.20,.102),far,'iron')
rod('Airport aerial',(towerX,17.1,towerZ),(towerX,23.5,towerZ),.124,far,'edge',7)
rod('Beacon lens',(towerX,23.08,towerZ),(towerX,23.58,towerZ),.17,far,'beacon',12)
for x,z in [(-37,65),(34,82)]:
    block('Remote service shed',(x,2.72,z),(14,5.36,16),far,'zinc',.07)
    block('Raised air duct',(x,5.61,z),(10,.33,10),far,'edge',.067)
    for i in range(5): block('Service window',(x-5.2+i*2.45,3.48,z-8.06),(1.88,1,.12),far,'nightglass',.02)
for parent in (structure,service,far): merge(parent)
directory=HERE.parent/'public'/'studio'
directory.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'models'/'hangar.blend'),compress=True)
bpy.ops.export_scene.gltf(filepath=str(directory/'hangar-dusk.glb'),export_format='GLB',export_yup=True,export_cameras=False,export_lights=False,export_apply=True)
