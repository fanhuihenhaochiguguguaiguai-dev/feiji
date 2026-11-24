import { Engine } from '@babylonjs/core/Engines/engine';
import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import { Scene } from '@babylonjs/core/scene';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode';
import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Backend } from './profile';
import type { FlightEvent } from './sortie';
import { deadline } from './startup';

export class GraphicsFailure extends Error {
  constructor(readonly code:'shader'|'frame'|'device'|'timeout',cause?:unknown){
    super('图形故障 · '+code,{cause});
  }
}

/** The frame callback advances fixed simulation; rendering consumes its interpolated pose. */
export class SceneRuntime {
  readonly scene:Scene;
  readonly root:TransformNode;
  private readonly frames=new Set<()=>void>();
  private readonly postrender=new Set<()=>void>();
  private readonly events=new Set<(e:FlightEvent)=>void>();
  private pending:{promise:Promise<void>;resolve:()=>void;reject:(error:GraphicsFailure)=>void}|null=null;
  private fault:GraphicsFailure|null=null;
  private faultListener:(error:GraphicsFailure)=>void=()=>{};
  private watch?:ReturnType<typeof setInterval>;
  private lastFrame=performance.now();
  private visibleSince=performance.now();
  private contextLostAt:number|null=null;
  private checkStarted=0;
  private readonly visibility=()=>{this.visibleSince=performance.now();};
  renderNextFrame=true;
  frameMs=0;
  constructor(readonly device:AbstractEngine,readonly backend:'gpu'|'gl',readonly safe=false){
    this.scene=new Scene(device);
    this.scene.useRightHandedSystem=true;
    this.root=new TransformNode('苍穹锋刃',this.scene);
    device.onEffectErrorObservable.add(({effect,errors})=>{
      if(!effect.isReady())this.fail(new GraphicsFailure('shader',errors));
    });
    device.onContextLostObservable.add(()=>{
      if(backend==='gpu')this.fail(new GraphicsFailure('device'));
      else this.contextLostAt=performance.now();
    });
    device.onContextRestoredObservable.add(()=>{
      this.contextLostAt=null;this.lastFrame=performance.now();
    });
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
  observeNativeDevice(device:GPUDevice){
    device.addEventListener('uncapturederror',event=>{
      this.fail(new GraphicsFailure('device',(event as Event&{error:GPUError}).error.message));
    });
  }
  onGraphicsFailure(listener:(error:GraphicsFailure)=>void){
    this.faultListener=listener;
    if(this.fault)listener(this.fault);
  }
  fire(event:'sortie-event',data:FlightEvent){if(event==='sortie-event')for(const run of this.events)run(data);}
  get checkingFrame(){return this.pending!==null;}
  whenDrawn(){
    if(this.fault)return Promise.reject(this.fault);
    if(this.pending)return this.pending.promise;
    let resolve!:()=>void,reject!:(error:GraphicsFailure)=>void;
    const promise=new Promise<void>((yes,no)=>{resolve=yes;reject=no;});
    this.pending={promise,resolve,reject};this.checkStarted=performance.now();
    return promise;
  }
  private fail(error:GraphicsFailure){
    if(this.fault)return;
    this.fault=error;
    const pending=this.pending;this.pending=null;
    this.stop();
    if(pending)pending.reject(error);
    else this.faultListener(error);
  }
  stop(){
    this.device.stopRenderLoop();
    clearInterval(this.watch);
    document.removeEventListener('visibilitychange',this.visibility);
  }
  private frameReady(){
    if(!this.scene.getActiveIndices())return false;
    if(this.scene.frameGraph)return this.scene.frameGraph.isReady();
    if(!this.scene.activeCamera?.isReady(true))return false;
    const visible=this.scene.getActiveMeshes();
    for(let i=0;i<visible.length;i++)if(!visible.data[i].isReady(true))return false;
    return true;
  }
  start(){
    if(this.fault)return Promise.reject(this.fault);
    const first=this.whenDrawn();
    this.lastFrame=this.visibleSince=performance.now();
    document.addEventListener('visibilitychange',this.visibility);
    this.watch=setInterval(()=>{
      const now=performance.now();
      if(document.hidden){this.visibleSince=now;return;}
      const since=(at:number)=>now-Math.max(at,this.visibleSince);
      if(this.contextLostAt!==null){
        if(since(this.contextLostAt)>5500)this.fail(new GraphicsFailure('device'));
      }else if((this.pending&&since(this.checkStarted)>24000)||since(this.lastFrame)>14000){
        this.fail(new GraphicsFailure('timeout'));
      }
    },1500);
    this.device.runRenderLoop(()=>{
      const start=performance.now();
      this.lastFrame=start;
      if(document.hidden)this.visibleSince=start;
      if(this.fault||this.contextLostAt!==null)return;
      try{
        for(const run of this.frames)run();
        if(!this.renderNextFrame)return;
        this.scene.render(false);
        if(this.fault)return;
        this.frameMs=performance.now()-start;
        for(const run of this.postrender)run();
        if(this.pending&&this.frameReady()){
          const ready=this.pending;this.pending=null;ready.resolve();
        }
      }catch(error){this.fail(new GraphicsFailure('frame',error));}
    });
    return first;
  }
}
export interface OpenEngine {app:SceneRuntime;canvas:HTMLCanvasElement;backend:'gpu'|'gl';fallback:boolean}
export async function openEngine(canvas:HTMLCanvasElement,mode:Backend,safe=false):Promise<OpenEngine>{
  const options={alpha:false,antialias:!safe,stencil:false,powerPreference:safe?undefined:'high-performance'} as const;
  if(mode!=='gl'&&navigator.gpu){
    try{
      let expired=false;
      const initializing=(async()=>{
        const {WebGPUEngine}=await import('@babylonjs/core/Engines/webgpuEngine');
        await import('@babylonjs/core/Engines/WebGPU/Extensions/index');
        if(expired)throw new GraphicsFailure('timeout');
        const device=new WebGPUEngine(canvas,options);
        try{await device.initAsync();if(expired)throw new GraphicsFailure('timeout');}
        catch(error){device.dispose();throw error;}
        return device;
      })();
      const device=await deadline(initializing,9500,'等待 WebGPU 设备超时',()=>{expired=true;});
      const app=new SceneRuntime(device,'gpu');
      app.observeNativeDevice(device._device);
      return {app,canvas,backend:'gpu',fallback:false};
    }catch(error){console.warn('WebGPU 初始化失败，使用 WebGL2',error);}
  }
  // A canvas that acquired a WebGPU context cannot subsequently acquire WebGL.
  if(mode!=='gl'&&navigator.gpu){const next=canvas.cloneNode() as HTMLCanvasElement;canvas.replaceWith(next);canvas=next;}
  const device=new Engine(canvas,!safe,options);
  if(device.webGLVersion!==2){device.dispose();throw new Error('需要 WebGPU 或 WebGL2');}
  return {app:new SceneRuntime(device,'gl',safe),canvas,backend:'gl',fallback:mode==='gpu'};
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
