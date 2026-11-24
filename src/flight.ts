import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { PlaneSpec } from './data';
import { clamp, Terrain } from './terrain';
import { flightAssist } from './flight-assist';
import { sectionDrag,sectionLift } from './aero-tables';

export interface Controls {pitch:number; roll:number; yaw:number; throttle:number; boost:boolean; gun:boolean; missile:boolean; bomb:boolean; assist:boolean; steering?:number; manual?:boolean}
export const idle:Controls={pitch:0,roll:0,yaw:0,throttle:.74,boost:false,gun:false,missile:false,bomb:false,assist:true,steering:0,manual:false};
export const FLIGHT_STEP=1/90;
export const BASE_DURABILITY=2000;
export const ahead=new Vector3(0,0,-1);
export const above=new Vector3(0,1,0);
export const right=new Vector3(1,0,0);
const localRight=new Vector3(),localUp=new Vector3(),acc=new Vector3(),axis=new Vector3(),turn=Quaternion.Identity();

export class Airframe {
  readonly position=new Vector3();
  readonly previous=new Vector3();
  readonly velocity=new Vector3();
  readonly forward=new Vector3(0,0,-1);
  readonly orientation=Quaternion.Identity();
  readonly previousOrientation=Quaternion.Identity();
  readonly angular=new Vector3();
  readonly controls:Controls={...idle};
  hp:number; maxHp:number;
  readonly hitFrom=new Vector3();
  readonly damage={left:0,right:0,engine:0,body:0};
  hitIntensity=0;
  handling=1;
  experience=0;
  ace=false;
  lockAt:number|null=null;
  firepower=1;
  bombsLimit?:number;
  cannon=0; missiles=0; bombs=0; boost=0; throttle=.74; speed=0; stall=0;
  alpha=0; beta=0; loadG=1;
  gear=0; gearTarget=0; grounded=false;
  gunsAt=0; missileAt=0; bombAt=0; alive=true; down=0;
  evadeSide=1; evadeReadyAt=0;
  atStage=0; role=0; phase=0; evadeUntil=0; cooldown=0; hitTime=-100;
  generation=0; enginePower=1;
  constructor(readonly id:number, public type:PlaneSpec, readonly side:0|1|2){
    this.hp=this.maxHp=side===0?Math.max(BASE_DURABILITY,type.durability):106;
  }
  reset(x:number,y:number,z:number,heading:number,speed=this.type.trim){
    this.generation++;
    this.position.set(x,y,z);this.previous.copyFrom(this.position);this.angular.setAll(0);
    Quaternion.RotationAxisToRef(above,-heading,this.orientation);
    this.previousOrientation.copyFrom(this.orientation);
    ahead.rotateByQuaternionToRef(this.orientation,this.forward);
    this.velocity.copyFrom(this.forward).scaleInPlace(speed);
    this.speed=speed;this.cannon=this.side===0?0:this.type.ammo;
    this.missiles=this.side===0?0:this.type.missiles;
    this.bombs=this.bombsLimit??this.type.bombs;
    this.damage.left=this.damage.right=this.damage.engine=this.damage.body=0;
    this.hp=this.maxHp;this.alive=true;this.down=this.stall=this.boost=this.hitIntensity=0;this.hitTime=-100;
    this.gear=this.gearTarget=this.type.gearFixed?1:0;this.grounded=false;
    this.throttle=.74;this.gunsAt=this.missileAt=this.bombAt=0;
    this.alpha=this.beta=0;this.loadG=1;this.evadeSide=1;this.evadeReadyAt=0;
    this.phase=0;this.atStage=this.cooldown=this.evadeUntil=0;this.lockAt=null;
    Object.assign(this.controls,idle);
  }
  heading(){return (Math.atan2(this.forward.x,-this.forward.z)*180/Math.PI+360)%360;}
  gearChange(){
    if(this.type.gearFixed||this.grounded||!this.type.gearClearance)return false;
    if(this.speed>this.type.trim*1.22&&this.gearTarget===0)return false;
    this.gearTarget=1-this.gearTarget;return true;
  }
}
export class FlightPose {
  readonly position=new Vector3();
  readonly orientation=Quaternion.Identity();
  readonly forward=new Vector3();
  sample(plane:Airframe,alpha:number){
    Vector3.LerpToRef(plane.previous,plane.position,alpha,this.position);
    Quaternion.SlerpToRef(plane.previousOrientation,plane.orientation,alpha,this.orientation);
    ahead.rotateByQuaternionToRef(this.orientation,this.forward);
    return this;
  }
}
export function advanceFlight(p:Airframe,input:Controls,dt:number,world:Terrain,time:number){
  p.previousOrientation.copyFrom(p.orientation);
  const t=p.type,r=p.speed,damage=p.hp/p.maxHp;
  ahead.rotateByQuaternionToRef(p.orientation,p.forward);
  above.rotateByQuaternionToRef(p.orientation,localUp);
  right.rotateByQuaternionToRef(p.orientation,localRight);
  const responsiveness=(.77+.23*damage)*clamp((r-t.stall*.35)/(t.stall*.9),p.grounded?.35:.19,1)*clamp(1-(r/t.maxSpeed-.63)*.66,.62,1);
  const bank=Math.atan2(localRight.y,localUp.y);
  const incline=Math.asin(clamp(p.forward.y,-1,1));
  const assist=flightAssist(input,localUp.y,localRight.y,bank,incline,p.velocity.y,t.trim,r>t.stall*1.13&&!p.grounded,p.loadG);
  const inertia=clamp(.82+(t.length*t.span)/1150,.86,1.64);
  const rate=1-Math.exp(-dt*(t.support?5.9:8.65)/inertia);
  const turning=1+Math.abs(input.steering??0)*(t.support?.48:.82);
  const disruption=p.hitIntensity*Math.max(0,1-(time-p.hitTime)*3.5);
  const rollShock=disruption*Vector3.Dot(p.hitFrom,localRight)*.35;
  const climbing=p.side===0&&input.pitch>0;
  const pull=climbing?.68+.65*Math.sqrt(input.pitch):1;
  let pitchRate=input.pitch*t.pitch*responsiveness*t.grip*p.handling*pull;
  if(climbing&&input.assist&&localUp.y>0){
    const margin=clamp((r/t.stall-1)*2,0,1),bodyAlpha=clamp((p.alpha-.31)/.42,0,1);
    const load=clamp((p.loadG-4.3)/2.4,0,1);
    const cap=(1.31-incline)*3.7;
    pitchRate=Math.min(pitchRate*(.74+margin*.26)*(1-.51*bodyAlpha)*(1-.26*load),cap,2.05);
  }
  const {x:rollX,y:yawY,z:rollZ}=p.angular;
  p.angular.x+=(pitchRate+assist.pitch-p.angular.x)*(climbing?1-Math.pow(1-rate,1.19):rate);
  p.angular.y+=(input.yaw*t.yaw*responsiveness*turning*t.grip*p.handling+assist.yaw-p.angular.y)*rate;
  p.angular.z+=(input.roll*t.roll*responsiveness*t.grip*p.handling+assist.roll+rollShock+(p.damage.right-p.damage.left)*.46-p.angular.z)*rate;
  p.angular.x+=yawY*rollZ*.12*dt;
  p.angular.y+=rollX*rollZ*.29*dt;
  p.angular.z-=rollX*yawY*.20*dt;
  if(p.grounded){p.angular.z*=.76;p.angular.y*=.82;p.angular.x=clamp(p.angular.x,-.02,.72);}
  const spin=p.angular.length();
  if(spin>.0001){
    axis.copyFrom(p.angular).scaleInPlace(1/spin);
    Quaternion.RotationAxisToRef(axis,spin*dt,turn);
    p.orientation.multiplyInPlace(turn).normalize();
  }
  ahead.rotateByQuaternionToRef(p.orientation,p.forward);
  above.rotateByQuaternionToRef(p.orientation,localUp);
  right.rotateByQuaternionToRef(p.orientation,localRight);
  const climbingOrBanking=input.pitch>.15||Math.abs(input.steering??0)>.23;
  const energyFloor=p.side===0&&input.assist&&!p.grounded&&climbingOrBanking?
    clamp((1.42-r/t.stall)*1.7,0,.92):0;
  p.throttle+=(Math.max(input.throttle,energyFloor)-p.throttle)*(1-Math.exp(-dt*3.1));
  p.boost+=((input.boost&&t.boost?1:0)-p.boost)*(1-Math.exp(-dt*5.1));
  p.gear+=(p.gearTarget-p.gear)*(1-Math.exp(-dt*2.65));
  const density=clamp(Math.exp(-p.position.y/14900),.56,1.08);
  const axial=Vector3.Dot(p.velocity,p.forward),cross=Vector3.Dot(p.velocity,localRight),vertical=Vector3.Dot(p.velocity,localUp);
  const aoa=Math.atan2(-vertical,Math.max(t.stall*.5,axial));
  p.alpha=aoa;p.beta=Math.atan2(cross,Math.hypot(axial,vertical)+.01);
  p.stall=p.grounded?0:clamp((t.stall-r)/(t.stall*.45)+Math.max(0,Math.abs(aoa)-.39)*1.7,0,1);
  const factor=clamp((r/t.stall-.49)*1.8,.015,1);
  const loadLimit=t.support?3.0:t.props.length?4.48:5.92;
  const lift=clamp(sectionLift(aoa,t.props.length?1.08:t.era==='stealth'?.94:1)*(r/t.trim)**2*factor*density,-1.17,loadLimit)*9.81;
  p.loadG=lift/9.81;
  const nominal=12+t.trim*.128;
  const thrust=(3+nominal*p.throttle+t.boost*p.boost)*density*p.enginePower*(1-p.damage.engine*.35)*t.acceleration*(.70+.30*damage);
  const induced=(sectionDrag(aoa,p.beta,r/Math.max(298,340-p.position.y*.0025))+Math.abs(cross)*.009)*clamp(r/t.trim,.25,1.7);
  const drag=(3+nominal+t.boost)*density*(r/t.maxSpeed)**2+r*p.gear*.010+induced+(Math.abs(p.angular.x)+Math.abs(p.angular.y))*2.02;
  acc.copyFrom(p.forward).scaleInPlace(thrust);
  acc.addInPlaceFromFloats(-p.velocity.x*drag/Math.max(r,1),-9.81-p.velocity.y*drag/Math.max(r,1),-p.velocity.z*drag/Math.max(r,1));
  acc.addInPlaceFromFloats(localUp.x*(lift-vertical*factor*2.25),localUp.y*(lift-vertical*factor*2.25),localUp.z*(lift-vertical*factor*2.25));
  acc.addInPlaceFromFloats(-cross*localRight.x*(1.32+factor*1.46),-cross*localRight.y*(1.32+factor*1.46),-cross*localRight.z*(1.32+factor*1.46));
  acc.y+=assist.vertical;
  p.previous.copyFrom(p.position);
  p.velocity.addInPlaceFromFloats(acc.x*dt,acc.y*dt,acc.z*dt);
  p.position.addInPlaceFromFloats(p.velocity.x*dt,p.velocity.y*dt,p.velocity.z*dt);
  if(p.grounded){
    const runway=world.runway(p.position.x,p.position.z);
    const rotate=p.forward.y>.098&&r>t.stall*1.20&&input.pitch>.21;
    if(runway&&!rotate){
      p.position.y=world.at(p.position.x,p.position.z,time)+Math.max(.8,t.gearClearance);
      p.velocity.y=0;
      const friction=Math.exp(-dt*(input.throttle<.28?.39:.041));
      p.velocity.x*=friction;p.velocity.z*=friction;
    }else{
      p.grounded=false;
      if(rotate||r>t.stall*.98){p.position.y+=1.65;p.velocity.y=Math.max(p.velocity.y,9);}
    }
  }
  p.speed=p.velocity.length();
  Object.assign(p.controls,input);
}
