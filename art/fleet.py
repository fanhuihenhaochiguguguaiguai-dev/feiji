"""Bake original aircraft and cockpit assemblies into GLB with Blender 4.3."""
import bpy
import bmesh
import json
import math
import sys
import numpy as np
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ART = Path(__file__).resolve().parent
sys.path.insert(0, str(ART))
from airframes import REGISTRY

OUTPUT = ART.parent / 'public' / 'fleet'
SOURCES = ART / 'models'
CATALOG = ART / 'catalog'
PALETTES = {
    'oxblood': ('713835','a75143','eee5ce','e4c193'), 'linen': ('685d3d','9c8653','e1d7a7','553f27'),
    'raf': ('4c5545','666956','b7c5a8','c69355'), 'mustang': ('899da8','bbc9cf','64707c','c17453'),
    'zero': ('7c8e75','a9b69d','d9cfac','b45f47'), 'meadow': ('5a695b','798272','9baca0','efd199'),
    'italy': ('68776d','a4a99c','c9c3af','b75a40'), 'dural': ('8b9ca2','afc0c7','cad5d3','677f6a'),
    'ice': ('6b8094','899db2','b8c7d5','d8a86e'), 'navy': ('546676','7c8c99','647783','d8ad71'),
    'china': ('5f737b','7d929c','526775','cb8657'), 'stealth': ('363e4b','637483','4e5a69','a6b2b5'),
    'flanker': ('668a9e','9fadbc','7796ac','d39766'), 'transport': ('6d7a76','9da7a0','b6bcaa','d8a96c')
}
MAT = {}
quality = 1


def v(point):
    x, y, z = point
    return Vector((x, -z, y))


def linear(c):
    c = int(c, 16) / 255
    return c / 12.92 if c < .04045 else ((c + .055) / 1.055) ** 2.4


def coating(name, hex_, metal, rough, detail=False, alpha=1, radiance=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*[linear(hex_[i:i+2]) for i in (0,2,4)], alpha)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Alpha'].default_value = alpha
    if alpha < 1:
        mat.surface_render_method = 'BLENDED'
    if radiance:
        bsdf.inputs['Emission Color'].default_value = bsdf.inputs['Base Color'].default_value
        bsdf.inputs['Emission Strength'].default_value = radiance
    if name in ('skin','panel','belly'):
        bsdf.inputs['Coat Weight'].default_value=.22 if name!='belly' else .13
        bsdf.inputs['Coat Roughness'].default_value=.36
        weather=mat.node_tree.nodes.new('ShaderNodeTexImage')
        weather.image=surface_map
        channels=mat.node_tree.nodes.new('ShaderNodeSeparateColor')
        mat.node_tree.links.new(weather.outputs['Color'],channels.inputs['Color'])
        mat.node_tree.links.new(channels.outputs['Green'],bsdf.inputs['Roughness'])
        if ao_group is not None:
            output=mat.node_tree.nodes.new('ShaderNodeGroup');output.node_tree=ao_group
            mat.node_tree.links.new(weather.outputs['Color'],output.inputs['Occlusion'])
    if name=='glass':
        bsdf.inputs['Coat Weight'].default_value=.55
        bsdf.inputs['Coat Roughness'].default_value=.12
        bsdf.inputs['IOR'].default_value=1.465
    if detail:
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = texture
        tex.interpolation = 'Linear'
        normal = mat.node_tree.nodes.new('ShaderNodeNormalMap')
        normal.inputs['Strength'].default_value = .31
        mat.node_tree.links.new(tex.outputs['Color'], normal.inputs['Color'])
        mat.node_tree.links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def baked_surface(size=288):
    ax=np.linspace(0,1,size,endpoint=False,dtype=np.float32)
    u,w=np.meshgrid(ax,ax)
    seam_u=np.exp(-((np.mod(u*4+.5+.1*np.sin(w*6.283),1)-.5)*26)**2)
    seam_v=np.exp(-((np.mod(w*6+.5,1)-.5)*38)**2)
    rows=np.clip(seam_u+seam_v,0,1)
    bolts=(np.roll(seam_v,4,0)+np.roll(seam_v,-4,0))*np.maximum(0,np.cos(u*81.6814))**22
    random=np.random.default_rng(743)
    grain=.011*random.normal(size=u.shape)+.017*np.sin(u*81.68+w*46.49)
    relief=-rows*.22+bolts*.31+grain
    nx=(np.roll(relief,1,1)-np.roll(relief,-1,1))*.69
    ny=(np.roll(relief,1,0)-np.roll(relief,-1,0))*.69
    n=np.stack((.5+nx,.5+ny,np.sqrt(np.maximum(.1,1-4*(nx*nx+ny*ny))),np.ones_like(u)),-1)
    rough=np.clip(.47+.18*rows+.072*np.cos(w*6.283+u*18.849)+grain*.65,.24,.69)
    orm=np.stack((1-rows*.29,rough,np.zeros_like(u),np.ones_like(u)),-1)
    packed=[]
    for name,array in [('Airframe panel and fastener relief',n),('Panel recess and varnish',orm)]:
        img=bpy.data.images.new(name,size,size,alpha=False)
        img.colorspace_settings.name='Non-Color'
        img.pixels.foreach_set(array.astype(np.float32).reshape(-1));img.pack();packed.append(img)
    return packed


