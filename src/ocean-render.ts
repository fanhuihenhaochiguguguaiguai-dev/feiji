import { ADDRESS_CLAMP_TO_EDGE,ADDRESS_REPEAT,FILTER_LINEAR,PIXELFORMAT_RGBA8,Texture,type GraphicsDevice,type ShaderMaterial } from 'playcanvas';
import { OceanSpectrum, ShallowWake, heightPerByte, oceanSize, pressureStrength, swellPeriod, wakeCell, type WaterMotion } from './ocean-solver';

interface OceanPacket {cycle:number;time:number;swell:Uint8Array;pressure:Uint8Array;x:number;z:number;fft?:{path:string;reason?:string;benchmark?:{cpuMs:number;gpuMs:number;maxError:number}};}
const empty=new Uint8Array(oceanSize**2*4);
for(let i=0;i<empty.length;i+=4){empty[i]=empty[i+2]=empty[i+3]=128;}
const repeat=(n:number)=>(n%oceanSize+oceanSize)%oceanSize;
function sample(data:Uint8Array,x:number,y:number,tiles:boolean){
  const a=Math.floor(x),b=Math.floor(y),u=x-a,v=y-b;
  if(!tiles&&(a<0||b<0||a>=oceanSize-1||b>=oceanSize-1))return 0;
  const lo=repeat(a),hi=repeat(a+1),near=repeat(b)*oceanSize,far=repeat(b+1)*oceanSize;
  const x0=data[(near+lo)*4]*(1-u)+data[(near+hi)*4]*u;
  const x1=data[(far+lo)*4]*(1-u)+data[(far+hi)*4]*u;
  return (x0*(1-v)+x1*v-128)*heightPerByte;
}
export class OceanRender {
  readonly swell:Texture;
  readonly wake:Texture;
  private readonly origin=new Float32Array(3);
  private readonly washCenter=new Float32Array(4);
  private readonly washTrack=new Float32Array(2);
  private packet:OceanPacket|null=null;
  private worker:Worker|null=null;
  private fallback: { sea:OceanSpectrum;patch:ShallowWake }|null=null;
  private bed:Int16Array|null=null;
  private pending=false;
  private cycle=0;
  private updated=-1;
  constructor(private readonly device:GraphicsDevice,material:ShaderMaterial){
    const make=(name:string,repeat:boolean)=>new Texture(device,{name,width:oceanSize,height:oceanSize,format:PIXELFORMAT_RGBA8,
      mipmaps:false,minFilter:FILTER_LINEAR,magFilter:FILTER_LINEAR,addressU:repeat?ADDRESS_REPEAT:ADDRESS_CLAMP_TO_EDGE,
      addressV:repeat?ADDRESS_REPEAT:ADDRESS_CLAMP_TO_EDGE});
    this.swell=make('逆 FFT 海浪',true);this.wake=make('浅水压力尾流',false);
    this.upload(this.swell,empty);this.upload(this.wake,empty);
    material.setParameter('spectrumTex',this.swell);material.setParameter('pressureTex',this.wake);
    material.setParameter('pressureOrigin',this.origin);
    material.setParameter('washCenter',this.washCenter);
    material.setParameter('washTrack',this.washTrack);
    if(typeof Worker==='function')try{
      const worker=this.worker=new Worker(new URL('./ocean-worker.ts',import.meta.url),{type:'module'});
      worker.onmessage=({data}:MessageEvent<OceanPacket>)=>this.accept(data);
      worker.onerror=()=>{worker.terminate();this.worker=null;this.pending=false;};
    }catch{/* CPU shares the same solver when the browser cannot start a Worker. */}
  }
  private upload(texture:Texture,bytes:Uint8Array){
    (texture.lock() as Uint8Array).set(bytes);texture.unlock();
  }
  private accept(p:OceanPacket){
    if(p.cycle!==this.cycle)return;
    this.pending=false;this.packet=p;
    this.origin.set([p.x,p.z,1]);
    this.upload(this.swell,p.swell);this.upload(this.wake,p.pressure);
  }
  reset(bed:Int16Array|null){
    this.cycle++;this.pending=false;this.updated=-1;this.packet=null;this.bed=bed;
    this.origin.fill(0);this.upload(this.swell,empty);this.upload(this.wake,empty);
    this.washCenter.fill(0);this.washTrack.fill(0);
    this.fallback?.patch.setBed(bed);
    if(this.worker&&bed){
      const copy=bed.slice();
      this.worker.postMessage({cycle:this.cycle,bed:copy},[copy.buffer]);
    }
  }
  advance(s:WaterMotion,dx:number,dz:number){
    const amount=pressureStrength(s);
    if(amount>0){
      const norm=Math.hypot(dx,dz)||1;
      this.washCenter.set([s.x,s.z,dx/norm,dz/norm]);
      this.washTrack.set([amount,s.time]);
    }
    if(this.pending||s.time-this.updated<(this.worker?.09:.16))return;
    this.updated=s.time;
    if(this.worker){
      this.pending=true;this.worker.postMessage({cycle:this.cycle,water:s,compute:this.device.isWebGPU&&this.device.supportsCompute});
    }else{
      if(!this.fallback){this.fallback={sea:new OceanSpectrum(),patch:new ShallowWake()};this.fallback.patch.setBed(this.bed);}
      const p=this.fallback,swell=new Uint8Array(empty.length),pressure=new Uint8Array(empty.length);
      p.sea.sample(s.time,swell);p.patch.step(s,pressure);
      this.accept({cycle:this.cycle,time:s.time,swell,pressure,x:p.patch.x,z:p.patch.z});
    }
  }
  height(x:number,z:number,strength:number){
    const p=this.packet;
    return p?sample(p.swell,x*oceanSize/swellPeriod,z*oceanSize/swellPeriod,true)*strength+
      sample(p.pressure,(x-p.x)/wakeCell,(z-p.z)/wakeCell,false):0;
  }
  details(){
    const p=this.packet;
    if(!p)return {active:false,foam:0,time:0,worker:!!this.worker,fft:this.packet?.fft??{path:'cpu'}};
    let foam=0;for(let i=1;i<p.pressure.length;i+=4)foam=Math.max(foam,p.pressure[i]);
    return {active:true,foam,time:p.time,worker:!!this.worker,fft:this.packet?.fft??{path:'cpu'}};
  }
}
