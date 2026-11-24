import { waves } from './wave-field';
import { base,structureTop } from './airfield-layout';
export { base } from './airfield-layout';

const mix=(a:number,b:number,t:number)=>a+(b-a)*t;
export const clamp=(v:number,a:number,b:number)=>Math.max(a,Math.min(b,v));
export function hash(x:number,z:number){
  const n=Math.sin(x*127.1+z*311.7)*43758.5453;
  return n-Math.floor(n);
}
export function noise(x:number,z:number){
  const a=Math.floor(x),b=Math.floor(z),u=x-a,v=z-b;
  return mix(mix(hash(a,b),hash(a+1,b),u*u*(3-2*u)),mix(hash(a,b+1),hash(a+1,b+1),u*u*(3-2*u)),v*v*(3-2*v));
}
export const gridSize=1025;
export const worldExtent=48000;
export const gridStep=worldExtent/(gridSize-1);
export const chunkCells=64;
export const chunksPerAxis=(gridSize-1)/chunkCells;
const seabed=-240;

interface TerrainSource {heights:Int16Array; max:number; blocks:{x:number;z:number}[]}
const sources=new Map<number,TerrainSource>();
const requests=new Map<number,Promise<void>>();

export function registerTerrain(seed:number,bytes:ArrayBuffer){
  const header=new DataView(bytes);
  if(bytes.byteLength!==12+gridSize*gridSize*2||header.getUint32(0)!==0x57463039||
    header.getUint16(4,true)!==gridSize||header.getUint16(6,true)!==4||header.getUint32(8,true)!==worldExtent){
    throw new Error('地貌资产格式无效');
  }
  const heights=new Int16Array(bytes,12),blocks:TerrainSource['blocks']=[];
  for(let z=0;z<gridSize-1;z+=chunkCells)for(let x=0;x<gridSize-1;x+=chunkCells){
    let visible=false;
    for(let j=z;j<=z+chunkCells&&!visible;j++)for(let i=x;i<=x+chunkCells;i++){
      if(heights[j*gridSize+i]>-42){visible=true;break;}
    }
    if(visible)blocks.push({x,z});
  }
  if(!blocks.length)throw new Error('地貌资产未包含陆地');
  let max=0;for(const height of heights)max=Math.max(max,height);
  sources.set(seed,{heights,blocks,max:max*.25});
}
export function loadTerrain(seed:number,url:string){
  if(sources.has(seed))return Promise.resolve();
  let pending=requests.get(seed);
  if(!pending){
    pending=fetch(url).then(r=>{
      if(!r.ok)throw new Error('地貌资产载入失败 · '+r.status);
      return r.arrayBuffer();
    }).then(b=>registerTerrain(seed,b)).finally(()=>requests.delete(seed));
    requests.set(seed,pending);
  }
  return pending;
}
export class Terrain {
  private readonly source:TerrainSource;
  readonly blocks:TerrainSource['blocks'];
  wavesScale=1;
  extraWater:((x:number,z:number,scale:number)=>number)|null=null;
  constructor(readonly seed:number){
    const source=sources.get(seed);
    if(!source)throw new Error('地貌未载入 · '+seed);
    this.source=source;this.blocks=source.blocks;
  }
  get flightCeiling(){return Math.max(this.source.max,120,this.wavesScale*2);}
  bathymetry(){return this.source.heights;}
  node(i:number,j:number){return this.source.heights[j*gridSize+i]*.25;}
  elevation(x:number,z:number){
    const u=(x+worldExtent*.5)/gridStep,v=(z+worldExtent*.5)/gridStep;
    if(u<0||v<0||u>=gridSize-1||v>=gridSize-1)return seabed;
    const i=u|0,j=v|0,s=u-i,t=v-j;
    // Match the diagonal and triangle interpolation used by the terrain mesh.
    if(s+t<=1){
      const a=this.node(i,j);
      return a+s*(this.node(i+1,j)-a)+t*(this.node(i,j+1)-a);
    }
    const d=this.node(i+1,j+1);
    return d+(1-t)*(this.node(i+1,j)-d)+(1-s)*(this.node(i,j+1)-d);
  }
  field(x:number,z:number){return Math.max(this.elevation(x,z),structureTop(x,z));}
  at(x:number,z:number,time:number){return Math.max(this.field(x,z),this.water(x,z,time));}
  obstruction(ax:number,ay:number,az:number,bx:number,by:number,bz:number,time:number,clearance=0){
    const x=bx-ax,y=by-ay,z=bz-az;
    const count=clamp(Math.ceil(Math.hypot(x,z)/5),4,14);
    for(let i=1;i<=count;i++){
      const f=i/count;
      if(ay+y*f<=this.at(ax+x*f,az+z*f,time)+clearance)return f;
    }
    return 1.01;
  }
  terrainMasks(ax:number,ay:number,az:number,bx:number,by:number,bz:number){
    const x=bx-ax,z=bz-az,y=by-ay;
    const steps=clamp(Math.ceil(Math.hypot(x,z)/146),4,35);
    for(let q=1;q<steps;q++){
      const k=q/steps;
      if(this.field(ax+x*k,az+z*k)+6>ay+y*k)return true;
    }
    return false;
  }
  water(x:number,z:number,time:number){
    // Invert the horizontal Gerstner displacement at the queried world point.
    let ox=0,oz=0;
    for(const w of waves){
      const d=Math.cos(w.x*x+w.z*z-time*w.rate)*w.height*w.steepness/Math.hypot(w.x,w.z);
      ox+=d*w.x;oz+=d*w.z;
    }
    x-=ox*this.wavesScale;z-=oz*this.wavesScale;
    let y=0;
    for(const wave of waves)y+=Math.sin(wave.x*x+wave.z*z-time*wave.rate)*wave.height;
    return y*this.wavesScale+(this.extraWater?.(x,z,this.wavesScale)??0);
  }
  runway(x:number,z:number){return Math.abs(x-base.x)<base.half-3&&z>base.near&&z<base.far;}
  classify(x:number,z:number){
    if(this.runway(x,z))return 'runway';
    const h=this.field(x,z),natural=this.elevation(x,z);
    if(h>natural+5)return 'structure';
    if(h<.12)return 'water';
    const slope=Math.hypot(this.elevation(x+26,z)-this.elevation(x-26,z),
      this.elevation(x,z+26)-this.elevation(x,z-26))/52;
    if(h<15&&slope<.41)return 'sand';
    return slope>.65||h>1320?'rock':noise(x*.014,z*.008)<.39?'soil':'grass';
  }
}
