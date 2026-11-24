import { OceanSpectrum, ShallowWake, oceanSize, type WaterMotion } from './ocean-solver';
import { OceanCompute } from './ocean-compute';

const sea=new OceanSpectrum(),wake=new ShallowWake();
let last=-1,started=false,busy=false;
let performanceResult:Awaited<ReturnType<typeof OceanCompute.qualified>>=null;

self.onmessage=async({data}:MessageEvent<{cycle:number;water?:WaterMotion;bed?:Int16Array;compute?:boolean}>)=>{
  if(data.cycle!==last){last=data.cycle;wake.setBed(data.bed??null);}
  const water=data.water;
  if(!water)return;
  if(data.compute&&!started){
    started=true;
    void Promise.resolve(navigator.gpu?.requestAdapter()).then(adapter=>
      OceanCompute.qualified(new OceanSpectrum(),adapter??null)
    ).then(result=>{performanceResult=result;}).catch(()=>{});
  }
  const swell=new Uint8Array(oceanSize**2*4),pressure=new Uint8Array(oceanSize**2*4);
  wake.step(water,pressure);
  const {x,z}=wake,solver=performanceResult?.solver;
  let fft='cpu';
  if(solver&&!busy){
    busy=true;
    try{await solver.sample(water.time,swell);fft='gpu';}
    catch{solver.dispose();performanceResult=null;sea.sample(water.time,swell);}
    finally{busy=false;}
  }else sea.sample(water.time,swell);
  if(data.cycle===last)self.postMessage({cycle:last,time:water.time,swell,pressure,x,z,fft,
    benchmark:performanceResult?.benchmark},{transfer:[swell.buffer,pressure.buffer]});
};
