import "@babylonjs/core/Engines/Extensions/engine.query";
import { SceneInstrumentation } from '@babylonjs/core/Instrumentation/sceneInstrumentation';
import { EngineInstrumentation } from '@babylonjs/core/Instrumentation/engineInstrumentation';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { FlightEvent } from './sortie';
import type { Game } from './engine';

export function instrument(g:Game,openedAt:number){
  const d=g.engine.device,nose=new Vector3(),projected=new Vector3(),origin=new Vector3();
  const profiler=new EngineInstrumentation(d);
  profiler.captureGPUFrameTime=true;
  const counters=new SceneInstrumentation(g.engine.scene);
  let frames=0,peakParticles=0;
  const contacts:{kind:string;weapon:string|null;id:number|null;track:number|null;terminal:boolean;at:number[];time:number;frame:number;cue:string}[]=[];
  g.engine.on('sortie-event',(e:FlightEvent)=>{
    if(e.kind==='trail')return;
    contacts.push({kind:e.kind,weapon:e.weapon??null,id:e.target?.id??null,track:e.track??null,
      terminal:!!e.terminal,at:[e.at.x,e.at.y,e.at.z],time:g.sortie?.time??0,frame:frames,cue:g.audio.lastCue});
    if(contacts.length>600)contacts.shift();
  });
  g.engine.on('postrender',()=>{frames++;peakParticles=Math.max(peakParticles,g.art.activeParticles());});
  return {
    combat:()=>({events:contacts,activeParticles:g.art.activeParticles(),audio:g.audio.stats()}),
    noseX(){
      const p=g.pilot.pivot,b=p.position,f=p.forward;
      nose.set(b.x+f.x*g.preview.length*.46,b.y+f.y*g.preview.length*.46,b.z+f.z*g.preview.length*.46);
      g.world.camera.project(nose,projected);
      return projected.x;
    },
    body(){
      const b=g.pilot.pivot.position;g.world.camera.project(origin.set(b.x,b.y,b.z),projected);
      return {x:projected.x/innerWidth,y:projected.y/innerHeight,altitude:g.sortie?.player.position.y??0};
    },
    alignment(){
      const camera=g.world.camera.native;
      const matrix=camera.getTransformationMatrix().m;
      const viewport=g.entry.canvas.getBoundingClientRect(),s=g.sortie;
      if(!s)return [];
      return g.foes.flatMap((view,i)=>{
        const target=s.enemies[i];
        const pin=document.querySelector<HTMLElement>('.target-pin[data-target="'+target.id+'"]:not([hidden]):not(.off)');
        if(!pin||!target.alive||!view.pivot.isEnabled())return [];
        const p=view.anchor;
        const clip=matrix[3]*p.x+matrix[7]*p.y+matrix[11]*p.z+matrix[15];
        const x=viewport.left+(1+(matrix[0]*p.x+matrix[4]*p.y+matrix[8]*p.z+matrix[12])/clip)*viewport.width/2;
        const y=viewport.top+(1-(matrix[1]*p.x+matrix[5]*p.y+matrix[9]*p.z+matrix[13])/clip)*viewport.height/2;
        const b=pin.getBoundingClientRect();
        return [{enemy:target.type.id,error:Math.hypot(x-b.left-b.width/2,y-b.top-b.height/2),range:clip,lod:view.lod}];
      });
    },
    sample(){
      return {
        renderer:g.entry.backend==='gpu'?'webgpu':'webgl2',frames,peakParticles,
        resolution:[d.getRenderWidth(),d.getRenderHeight()],fps:g.budget.fps,onePercentLow:g.budget.onePercentLow,target:g.budget.target,
        firstLoadMs:Math.round(performance.getEntriesByName('flagship-ready')[0]?.startTime??performance.now()-openedAt),
        cpuFrameMs:g.engine.frameMs,gpuFrameMs:profiler.gpuFrameTimeCounter.current/1e6||null,
        triangles:g.engine.scene.getActiveIndices()/3,
        drawCalls:counters.drawCallsCounter.current,videoMemory:g.world.assets.estimatedTextureBytes(),stream:g.world.terrainStats()
      };
    }
  };
}
