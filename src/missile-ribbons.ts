import { BLEND_NORMAL, Color, CULLFACE_NONE, Entity, Mesh, MeshInstance, PRIMITIVE_TRIANGLES, StandardMaterial } from 'playcanvas';
import type { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { WorldView } from './renderer';
import type { Sortie, WeaponTrack } from './sortie';

const slots=30,points=25,lanes=3,life=1.48;
const ring=points*4;
type Trail={track:WeaponTrack; serial:number;next:number;head:number;used:number};
export class MissileRibbons {
  private readonly trails=new Map<WeaponTrack,Trail>();
  private readonly history=new Float32Array(slots*ring);
  private readonly vertices=new Float32Array(slots*points*lanes*3);
  private readonly colors=new Uint8Array(slots*points*lanes*4).fill(255);
  private readonly mesh:Mesh;
  private readonly entity=new Entity('导弹连续尾迹');
  constructor(world:WorldView){
    const device=world.entry.app.graphicsDevice;
    this.mesh=new Mesh(device);
    this.mesh.clear(true,true,slots*points*lanes,slots*(points-1)*12);
    const normals=new Float32Array(this.vertices.length);
    for(let i=1;i<normals.length;i+=3)normals[i]=1;
    this.mesh.setPositions(this.vertices);this.mesh.setColors32(this.colors);this.mesh.setNormals(normals);
    const smoke=new StandardMaterial();
    smoke.diffuse=new Color(.62,.67,.72);
    smoke.emissive=new Color(.28,.31,.34);
    smoke.useLighting=false;smoke.opacityVertexColor=true;smoke.opacityVertexColorChannel='a';
    smoke.blendType=BLEND_NORMAL;smoke.depthWrite=false;smoke.cull=CULLFACE_NONE;smoke.update();
    this.mesh.update(PRIMITIVE_TRIANGLES,false);
    const instance=new MeshInstance(this.mesh,smoke);
    instance.cull=false;
    this.entity.addComponent('render',{meshInstances:[instance],castShadows:false,receiveShadows:false});
    world.effects.addChild(this.entity);
    this.entity.enabled=false;
  }
  clear(){this.trails.clear();this.entity.enabled=false;}
  update(game:Sortie,eye:Vector3,detail:number){
    const time=game.time;
    const tracks=[...game.groups.missile,...game.groups.bomb.slice(0,slots-game.groups.missile.length)];
    let index=0,used=0;
    const triangles:number[]=[];
    for(const round of tracks){
      const base=index++*ring;
      let t=this.trails.get(round);
      const active=round.live&&(round.kind==='missile'||round.guidedGround);
      if(!active&&(!t||t.next+life<time))continue;
      if(!t||t.serial!==round.serial){
        t={track:round,serial:round.serial,next:0,head:0,used:0};
        this.trails.set(round,t);
      }
      const p=round.position,d=round.direction;
      if(active&&round.age>.073&&time>=t.next){
        const j=base+t.head*4;
        this.history[j]=p.x-d.x*2.9;this.history[j+1]=p.y-d.y*2.9;this.history[j+2]=p.z-d.z*2.9;this.history[j+3]=time;
        t.head=(t.head+1)%points;t.used=Math.min(points,t.used+1);
        t.next=time+(detail<.8?.095:.063);
      }
      const count=Math.min(t.used,detail<.8?16:points);
      const start=used*points*lanes;
      for(let row=0;row<count;row++){
        const cell=(i:number)=>base+((t.head-1-i+points)%points)*4;
        const k=cell(row),a=cell(Math.max(0,row-1)),b=cell(Math.min(row+1,count-1));
        const age=Math.max(0,time-this.history[k+3]);
        const phase=this.history[k+3]*1.5+index;
        const x=this.history[k]+age*(2+Math.sin(phase)*1.2);
        const y=this.history[k+1]+age*.84;
        const z=this.history[k+2]+age*(.81+Math.cos(phase));
        const dx=this.history[b]-this.history[a],dy=this.history[b+1]-this.history[a+1],dz=this.history[b+2]-this.history[a+2];
        const ex=eye.x-x,ey=eye.y-y,ez=eye.z-z;
        const nx=dy*ez-dz*ey,ny=dz*ex-dx*ez,nz=dx*ey-dy*ex;
        const width=(.65+age*3.2)/Math.max(.001,Math.hypot(nx,ny,nz));
        const opacity=Math.round(170*Math.max(0,1-age/life)**1.56*(.8+.2*Math.cos(phase)));
        for(let lane=0;lane<lanes;lane++){
          const vertex=start+row*lanes+lane,shift=(lane-1)*width;
          this.vertices.set([x+nx*shift,y+ny*shift,z+nz*shift],vertex*3);
          this.colors[vertex*4+3]=lane===1?opacity:0;
          if(row>0&&lane>0)triangles.push(vertex-lanes-1,vertex-1,vertex-lanes,vertex-lanes,vertex-1,vertex);
        }
      }
      if(count>1)used++;
    }
    this.entity.enabled=triangles.length>0;
    if(!this.entity.enabled)return;
    this.mesh.setPositions(this.vertices);this.mesh.setColors32(this.colors);this.mesh.setIndices(triangles);
    this.mesh.update(PRIMITIVE_TRIANGLES,false);
  }
}