def empty(name, parent=None, pos=(0,0,0)):
    ob = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.location = v(pos)
    return ob


def mesh(name, verts, faces, parent, materials, indices=None, smooth=True, uv=None, closed=True):
    m = bpy.data.meshes.new(name)
    m.from_pydata([v(p) for p in verts], [], faces)
    m.update()
    for material in materials:
        m.materials.append(MAT[material])
    if closed:
        edit = bmesh.new()
        edit.from_mesh(m)
        bmesh.ops.recalc_face_normals(edit, faces=list(edit.faces))
        edit.to_mesh(m)
        edit.free()
    coords = m.uv_layers.new(name='UVMap')
    for face in m.polygons:
        face.use_smooth = smooth
        if indices:
            face.material_index = indices[face.index]
        for loop in face.loop_indices:
            ix = m.loops[loop].vertex_index
            x, y, z = verts[ix]
            coords.data[loop].uv = uv[ix] if uv else (x*.14+z*.46, y*.48+z*.09)
    ob = bpy.data.objects.new(name, m)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def monotone(a, b, c, d, t):
    # Piecewise cubic with limited slopes at the input stations.
    delta = c-b
    ab, cd = b-a, d-c
    m1 = math.copysign(min(abs(delta)*2,abs(ab),abs(delta)),delta) if ab*delta>0 else 0
    m2 = math.copysign(min(abs(delta)*2,abs(cd),abs(delta)),delta) if cd*delta>0 else 0
    return b + t*(m1+t*(3*delta-2*m1-m2+t*(-2*delta+m1+m2)))


