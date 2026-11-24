import { Engine } from '@babylonjs/core/Engines/engine';
import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { Scene } from '@babylonjs/core/scene';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode';
import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Backend } from './profile';
import type { FlightEvent } from './sortie';

/** The frame callback advances fixed simulation; rendering consumes its interpolated pose. */
export class SceneRuntime {
  readonly scene:Scene;
  readonly root:TransformNode;
  private readonly frames=new Set<()=>void>();
  private readonly postrender=new Set<()=>void>();
  private readonly events=new Set<(e:FlightEvent)=>void>();
  renderNextFrame=true;
  frameMs=0;
  constructor(readonly device:AbstractEngine,readonly backend:'gpu'|'gl'){
    this.scene=new Scene(device);
    this.scene.useRightHandedSystem=true;
    this.root=new TransformNode('苍穹锋刃',this.scene);
  }
  on(event:'update'|'postrender',callback:()=>void):void;
  on(event:'sortie-event',callback:(e:FlightEvent)=>void):void;
  on(event:'update'|'postrender'|'sortie-event',callback:(e:FlightEvent)=>void){
    if(event==='sortie-event')this.events.add(callback);
    else (event==='update'?this.frames:this.postrender).add(callback as ()=>void);
  }
  once(event:'postrender',callback:()=>void){
    const listen=()=>{this.postrender.delete(listen);callback();};
    this.on(event,listen);
  }
  fire(event:'sortie-event',data:FlightEvent){if(event==='sortie-event')for(const run of this.events)run(data);}
  start(){
    this.device.runRenderLoop(()=>{
      const start=performance.now();
      for(const run of this.frames)run();
      if(!this.renderNextFrame)return;
      this.scene.render(false);
      this.frameMs=performance.now()-start;
      for(const run of this.postrender)run();
    });
  }
}
export interface OpenEngine {app:SceneRuntime;canvas:HTMLCanvasElement;backend:'gpu'|'gl';fallback:boolean}
export async function openEngine(canvas:HTMLCanvasElement,mode:Backend):Promise<OpenEngine>{
  const options={alpha:false,antialias:true,stencil:false,powerPreference:'high-performance'} as const;
  if(mode!=='gl'&&navigator.gpu){
    try{
      const {WebGPUEngine}=await import('@babylonjs/core/Engines/webgpuEngine');
      await import('@babylonjs/core/Engines/WebGPU/Extensions/index');
      const device=new WebGPUEngine(canvas,options);
      try{await device.initAsync();}
      catch(error){device.dispose();throw error;}
      return {app:new SceneRuntime(device,'gpu'),canvas,backend:'gpu',fallback:false};
    }catch(error){console.warn('WebGPU 初始化失败，使用 WebGL2',error);}
  }
  // A canvas that acquired a WebGPU context cannot subsequently acquire WebGL.
  if(mode!=='gl'&&navigator.gpu){const next=canvas.cloneNode() as HTMLCanvasElement;canvas.replaceWith(next);canvas=next;}
  const device=new Engine(canvas,true,options);
  if(device.webGLVersion!==2){device.dispose();throw new Error('需要 WebGPU 或 WebGL2');}
  return {app:new SceneRuntime(device,'gl'),canvas,backend:'gl',fallback:mode==='gpu'};
}
export const radians=Math.PI/180;
export function rotate(node:TransformNode,pitch:number,yaw:number,roll:number){
  node.rotationQuaternion??=Quaternion.Identity();
  Quaternion.RotationYawPitchRollToRef(yaw*radians,pitch*radians,roll*radians,node.rotationQuaternion);
}
export function localAngles(node:TransformNode){
  return (node.rotationQuaternion?.toEulerAngles()??node.rotation.clone()).scaleInPlace(1/radians);
}
export function findNode(root:TransformNode,name:string){return root.getChildTransformNodes().find(n=>n.name===name);}
export function directionRotation(from:Vector3,to:Vector3,out:Quaternion){
  Quaternion.FromUnitVectorsToRef(from,to,out);return out;
}
