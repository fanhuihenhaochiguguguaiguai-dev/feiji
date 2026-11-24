import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import type { FrameRate,Quality } from './profile';

const display={
  high:{detail:1.15,ratio:1.75,pixels:3650000},
  medium:{detail:1.0,ratio:1.38,pixels:2730000},
  low:{detail:.69,ratio:1.05,pixels:1670000}
} as const;

export class RenderBudget {
  private active:FrameRate=60;
  private readonly timings=new Float32Array(240);
  private index=0;
  private samples=0;
  private time=0;
  private sinceChange=0;
  private stage=0;
  private width=0;
  private height=0;
  fps=0;
  onePercentLow=0;
  target:FrameRate=60;
  display90=false;
  constructor(readonly device:AbstractEngine,readonly touch:boolean){
    let last=0,measured=0,fast=0;
    const measure=(at:number)=>{
      if(last&&at-last>2){measured++;if(at-last<=13.05)fast++;}
      last=at;
      if(measured<20){requestAnimationFrame(measure);return;}
      this.display90=fast>=7;
    };
    requestAnimationFrame(measure);
  }
  apply(requested:FrameRate,dt:number,manualScale:number,safe:boolean,override:Quality|null=null){
    const mode=override??'auto';
    if(requested!==this.active){this.active=requested;this.stage=this.sinceChange=this.index=this.samples=this.time=0;}
    const preset=display[safe?'low':mode==='auto'?(this.touch?'medium':'high'):mode];
    this.target=!safe&&requested===90&&this.display90&&this.stage<4?90:60;
    if(this.device.maxFPS!==this.target)this.device.maxFPS=this.target;
    if(dt>.002&&dt<2){
      this.timings[this.index++%this.timings.length]=dt;this.samples=Math.min(this.samples+1,this.timings.length);
      this.time+=dt;this.sinceChange+=dt;
      if(this.time>=1.1){
        this.time=0;
        const values=this.timings.slice(0,this.samples).sort();
        this.fps=values.length/(values.reduce((a,b)=>a+b,0)||1);
        const worst=Math.max(1,Math.ceil(values.length*.01));
        this.onePercentLow=worst/(values.subarray(values.length-worst).reduce((a,b)=>a+b,0)||1);
        if(!safe&&mode==='auto'&&this.sinceChange>4.5&&this.samples>24&&this.fps<this.target*.83&&this.stage<5){
          this.stage++;this.sinceChange=0;
        }else if(!safe&&mode==='auto'&&this.sinceChange>(this.stage===4?18:9)&&this.fps>this.target*.96&&this.onePercentLow>this.target*.75&&this.stage>0){
          this.stage--;this.sinceChange=0;
        }
      }
    }
    // Reduce secondary world complexity twice before touching raster resolution.
    const detail=Math.max(.59,preset.detail-Math.min(3,this.stage)*.14);
    const cap=preset.ratio*(this.stage>=4?.90:this.stage===3?.96:1);
    const ratio=Math.max(.61,Math.min(devicePixelRatio,cap,Math.sqrt(preset.pixels/Math.max(1,innerWidth*innerHeight)))*manualScale);
    const width=Math.round(innerWidth*ratio),height=Math.round(innerHeight*ratio);
    if(width!==this.width||height!==this.height){
      this.width=width;this.height=height;this.device.setSize(width,height,true);
    }
    return detail;
  }
}