def loft(name, rows, parent, mats, *, style='round', hollow=False, smooth_steps=2):
    segments = 44 if quality==2 else 19 if quality else 10
    steps = []
    for i in range(len(rows)-1):
        a,b,c,d = [rows[max(0,min(len(rows)-1,i+k))] for k in (-1,0,1,2)]
        for j in range(smooth_steps+1 if quality else 1):
            t = j / (smooth_steps+1 if quality else 1)
            rows_interp = [monotone(a[i],b[i],c[i],d[i],t) for i in range(1,4)]
            steps.append([b[0]+(c[0]-b[0])*t,*rows_interp])
    steps.append(rows[-1])
    power = .74 if style == 'crease' else 1
    verts, faces, palette, uv = [], [], [], []
    for k,(z,w,h,y) in enumerate(steps):
        for j in range(segments):
            a = math.tau*j/segments
            ca, sa = math.cos(a),math.sin(a)
            verts.append((math.copysign(abs(ca)**power,ca)*w,y+math.copysign(abs(sa)**power,sa)*h,z))
            uv.append((j/segments,k/(len(steps)-1)))
            if k == 0:
                continue
            p=(k-1)*segments+j
            q=(k-1)*segments+(j+1)%segments
            faces.append((p,q,q+segments,p+segments))
            index = 0
            if len(mats)>1 and (segments*.51 < j < segments*.98):
                index = 1
            if len(mats)>2 and ((j in (1,segments//2-2) and 1<k<len(steps)-1) or k in (3,len(steps)-4)):
                index = 2
            if 'radome' in mats and z< -4.62:
                index=mats.index('radome')
            palette.append(index)
    if not hollow:
        faces.extend([tuple(reversed(range(segments))),tuple(range(len(verts)-segments,len(verts)))])
        palette.extend([0,0])
    return mesh(name,verts,faces,parent,mats,palette,uv=uv,closed=not hollow)


def finfoil(name, stops, side, parent, variant='wing', chord=(0,1), origin=(0,0,0), mats=('skin','belly','panel')):
    if not stops:
        return
    points, faces, colors, uv = [],[],[],[]
    n = 20 if quality else 7
    for i,(span,y,lead,tail,depth) in enumerate(stops):
        for k in range(n):
            a = math.tau*k/n
            fraction = chord[0]+(chord[1]-chord[0])*(1-math.cos(a))*.5
            z = lead+(tail-lead)*fraction
            thick = math.sin(a)*(1.3-.67*fraction)*depth
            if chord[0]>0:
                thick *= .52
            x = span*side
            x, py = (x+thick,y) if variant=='fin' else (x,y+thick)
            points.append((x-origin[0],py-origin[1],z-origin[2]))
            uv.append((span*.12,fraction))
            if i > 0:
                p=(i-1)*n+k; q=(i-1)*n+(k+1)%n
                faces.append((p,p+n,q+n,q))
                colors.append(1 if len(mats)>1 and k>n*.5 else 2 if len(mats)>2 and (i==len(stops)-1 or k==0) else 0)
    faces.extend([tuple(reversed(range(n))),tuple(range(len(points)-n,len(points)))])
    colors.extend([0,0])
    return mesh(name,points,faces,parent,mats,colors,uv=uv)


def rod(name, a, b, width, parent, mat='dark', sides=8, end_width=None):
    a, b = v(a), v(b)
    d = b-a
    length=d.length
    if length<.0001:
        return
    orient=d.to_track_quat('Z','Y')
    verts=[]
    for p,r in ((a,end_width if end_width is not None else width),(b,width)):
        for i in range(sides):
            theta=math.tau*i/sides
            q=p+orient@Vector((r*math.cos(theta),r*math.sin(theta),0))
            verts.append((q.x,q.z,-q.y))
    faces=[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    faces.extend([tuple(reversed(range(sides))),tuple(range(sides,2*sides))])
    return mesh(name, verts, faces, parent, [mat])


def block(name,pos,size,parent,mat='dark',bevel=.026, tilt=0):
    x,y,z=pos
    sx,sy,sz=[s*.5 for s in size]
    verts=[(x+dx*sx,y+dy*sy*math.cos(tilt)-dz*sz*math.sin(tilt),z+dz*sz*math.cos(tilt)+dy*sy*math.sin(tilt))
           for dx,dy,dz in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    ob=mesh(name,verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(1,5,6,2),(0,3,7,4)],parent,[mat],smooth=False)
    if bevel>0:
        mod=ob.modifiers.new('Manufactured bevel','BEVEL')
        mod.width=bevel
        mod.segments=2 if quality else 1
        mod.affect='EDGES'
        mod.harden_normals=True
    return ob


def tube(name,c,stations,parent,mats, power=1):
    x,y,_=c
    n=28 if quality else 10
    p,f,shade=[],[],[]
    for j,(z,w,h) in enumerate(stations):
        for i in range(n):
            a=math.tau*i/n
            ca,sa=math.cos(a),math.sin(a)
            p.append((x+math.copysign(abs(ca)**power,ca)*w,y+math.copysign(abs(sa)**power,sa)*h,z))
            if j:
                k=(j-1)*n+i
                b=(j-1)*n+(i+1)%n
                f.append((k,k+n,b+n,b))
                shade.append(min(len(mats)-1,j-1))
    return mesh(name,p,f,parent,mats,shade,closed=False)


def merge(parent):
    children=[o for o in parent.children if o.type=='MESH' and o.data.materials and
              not any(m.surface_render_method=='BLENDED' for m in o.data.materials)]
    if len(children)<2:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for o in children:
        o.select_set(True)
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active=children[0]
    bpy.ops.object.join()
    children[0].name=parent.name+' mesh'


def wing_assembly(name, stops, root, controls=True, side=None, kind='wing', accent='panel'):
    if not stops:
        return
    sides=(-1,1) if side is None else (side,)
    for s in sides:
        if name=='Canard' and quality:
            span,y,lead,trail,_=stops[0]
            pivot=empty(name+('L' if s<0 else 'R'),root,(span*s,y,lead+(trail-lead)*.36))
            origin=(span*s,y,lead+(trail-lead)*.36)
            finfoil(name,stops,s,pivot,kind,origin=origin,mats=('skin','belly',accent))
            continue
        articulated=controls and quality
        finfoil(name,stops,s,root,kind,(0,.749) if articulated else (0,1),mats=('skin','belly',accent))
        if not articulated:
            continue
        finfoil(name+' root',stops[:2],s,root,kind,(.747,1),mats=('panel','belly'))
        span,y,lead,trail,_=stops[1]
        hinge = (span*s+(.07*s if kind=='fin' else 0),y,lead+(trail-lead)*.749)
        pivot=empty(name+('L' if s<0 else 'R'),root,hinge)
        finfoil('Hinged '+name,stops[1:],s,pivot,kind,(.752,1),hinge,('panel','belly'))



def canopy_shell(d, parent, pos, size, cockpit=False):
    z,w,h=pos
    center = size
    length=h*(2.8 if d['cockpit']=='crew' else 2.4)
    contour=[(z-length,.05,.024,center-.065),(z-length*.68,w*.64,h*.53,center+.13*h),
             (z-.14*length,w,h*.96,center+.23*h),(z+length*.49,w*.80,h*.73,center+.13*h),
             (z+length*.88,w*.41,h*.18,center+.03*h),(z+length,.025,.021,center-.015)]
    if d['cockpit']=='open':
        # The rim leaves the opening visibly open from every side.
        points=[]
        for j in range(17):
            a=j*math.tau/16
            points.append((math.sin(a)*w*.86,center+.23, z+math.cos(a)*h*1.96))
        for a,b in zip(points,points[1:]):
            rod('Leather coaming',a,b,.044,parent,'rubber',7)
        return
    loft('Canopy glass',contour,parent,('glass',),style='round',smooth_steps=3)
    if quality:
        stations=(.16,.77) if d['cockpit'] in ('glass','glass-wide') else (.25,.58,.79)
        for t in stations:
            station=z-length+length*2*t
            r=(.5+.5*math.sin(t*math.pi))
            arc=[(math.cos(a)*w*r,center+math.sin(a)*h*(r+.11),station) for a in [j*math.pi/10 for j in range(11)]]
            for a,b in zip(arc,arc[1:]):
                rod('Canopy bow',a,b,.018 if d['cockpit']!='crew' else .036,parent,'trim',6)


def landing(d, root):
    length,span=d['length'],d['span']
    prop=bool(d['props'])
    fixed=d['era']=='ww1'
    lower=.62 if fixed else min(1.52,.49+length*.036)
    locations=[(-span*(.13 if prop else .107),-.24,-length*.04),(span*(.13 if prop else .107),-.24,-length*.04)]
    if prop and not fixed:
        locations.append((0,.08,length*.40))
    if not prop:
        locations.append((0,-.34,-length*.29))
    for k,p in enumerate(locations):
        joint=empty('Gear_'+str(k),root,p)
        radius=(lower*.23 if k<2 else lower*.15)
        h=lower if k<2 or not prop else lower*.55
        rod('Strut',(0,0,0),((k-1)*.08,-h,0),.049 if length<11 else .078,joint,'titanium')
        rod('Brace',(0,-h*.03,.17),(0,-h*.78,0),.039,joint,'dark')
        rod('Wheel',(-.10,-h,0),(.10,-h,0),radius,joint,'rubber',16)
        rod('Axle',(-.12,-h,0),(.12,-h,0),radius*.51,joint,'titanium',12)
        rod('Oleopneumatic piston',(0,-h*.39,0),(0,-h*.85,0),.049,joint,'titanium',12)
        for side in (-1,1):
            rod('Torque link',(side*.068,-h*.42,0),(side*.068,-h*.62,.115),.024,joint,'dark',7)
            rod('Lower link',(side*.068,-h*.62,.115),(side*.068,-h*.82,0),.024,joint,'titanium',7)
            rod('Wheel hub cap',(side*.119,-h,0),(side*.132,-h,0),radius*.37,joint,'panel',12)
        if not fixed:
            joint.rotation_mode='QUATERNION'
            joint.rotation_quaternion=Quaternion((1,0,0),1.48 if k!=2 else -1.44)
            joint.keyframe_insert('rotation_quaternion',frame=1)
            joint.rotation_quaternion=Quaternion((1,0,0),0)
            joint.keyframe_insert('rotation_quaternion',frame=31)
            for curve in joint.animation_data.action.fcurves:
                for point in curve.keyframe_points:
                    point.interpolation='LINEAR'
        merge(joint)
    return lower+.33


def propeller(root,p,k,d):
    x,y,z,r,blades=p
    rotor=empty('Prop_'+str(k),root,(x,y,z))
    for i in range(blades):
        a=i/blades*math.tau
        pairs=[(.10,.067,.051),(.31,.125,.034),(.66,.114,-.006),(.90,.079,-.038),(1.0,.025,-.058)]
        points=[]
        for along,w,shift in pairs:
            for f in (-1,1):
                side=w*f+shift
                points.append((r*(math.sin(a)*along+math.cos(a)*side),r*(math.cos(a)*along-math.sin(a)*side),side*.13))
        faces=[(j,j+1,j+3,j+2) for j in range(0,len(points)-2,2)]
        mesh('Propeller blade',points,faces,rotor,['dark','stripe'],[0,0,0,1],closed=False)
    center=empty('Spinner_'+str(k),root,(x,y,z))
    loft('Spinner',[(-r*.25,.025,.025,0),(-r*.15,r*.108,r*.097,0),(.031,r*.165,r*.164,0),(.14,r*.153,r*.152,0)],center,('trim','titanium'))
    if d['support']:
        nacelle=empty('Drive nacelle',root,(x,y,z))
        loft('Drive fairing',[(.18,.54,.68,0),(.87,.67,.68,0),(2.5,.64,.57,0),(3.73,.18,.22,0)],nacelle,('skin','belly','panel'))
        merge(nacelle)
    merge(rotor)


def exterior(d, quality_level):
    global quality
    quality=quality_level
    detailed=quality==2
    root=empty('Exterior' if detailed else 'Combat' if quality else 'LOD')
    static=empty('Airframe shell',root)
    profile = d['fuselage']
    if d['id'] not in ('b2',):
        skin=('skin','belly','panel','radome') if d['id']=='f16' else ('skin','belly','panel')
        loft('Fuselage',profile,static,skin,style='crease' if d['id'] in ('j20','su35','hornet') else 'round')
    if d['id']=='f16':
        for side in (-1,1):
            finfoil('Ventral stabilizer',[(.69,-.39,4.35,6.68,.058),(.87,-.73,5.08,6.54,.043),
                    (.98,-1.03,5.82,6.34,.016)],side,static,'fin',mats=('belly','panel'))
            finfoil('Leading edge root fairing',[(.51,.05,-3.89,1.83,.154),(.83,-.001,-3.10,1.98,.123),
                    (1.39,-.015,-1.55,2.07,.036)],side,static,mats=('skin','panel'))
            rod('Wingtip track',(side*4.97,.12,2.18),(side*4.97,.12,4.06),.064,static,'titanium',10)
            if detailed:
                rod('Static discharge whip',(side*4.93,.12,4.43),(side*4.93,.12,4.70),.018,static,'dark',6)
                rod('Elevator discharge whip',(side*2.71,.064,6.99),(side*2.71,.064,7.29),.018,static,'dark',6)
        if detailed:
            rod('Nose probe',(0,.01,-7.49),(0,.01,-7.70),.020,static,'titanium',10,end_width=.008)
            block('Flush antenna',(0,.89,.79),(.21,.066,.37),static,'panel',.029)
    for n,stops in [('Aileron',d['wing']),('Elevator',d['tail']),('Canard',d['canards'])]:
        wing_assembly(n,stops,static,detailed and n!='Canard')
    for stops in d['extra_wings']:
        continuous=[(0,*stops[0][1:]),*stops]
        wing_assembly('Upper plane',continuous,static,False)
        root_y=stops[0][1]
        for side in [-1,1]:
            if root_y>1:
                rod('Cabane strut',(side*.26,.49,-.72),(side*.71,root_y,-.58),.035,static,'trim',7)
                rod('Cabane brace',(side*.25,.46,-.17),(side*.71,root_y,.04),.028,static,'trim',7)
            for shift in [-.47,.33]:
                rod('Interplane strut',(side*2.15,root_y-.94,shift+.36),(side*2.03,root_y,shift),.036,static,'trim',6)
                if d['id']=='camel':
                    rod('Flying wire',(side*.53,-.23,shift),(side*2.03,root_y,shift*.66),.010,static,'titanium',5)
    for i,stops in enumerate(d['fins']):
        wing_assembly('Rudder'+str(i),stops,static,detailed,1,'fin',accent='trim')
    for x,y,z,a,h,length in d['intake']:
        shape=[(z+.31,.91*a,.92*h),(z,.98*a,.96*h),(z+.14,1.09*a,1.10*h),
               (z+length*.41,1.18*a,1.15*h),(z+length,.69*a,.64*h)]
        tube('Machined intake lip',(x,y,z),shape,static,['intake','titanium','skin','belly'],.78 if d['era'] in ('modern','stealth') else 1)
        rod('Inlet throat',(x,y,z+.26),(x,y,z+.43),a*.78,static,'intake',14)
        if d['id']=='f16':
            tube('Shaped inner inlet duct',(x,y,z),[(z+.31,a*.83,h*.84),(z+.69,a*.74,h*.73),(z+1.14,a*.68,h*.65)],
                 static,['dark','intake'],.78)
            block('Boundary-layer splitter',(x,y+h+.107,z+.30),(a*1.83,.047,.95),static,'titanium',.017)
        if d['id']=='mig21':
            rod('Nose shock cone',(x,y,z-.39),(x,y,z+.33),a*.36,static,'trim',16,end_width=.03)
    for x,y,z,r in d['engine']:
        tube('Heat-treated nozzle',(x,y,z),[(z-1.1,r*1.04,r),(z-.1,r*1.16,r*1.05),
             (z+.22,r*.99,r*.99),(z+.25,r*.79,r*.79),(z-.72,r*.75,r*.75)],static,['titanium','dark','titanium','intake'])
        rod('Nozzle core',(x,y,z-.71),(x,y,z-.62),r*.73,static,'intake',16)
        if detailed:
            tube('Inner heat shield',(x,y,z),[(z-.69,r*.72,r*.72),(z-.35,r*.705,r*.705),
                  (z-.14,r*.73,r*.73),(z+.12,r*.76,r*.76)],static,['heat','intake','dark'])
            rod('Turbine hub',(x,y,z-.599),(x,y,z-.43),r*.192,static,'titanium',17)
            for i in range(12):
                angle=i*math.tau/12
                lx,ly=math.cos(angle)*r,math.sin(angle)*r
                start=(x+lx*.19,y+ly*.19,z-.53)
                blade=(x+lx*.68-ly*.14,y+ly*.68+lx*.14,z-.575)
                rod('Scalloped flame holder',start,blade,r*.032,static,'heat',5,end_width=r*.055)
            for i in range(16):
                a=i/16*math.tau
                ux,uy=math.cos(a)*r,math.sin(a)*r
                rod('Nozzle petal rib',(x+ux*1.11,y+uy*1.07,z-.41),(x+ux,y+uy,z+.18),.031,static,'titanium',5)
                rod('Thermal retaining pin',(x+ux*.91,y+uy*.91,z+.22),(x+ux*.85,y+uy*.85,z+.32),.018,static,'dark',5)
    if d['canopy']:
        nose=d['canopy']
        canopy_shell(d,static,nose,profile[max(0,len(profile)//3)][2]*.82)
    if d['id']=='e2':
        radar=empty('RadarSpin',root,(0,2.86,2.08))
        disc=[(0.02,.11,.11),(2.6,.34,2.62),(3.48,.19,3.48),(3.71,.04,3.71)]
        pts,fs=[],[]
        for xradius,y,zradius in disc:
            for i in range(32 if detailed else 16):
                a=i*math.tau/(32 if detailed else 16)
                pts.append((math.sin(a)*xradius,y, math.cos(a)*zradius))
        n=len(pts)//4
        for r in range(3):
            for i in range(n):
                a=r*n+i;b=r*n+(i+1)%n
                fs.append((a,b,b+n,a+n))
        fs += [tuple(range(n)),tuple(range(3*n,4*n))]
        mesh('Rotodome',pts,fs,radar,['panel'])
        rod('Rotodome pylon',(0,1.13,1.77),(0,2.95,2.07),.28,static,'dark',8)
    if d['id']=='ea6b':
        for s in (-1,1):
            pod=empty('Jammer pod',static,(s*4.81,-.8,1.02))
            loft('Jamming pod',[(-1.43,.10,.10,0),(-1.01,.28,.26,0),(1.06,.27,.25,0),(1.41,.15,.14,0)],pod,('panel','belly'))
    for k,p in enumerate(d['props']):
        propeller(root,p,k,d)
    for k,(x,y,z) in enumerate(d['rails']):
        if d['id']=='j20':
            door=empty('Bay_'+str(k),root,(x,y,z))
            block('Weapons bay door',(0,-.035,0),(.61,.06,2.59),door,'panel',.014)
            continue
        block('Pylon',(x,y+.15,z),(.18,.31,1.26),static,'panel',.02)
        pay=empty('Store_'+str(k),root,(x,y-.15,z))
        loft('Training missile',[(-1.24,.009,.009,0),(-.95,.092,.09,0),(-.64,.11,.11,0),(.92,.108,.107,0),(1.25,.069,.069,0)],pay,('belly','panel','stripe'))
        for side in (-1,1):
            finfoil('Tail vane',[(0,0,.59,.99,.046),(.31,0,.81,1.07,.016)],side,pay,mats=('panel',))
        merge(pay)
    if detailed:
        x,y,le,te,_=d['wing'][-1]
        for s in [-1,1]:
            rod('Tip light',(s*x,y,(le+te)*.5-.16),(s*x,y,(le+te)*.5+.11),.065,static,'nav-red' if s<0 else 'nav-green',9)
        for p in d['guns']:
            x,y,z=p
            rod('Muzzle rim',(x,y,z+.20),(x,y,z-.035),.064,static,'dark',9)
    if detailed:
        surface_marks(d,static)
        gear=landing(d,root)
    else:
        gear=0
    merge(static)
    return gear


def surface_marks(d, parent):
    # Millimetre-scale panels follow the fairing and wing airfoil rather than intersecting it.
    L,span=d['length'],d['span']
    wing=d['wing']
    for side in (-1,1):
        for k in range(1,len(wing)-1):
            x,y,z0,z1,depth=wing[k]
            if x < span*.14 or x > span*.43:
                continue
            for frac in (.36,.62):
                z=z0+(z1-z0)*frac
                a=math.acos(1-2*frac)
                h=y+math.sin(a)*(1.30-.67*frac)*depth+.018
                rod('Panel break',(side*(x-.19),h,z-.07),(side*(x+.22),h,z+.14),.014,parent,'dark',5)
        x,y,z0,z1,dep=wing[-2]
        z=z0+(z1-z0)*.3
        h=y+math.sqrt(.84)*1.099*dep+.017
        rod('Service stencil',(side*(x-.12),h,z),(side*(x+.24),h,z+.07),.027,parent,'trim',5)
    if d['id']=='j20':
        for side in (-1,1):
            pos=side*.81
            rod('Flush antenna',(pos,.53,-4.8),(pos*1.18,.51,-3.96),.043,parent,'panel',8)


def cockpit(d):
    global quality
    quality=1
    root=empty('Cockpit')
    form=d['cockpit']
    old=form in ('open','imperial','metric-original','soviet')
    open_air=form=='open'
    width=1.02 if form in ('glass-wide','naval','attack','crew') else .89 if not open_air else .77
    depth=1.67 if not open_air else 1.48
    p_y=-.615
    shell=empty('Cockpit shell',root)
    block('Floor keel',(0,-1.19,-.56),(width*2.13,.17,2.53),shell,'cockpit',.087)
    block('Acoustic cover',(0,-.932,-depth-.05),(width*1.97,.35,.34),shell,'cockpit',.055)
    block('Instrument shroud',(0,-.44,-depth-.16),(width*1.93,.065,.47),shell,'rubber',.028)
    block('Instrument bulkhead',(0,-.69,-depth-.07),(width*1.92,.46,.14),shell,'wood' if open_air else 'instrument',.041)
    for side in (-1,1):
        block('Side rail',(side*width,-.64,-.57),(.155,.15,1.97),shell,'titanium',.038)
        block('Side pedestal',(side*width*.96,-.93,-.56),(.23,.475,1.34),shell,'cockpit',.066)
        block('Console',(side*width*.96,-.674,-.68),(.238,.094,1.21),shell,'instrument',.039)
        for i in range(10 if not old else 5):
            x=side*(width*.94+(.052 if i%2 else -.043)); z=-1.13+(i//2)*.17
            rod('Switch housing',(x,-.634,z),(x,-.583,z),.023,shell,'stripe' if i%3==0 else 'titanium',8)
    if not open_air:
        apex={'naval':.81,'glass-wide':.76,'soviet-glass':.71,'imperial':.76,'attack':.67}.get(form,.81)
        bow=[(math.cos(a)*width*1.02,-.46+math.sin(a)*1.26+apex-.80,-depth-.07-math.sin(a)*.42)
             for a in [j*math.pi/16 for j in range(17)]]
        for a,b in zip(bow,bow[1:]):
            rod('Windscreen bow',a,b,.019 if form=='imperial' else .023,shell,'titanium',8)
        if form in ('metric-original','soviet','attack'):
            for side in [-1,1]:
                rod('Windscreen mullion',(side*width*.70,-.43,-depth-.24),(side*width*.44,.45,-depth-.49),.019,shell,'cockpit',8)
    else:
        bow=[(math.cos(a)*.34,-.405+math.sin(a)*.32,-depth-.34) for a in [j*math.pi/13 for j in range(14)]]
        for a,b in zip(bow,bow[1:]):
            rod('Small windscreen',a,b,.014,shell,'titanium',6)
    block('Seat pad',(0,-.86,.27),(width*1.14,.11,.43),shell,'rubber',.052)
    block('Seat back',(0,-.54,.54),(width*1.09,.65,.13),shell,'rubber',.054,.13)
    for s in (-1,1):
        block('Harness',(s*.215,-.51,.449),(.055,.51,.029),shell,'belt',.010,.12)
    stick=empty('Stick',root,(.31 if form=='glass' else .03,-1.046,-.91))
    rod('Control column',(0,0,0),(-.045,.28,-.028),.036,stick,'titanium',10)
    block('Joystick grip',(-.045,.298,-.041),(.09,.156,.103),stick,'rubber',.02,-.17)
    rod('Thumb button',(-.04,.348,-.001),(-.04,.348,.026),.019,stick,'stripe',8)
    merge(stick)
    lever=empty('Throttle',root,(-width*.98,-.63,-.73))
    rod('Throttle lever',(0,0,0),(0,.107,-.031),.026,lever,'titanium',8)
    block('Throttle grip',(0,.111,-.031),(.121,.064,.078),lever,'rubber',.013)
    merge(lever)
    if old or form in ('hybrid','attack'):
        layout=[('SPD',-.48,-.61,.117),('ALT',.47,-.61,.117),('ATT',0,-.61,.139),('RPM',-.24,-.80,.080),
                ('VSI',.26,-.80,.080),('HDG',0,-.82,.070),('SPD',-.70,-.79,.054),('ALT',.68,-.79,.054)]
        if open_air:
            layout=[('RPM',-.35,-.62,.117),('SPD',0,-.61,.121),('ALT',.36,-.62,.117),('HDG',0,-.81,.085)]
        if form in ('hybrid','attack'):
            layout=[('SPD',-.59,-.57,.092),('ALT',.58,-.59,.087),('ATT',0,-.76,.088),('RPM',.64,-.78,.074)]
        for k,(kind,x,y,r) in enumerate(layout):
            c=empty('Gauge_'+kind+'_'+str(k),root,(x,y,-depth+.033))
            c['radius']=r
            tube('Machined instrument bezel',(x,y,0),[(-depth+.01,r*1.11,r*1.11),(-depth+.027,r*1.14,r*1.14),
                 (-depth+.044,r*1.05,r*1.05),(-depth+.049,r*.94,r*.94)],shell,['intake','titanium','dark'])
    if d['id']=='f16':
        for side in (-1,1):
            block('HUD support',(side*.213,-.394,-depth-.07),(.048,.145,.29),shell,'instrument',.019)
            rod('Combiner clamp',(side*.187,-.327,-depth+.025),(side*.187,-.176,-depth-.09),.021,shell,'titanium',7)
        mesh('HUD combiner glass',[(-.19,-.318,-depth+.024),(.19,-.318,-depth+.024),
             (.174,-.158,-depth-.082),(-.174,-.158,-depth-.082)],[(0,1,2,3)],shell,['combiner'],smooth=False,closed=False)
        for s in (-1,1):
            for j in range(4):
                rod('Side-console selector',(s*.81,-.68,-.45+j*.14),(s*.81,-.638,-.45+j*.14),.022,shell,'titanium',10)
    if not old:
        screens=[(-.394,.49,.33),(.41,.47,.32)]
        if form in ('glass-wide','soviet-glass'):
            screens=[(-.38,.573,.326),(.40,.535,.326)]
        if form in ('hybrid','attack'):
            screens=[(.18,.475,.26)]
        for k,(x,w,h) in enumerate(screens):
            pane=empty('Display_'+str(k),root,(x,-.657,-depth+.05))
            pane['width']=w;pane['height']=h
            block('MFD casing',(x,-.658,-depth+.007),(w+.13,h+.09,.058),shell,'rubber',.04)
            for side in (-1,1):
                for j in range(5):
                    block('Bezel control',(x+side*(w*.5+.027),-.52-j*.066,-depth+.05),(.035,.036,.025),
                         shell,'stripe' if j==0 and side==1 else 'titanium',.004)
    merge(shell)


def configure(d):
    global texture,surface_map,ao_group
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MAT.clear()
    texture,surface_map=baked_surface(448 if d['id']=='f16' else 288)
    ao_group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
    ao_group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
    a,b,c,e=PALETTES[d['scheme']]
    metal=.17 if d['era']=='ww1' else .71 if d['scheme'] in ('mustang','dural') else .46
    definitions = {
        'skin':(a,metal,.54,True), 'belly':(c,metal*.90,.66,True), 'panel':(b,metal+.04,.48,True),
        'trim':(e,.28,.48), 'stripe':(e,.23,.43), 'titanium':('7e8a91',.83,.39,True),
        'intake':('141d27',.55,.81), 'dark':('293746',.49,.68), 'heat':('805c55',.87,.45,True),
        'rubber':('23282c',.035,.91), 'glass':('779ab4',.09,.164,False,.40),
        'radome':('646d79',.04,.67,True), 'combiner':('a5c9b7',.03,.19,False,.22),
        'cockpit':('46545d',.21,.71,True), 'instrument':('28353b',.31,.66),
        'belt':('a09478',.07,.81), 'wood':('956440',.04,.54,True),
        'nav-red':('e78670',.1,.42,False,1,.35), 'nav-green':('91ddc5',.09,.4,False,1,.36)}
    for name, spec in definitions.items():
        MAT[name]=coating(name,*spec)


def stats(d, clearance):
    fields='id name origin era role length span cockpit trim maxSpeed stall roll pitch yaw boost ammo missiles bombs support service feature guns rails props engine'.split()
    row={key:d[key] for key in fields}
    row['gearClearance']=round(clearance,3)
    row['gearFixed']=d['era']=='ww1'
    row['tailMissing']=not d['tail']
    row['visualRadius']=max(d['span'],d['length'])*.56
    row['eye']=[0,round((d['canopy'][2] if d['canopy'] else .64)+d['fuselage'][3][2]*.70,3),
                d['canopy'][0] if d['canopy'] else -2]
    return row


def run():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    SOURCES.mkdir(exist_ok=True)
    CATALOG.mkdir(exist_ok=True)
    selection=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    for d in REGISTRY:
        if selection and d['id'] not in selection:
            continue
        configure(d)
        clearance=exterior(d,2)
        exterior(d,1)
        exterior(d,0)
        if not d['support']:
            cockpit(d)
        scene=bpy.context.scene
        scene.render.fps=30
        scene.frame_start=1;scene.frame_end=31;scene.frame_set(1)
        if d['id'] in ('j20','j10','f16','su35','a10','spitfire','dr1','hornet'):
            bpy.ops.wm.save_as_mainfile(filepath=str(SOURCES/(d['id']+'.blend')), compress=True)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT/(d['id']+'.glb')),export_format='GLB',export_yup=True,
                                  export_cameras=False,export_lights=False,export_apply=True,export_extras=True,
                                  export_animation_mode='SCENE',export_frame_range=True,export_anim_single_armature=True)
        (CATALOG/(d['id']+'.json')).write_text(json.dumps(stats(d,clearance),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(f'Baked {d["id"]} {(OUTPUT/(d["id"]+".glb")).stat().st_size:,} bytes',flush=True)


if __name__=='__main__':
    run()
