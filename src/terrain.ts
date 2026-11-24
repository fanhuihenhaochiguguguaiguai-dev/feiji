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
export const coarseSize=1025;
export const gridSize=4097;
const subdivision=4;
export const worldExtent=48000;
export const gridStep=worldExtent/(gridSize-1);
export const chunkCells=256;
export const chunksPerAxis=(gridSize-1)/chunkCells;
const seabed=-240;

interface TerrainPatch {i:number;j:number;cells:number;detail:Int8Array}
interface TerrainSource {heights:Int16Array; detail:Int8Array|null; patch:TerrainPatch|null; max:number; blocks:{x:number;z:number}[]}
const sources=new Map<number,TerrainSource>();
const requests=new Map<number,Promise<void>>();

export async function decodeTerrain(bytes:ArrayBuffer){
  if(new DataView(bytes).getUint16(0)!==0x1f8b)return bytes;
  const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream).arrayBuffer();
}

export function registerTerrain(seed:number,bytes:ArrayBuffer){
  const header=new DataView(bytes);
  const fine=header.getUint32(0)===0x57463138;
  const baseBytes=12+coarseSize*coarseSize*2;
  const regularBytes=baseBytes+(fine?gridSize*gridSize:0);
  if(bytes.byteLength<regularBytes||(!fine&&header.getUint32(0)!==0x57463039)||
    header.getUint16(4,true)!==(fine?gridSize:coarseSize)||header.getUint16(6,true)!==4||header.getUint32(8,true)!==worldExtent){
    throw new Error('地貌资产格式无效');
  }
  const heights=new Int16Array(bytes,12,coarseSize*coarseSize);
  const detail=fine?new Int8Array(bytes,baseBytes,gridSize*gridSize):null;
  let patch:TerrainPatch|null=null;
  if(bytes.byteLength!==regularBytes){
    if(!fine||bytes.byteLength<regularBytes+6)throw new Error('地貌局部细节无效');
    const i=header.getUint16(regularBytes,true),j=header.getUint16(regularBytes+2,true),cells=header.getUint16(regularBytes+4,true);
    if(cells!==64||i%64||j%64||i+cells>=gridSize||j+cells>=gridSize||
      bytes.byteLength!==regularBytes+6+(cells*2+1)**2)throw new Error('地貌局部细节范围无效');
    patch={i,j,cells,detail:new Int8Array(bytes,regularBytes+6)};
  }
  const blocks:TerrainSource['blocks']=[];
  const tile=chunkCells/subdivision;
  for(let z=0;z<coarseSize-1;z+=tile)for(let x=0;x<coarseSize-1;x+=tile){
    let visible=false;
    for(let j=z;j<=z+tile&&!visible;j++)for(let i=x;i<=x+tile;i++){
      if(heights[j*coarseSize+i]>-42){visible=true;break;}
    }
    if(visible)blocks.push({x:x*subdivision,z:z*subdivision});
  }
  if(!blocks.length)throw new Error('地貌资产未包含陆地');
  let max=0;for(const height of heights)max=Math.max(max,height);
  sources.set(seed,{heights,detail,patch,blocks,max:max*.25+(fine?33:0)});
}
export function loadTerrain(seed:number,url:string){
  if(sources.has(seed))return Promise.resolve();
  let pending=requests.get(seed);
  if(!pending){
    pending=fetch(url).then(r=>{
      if(!r.ok)throw new Error('地貌资产载入失败 · '+r.status);
      return r.arrayBuffer();
    }).then(decodeTerrain).then(b=>registerTerrain(seed,b)).finally(()=>requests.delete(seed));
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
  get priorityArea(){return this.source.patch;}
  get flightCeiling(){return Math.max(this.source.max,120,this.wavesScale*2);}
  bathymetry(){return this.source.heights;}
  node(i:number,j:number){
    const {heights,detail}=this.source;
    const x=Math.min(coarseSize-2,i>>2),z=Math.min(coarseSize-2,j>>2);
    const s=i/subdivision-x,t=j/subdivision-z,k=z*coarseSize+x;
    const a=heights[k],b=heights[k+1],c=heights[k+coarseSize],d=heights[k+coarseSize+1];
    const base=s+t<=1?a+s*(b-a)+t*(c-a):d+(1-t)*(b-d)+(1-s)*(c-d);
    return (base+(detail?.[j*gridSize+i]??0))*.25;
  }
  private baseHeight(u:number,v:number){
    const i=Math.min(gridSize-2,Math.floor(u)),j=Math.min(gridSize-2,Math.floor(v)),s=u-i,t=v-j;
    if(s+t<=1){
      const a=this.node(i,j);
      return a+s*(this.node(i+1,j)-a)+t*(this.node(i,j+1)-a);
    }
    const d=this.node(i+1,j+1);
    return d+(1-t)*(this.node(i+1,j)-d)+(1-s)*(this.node(i,j+1)-d);
  }
  sampleNode(u:number,v:number){
    const patch=this.source.patch;
    if(!patch||u<patch.i||u>patch.i+patch.cells||v<patch.j||v>patch.j+patch.cells)return this.baseHeight(u,v);
    const x=(u-patch.i)*2,z=(v-patch.j)*2,step=patch.cells*2;
    const i=Math.min(step-1,Math.floor(x)),j=Math.min(step-1,Math.floor(z)),s=x-i,t=z-j;
    const lattice=(a:number,b:number)=>this.baseHeight(patch.i+a*.5,patch.j+b*.5)+patch.detail[b*(step+1)+a]*.25;
    if(s+t<=1){
      const a=lattice(i,j);
      return a+s*(lattice(i+1,j)-a)+t*(lattice(i,j+1)-a);
    }
    const d=lattice(i+1,j+1);
    return d+(1-t)*(lattice(i+1,j)-d)+(1-s)*(lattice(i,j+1)-d);
  }
  elevation(x:number,z:number){
    const u=(x+worldExtent*.5)/gridStep,v=(z+worldExtent*.5)/gridStep;
    if(u<0||v<0||u>=gridSize-1||v>=gridSize-1)return seabed;
    return this.sampleNode(u,v);
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
    // Include the micro-tile residual above the general terrain ceiling.
    if(Math.min(ay,by)>this.flightCeiling+40)return false;
    const x=bx-ax,z=bz-az,y=by-ay;
    const steps=clamp(Math.ceil(Math.hypot(x,z)/52),4,128);
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
