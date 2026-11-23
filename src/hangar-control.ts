import { clamp } from './terrain';

export class HangarOrbit {
  angle=0;
  elevation=.10;
  distance=1;
  private readonly pointers=new Map<number,{x:number;y:number}>();
  private velocity=0;
  private stamp=0;
  constructor(surface:HTMLCanvasElement,available:()=>boolean){
    surface.addEventListener('pointerdown',e=>{
      if(!available()||this.pointers.size>=2||e.button!==0)return;
      surface.setPointerCapture(e.pointerId);
      this.pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
      this.stamp=e.timeStamp;this.velocity=0;
    });
    surface.addEventListener('pointermove',e=>{
      const from=this.pointers.get(e.pointerId);
      if(!from)return;
      const x=e.clientX,y=e.clientY;
      if(this.pointers.size===2){
        const second=[...this.pointers.entries()].find(([id])=>id!==e.pointerId)![1];
        const prior=Math.hypot(from.x-second.x,from.y-second.y),next=Math.hypot(x-second.x,y-second.y);
        if(prior>8&&next>8)this.distance=clamp(this.distance*prior/next,.72,1.68);
      }else{
        const angle=(x-from.x)*.0063;
        this.angle+=angle;
        this.elevation=clamp(this.elevation+(y-from.y)*.0025,-.15,.48);
        this.velocity=clamp(angle/Math.max(.010,(e.timeStamp-this.stamp)/1000),-2.6,2.6);
      }
      from.x=x;from.y=y;this.stamp=e.timeStamp;
    });
    const release=(e:PointerEvent)=>{
      if(this.pointers.delete(e.pointerId)&&e.timeStamp-this.stamp>85)this.velocity=0;
    };
    surface.addEventListener('pointerup',release);
    surface.addEventListener('lostpointercapture',release);
    surface.addEventListener('pointercancel',release);
    surface.addEventListener('wheel',e=>{
      if(!available())return;
      e.preventDefault();
      this.distance=clamp(this.distance*Math.exp(clamp(e.deltaY,-100,100)*.0018),.72,1.68);
    },{passive:false});
  }
  update(dt:number){
    if(this.pointers.size)return;
    this.angle+=this.velocity*dt;
    this.velocity*=Math.exp(-dt*12.0);
  }
}
