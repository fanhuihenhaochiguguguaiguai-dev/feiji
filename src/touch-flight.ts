import { clamp } from './terrain';

export class TouchFlightController {
  private pointer:number|null=null;
  private previousX=0;
  private previousY=0;
  private pendingX=0;
  private pendingY=0;
  private distance=0;
  private turn=0;
  private pitch=0;
  readonly axis={heading:0,pitch:0};
  constructor(readonly surface:HTMLCanvasElement,readonly flying:()=>boolean){
    surface.addEventListener('pointerdown',e=>{
      if(!flying()||this.pointer!==null||e.pointerType==='mouse')return;
      e.preventDefault();
      this.pointer=e.pointerId;this.previousX=e.clientX;this.previousY=e.clientY;this.distance=0;
      surface.setPointerCapture(e.pointerId);
    });
    surface.addEventListener('pointermove',e=>{
      if(e.pointerId!==this.pointer)return;
      const samples=e.getCoalescedEvents?.();
      if(samples?.length)for(const sample of samples)this.sample(sample);
      else this.sample(e);
    });
    const release=(e:PointerEvent)=>{if(this.pointer===e.pointerId)this.pointer=null;};
    surface.addEventListener('pointerup',release);
    surface.addEventListener('pointercancel',release);
    surface.addEventListener('lostpointercapture',release);
  }
  private sample(e:PointerEvent){
    const dx=e.clientX-this.previousX,dy=e.clientY-this.previousY;
    this.previousX=e.clientX;this.previousY=e.clientY;
    this.distance+=Math.hypot(dx,dy);
    if(this.distance<2.4)return;
    this.pendingX+=dx;this.pendingY+=dy;
  }
  clear(){
    const id=this.pointer;this.pointer=null;
    if(id!==null&&this.surface.hasPointerCapture(id))this.surface.releasePointerCapture(id);
    this.pendingX=this.pendingY=this.turn=this.pitch=this.distance=this.axis.heading=this.axis.pitch=0;
  }
  read(dt:number,sensitivity:number){
    const scale=Math.max(138,Math.min(this.surface.clientWidth,this.surface.clientHeight));
    const drag=Math.exp(-dt*(this.pointer===null?7.35:4.38));
    this.turn=clamp(this.turn*drag-this.pendingX*5.16*sensitivity/scale,-1.42,1.42);
    const pitchDecay=Math.exp(-dt*(this.pointer===null?5.25:3.90));
    this.pitch=clamp(this.pitch*pitchDecay-this.pendingY*4.82*sensitivity/scale,-2.15,2.15);
    this.pendingX=this.pendingY=0;
    const response=1-Math.exp(-dt*31);
    const curve=(v:number)=>{const x=clamp(v,-1,1);return Math.abs(x)<.022?0:x*(1.20-.20*Math.abs(x));};
    this.axis.heading+=(curve(this.turn)-this.axis.heading)*response;
    const pitchCommand=Math.abs(this.pitch)<.018?0:Math.tanh(this.pitch*1.26);
    this.axis.pitch+=(pitchCommand-this.axis.pitch)*response;
    return this.axis;
  }
}
