import { clamp } from './terrain';

// Trim-normalized samples at ten-degree angle-of-attack intervals.
const lift=[-.62,-.91,-1.06,-.83,-.22,.47,1.05,1.33,1.49,1.28,.98,.73,.55];
const drag=[22,15,10,5.1,2.7,.6,0,.73,2.8,7.2,12.1,19,27];
const compression=[0,0,0,.08,.32,1,.66,.47,.37,.32,.35];
const stride=Math.PI/18;

function interpolate(samples:readonly number[],coordinate:number){
  const t=clamp(coordinate,0,samples.length-1),i=Math.min(samples.length-2,t|0);
  return samples[i]+(samples[i+1]-samples[i])*(t-i);
}

export function sectionLift(alpha:number,wingFactor:number){
  return interpolate(lift,alpha*wingFactor/stride+6);
}

export function sectionDrag(alpha:number,beta:number,mach:number){
  return interpolate(drag,alpha/stride+6)+Math.abs(beta)*3.4+interpolate(compression,mach*5)*2.5;
}
