import type { GraphicsDevice } from 'playcanvas';
import type { Quality } from './profile';

const display={
  high:{detail:1.15,ratio:1.75,pixels:3650000},
  medium:{detail:.95,ratio:1.30,pixels:2730000},
  low:{detail:.69,ratio:1.05,pixels:1670000}
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
  target:60|90=60;
  private next=0;
  private lastDraw=0;
  private hostInterval=1000/60;
  frame(now:number,hostSpan:number,target:60|90){
    this.hostInterval+=(Math.min(30,hostSpan*1000)-this.hostInterval)*.15;
    if(target!==this.target||now-this.lastDraw>240){this.next=0;this.lastDraw=0;}
    this.target=target;
    const interval=1000/target;
    // When requestAnimationFrame is slower than the cap, use every available refresh.
    if(this.hostInterval<interval-1&&now+this.hostInterval*.30<this.next)return 0;
    const elapsed=this.lastDraw?(now-this.lastDraw)/1000:hostSpan;
    this.next=Math.max(now-interval*.70,this.next)+interval;
    this.lastDraw=now;
    return elapsed;
  }
  constructor(readonly device:GraphicsDevice,readonly touch:boolean){}
  apply(mode:Quality,dt:number,manualScale:number){
    if(mode!==this.active){this.active=mode;this.stage=this.sinceChange=this.index=this.samples=this.time=0;}
    const preset=display[mode==='auto'?(this.touch?'medium':'high'):mode];
    if(dt>.002&&dt<2){
      this.timings[this.index++%this.timings.length]=dt;this.samples=Math.min(this.samples+1,this.timings.length);
      this.time+=dt;this.sinceChange+=dt;
      if(this.time>=1.1){
        this.time=0;
        const values=this.timings.slice(0,this.samples).sort();
        this.fps=values.length/(values.reduce((a,b)=>a+b,0)||1);
        const worst=Math.max(1,Math.ceil(values.length*.01));
        this.onePercentLow=worst/(values.subarray(values.length-worst).reduce((a,b)=>a+b,0)||1);
        if(mode==='auto'&&this.sinceChange>4.5&&this.samples>24&&this.fps<Math.min(this.target,1000/this.hostInterval)*.82&&this.stage<4){
          this.stage++;this.sinceChange=0;
        }else if(mode==='auto'&&this.sinceChange>9&&this.fps>Math.min(this.target,1000/this.hostInterval)*.95&&this.onePercentLow>45&&this.stage>0){
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
      this.width=width;this.height=height;this.device.setResolution(width,height);
    }
    return detail;
  }
}
