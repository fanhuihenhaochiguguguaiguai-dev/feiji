import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { PlaneSpec } from './data';
import { clamp, Terrain } from './terrain';
import { envelopePitch,flightAssist } from './flight-assist';
import { aeroForces } from './aerodynamics';

export interface Controls {pitch:number; roll:number; yaw:number; throttle:number; boost:boolean; gun:boolean; missile:boolean; bomb:boolean; assist:boolean; steering?:number}
export const idle:Controls={pitch:0,roll:0,yaw:0,throttle:.74,boost:false,gun:false,missile:false,bomb:false,assist:true};
export const FLIGHT_STEP=1/90;
export const BASE_DURABILITY=2000;
export const ahead=new Vector3(0,0,-1);
export const above=new Vector3(0,1,0);
export const right=new Vector3(1,0,0);
const localRight=new Vector3(),localUp=new Vector3(),acc=new Vector3(),axis=new Vector3(),turn=Quaternion.Identity();
const aerodynamic={lift:0,drag:0,density:1,flow:1,stalled:0};

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
  roundsLimit?:number; missilesLimit?:number; bombsLimit?:number;
  cannon=0; missiles=0; bombs=0; boost=0; throttle=.74; speed=0; stall=0;
  alpha=0; sideslip=0; normalG=1;
  gear=0; gearTarget=0; grounded=false;
  gunsAt=0; missileAt=0; bombAt=0; alive=true; down=0;
  atStage=0; role=0; phase=0; evadeUntil=0; cooldown=0; hitTime=-100;
  generation=0; enginePower=1; storesBonus=0;
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
    this.speed=speed;this.cannon=this.roundsLimit??this.type.ammo;
    this.alpha=this.sideslip=0;this.normalG=1;
    this.missiles=this.missilesLimit??(this.type.missiles+(this.type.missiles?this.storesBonus:0));
    this.bombs=this.bombsLimit??(this.type.bombs+(this.type.bombs?this.storesBonus:0));
    this.damage.left=this.damage.right=this.damage.engine=this.damage.body=0;
    this.hp=this.maxHp;this.alive=true;this.down=this.stall=this.boost=this.hitIntensity=0;this.hitTime=-100;
    this.gear=this.gearTarget=this.type.gearFixed?1:0;this.grounded=false;
    this.throttle=.74;this.gunsAt=this.missileAt=this.bombAt=0;
    this.phase=0;this.atStage=this.cooldown=this.evadeUntil=0;this.lockAt=null;
    Object.assign(this.controls,idle);
  }
  heading(){return (Math.atan2(this.forward.x,-this.forward.z)*180/Math.PI+360)%360;}
  get specificEnergy(){return this.speed*this.speed*.5+9.81*this.position.y;}
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
  const assist=flightAssist(input,localUp.y,localRight.y,bank,incline,p.velocity.y,t.trim,r>t.stall*1.13);
  const inertia=clamp(.82+(t.length*t.span)/1150,.86,1.64);
  const rate=1-Math.exp(-dt*(t.support?5.9:8.65)/inertia);
  const turning=1+Math.abs(input.steering??0)*(t.support?.48:.92);
  const disruption=p.hitIntensity*Math.max(0,1-(time-p.hitTime)*3.5);
  const rollShock=disruption*Vector3.Dot(p.hitFrom,localRight)*.35;
  const climbing=p.side===0&&input.pitch>0;
  const pull=climbing?.68+.65*Math.sqrt(input.pitch):1;
  let pitchRate=input.pitch*t.pitch*responsiveness*t.grip*p.handling*pull;
  if(climbing&&input.assist&&localUp.y>0){
    const speedReserve=r/t.stall;
    pitchRate=envelopePitch(pitchRate,incline,p.alpha,p.normalG,(speedReserve*speedReserve-1)*.5);
  }
  p.angular.x+=(pitchRate+assist.pitch-p.angular.x)*(climbing?1-Math.pow(1-rate,1.19):rate);
  p.angular.y+=(input.yaw*t.yaw*responsiveness*turning*t.grip*p.handling+assist.yaw-p.angular.y)*rate;
  p.angular.z+=(input.roll*t.roll*responsiveness*t.grip*p.handling+assist.roll+rollShock+(p.damage.right-p.damage.left)*.46-p.angular.z)*rate;
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
  p.throttle+=(input.throttle-p.throttle)*(1-Math.exp(-dt*3.1));
  p.boost+=((input.boost&&t.boost?1:0)-p.boost)*(1-Math.exp(-dt*5.1));
  p.gear+=(p.gearTarget-p.gear)*(1-Math.exp(-dt*2.65));
  const axial=Vector3.Dot(p.velocity,p.forward),cross=Vector3.Dot(p.velocity,localRight),vertical=Vector3.Dot(p.velocity,localUp);
  const aoa=Math.atan2(-vertical,Math.max(t.stall*.5,axial));
  const sideslip=Math.atan2(cross,Math.hypot(axial,vertical)+.01);
  const aero=aeroForces(t,p.position.y,r,aoa,sideslip,aerodynamic);
  const {density,flow}=aero;
  const normal=aero.lift-vertical*flow*(2.34-.69*aero.stalled);
  p.alpha=aoa;p.sideslip=sideslip;p.normalG=normal/9.81;p.stall=p.grounded?0:aero.stalled;
  const nominal=12+t.trim*.128;
  const thrust=(3+nominal*p.throttle+t.boost*p.boost)*density*p.enginePower*(1-p.damage.engine*.35)*t.acceleration*(.70+.30*damage);
  const drag=(3+nominal+t.boost)*density*(r/t.maxSpeed)**2+r*p.gear*.010+aero.drag+(Math.abs(p.angular.x)+Math.abs(p.angular.y))*2.02;
  acc.copyFrom(p.forward).scaleInPlace(thrust);
  acc.addInPlaceFromFloats(-p.velocity.x*drag/Math.max(r,1),-9.81-p.velocity.y*drag/Math.max(r,1),-p.velocity.z*drag/Math.max(r,1));
  acc.addInPlaceFromFloats(localUp.x*normal,localUp.y*normal,localUp.z*normal);
  const side=-cross*(.72+2.06*flow)*(1-.28*aero.stalled);
  acc.addInPlaceFromFloats(side*localRight.x,side*localRight.y,side*localRight.z);
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
