import { clamp } from './terrain';
import type { Controls } from './flight';

const resolved={pitch:0,roll:0,yaw:0,vertical:0};
export function flightAssist(input:Controls,up:number,right:number,bank:number,nose:number,
  verticalSpeed:number,trimSpeed:number,airborne:boolean,load:number){
  const stable=input.assist&&up>.22;
  const swipe=input.steering??0;
  const authority=clamp(Math.max(Math.abs(swipe),Math.abs(input.pitch))*2.4,0,1);
  const bankTarget=swipe*1.02;
  const balancing=(stable||Math.abs(swipe)>.035)&&up>.14;
  const pitchAuthority=clamp(Math.abs(input.pitch)*6.8,0,1);
  const pitchTrim=clamp(-nose*.98-verticalSpeed/(trimSpeed*10),-.52,.52);
  const turnLoad=1/Math.max(.59,Math.cos(bank));
  const coordinated=airborne&&Math.abs(swipe)>.06?
    clamp((turnLoad-load)*.58,0,.43)*clamp(Math.abs(bank)*2.04,0,1)*clamp(Math.abs(swipe)*3.5,0,1):0;
  resolved.pitch=stable?(pitchTrim+coordinated)*(1-pitchAuthority):0;
  resolved.roll=balancing?clamp((bankTarget-bank)*3.26,-2.46,2.46)*(1-clamp(Math.abs(input.roll)*8,0,1)):0;
  resolved.yaw=right*(stable?.40:.16);
  resolved.vertical=stable&&airborne&&Math.abs(nose)<.34?clamp(-verticalSpeed*.36,-6,6)*(1-Math.max(pitchAuthority,authority)):0;
  return resolved;
}
