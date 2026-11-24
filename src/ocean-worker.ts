import { OceanSpectrum, ShallowWake, oceanSize, type WaterMotion } from './ocean-solver';
import { GpuOceanSpectrum } from './ocean-gpu';

const sea=new OceanSpectrum(),wake=new ShallowWake();
let last=-1,probing=false,gpuBusy=false;
let gpu:GpuOceanSpectrum|undefined;
let fft:{path:'cpu'|'gpu';reason?:string;benchmark?:{cpuMs:number;gpuMs:number;maxError:number}}={path:'cpu',reason:'compatible'};
self.onmessage=async({data}:MessageEvent<{cycle:number;water?:WaterMotion;bed?:Int16Array;compute?:boolean}>)=>{
  const {cycle,water}=data;
  if(cycle!==last){last=cycle;wake.setBed(data.bed??null);}
  if(!water)return;
  if(data.compute&&!probing){
    probing=true;
    void GpuOceanSpectrum.qualify(new OceanSpectrum()).then(({path,benchmark,...result})=>{
      fft={path,benchmark,reason:'reason' in result?result.reason:undefined};
      if('gpu' in result)gpu=result.gpu;
    }).catch(()=>{fft={path:'cpu',reason:'unavailable'};});
  }
  const swell=new Uint8Array(oceanSize**2*4),pressure=new Uint8Array(oceanSize**2*4);
  wake.step(water,pressure);
  const {x,z}=wake;
  if(gpu&&!gpuBusy){
    gpuBusy=true;
    try{await gpu.sample(water.time,swell);}
    catch{gpu.dispose();gpu=undefined;fft={path:'cpu',reason:'device-lost'};sea.sample(water.time,swell);}
    finally{gpuBusy=false;}
  }else sea.sample(water.time,swell);
  if(cycle===last)self.postMessage({cycle,time:water.time,swell,pressure,x,z,fft},{transfer:[swell.buffer,pressure.buffer]});
};
