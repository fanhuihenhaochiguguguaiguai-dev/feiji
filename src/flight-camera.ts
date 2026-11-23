import { Quaternion,Vector3 } from '@babylonjs/core/Maths/math.vector';
export interface FlightCameraView {
  position:Vector3; rotationQuaternion:Quaternion|null; upVector:Vector3; fov:number; minZ:number;
  setTarget(target:Vector3):void;
}
import type { Airframe,FlightPose } from './flight';
import { clamp,type Terrain } from './terrain';

export class FlightCamera {
  private bank=0;
  private readonly goal=new Vector3();
  private readonly aim=new Vector3();
  private readonly eyePoint=new Vector3();
  private readonly focus=new Vector3();
  private collapsed=false;
  private lookPitch=0;
  private field=1.012;
  private readonly drift=new Vector3();
  private readonly levelForward=new Vector3(0,0,-1);
  update(camera:FlightCameraView,plane:Airframe,target:Airframe|null,terrain:Terrain,dt:number,time:number,inside:boolean,reset:boolean,pose:Pick<FlightPose,'position'|'orientation'|'forward'>=plane){
    const p=pose.position;
    if(inside){
      this.eyePoint.set(...plane.type.eye as [number,number,number]).rotateByQuaternionToRef(pose.orientation,this.eyePoint);
      camera.position.copyFrom(p).addInPlace(this.eyePoint);
      camera.rotationQuaternion??=Quaternion.Identity();camera.rotationQuaternion.copyFrom(pose.orientation);
      camera.fov=1.20+plane.boost*.068;camera.minZ=.11;return;
    }
    camera.rotationQuaternion=null;camera.minZ=.54;
    const normal=pose.forward,span=Math.max(10,plane.type.span),dist=span*1.46+9+plane.boost*4.2;
    const horizontal=Math.hypot(normal.x,normal.z);
    if(horizontal>.15)this.levelForward.set(normal.x/horizontal,0,normal.z/horizontal);
    const level=this.levelForward,trail=Math.max(.43,horizontal);
    const shock=reset?0:Math.max(0,1-(time-plane.hitTime)*5)*plane.hitIntensity;
    this.goal.set(p.x-level.x*trail*dist,p.y-normal.y*dist*.82+span*.34+6.1,p.z-level.z*trail*dist);
    this.goal.y=Math.max(this.goal.y+.20*shock,terrain.at(this.goal.x,this.goal.z,time)+7);
    this.goal.addInPlaceFromFloats(-plane.hitFrom.x*shock*.32,0,-plane.hitFrom.z*shock*.32);
    const eye=p.y+4.9;
    let blocked=terrain.obstruction(p.x,eye,p.z,this.goal.x,this.goal.y,this.goal.z,time,2.0);
    if(blocked<=1){
      this.goal.y+=(1.08-blocked)*24;
      blocked=terrain.obstruction(p.x,eye,p.z,this.goal.x,this.goal.y,this.goal.z,time,2.0);
    }
    this.collapsed=blocked<=1;
    if(this.collapsed){
      const factor=Math.max(.41,blocked-.13);
      this.goal.set(p.x+(this.goal.x-p.x)*factor,eye+(this.goal.y-eye)*factor+7,p.z+(this.goal.z-p.z)*factor);
      this.goal.y=Math.max(this.goal.y,terrain.at(this.goal.x,this.goal.z,time)+7);
    }
    Vector3.LerpToRef(camera.position,this.goal,reset||this.collapsed?1:1-Math.exp(-dt*13),camera.position);
    if(terrain.obstruction(p.x,eye,p.z,camera.position.x,camera.position.y,camera.position.z,time,1.8)<=1){
      camera.position.copyFrom(this.goal);camera.position.y+=5.0;
    }
    camera.position.y=Math.max(camera.position.y,terrain.at(camera.position.x,camera.position.z,time)+7);
    const wide=1.012+plane.boost*.099+Math.min(.045,Math.abs(plane.angular.y)*.036);
    this.field=reset?wide:this.field+(wide-this.field)*(1-Math.exp(-dt*6));
    camera.fov=this.field;
    this.aim.copyFrom(p).addInPlaceFromFloats(level.x*125,0,level.z*125);
    const subjectPitch=Math.atan2(p.y-camera.position.y,Math.hypot(p.x-camera.position.x,p.z-camera.position.z));
    const nosePitch=Math.asin(clamp(normal.y,-1,1));
    const desired=subjectPitch+Math.atan(.51*Math.tan(camera.fov*.5));
    const pitch=clamp(clamp(desired,nosePitch-.43,nosePitch+.34),-1.32,1.32);
    this.lookPitch=reset?pitch:this.lookPitch+(pitch-this.lookPitch)*(1-Math.exp(-dt*9.5));
    const aimDistance=Math.hypot(this.aim.x-camera.position.x,this.aim.z-camera.position.z);
    this.aim.y=camera.position.y+Math.tan(this.lookPitch)*aimDistance;
    if(target?.alive)target.position.subtractToRef(p,this.focus);
    else this.focus.setAll(0);
    const distance=this.focus.length();
    const weight=distance>2?clamp((Vector3.Dot(this.focus,normal)/distance-.57)*3.8,0,1)/distance:0;
    this.focus.set(this.focus.x*weight*9.5,this.focus.y*weight*4.1,this.focus.z*weight*9.5);
    Vector3.LerpToRef(this.drift,this.focus,reset?1:1-Math.exp(-dt*4.8),this.drift);
    this.aim.addInPlace(this.drift);
    const bankTarget=clamp(plane.angular.z*.23,-.26,.26);
    this.bank=reset?0:this.bank+(bankTarget-this.bank)*(1-Math.exp(-dt*7));
    camera.upVector.set(Math.sin(this.bank)*(-level.z),1,Math.sin(this.bank)*level.x);
    camera.setTarget(this.aim);
  }
}
