import type { HavokPhysicsWithBindings, HP_BodyId, HP_ShapeId } from '@babylonjs/havok';
import type { Airframe } from './flight';
import type { PlaneSpec } from './data';

// Each sortie owns one world. Flight controls never write to a Havok body.
export class WreckPhysics {
  private readonly world;
  private readonly bodies=new Map<Airframe,{id:HP_BodyId;generation:number}>();
  private readonly shapes=new Map<string,HP_ShapeId>();
  steps=0;

  constructor(private readonly hk:HavokPhysicsWithBindings,step:number){
    this.world=hk.HP_World_Create()[1];
    hk.HP_World_SetIdealStepTime(this.world,step);
    hk.HP_World_SetGravity(this.world,[0,-9.81,0]);
  }

  private shape(type:PlaneSpec){
    const old=this.shapes.get(type.id);
    if(old)return old;
    const hk=this.hk,{span,length}=type;
    const [,compound]=hk.HP_Shape_CreateContainer();
    for(const [z,w,h,l] of [[0,span*.22,span*.22,length*.92],[-length*.04,span*.92,span*.05,length*.38],[length*.36,span*.45,span*.14,length*.23]]){
      const [,part]=hk.HP_Shape_CreateBox([0,0,0],[0,0,0,1],[w,h,l]);
      hk.HP_Shape_AddChild(compound,part,[[0,0,z],[0,0,0,1],[1,1,1]]);
      hk.HP_Shape_Release(part);
    }
    this.shapes.set(type.id,compound);
    return compound;
  }

  remove(e:Airframe){
    const body=this.bodies.get(e);
    if(!body)return;
    this.hk.HP_World_RemoveBody(this.world,body.id);
    this.hk.HP_Body_Release(body.id);
    this.bodies.delete(e);
  }

  private add(e:Airframe){
    const hk=this.hk,shape=this.shape(e.type),[,id]=hk.HP_Body_Create();
    hk.HP_Body_SetShape(id,shape);
    hk.HP_Body_SetMassProperties(id,hk.HP_Shape_BuildMassProperties(shape)[1]);
    hk.HP_Body_SetMotionType(id,hk.MotionType.DYNAMIC);
    hk.HP_Body_SetAngularDamping(id,.04);
    hk.HP_Body_SetLinearDamping(id,.045);
    const {position:p,orientation:q,velocity:v,forward:f}=e;
    hk.HP_Body_SetPosition(id,[p.x,p.y,p.z]);
    hk.HP_Body_SetOrientation(id,[q.x,q.y,q.z,q.w]);
    hk.HP_Body_SetLinearVelocity(id,[v.x,v.y,v.z]);
    const spin=.53+(e.damage.right-e.damage.left)*1.8;
    hk.HP_Body_SetAngularVelocity(id,[f.x*spin,.10+f.y*spin,f.z*spin]);
    hk.HP_World_AddBody(this.world,id,false);
    this.bodies.set(e,{id,generation:e.generation});
  }

  advance(aircraft:readonly Airframe[],dt:number){
    for(const e of aircraft){
      const body=this.bodies.get(e);
      if(body&&(!e.down||body.generation!==e.generation))this.remove(e);
      if(e.down&&!this.bodies.has(e))this.add(e);
    }
    if(!this.bodies.size)return;
    this.hk.HP_World_Step(this.world,dt);this.steps++;
    for(const [e,{id}] of this.bodies){
      e.position.set(...this.hk.HP_Body_GetPosition(id)[1]);
      e.orientation.set(...this.hk.HP_Body_GetOrientation(id)[1]);
      e.velocity.set(...this.hk.HP_Body_GetLinearVelocity(id)[1]);
    }
  }

  dispose(){
    for(const e of this.bodies.keys())this.remove(e);
    for(const shape of this.shapes.values())this.hk.HP_Shape_Release(shape);
    this.shapes.clear();this.hk.HP_World_Release(this.world);
  }
}

let native:Promise<HavokPhysicsWithBindings>|undefined;
export async function openWreckPhysics(step:number){
  try{
    const {default:asset}=await import('@babylonjs/havok/lib/esm/HavokPhysics.wasm?url');
    const {default:create}=await import('@babylonjs/havok');
    return new WreckPhysics(await (native??=create({locateFile:()=>asset})),step);
  }catch{
    native=undefined;
    return null;
  }
}
