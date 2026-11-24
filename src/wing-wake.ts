import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import { VertexBuffer } from '@babylonjs/core/Buffers/buffer';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Material } from '@babylonjs/core/Materials/material';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { FlightPose } from './flight';
import type { WorldView } from './renderer';
import type { Sortie } from './sortie';

const samples=34;
const lanes=3;
const lifetime=1.08;

export class WingWake {
  private readonly history=new Float32Array(samples*7);
  private readonly vertices=new Float32Array(samples*2*lanes*3);
  private readonly colors=new Float32Array(samples*2*lanes*4).fill(1);
  private readonly tip=new Vector3();
  private readonly mesh:Mesh;
  private readonly indices:number[]=[];
  private head=0;
  private used=0;
  private time=-1;

  constructor(world:WorldView){
    const scene=world.entry.app.scene;
    this.mesh=new Mesh('翼尖凝结尾迹',scene);
    this.mesh.parent=world.effects;
    for(let side=0;side<2;side++)for(let row=0;row<samples-1;row++)for(let lane=0;lane<2;lane++){
      const a=(side*samples+row)*lanes+lane;
      this.indices.push(a,a+lanes,a+1,a+1,a+lanes,a+lanes+1);
    }
    const material=new StandardMaterial('机翼凝结云',scene);
    material.emissiveColor.set(.77,.86,.96);material.disableLighting=true;
    material.transparencyMode=Material.MATERIAL_ALPHABLEND;
    material.disableDepthWrite=true;material.backFaceCulling=false;
    const data=new VertexData();data.positions=this.vertices;data.colors=this.colors;data.indices=this.indices;
    data.applyToMesh(this.mesh,true);
    this.mesh.hasVertexAlpha=true;this.mesh.alwaysSelectAsActiveMesh=true;this.mesh.material=material;
    this.mesh.setEnabled(false);
  }

  clear(){this.head=this.used=0;this.time=-1;this.mesh.setEnabled(false);}

  update(s:Sortie,pose:FlightPose,eye:Vector3,step:number,show:boolean){
    const p=s.player,time=s.time;
    if(!p.alive){this.clear();return;}
    const strength=Math.max(0,Math.min(1,(p.speed-p.type.stall)/(p.type.trim-p.type.stall)*.65+p.boost*.34+Math.abs(p.angular.z)*.30));
    if(step>0&&time-this.time>=.035){
      const cell=this.head*7;
      this.history[cell]=time;
      for(let side=0;side<2;side++){
        this.tip.set((side?1:-1)*p.type.span*.478,.018,p.type.length*.115).rotateByQuaternionToRef(pose.orientation,this.tip);
        this.tip.addInPlace(pose.position);
        this.tip.toArray(this.history,cell+1+side*3);
      }
      this.time=time;
      this.head=(this.head+1)%samples;
      this.used=Math.min(this.used+1,samples);
    }
    this.mesh.setEnabled(show&&this.used>=2&&strength>.07);
    if(!this.mesh.isEnabled())return;
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
      const halfWidth=(.23+Math.min(lifetime,elapsed)*.64)*Math.max(.66,p.type.span/12)/Math.max(.001,Math.hypot(nx,ny,nz));
      const opacity=i>=this.used?0:.82*strength*Math.max(0,1-elapsed/lifetime)**1.65;
      for(let lane=0;lane<lanes;lane++){
        const vertex=(side*samples+i)*lanes+lane,across=(lane-1)*halfWidth;
        this.vertices[vertex*3]=x+nx*across;
        this.vertices[vertex*3+1]=y+ny*across;
        this.vertices[vertex*3+2]=z+nz*across;
        this.colors[vertex*4+3]=lane===1?opacity:0;
      }
    }
    this.mesh.updateVerticesData(VertexBuffer.PositionKind,this.vertices,false);
    this.mesh.updateVerticesData(VertexBuffer.ColorKind,this.colors,false);
  }
}
