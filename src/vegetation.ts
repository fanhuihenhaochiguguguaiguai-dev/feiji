import { BUFFER_DYNAMIC, Mat4, Quat, Vec3, VertexBuffer, VertexFormat, type Entity } from 'playcanvas';
import { material, primitive, type WorldView } from './renderer';
import { hash, type Terrain } from './terrain';

// Cells are stable in world coordinates, and stream through a single instanced draw.
const cell=84,capacity=520;
export class Vegetation {
  private readonly entity:Entity;
  private readonly buffer:VertexBuffer;
  private readonly matrices=new Float32Array(capacity*16);
  private readonly treePosition=new Vec3();
  private readonly treeScale=new Vec3();
  private readonly lean=new Quat();
  private readonly transform=new Mat4();
  private centerX=Infinity;
  private centerZ=Infinity;
  private seed=-1;
  private radius=0;
  constructor(world:WorldView){
    const device=world.entry.app.graphicsDevice;
    const tree=material('海风针叶林','#456250',.0,.94);
    this.entity=primitive(world.terrainRoot,'沿岸常绿植被','cone',tree,0,0,0,1,1,1);
    this.buffer=new VertexBuffer(device,VertexFormat.getDefaultInstancingFormat(device),capacity,
      {usage:BUFFER_DYNAMIC,data:this.matrices.buffer});
    const instance=this.entity.render!.meshInstances[0];
    instance.setInstancing(this.buffer);instance.cull=false;
    this.entity.enabled=false;
    this.entity.once('destroy',()=>{this.buffer.destroy();tree.destroy();});
  }
  update(terrain:Terrain,x:number,z:number,detail:number,time:number){
    const i=Math.floor(x/cell),j=Math.floor(z/cell),radius=detail<.8?9:13;
    if(this.centerX===i&&this.centerZ===j&&this.seed===terrain.seed&&this.radius===radius)return;
    this.centerX=i;this.centerZ=j;this.seed=terrain.seed;this.radius=radius;
    let count=0;
    for(let a=-radius;a<=radius;a++)for(let b=-radius;b<=radius;b++){
      if(count>=capacity||a*a+b*b>radius*radius)continue;
      const density=hash(i+a,j+b+terrain.seed);
      if(density<.46)continue;
      const px=(i+a+.12+density*.73)*cell,pz=(j+b+hash(j+b,i+a)*.77)*cell;
      const floor=terrain.elevation(px,pz);
      if(floor<19||floor>(terrain.seed===704?1600:2100)||terrain.classify(px,pz)!=='grass')continue;
      const height=6.0+density*11.5,width=2.8+density*5.2;
      this.treePosition.set(px,floor+height*.43,pz);
      this.treeScale.set(width,height,width*.91);
      this.lean.setFromEulerAngles(-2+Math.sin(time*.22+px*.017)*2.2,density*360,-2+hash(i+a,j+b)*4);
      this.transform.setTRS(this.treePosition,this.lean,this.treeScale);
      this.matrices.set(this.transform.data,count++*16);
    }
    this.entity.enabled=count>0;
    if(count){this.entity.render!.meshInstances[0].instancingCount=count;this.buffer.setData(this.matrices.buffer);}
  }
}
