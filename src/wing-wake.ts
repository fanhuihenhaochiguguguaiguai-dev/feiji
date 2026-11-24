import { BLEND_NORMAL, Color, CULLFACE_NONE, Entity, Mesh, MeshInstance, PRIMITIVE_TRIANGLES, StandardMaterial } from 'playcanvas';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { FlightPose } from './flight';
import type { WorldView } from './renderer';
import type { Sortie } from './sortie';
import { highContrail, humidityFor, machFor } from './aero-vapor';

const samples=34;
const lanes=3;


export class WingWake {
  private readonly history=new Float32Array(samples*7);
  private readonly vertices=new Float32Array(samples*2*lanes*3);
  private readonly colors=new Uint8Array(samples*2*lanes*4).fill(255);
  private readonly tip=new Vector3();
  private readonly mesh:Mesh;
  private readonly indices:number[]=[];
  private readonly entity=new Entity('翼尖凝结尾迹');
  private head=0;
  private used=0;
  private time=-1;
  private lasting=false;

  constructor(world:WorldView){
    this.mesh=new Mesh(world.entry.app.graphicsDevice);
    this.mesh.clear(true,false,samples*2*lanes,(samples-1)*24);
    for(let side=0;side<2;side++)for(let row=0;row<samples-1;row++)for(let lane=0;lane<2;lane++){
      const a=(side*samples+row)*lanes+lane;
      this.indices.push(a,a+lanes,a+1,a+1,a+lanes,a+lanes+1);
    }
    const material=new StandardMaterial();
    material.diffuse=new Color(.79,.90,1);
    material.emissive=new Color(.17,.23,.30);
    material.useLighting=false;
    material.opacityVertexColor=true;
    material.opacityVertexColorChannel='a';
    material.blendType=BLEND_NORMAL;
    material.depthWrite=false;
    material.cull=CULLFACE_NONE;
    material.update();
    this.mesh.setPositions(this.vertices);
    const normals=new Float32Array(this.vertices.length);
    for(let i=1;i<normals.length;i+=3)normals[i]=1;
    this.mesh.setNormals(normals);
    this.mesh.setColors32(this.colors);
    this.mesh.setIndices(this.indices);
    this.mesh.update(PRIMITIVE_TRIANGLES,false);
    const instance=new MeshInstance(this.mesh,material);
    instance.cull=false;
    this.entity.addComponent('render',{meshInstances:[instance],castShadows:false,receiveShadows:false});
    world.effects.addChild(this.entity);
    this.entity.enabled=false;
  }

  clear(){this.head=this.used=0;this.time=-1;this.lasting=false;this.entity.enabled=false;}

  update(s:Sortie,pose:FlightPose,eye:Vector3,step:number,show:boolean,weather:number){
    const p=s.player,time=s.time;
    if(!p.alive){this.clear();return;}
    const mach=machFor(p),moisture=humidityFor(weather),ice=highContrail(p);
    const maneuver=Math.max(0,Math.abs(p.loadG)-1.1)*.28+Math.abs(p.alpha)*1.47;
    const strength=Math.min(1,Math.max(ice*.84,(maneuver+(mach-.60)*.27)*moisture));
    const contrail=ice>(this.lasting?.20:.38),lifetime=contrail?4.7:1.08;
    if(contrail!==this.lasting){this.used=0;this.time=-1;this.lasting=contrail;}
    if(step>0&&time-this.time>=(contrail?.145:.035)){
      const cell=this.head*7;
      this.history[cell]=time;
      for(let side=0;side<2;side++){
        const nozzle=contrail?p.type.engine[Math.min(side,p.type.engine.length-1)]:null;
        if(nozzle)this.tip.set(nozzle[0]+(p.type.engine.length===1?(side?1:-1)*.35:0),nozzle[1],nozzle[2]+1.8);
        else this.tip.set((side?1:-1)*p.type.span*.478,.018,p.type.length*.115);
        this.tip.rotateByQuaternionToRef(pose.orientation,this.tip);
        this.tip.addInPlace(pose.position);
        this.tip.toArray(this.history,cell+1+side*3);
      }
      this.time=time;
      this.head=(this.head+1)%samples;
      this.used=Math.min(this.used+1,samples);
    }
    this.entity.enabled=show&&this.used>=2&&strength>.07;
    if(!this.entity.enabled)return;
    for(let side=0;side<2;side++)for(let i=0;i<samples;i++){
      const offset=(this.head-1-Math.min(i,this.used-1)+samples)%samples*7;
      const from=(this.head-1-Math.max(0,Math.min(i-1,this.used-1))+samples)%samples*7;
      const to=(this.head-1-Math.min(i+1,this.used-1)+samples)%samples*7;
      const pos=offset+1+side*3,a=from+1+side*3,b=to+1+side*3;
      const x=this.history[pos],y=this.history[pos+1],z=this.history[pos+2];
      const dx=this.history[b]-this.history[a],dy=this.history[b+1]-this.history[a+1],dz=this.history[b+2]-this.history[a+2];
      const vx=eye.x-x,vy=eye.y-y,vz=eye.z-z;
      const nx=dy*vz-dz*vy,ny=dz*vx-dx*vz,nz=dx*vy-dy*vx;
      const elapsed=time-this.history[offset];
      const halfWidth=(.17+Math.min(lifetime,elapsed)*(contrail?.93:.58))*Math.max(.66,p.type.span/12)/Math.max(.001,Math.hypot(nx,ny,nz));
      const opacity=i>=this.used?0:Math.round(210*strength*Math.max(0,1-elapsed/lifetime)**1.65);
      for(let lane=0;lane<lanes;lane++){
        const vertex=(side*samples+i)*lanes+lane,across=(lane-1)*halfWidth;
        this.vertices[vertex*3]=x+nx*across+elapsed*(contrail?3.9:1.6);
        this.vertices[vertex*3+1]=y+ny*across;
        this.vertices[vertex*3+2]=z+nz*across+elapsed*1.1;
        this.colors[vertex*4+3]=lane===1?opacity:0;
      }
    }
    this.mesh.setPositions(this.vertices);
    this.mesh.setColors32(this.colors);
    this.mesh.update(PRIMITIVE_TRIANGLES,false);
  }
}
