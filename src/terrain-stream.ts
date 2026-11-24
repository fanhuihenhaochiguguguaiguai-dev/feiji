import { chunkCells, chunksPerAxis, gridStep, worldExtent } from './terrain';

interface Block {x:number;z:number;}
export interface Patch extends Block {size:number;stride:number;}
const blockMeters=chunkCells*gridStep;
const center=worldExtent*.5;

// All LODs meet on one piecewise-linear edge. Avoid tall skirt walls between leaves.
export function edgeNode(i:number,j:number,alongX:boolean,node:(i:number,j:number)=>number){
  const position=alongX?i:j,start=Math.floor(position/4)*4,blend=(position-start)*.25;
  if(!blend)return node(i,j);
  const a=alongX?node(start,j):node(i,start),b=alongX?node(start+4,j):node(i,start+4);
  return a+(b-a)*blend;
}

function between(value:number,low:number,high:number){return Math.min(high,Math.max(low,value));}
export function keyOf(x:number,z:number){return x+':'+z;}
/** Preserve authored landmarks while extending the same lattice around the active sectors. */
export function streamBlocks(x:number,z:number,leadX:number,leadZ:number,authored:readonly Block[]){
  const nearX=Math.floor((x+center)/blockMeters),nearZ=Math.floor((z+center)/blockMeters);
  const futureX=Math.floor((x+leadX+center)/blockMeters),futureZ=Math.floor((z+leadZ+center)/blockMeters);
  const result=[...authored];
  const fromX=between(futureX,nearX-1,nearX+1),fromZ=between(futureZ,nearZ-1,nearZ+1);
  for(let j=fromZ-5;j<=fromZ+5;j++)for(let i=fromX-5;i<=fromX+5;i++){
    if(i>=0&&j>=0&&i<chunksPerAxis&&j<chunksPerAxis)continue;
    result.push({x:i*chunkCells,z:j*chunkCells});
  }
  return result;
}
export function partition(block:Block,x:number,z:number,near:number):Patch[]{
  const children:Patch[]=[];
  const visit=(i:number,j:number,size:number)=>{
    const left=i*gridStep-center,top=j*gridStep-center,side=size*gridStep;
    const distance=Math.hypot(x-between(x,left,left+side),z-between(z,top,top+side));
    if(distance<near&&size>16){
      const half=size/2;
      visit(i,j,half);visit(i+half,j,half);visit(i,j+half,half);visit(i+half,j+half,half);
    }else children.push({x:i,z:j,size,stride:size===16?1:2});
  };
  visit(block.x,block.z,chunkCells);return children;
}
