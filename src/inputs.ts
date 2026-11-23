import { clamp } from './terrain';
import { idle, type Controls } from './flight';
import { TouchFlightController } from './touch-flight';

export class FlightInput {
  private readonly keys=new Set<string>();
  private readonly held=new Map<number,string>();
  readonly touch:TouchFlightController;
  private readonly slider=document.querySelector<HTMLInputElement>('#power')!;
  private throttle=.74;
  private gun=false;
  private missile=false;
  private bomb=false;
  readonly values:Controls={...idle};
  selected:'gun'|'missile'|'bomb'='gun';
  on=false;
  constructor(canvas:HTMLCanvasElement,readonly action:(name:string)=>void){
    this.touch=new TouchFlightController(canvas,()=>this.on);
    for(const [id,kind] of [['gun','gun'],['missile','missile'],['bomb','bomb'],['boost','boost']]){
      const b=document.getElementById(id)!;
      b.addEventListener('pointerdown',e=>{
        if(!this.on)return;
        e.preventDefault();b.setPointerCapture(e.pointerId);this.held.set(e.pointerId,kind);
        b.classList.add('pressed');
        if(kind==='gun')this.gun=true;
        if(kind==='missile')this.missile=true;
        if(kind==='bomb')this.bomb=true;
      });
      for(const n of ['pointerup','pointercancel','lostpointercapture'])b.addEventListener(n,e=>{
        this.held.delete((e as PointerEvent).pointerId);b.classList.remove('pressed');
      });
      b.addEventListener('click',e=>{
        if(!this.on||(e as PointerEvent).detail)return;
        if(kind==='gun')this.gun=true;
        if(kind==='missile')this.missile=true;if(kind==='bomb')this.bomb=true;
      });
    }
    this.slider.addEventListener('input',()=>{this.throttle=Number(this.slider.value)/100;});
    addEventListener('keydown',e=>{
      if(e.code==='Escape'){if(!e.repeat)this.action('pause');return;}
      if(!this.on||(e.target as HTMLElement)?.closest('select,input'))return;
      if(['Space','Enter','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.code))e.preventDefault();
      this.keys.add(e.code);
      if(e.repeat)return;
      if(e.code==='Space'||e.code==='Enter'&&this.selected==='gun')this.gun=true;
      if(e.code==='KeyF'||e.code==='Enter'&&this.selected==='missile')this.missile=true;
      if(e.code==='KeyB'||e.code==='Enter'&&this.selected==='bomb')this.bomb=true;
      const commands:Record<string,string>={KeyC:'view',KeyG:'gear',KeyT:'lock',KeyX:'weapon',KeyZ:'counter',KeyH:'assist'};
      if(commands[e.code])this.action(commands[e.code]);
    });
    addEventListener('keyup',e=>this.keys.delete(e.code));addEventListener('blur',()=>this.reset(false));
  }
  reset(defaultThrottle:number|false=.74){
    this.touch.clear();this.keys.clear();this.held.clear();this.gun=this.missile=this.bomb=false;
    if(defaultThrottle!==false){this.throttle=defaultThrottle;this.slider.value=String(defaultThrottle*100);}
    for(const node of document.querySelectorAll('.pressed'))node.classList.remove('pressed');
  }
  read(dt:number,assist:boolean,invert:boolean,sensitivity:number){
    const axes=(a:string,b:string)=>Number(this.keys.has(a))-Number(this.keys.has(b));
    const touch=this.touch.read(dt,sensitivity);
    const r=this.values;
    r.pitch=clamp(axes('KeyS','KeyW')+axes('ArrowDown','ArrowUp')+touch.pitch,-1,1)*(invert?-1:1);
    r.roll=clamp(axes('KeyA','KeyD')+axes('ArrowLeft','ArrowRight'),-1,1);
    r.steering=clamp(touch.heading,-1,1);
    r.yaw=clamp(axes('KeyQ','KeyE')+r.steering*.89,-1,1);
    const delta=axes('KeyR','KeyV');
    if(delta){this.throttle=clamp(this.throttle+delta*dt*.57,.12,1);this.slider.value=String(Math.round(this.throttle*100));}
    r.throttle=this.throttle;r.assist=assist;
    r.boost=this.keys.has('ShiftLeft')||this.keys.has('ShiftRight');
    r.gun=this.gun||this.keys.has('Space')||this.selected==='gun'&&this.keys.has('Enter');
    for(const action of this.held.values()){
      if(action==='boost')r.boost=true;
      if(action==='gun')r.gun=true;
    }
    r.missile=this.missile;r.bomb=this.bomb;
    this.gun=this.missile=this.bomb=false;
    return r;
  }
}
