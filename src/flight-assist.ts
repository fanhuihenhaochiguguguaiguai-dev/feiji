import { clamp } from './terrain';
import type { Controls } from './flight';

const resolved={pitch:0,roll:0,yaw:0,vertical:0};

export function envelopePitch(request:number,nose:number,alpha:number,normalG:number,energyMargin:number){
  if(request<=0)return request;
  const control=1-.55*clamp((alpha-.37)/.34,0,1);
  const load=1-.32*clamp((normalG-4.9)/1.8,0,1);
  const reserve=clamp(.81+energyMargin*.18,.82,1);
  return Math.min(request*control*load*reserve,(1.31-nose)*3.7,2.08);
}
export function flightAssist(input:Controls,up:number,right:number,bank:number,nose:number,
  verticalSpeed:number,trimSpeed:number,airborne:boolean){
  const stable=input.assist&&up>.22;
  const swipe=input.steering??0;
  const authority=clamp(Math.max(Math.abs(swipe),Math.abs(input.pitch))*2.4,0,1);
  const bankTarget=swipe*1.02;
  const balancing=(stable||Math.abs(swipe)>.035)&&up>.14;
  const pitchAuthority=clamp(Math.abs(input.pitch)*6.8,0,1);
  const pitchTrim=clamp(-nose*.98-verticalSpeed/(trimSpeed*10),-.52,.52);
  resolved.pitch=stable?pitchTrim*(1-pitchAuthority):0;
  resolved.roll=balancing?clamp((bankTarget-bank)*3.26,-2.46,2.46)*(1-clamp(Math.abs(input.roll)*8,0,1)):0;
  resolved.yaw=right*(stable?.40:.16);
  resolved.vertical=stable&&airborne&&Math.abs(nose)<.34?clamp(-verticalSpeed*.36,-6,6)*(1-Math.max(pitchAuthority,authority)):0;
  return resolved;
}
