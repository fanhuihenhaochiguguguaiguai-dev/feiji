import { BLEND_NORMAL, Color, CULLFACE_NONE, Entity, Mesh, MeshInstance, StandardMaterial, calculateNormals } from 'playcanvas';
import type { Airframe,FlightPose } from './flight';
import type { WorldView } from './renderer';
import { clamp } from './terrain';

export const humidityFor=(weather:number)=>[.65,.34,.78,.93,1,.88,.83,.58][weather]??.65;
export const machFor=(plane:Airframe)=>plane.speed/Math.max(300,340-plane.position.y*.0024);
export const highContrail=(plane:Airframe)=>plane.type.engine.length?
  clamp((plane.position.y-4150)/2300,0,1)*clamp((plane.throttle-.49)*3.6,0,1):0;

export class VaporCone {
  private readonly node=new Entity('跨音速凝结层');
  private readonly material=new StandardMaterial();
  constructor(world:WorldView){
    const mesh=new Mesh(world.entry.app.graphicsDevice),positions:number[]=[],colors:number[]=[],indices:number[]=[];
    const sides=20,rows=8;
    for(let j=0;j<rows;j++)for(let i=0;i<=sides;i++){
      const f=j/(rows-1),angle=i*Math.PI*2/sides;
      const radius=.08+f*.88;
      positions.push(Math.cos(angle)*radius,Math.sin(angle)*radius,f);
      const opacity=Math.round((Math.sin(f*Math.PI)**1.8)*145);
      colors.push(255,255,255,opacity);
      if(j&&i){
        const a=j*(sides+1)+i;
        indices.push(a,a-1,a-sides-2,a,a-sides-2,a-sides-1);
      }
    }
    mesh.setPositions(positions);mesh.setNormals(calculateNormals(positions,indices));mesh.setColors32(colors);mesh.setIndices(indices);mesh.update();
    const m=this.material;m.diffuse=new Color(.68,.81,.91);m.emissive=new Color(.24,.30,.36);
    m.useLighting=false;m.opacity=.65;m.opacityVertexColor=true;m.opacityVertexColorChannel='a';
    m.blendType=BLEND_NORMAL;m.cull=CULLFACE_NONE;m.depthWrite=false;m.update();
    const instance=new MeshInstance(mesh,m);
    this.node.addComponent('render',{meshInstances:[instance],castShadows:false});
    world.effects.addChild(this.node);
    this.node.once('destroy',()=>{mesh.destroy();m.destroy();});
    this.node.enabled=false;
  }
  clear(){this.node.enabled=false;}
  update(plane:Airframe,pose:FlightPose,weather:number,exterior:boolean){
    const mach=machFor(plane),intensity=clamp(1-Math.abs(mach-.98)/.12,0,1)*humidityFor(weather);
    this.node.enabled=exterior&&plane.alive&&!plane.grounded&&intensity>.12;
    if(!this.node.enabled)return;
    const p=pose.position,q=pose.orientation;
    this.node.setPosition(p.x,p.y,p.z);this.node.setRotation(q.x,q.y,q.z,q.w);
    this.node.setLocalScale(plane.type.span*.61,plane.type.span*.47,plane.type.length*.73);
    this.node.render!.meshInstances[0].setParameter('material_opacity',intensity*.52);
  }
}
