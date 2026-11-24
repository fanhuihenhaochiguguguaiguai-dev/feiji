import { clamp } from './terrain';

// Heights describe the longest visible aircraft edge on a 360-pixel reference screen.
const ranges=[100,200,300,500,750,1000,1500,2000,3000,4000,5000,6000];
const pixels=[80,60,52,44,38,32,28,24,20,16,14,12];

export function targetPixels(range:number,screenHeight:number){
  for(let i=1;i<ranges.length;i++){
    if(range>ranges[i])continue;
    const blend=clamp((range-ranges[i-1])/(ranges[i]-ranges[i-1]),0,1);
    return (pixels[i-1]+(pixels[i]-pixels[i-1])*blend)*screenHeight/360;
  }
  return pixels.at(-1)!*screenHeight/360*Math.max(.35,6000/range);
}
