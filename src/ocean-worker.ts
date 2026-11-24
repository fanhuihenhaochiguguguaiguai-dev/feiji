import { OceanSpectrum, ShallowWake, oceanSize, type WaterMotion } from './ocean-solver';
const sea=new OceanSpectrum(),wake=new ShallowWake();
let last=-1;
self.onmessage=({data}:MessageEvent<{cycle:number;water?:WaterMotion;bed?:Int16Array}>)=>{
  if(data.cycle!==last){last=data.cycle;wake.setBed(data.bed??null);}
  if(!data.water)return;
  const swell=new Uint8Array(oceanSize**2*4),pressure=new Uint8Array(oceanSize**2*4);
  sea.sample(data.water.time,swell);wake.step(data.water,pressure);
  self.postMessage({cycle:last,time:data.water.time,swell,pressure,x:wake.x,z:wake.z},{transfer:[swell.buffer,pressure.buffer]});
};
