import '@babylonjs/core/Meshes/thinInstanceMesh';
import { Constants } from '@babylonjs/core/Engines/constants';
import { Material } from '@babylonjs/core/Materials/material';
import type { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import type { Mesh } from '@babylonjs/core/Meshes/mesh';
import type { Scene } from '@babylonjs/core/scene';
import { directionRotation,radians } from './scene-runtime';
import { Matrix, Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { material, primitive, type Primitive, type WorldView } from './renderer';
import type { FlightEvent, Sortie } from './sortie';
import type { FlightPose } from './flight';
import { WingWake } from './wing-wake';

const position=new Vector3(),scale=new Vector3(),direction=new Vector3(),rotation=Quaternion.Identity(),matrix=Matrix.Identity();
const zAxis=new Vector3(0,0,-1);
const types={
  smoke:{life:3.9,scale:4.5,gravity:-1.3,drag:1.01},
  dust:{life:2.7,scale:4.1,gravity:-.43,drag:.79},
  mist:{life:1.8,scale:3.4,gravity:9.8,drag:.85},
  fire:{life:.43,scale:4.9,gravity:-3.1,drag:2.2},
  fragment:{life:3.2,scale:.65,gravity:9.81,drag:.16},
  ring:{life:1.03,scale:3.3,gravity:0,drag:0},
  scorch:{life:19,scale:4.6,gravity:0,drag:0},
  sparks:{life:.36,scale:.68,gravity:11.5,drag:.39},
  shock:{life:.54,scale:6.5,gravity:0,drag:0},
  oil:{life:4.3,scale:5.2,gravity:-1.8,drag:1.16},
} as const;
type Effect=keyof typeof types;
type Particle={x:number;y:number;z:number;dx:number;dy:number;dz:number;life:number;age:number;size:number;kind:Effect;spin:number};
type Layer=readonly [kind:Effect,quantity:number,intensity:number];
const patterns={
  steel:[['sparks',6,.78],['fragment',3,.75],['smoke',2,.57]],
  cannon:[['fire',1,.34],['sparks',1,.45]],
  fuse:[['smoke',4,.9],['fire',2,1.2],['shock',1,1.2],['sparks',8,1.24],['fragment',4,.92]],
  hardGround:[['smoke',6,1.02],['scorch',1,.87],['fire',2,1.1],['fragment',5,1],['sparks',4,.89]],
  softGround:[['dust',8,1.23],['scorch',1,.94],['fire',2,1.02],['fragment',4,.84]],
  soilStrike:[['dust',2,.53],['fragment',2,.39]],
  rockStrike:[['dust',2,.60],['sparks',3,.51],['fragment',3,.48]],
  water:[['mist',10,1.28],['ring',2,.8]],
  fracture:[['fire',3,1.8],['shock',1,1.5],['fragment',13,1.75],['sparks',9,1.44],['oil',4,1.5]],
} satisfies Record<string,readonly Layer[]>;
class Batch {
  private count=0;
  private readonly data:Float32Array;
  private readonly model:Mesh;
  constructor(world:WorldView,name:string,shape:Primitive,mat:PBRMaterial,readonly capacity:number){
    this.model=primitive(world.effects,name,shape,mat,0,0,0,1,1,1);
    this.data=new Float32Array(capacity*16);
    this.model.thinInstanceSetBuffer('matrix',this.data,16,false);
    this.model.doNotSyncBoundingInfo=true;this.model.alwaysSelectAsActiveMesh=true;
    this.model.setEnabled(false);
  }
  put(x:number,y:number,z:number,w:number,h:number,l:number,q=identity){
    if(this.count>=this.capacity)return;
    Matrix.ComposeToRef(scale.set(w,h,l),q,position.set(x,y,z),matrix);
    this.data.set(matrix.m,this.count++*16);
  }
  flush(){
    this.model.setEnabled(this.count>0);
    if(this.count){this.model.thinInstanceCount=this.count;this.model.thinInstanceBufferUpdated('matrix');}
    this.count=0;
  }
}
const tint=(scene:Scene,name:string,color:string,gain:number,blend=false)=>{
  const m=material(scene,name,color,.12,.46);
  if(gain){m.unlit=true;m.albedoColor.scaleToRef(gain,m.emissiveColor);}
  if(blend){m.alphaMode=Constants.ALPHA_ADD;m.transparencyMode=Material.MATERIAL_ALPHABLEND;m.disableDepthWrite=true;}
  return m;
};

export class CombatArt {
  private readonly particles:Particle[]=Array.from({length:360},()=>({x:0,y:0,z:0,dx:0,dy:0,dz:0,life:0,age:0,size:0,kind:'smoke',spin:0}));
  private readonly batches:Record<Effect,Batch>;
  private readonly exhaustPosition=new Vector3();
  private readonly exhaustOffset=new Vector3();
  private readonly projectilePosition=new Vector3();
  private readonly wingWake:WingWake;
  private readonly effectsClock=new Map<number,number>();
  private readonly rounds:Batch[];
  private cursor=0;
  private live=0;
  private readonly precipitation:Batch;
  weather=0;
  constructor(readonly world:WorldView){
    const scene=world.entry.app.scene;
    this.wingWake=new WingWake(world);
    const rain=tint(scene,'天气降水','#b8d4e6',.44,true);
    this.precipitation=new Batch(world,'近景雨雪','box',rain,66);
    const smoke=tint(scene,'软边烟尘','#a9abb1',0);
    const oil=tint(scene,'持续损伤黑烟','#6b625d',0);
    const dust=tint(scene,'扬起的地表粉尘','#ad9377',0);
    const mist=tint(scene,'海面雾滴','#bfe1e9',.5);
    const flame=tint(scene,'火球辐照','#ff8b43',2.25,true);
    const ash=tint(scene,'砂岩飞溅','#a69578',0);
    const scorch=tint(scene,'烧灼残留','#2c2b2b',0);
    const flash=tint(scene,'高速白炽碎火','#ffe8ad',2.0,true);
    const shock=tint(scene,'空中折光冲击','#a2c6e3',.35,true);
    for(const [m,file] of [[smoke,'soot.webp'],[oil,'soot.webp'],[dust,'soot.webp'],[mist,'water.png'],[flame,'combustion.webp'],[flash,'spark.webp'],[shock,'pressure.webp']] as const){
      m.backFaceCulling=false;m.alphaMode=m===flame||m===flash?Constants.ALPHA_ONEONE:Constants.ALPHA_COMBINE;m.disableDepthWrite=true;
      m.transparencyMode=Material.MATERIAL_ALPHABLEND;
      m.alpha=m===flame?.84:m===mist?.62:m===shock?.48:.57;
      void world.assets.texture('surface/'+file).then(t=>{
        t.hasAlpha=true;m.albedoTexture=t;m.opacityTexture=t;m.emissiveTexture=t;
      }).catch(()=>{});
    }
    const waterRing=tint(scene,'水面冲击环','#d4f8ff',.65,true);
    this.batches={
      smoke:new Batch(world,'涡流烟迹','plane',smoke,164),
      dust:new Batch(world,'受击尘浪','plane',dust,44),
      mist:new Batch(world,'水花与雾','plane',mist,60),
      fire:new Batch(world,'爆炸火球','plane',flame,56),
      fragment:new Batch(world,'抛出碎片','box',ash,64),
      ring:new Batch(world,'水面冲击环','torus',waterRing,15),
      scorch:new Batch(world,'地表焦痕','cylinder',scorch,22),
      sparks:new Batch(world,'金属高温火花','plane',flash,45),
      shock:new Batch(world,'空气冲击环','plane',shock,14),
      oil:new Batch(world,'损伤燃烧烟迹','plane',oil,68),
    };
    this.rounds=[
      new Batch(world,'己方曳光','box',tint(scene,'曳光黄色','#ffd49c',2.10,true),170),
      new Batch(world,'敌方曳光','box',tint(scene,'曳光橙红','#ff7352',2.4,true),170),
      new Batch(world,'导弹与挂载','cylinder',material(scene,'武器抛光金属','#c5c7cd',.47,.47),40),
      new Batch(world,'导弹点火','box',tint(scene,'推进核','#ffa46b',2.7,true),40),
      new Batch(world,'红外弹短焰','box',tint(scene,'赤尾尾焰','#ff644e',2.5,true),24),
      new Batch(world,'远程弹蓝焰','box',tint(scene,'苍矛尾焰','#a1d9ff',2.6,true),24),
    ];
  }
  clear(){for(const p of this.particles)p.life=0;this.live=0;this.effectsClock.clear();this.wingWake.clear();}
  activeParticles(){return this.live;}
  burst(v:Vector3,n:number,kind:Effect,power=1,inherited?:Vector3,axis?:Vector3){
    const spec=types[kind],fixed=kind==='ring'||kind==='shock'||kind==='scorch';
    const kick=axis?(kind==='sparks'?14:kind==='fragment'?7:kind==='dust'?2:0)*power:0;
    for(let i=0;i<n;i++){
      const p=this.particles[this.cursor++%this.particles.length],a=Math.random()*Math.PI*2;
      const speed=kind==='fragment'?17+Math.random()*39:kind==='sparks'?20+Math.random()*58:2+Math.random()*8;
      const carry=kind==='fragment'?.78:kind==='sparks'?.32:.12;
      p.x=v.x;p.y=v.y;p.z=v.z;
      p.dx=fixed?0:Math.cos(a)*speed*power+(inherited?.x??0)*carry+(axis?.x??0)*kick;
      p.dz=fixed?0:Math.sin(a)*speed*power+(inherited?.z??0)*carry+(axis?.z??0)*kick;
      p.dy=fixed?0:(kind==='mist'?5+Math.random()*14:speed*(.09+Math.random()*.59))*power+(inherited?.y??0)*carry;
      p.kind=kind;p.age=0;p.spin=a;
      p.life=spec.life*(.86+Math.random()*.28);
      p.size=spec.scale*power*(.75+Math.random()*.48);
    }
  }
  private emit(e:FlightEvent,layers:readonly Layer[],power:number){
    const range=Vector3.Distance(e.at,this.world.camera.position);
    if(range>10500)return;
    const budget=range>3500?.46:range>1600?.73:1;
    for(const [kind,count,gain] of layers){
      this.burst((kind==='sparks'||e.weapon==='gun')?e.strike??e.at:e.at,Math.max(1,Math.round(count*budget)),kind,power*gain,e.target?.velocity,e.direction);
    }
  }
  event(e:FlightEvent){
    const power=e.scale??1;
    if(e.kind==='gun'){this.emit(e,patterns.cannon,1);return;}
    if(e.kind==='trail'){this.burst(e.at,1,'smoke',.63);return;}
    if(e.kind==='missile'){this.burst(e.at,2,'smoke',.78);this.burst(e.at,1,'fire',.77);return;}
    if(e.kind==='counter'){
      if(e.cue==='released'||e.side===1&&e.cue==='diverted')this.burst(e.at,8,e.defense==='flare'?'fire':'smoke',.54);
      return;
    }
    if(e.kind==='breakup'){this.emit(e,patterns.fracture,power);return;}
    if(e.kind==='hit'){if(!e.terminal)this.emit(e,e.weapon==='gun'?patterns.steel:patterns.fuse,power);return;}
    if(e.kind!=='impact')return;
    if(e.surface==='water'){
      if(e.weapon==='gun')this.burst(e.at,2,'mist',.44);
      else this.emit(e,patterns.water,power);
      return;
    }
    const soft=e.surface==='sand'||e.surface==='soil'||e.surface==='grass';
    const strike=soft?patterns.soilStrike:e.surface==='rock'?patterns.rockStrike:patterns.steel;
    this.emit(e,e.weapon==='gun'?strike:soft?patterns.softGround:patterns.hardGround,power);
  }
  private damaged(s:Sortie,eye:Vector3){
    for(const a of [...s.enemies,s.ally]){
      if(!(a.down||a.alive&&a.hp<a.maxHp*.66)||Vector3.DistanceSquared(a.position,eye)>4600**2)continue;
      const stage=a.down?1:1-a.hp/a.maxHp,key=a.id*10000+a.generation;
      if((this.effectsClock.get(key)??0)>s.time)continue;
      this.effectsClock.set(key,s.time+(stage>.64?.073:.138));
      const bias=(a.damage.right-a.damage.left)*a.type.span*.37;
      this.exhaustOffset.set(bias,.02,a.type.length*(a.damage.engine>.18?.35:.13)).rotateByQuaternionToRef(a.orientation,this.exhaustOffset);
      this.exhaustPosition.copyFrom(a.position).addInPlace(this.exhaustOffset);
      this.burst(this.exhaustPosition,1,stage>.58?'oil':'smoke',.58+stage*.56,a.velocity);
      if(stage>.67&&Math.floor(s.time*13+a.id)%3===0)this.burst(this.exhaustPosition,1,'fire',.44,a.velocity);
    }
  }
  update(s:Sortie,dt:number,eye:Vector3,cam:Quaternion,level:number,time:number,pose:FlightPose,alpha:number){
    rotation.copyFrom(cam).multiplyInPlace(billboard);
    this.wingWake.update(s,pose,eye,dt,this.world.view===0);
    if(dt>0)this.damaged(s,eye);
    let live=0;
    for(const p of this.particles){
      if(p.age>=p.life)continue;
      p.age+=dt;
      const fraction=Math.min(1,p.age/p.life),spec=types[p.kind];
      const drag=1/(1+spec.drag*dt);
      p.dx*=drag;p.dy=(p.dy-spec.gravity*dt)*drag;p.dz*=drag;
      p.x+=p.dx*dt;p.y+=p.dy*dt;p.z+=p.dz*dt;
      const dist=(p.x-eye.x)**2+(p.y-eye.y)**2+(p.z-eye.z)**2;
      if(dist>11000**2||level<.68&&p.kind==='smoke'&&dist>2300**2)continue;
      const batch=this.batches[p.kind];
      if(p.kind==='fragment'){
        const surface=s.world.at(p.x,p.z,s.time);
        if(p.y<surface){
          if(p.dy<-9){p.y=surface+.1;p.dy*=-.25;p.dx*=.48;p.dz*=.48;}
          else {p.life=p.age;continue;}
        }
        const q=Quaternion.RotationYawPitchRollToRef(p.age*91*radians,(p.spin*23+p.age*176)*radians,p.spin*51*radians,particleRotation);
        batch.put(p.x,p.y,p.z,p.size,p.size*.18,p.size*1.4,q);
      }else if(p.kind==='ring'||p.kind==='scorch'){
        const size=p.kind==='ring'?p.size*(1+fraction*9):p.size;
        batch.put(p.x,p.y+.06,p.z,size,p.kind==='ring'?.04+(1-fraction)*.05:.022,size);
      }else{
        const grow=p.kind==='fire'?(.28+fraction*2.65)*(1-fraction):p.kind==='shock'?.65+fraction*6:p.kind==='sparks'?1-fraction:(.62+1.55*fraction)*Math.min(1,(1-fraction)*3.7);
        const size=p.size*grow;
        batch.put(p.x,p.y,p.z,size,1,size*(p.kind==='sparks'?2.25:1),rotation);
      }
      live++;
    }
    this.live=live;
    for(const p of s.projectiles){
      if(!p.live)continue;
      const v=this.projectilePosition,d=p.direction;
      Vector3.LerpToRef(p.previous,p.position,alpha,v);
      if(p.kind==='gun'){
        const speed=p.velocity.length();
        this.tracer(v,d,p.owner?.side?1:0,Math.min(23,speed*.012,speed*p.age));continue;
      }
      const q=directionRotation(Vector3.UpReadOnly,direction.copyFrom(d),weaponRotation);
      this.rounds[2].put(v.x,v.y,v.z,.44,p.kind==='bomb'&&!p.guidedGround?2.4:3.9,.44,q);
      if(p.kind==='missile'||p.guidedGround){
        const after=directionRotation(zAxis,direction,weaponRotation);
        const shape=p.guidedGround?0:p.profile.shape,long=shape===2?10:shape===1?5:7;
        this.rounds[3+shape].put(v.x-d.x*(2+long*.42),v.y-d.y*(2+long*.42),v.z-d.z*(2+long*.42),.58,.58,long,after);
      }
    }
    for(const b of Object.values(this.batches))b.flush();
    if(this.weather===3||this.weather===4||this.weather===6){
      const snow=this.weather===6,count=Math.round((this.weather===4?62:snow?49:36)*Math.min(1,level));
      for(let i=0;i<count;i++){
        const phase=i*.618033988;
        const x=eye.x+(((i*37)%67)/67-.5)*109+Math.sin(time*.62+phase)*6;
        const y=eye.y+(((phase-time*(snow?.071:.24))%1+1)%1-.5)*75;
        const z=eye.z+(((i*23)%71)/71-.5)*112;
        this.precipitation.put(x,y,z,snow?.18:.045,snow?.17:1.20,snow?.18:.046,weatherAngle);
      }
    }
    this.precipitation.flush();

  }
  private tracer(p:Vector3,d:Vector3,kind:0|1,length:number){
    if(length<1)return;
    directionRotation(zAxis,direction.copyFrom(d).normalize(),weaponRotation);
    this.rounds[kind].put(p.x-d.x*length*.45,p.y-d.y*length*.45,p.z-d.z*length*.45,.16,.16,length,weaponRotation);
  }
  flush(){for(const b of this.rounds)b.flush();}
}
const identity=Quaternion.Identity(),billboard=Quaternion.RotationAxis(Vector3.Right(),Math.PI/2);
const particleRotation=Quaternion.Identity(),weaponRotation=Quaternion.Identity(),weatherAngle=Quaternion.RotationYawPitchRoll(0,10*radians,12*radians);
