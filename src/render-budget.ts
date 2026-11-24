import type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine';
import type { Quality } from './profile';

const display={
  high:{detail:1.15,ratio:1.75,pixels:3650000,target:60},
  medium:{detail:.95,ratio:1.30,pixels:2730000,target:60},
  low:{detail:.69,ratio:1.05,pixels:1670000,target:30}
} as const;

export class RenderBudget {
  private active:Quality='auto';
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
  target=60;
  constructor(readonly device:AbstractEngine,readonly touch:boolean){}
  apply(mode:Quality,dt:number,manualScale:number){
    if(mode!==this.active){this.active=mode;this.stage=this.sinceChange=this.index=this.samples=this.time=0;}
    const preset=display[mode==='auto'?(this.touch?'medium':'high'):mode];
    this.target=preset.target;
    if(dt>.002&&dt<2){
      this.timings[this.index++%this.timings.length]=dt;this.samples=Math.min(this.samples+1,this.timings.length);
      this.time+=dt;this.sinceChange+=dt;
      if(this.time>=1.1){
        this.time=0;
        const values=this.timings.slice(0,this.samples).sort();
        this.fps=values.length/(values.reduce((a,b)=>a+b,0)||1);
        const worst=Math.max(1,Math.ceil(values.length*.01));
        this.onePercentLow=worst/(values.subarray(values.length-worst).reduce((a,b)=>a+b,0)||1);
        if(mode==='auto'&&this.sinceChange>4.5&&this.samples>24&&this.fps<49&&this.stage<4){
          this.stage++;this.sinceChange=0;
        }else if(mode==='auto'&&this.sinceChange>9&&this.fps>58&&this.onePercentLow>45&&this.stage>0){
          this.stage--;this.sinceChange=0;
        }
      }
    }
    // Reduce secondary world complexity twice before touching raster resolution.
    const detail=Math.max(.59,preset.detail-Math.min(3,this.stage)*.14);
    const cap=preset.ratio*(this.stage>=4?.82:1);
    const ratio=Math.max(.61,Math.min(devicePixelRatio,cap,Math.sqrt(preset.pixels/Math.max(1,innerWidth*innerHeight)))*manualScale);
    const width=Math.round(innerWidth*ratio),height=Math.round(innerHeight*ratio);
    if(width!==this.width||height!==this.height){
      this.width=width;this.height=height;this.device.setSize(width,height,true);
    }
    return detail;
  }
}
