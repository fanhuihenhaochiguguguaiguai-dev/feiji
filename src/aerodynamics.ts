import type { PlaneSpec } from './data';
import { clamp } from './terrain';

// Dimensionless, trim-normalized test curves. Angle samples span -0.8 to +1.2 rad.
// Beyond peak lift, lift falls while profile drag continues to grow.
const wingLift=[-.25,-.25,-.21,-.12,.05,.30,.56,.81,1.04,1.23,1.37,1.46,1.48,1.41,1.27,1.06,.84,.65,.50,.39,.31];
const profileDrag=[11.5,9.4,6.7,4.5,3.1,1.82,.78,.19,0,.20,.8,1.7,3.1,5.1,7.7,10.8,14.5,18.4,22.6,27,31];
const waveDrag=[0,0,0,0,.022,.15,.092,.058,.044,.038,.036,.041,.049];

function curve(table:readonly number[],index:number){
  const sample=clamp(index,0,table.length-1),left=Math.floor(sample);
  const a=table[left],b=table[Math.min(left+1,table.length-1)];
  return a+(b-a)*(sample-left);
}

export interface AeroForces { lift:number; drag:number; density:number; flow:number; stalled:number }

export function aeroForces(type:PlaneSpec,altitude:number,speed:number,alpha:number,beta:number,out:AeroForces){
  const slow=speed/type.stall,trim=speed/type.trim;
  const density=clamp(Math.exp(-Math.max(-550,altitude)/10700),.56,1.09);
  const mach=speed/clamp(340.3-altitude*.0031,299,345);
  const effectiveAlpha=alpha*(type.props.length?1.14:type.era==='stealth'?.88:1);
  const sample=effectiveAlpha*10+8,flow=clamp((slow-.47)*1.79,.014,1);
  const gLimit=type.support?3.0:type.props.length?4.48:5.92;
  out.lift=clamp(curve(wingLift,sample)*trim*trim*flow*density*(1-.14*Math.abs(beta)),-1.34,gLimit)*9.81;
  out.drag=(curve(profileDrag,sample)+Math.abs(beta)*speed*.014+curve(waveDrag,mach*5)*12.5)*clamp(trim,.23,1.75);
  const speedStall=clamp((1-slow)/.45,0,1);
  const separated=clamp((Math.abs(effectiveAlpha)-.39)/.43,0,1);
  out.stalled=1-(1-speedStall)*(1-separated);
  out.density=density;out.flow=flow;
  return out;
}
