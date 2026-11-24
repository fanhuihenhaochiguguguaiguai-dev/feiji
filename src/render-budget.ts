import type { GraphicsDevice } from 'playcanvas';
import type { Quality } from './profile';

const preset={
  low:{height:720,detail:.72},
  medium:{height:900,detail:.91},
  high:{height:1080,detail:1.04},
  ultra:{height:1440,detail:1.19}
} as const;

export class RenderBudget {
  private next=0;
  private rendered=0;
  private refresh=1000/60;
  private elapsed=0;
  private summed=0;
  private slowest=0;
  private frames=0;
  private scale=1;
  private active:Quality='auto';
  private width=0;
  private height=0;
  fps=0;
  onePercentLow=0;
  target:60|90=60;
  sceneScale=1;
  constructor(readonly device:GraphicsDevice,readonly touch:boolean){}

  sampleFrame(now:number,interval:number,target:60|90){
    this.refresh+=(Math.min(45,interval*1000)-this.refresh)*.12;
    if(target!==this.target||now-this.rendered>350){this.next=0;this.rendered=0;}
    this.target=target;
    const cap=1000/target;
    if(this.refresh<cap-.9&&now+this.refresh*.26<this.next)return 0;
    const dt=this.rendered?(now-this.rendered)/1000:interval;
    this.next=Math.max(this.next,now-cap*.6)+cap;
    this.rendered=now;
    return dt;
  }

  apply(mode:Quality,dt:number,manualScale:number){
    const settings=preset[mode==='auto'?'high':mode];
    if(mode!==this.active){
      this.active=mode;this.elapsed=this.summed=this.slowest=this.frames=0;this.scale=1;
    }
    if(dt>.002&&dt<.8){
      this.elapsed+=dt;this.summed+=dt;this.frames++;this.slowest=Math.max(this.slowest,dt);
      if(this.elapsed>=1.1){
        this.fps=this.frames/this.summed;this.onePercentLow=1/this.slowest;
        const attainable=Math.min(this.target,1000/this.refresh);
        if(this.fps<attainable*.78)this.scale=Math.max(.50,this.scale-.07);
        else if(this.fps>attainable*.94&&this.onePercentLow>attainable*.64)this.scale=Math.min(1,this.scale+.022);
        this.elapsed=this.summed=this.slowest=this.frames=0;
      }
    }
    const ratio=Math.max(1,innerWidth)/Math.max(1,innerHeight);
    const cap=Math.min(settings.height,this.device.maxTextureSize/Math.max(1,ratio));
    const width=Math.round(cap*ratio),height=Math.round(cap);
    if(width!==this.width||height!==this.height){
      this.width=width;this.height=height;this.device.setResolution(width,height);
    }
    this.sceneScale=Math.round(Math.max(.48,this.scale*manualScale)*50)/50;
    return settings.detail*(.65+.35*this.sceneScale);
  }
}
