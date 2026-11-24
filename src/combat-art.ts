import { BLEND_ADDITIVE, BLEND_ADDITIVEALPHA, BLEND_NORMAL, BUFFER_DYNAMIC, CULLFACE_NONE, Entity, Mat4, Mesh, MeshInstance, calculateNormals, Quat, Vec3, VertexBuffer, VertexFormat, type Material } from 'playcanvas';
import { Vector3, type Quaternion } from '@babylonjs/core/Maths/math.vector';
import { material, primitive, type Primitive, type WorldView } from './renderer';
import type { FlightEvent, Sortie } from './sortie';
import { VaporCone, humidityFor } from './aero-vapor';
import type { FlightPose } from './flight';
import { WingWake } from './wing-wake';
import { MissileRibbons } from './missile-ribbons';
import { combatSprite } from './combat-sprite';
import { WeatherParticles } from './weather-particles';

const position=new Vec3(),scale=new Vec3(),direction=new Vec3(),rotation=new Quat(),matrix=new Mat4();
const angle=new Vec3(),zAxis=new Vec3(0,0,-1);
const types={
  smoke:{life:3.9,scale:4.5,gravity:-1.3,drag:1.01},
  dust:{life:2.7,scale:4.1,gravity:-.43,drag:.79},
  mist:{life:1.8,scale:3.4,gravity:9.8,drag:.85},
  fire:{life:.61,scale:4.9,gravity:-3.1,drag:2.2},
  flash:{life:.145,scale:2.4,gravity:0,drag:0},
  fragment:{life:3.2,scale:.65,gravity:9.81,drag:.16},
  panel:{life:4.2,scale:1,gravity:9.81,drag:.21},
  ring:{life:1.03,scale:3.3,gravity:0,drag:0},
  scorch:{life:19,scale:4.6,gravity:0,drag:0},
  sparks:{life:.36,scale:.68,gravity:11.5,drag:.39},
  oil:{life:4.3,scale:5.2,gravity:-1.8,drag:1.16},
} as const;
type Effect=keyof typeof types;
type Particle={x:number;y:number;z:number;dx:number;dy:number;dz:number;life:number;age:number;size:number;kind:Effect;spin:number;qx?:number;qy?:number;qz?:number;qw?:number};
type Layer=readonly [kind:Effect,quantity:number,intensity:number];
const patterns={
  steel:[['sparks',6,.78],['fragment',3,.75],['smoke',2,.57]],
  cannon:[['fire',1,.34],['sparks',1,.45]],
  fuse:[['flash',1,1.62],['smoke',4,.9],['fire',2,1.2],['sparks',8,1.24],['fragment',4,.92]],
  hardGround:[['smoke',6,1.02],['scorch',1,.87],['fire',2,1.1],['fragment',5,1],['sparks',4,.89]],
  softGround:[['dust',8,1.23],['scorch',1,.94],['fire',2,1.02],['fragment',4,.84]],
  soilStrike:[['dust',2,.53],['fragment',2,.39]],
  rockStrike:[['dust',2,.60],['sparks',3,.51],['fragment',3,.48]],
  water:[['mist',10,1.28],['ring',2,.8]],
  fracture:[['flash',1,1.84],['fire',3,1.8],['fragment',13,1.75],['sparks',9,1.44],['oil',4,1.5]],
} satisfies Record<string,readonly Layer[]>;
class Batch {
  private count=0;
  private readonly data:Float32Array;
  private readonly vb:VertexBuffer;
  private readonly model:Entity;
  constructor(world:WorldView,name:string,shape:Primitive|Mesh,mat:Material,readonly capacity:number){
    if(shape instanceof Mesh){
      this.model=new Entity(name);world.effects.addChild(this.model);
      this.model.addComponent('render',{meshInstances:[new MeshInstance(shape,mat)],castShadows:false});
      this.model.once('destroy',()=>shape.destroy());
    }else this.model=primitive(world.effects,name,shape,mat,0,0,0,1,1,1);
    const gpu=world.entry.app.graphicsDevice;
    this.data=new Float32Array(capacity*16);
    this.vb=new VertexBuffer(gpu,VertexFormat.getDefaultInstancingFormat(gpu),capacity,{usage:BUFFER_DYNAMIC,data:this.data.buffer as ArrayBuffer});
    this.model.render!.meshInstances[0].setInstancing(this.vb);
    this.model.render!.meshInstances[0].cull=false;
    this.model.enabled=false;
  }
  put(x:number,y:number,z:number,w:number,h:number,l:number,q:Quat=Quat.IDENTITY,age=0){
    if(this.count>=this.capacity)return;
    matrix.setTRS(position.set(x,y,z),q,scale.set(w,h,l));
    const offset=this.count++*16;
    this.data.set(matrix.data,offset);this.data[offset+3]=age;
  }
  flush(){
    this.model.enabled=this.count>0;
    if(this.count){
      this.model.render!.meshInstances[0].instancingCount=this.count;
      this.vb.setData(this.data.buffer as ArrayBuffer);
    }
    this.count=0;
  }
}
const tint=(name:string,color:string,gain:number,blend=false)=>{
  const m=material(name,color,.12,.46);
  if(gain){m.useLighting=false;m.emissive.copy(m.diffuse).mulScalar(gain);}
  if(blend){m.blendType=BLEND_ADDITIVE;m.depthWrite=false;}
  m.update();return m;
};

export class CombatArt {
  private readonly particles:Particle[]=Array.from({length:360},()=>({x:0,y:0,z:0,dx:0,dy:0,dz:0,life:0,age:0,size:0,kind:'smoke',spin:0}));
  private readonly batches:Record<Effect,Batch>;
  private readonly exhaustPosition=new Vector3();
  private readonly exhaustOffset=new Vector3();
  private readonly projectilePosition=new Vector3();
  private readonly wingWake:WingWake;
  private readonly vapor:VaporCone;
  private wingMistAt=0;
  private readonly ribbons:MissileRibbons;
  private readonly effectsClock=new Map<number,{generation:number;next:number}>();
  private readonly rounds:Batch[];
  private cursor=0;
  private live=0;
  private readonly precipitation:WeatherParticles;
  readonly ready:Promise<void>;
  weather=0;
  constructor(readonly world:WorldView){
    this.wingWake=new WingWake(world);
    this.vapor=new VaporCone(world);
    this.ribbons=new MissileRibbons(world);
    this.precipitation=new WeatherParticles(world);
    const smoke=combatSprite('深度烟迹',[1.19,1.06,1.03,.64],8);
    const oil=combatSprite('缺氧燃烧烟',[.27,.24,.23,.82],8);
    const dust=combatSprite('掀起地表尘',[.97,.78,.56,.53],8);
    const mist=combatSprite('海面水汽',[.86,1.04,1.20,.74],1);
    const flame=combatSprite('容积火团',[4.1,2.42,1.19,.91],8,true);
    this.ready=Promise.all([
      world.assets.texture('surface/smoke-frames.webp').then(t=>{for(const m of [smoke,oil,dust])m.setParameter('spriteFrames',t);}),
      world.assets.texture('surface/fire-frames.webp').then(t=>flame.setParameter('spriteFrames',t)),
      world.assets.texture('surface/water.png').then(t=>mist.setParameter('spriteFrames',t)),
    ]).then(()=>undefined);
    const ash=tint('砂岩飞溅','#a69578',0);
    const scorch=tint('烧灼残留','#2c2b2b',0);
    const flash=tint('高速白炽碎火','#ffe8ad',2.0,true);
    flash.cull=CULLFACE_NONE;flash.blendType=BLEND_ADDITIVEALPHA;flash.depthWrite=false;flash.opacity=.81;
    void world.assets.texture('surface/spark.webp').then(t=>{
      flash.diffuseMap=t;flash.opacityMap=t;flash.opacityMapChannel='a';flash.emissiveMap=t;flash.update();
    }).catch(()=>{});
    const panel=new Mesh(world.entry.app.graphicsDevice);
    const panelPositions=[-.53,-.06,-.31,.5,-.034,-.13,.35,-.041,.34,-.42,-.072,.19,
      -.48,.066,-.29,.50,.037,-.12,.32,.048,.34,-.40,.055,.21];
    const panelIndices=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7];
    panel.setPositions(panelPositions);panel.setNormals(calculateNormals(panelPositions,panelIndices));panel.setIndices(panelIndices);panel.update();
    const waterRing=tint('水面冲击环','#d4f8ff',.65,true);
    this.batches={
      smoke:new Batch(world,'涡流烟迹','plane',smoke,164),
      dust:new Batch(world,'受击尘浪','plane',dust,44),
      mist:new Batch(world,'水花与雾','plane',mist,60),
      fire:new Batch(world,'爆炸火球','plane',flame,56),
      flash:new Batch(world,'冲击辐射','sphere',tint('白热发光体','#ffe0ad',3.3,true),16),
      fragment:new Batch(world,'抛出碎片','box',ash,64),
      panel:new Batch(world,'分离的舵面与蒙皮',panel,material('断口铝合金','#656869',.55,.63),12),
      ring:new Batch(world,'水面冲击环','torus',waterRing,15),
      scorch:new Batch(world,'地表焦痕','cylinder',scorch,22),
      sparks:new Batch(world,'金属高温火花','plane',flash,45),
      oil:new Batch(world,'损伤燃烧烟迹','plane',oil,68),
    };
    this.rounds=[
      new Batch(world,'己方曳光','box',tint('曳光黄色','#ffd49c',2.10,true),170),
      new Batch(world,'敌方曳光','box',tint('曳光橙红','#ff7352',2.4,true),170),
      new Batch(world,'导弹与挂载','cylinder',material('武器抛光金属','#c5c7cd',.47,.47),40),
      new Batch(world,'导弹点火','box',tint('推进核','#ffa46b',2.7,true),40),
      new Batch(world,'红外弹短焰','box',tint('赤尾尾焰','#ff644e',2.5,true),24),
      new Batch(world,'远程弹蓝焰','box',tint('苍矛尾焰','#a1d9ff',2.6,true),24),
    ];
  }
  clear(){for(const p of this.particles)p.life=0;this.live=0;this.effectsClock.clear();this.wingWake.clear();this.vapor.clear();this.wingMistAt=0;this.ribbons.clear();}
  activeParticles(){return this.live;}
  detachPanel(at:Vec3,shape:Quat,velocity:Vector3,size:number,direction:number){
    const p=this.particles[this.cursor++%this.particles.length];
    p.kind='panel';p.age=0;p.life=4.2;p.size=size;p.spin=direction;
    p.x=at.x;p.y=at.y;p.z=at.z;
    p.dx=velocity.x+direction*11;p.dy=velocity.y-2;p.dz=velocity.z;
    p.qx=shape.x;p.qy=shape.y;p.qz=shape.z;p.qw=shape.w;
  }
  burst(v:Vector3,n:number,kind:Effect,power=1,inherited?:Vector3,axis?:Vector3){
    const spec=types[kind],fixed=kind==='ring'||kind==='scorch'||kind==='flash';
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
    if(e.kind==='trail'){this.burst(e.at,1,'smoke',.43);return;}
    if(e.kind==='missile'){this.burst(e.at,2,'smoke',.78);this.burst(e.at,1,'fire',.77);return;}
    if(e.kind==='counter'){
      if(e.cue==='released'||e.side===1&&e.cue==='diverted')this.burst(e.at,8,e.defense==='flare'?'fire':'smoke',.54);
      return;
    }
    if(e.kind==='breakup'){this.emit(e,patterns.fracture,power*3.4);return;}
    if(e.kind==='hit'){if(!e.terminal)this.emit(e,e.weapon==='gun'?patterns.steel:patterns.fuse,power*(e.weapon==='gun'?1:2.45));return;}
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
    for(const a of [s.player,...s.enemies,s.ally]){
      if(!(a.down||a.alive&&a.hp<a.maxHp*.66)||Vector3.DistanceSquared(a.position,eye)>4600**2)continue;
      const stage=a.down?1:1-a.hp/a.maxHp;
      const timer=this.effectsClock.get(a.id);
      if(timer?.generation===a.generation&&timer.next>s.time)continue;
      this.effectsClock.set(a.id,{generation:a.generation,next:s.time+(stage>.64?.073:.138)});
      const bias=(a.damage.right-a.damage.left)*a.type.span*.37;
      this.exhaustOffset.set(bias,.02,a.type.length*(a.damage.engine>.18?.35:.13)).rotateByQuaternionToRef(a.orientation,this.exhaustOffset);
      this.exhaustPosition.copyFrom(a.position).addInPlace(this.exhaustOffset);
      this.burst(this.exhaustPosition,1,stage>.58?'oil':'smoke',.58+stage*.56,a.velocity);
      if(stage>.67&&Math.floor(s.time*13+a.id)%3===0)this.burst(this.exhaustPosition,1,'fire',.44,a.velocity);
    }
  }
  update(s:Sortie,dt:number,eye:Vector3,cam:Quaternion,level:number,time:number,pose:FlightPose,alpha:number){
    rotation.set(cam.x,cam.y,cam.z,cam.w).mul(billboard);
    const plane=s.player,external=this.world.view===0;
    this.wingWake.update(s,pose,eye,dt,external,this.weather);
    this.vapor.update(plane,pose,this.weather,external);
    const wingCloud=Math.max(0,Math.abs(plane.loadG)-1.7)*humidityFor(this.weather)*Math.min(1,Math.abs(plane.alpha)*4.3);
    if(dt>0&&external&&plane.alive&&!plane.grounded&&wingCloud>.27&&s.time>=this.wingMistAt){
      this.wingMistAt=s.time+.145;
      for(const side of [-1,1]){
        this.exhaustOffset.set(side*plane.type.span*.25,.24,plane.type.length*.015).rotateByQuaternionToRef(pose.orientation,this.exhaustOffset);
        this.exhaustPosition.copyFrom(pose.position).addInPlace(this.exhaustOffset);
        this.burst(this.exhaustPosition,1,'mist',Math.min(.82,.29+wingCloud*.22),plane.velocity);
        const mist=this.particles[(this.cursor-1)%this.particles.length];
        mist.life=.52;mist.dx=plane.velocity.x*.70;mist.dy=plane.velocity.y*.70;mist.dz=plane.velocity.z*.70;
      }
    }
    this.ribbons.update(s,eye,level);
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
      if(p.kind==='fragment'||p.kind==='panel'){
        const surface=s.world.at(p.x,p.z,s.time);
        if(p.y<surface){
          if(p.dy<-9){p.y=surface+.1;p.dy*=-.25;p.dx*=.48;p.dz*=.48;}
          else {p.life=p.age;continue;}
        }
        if(p.kind==='panel'){
          particleRotation.setFromEulerAngles(p.spin*p.age*103,p.age*124,p.spin*p.age*64);
          detachedRotation.set(p.qx!,p.qy!,p.qz!,p.qw!).mul(particleRotation);
          batch.put(p.x,p.y,p.z,p.size,p.size,p.size*.68,detachedRotation);
        }else{
          const q=particleRotation.setFromEulerAngles(p.spin*23+p.age*176,p.age*91,p.spin*51);
          batch.put(p.x,p.y,p.z,p.size,p.size*.18,p.size*1.4,q);
        }
      }else if(p.kind==='flash'){
        const size=Math.max(0,p.size*(1-fraction)**.71);
        batch.put(p.x,p.y,p.z,size,size,size);
      }else if(p.kind==='ring'||p.kind==='scorch'){
        const size=p.kind==='ring'?p.size*(1+fraction*9):p.size;
        batch.put(p.x,p.y+.06,p.z,size,p.kind==='ring'?.04+(1-fraction)*.05:.022,size);
      }else{
        const grow=p.kind==='fire'?(.28+fraction*2.65)*(1-fraction):p.kind==='sparks'?1-fraction:(.62+1.55*fraction)*Math.min(1,(1-fraction)*3.7);
        const size=p.size*grow;
        batch.put(p.x,p.y,p.z,size,1,size*(p.kind==='sparks'?2.25:1),rotation,p.kind==='sparks'?0:fraction);
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
      const q=weaponRotation.setFromDirections(Vec3.UP,direction.set(d.x,d.y,d.z));
      const missile=p.kind==='missile'||p.guidedGround;
      const apparent=missile?Math.min(2.9,Math.max(1.65,Vector3.Distance(v,eye)*.0015)):1;
      this.rounds[2].put(v.x,v.y,v.z,.44*apparent,missile?3.9*apparent:2.4,.44*apparent,q);
      if(p.kind==='missile'||p.guidedGround){
        const after=weaponRotation.setFromDirections(zAxis,direction);
        const shape=p.guidedGround?0:p.profile.shape;
        const long=(shape===2?10:shape===1?5:7)*apparent*Math.min(1,p.age*8);
        this.rounds[3+shape].put(v.x-d.x*(2+long*.42),v.y-d.y*(2+long*.42),v.z-d.z*(2+long*.42),.71*apparent,.71*apparent,long,after);
      }
    }
    for(const b of Object.values(this.batches))b.flush();
    this.precipitation.update(this.weather,level,eye,cam,s.time);
  }
  private tracer(p:Vector3,d:Vector3,kind:0|1,length:number){
    if(length<1)return;
    weaponRotation.setFromDirections(zAxis,direction.set(d.x,d.y,d.z).normalize());
    this.rounds[kind].put(p.x-d.x*length*.45,p.y-d.y*length*.45,p.z-d.z*length*.45,.16,.16,length,weaponRotation);
  }
  flush(){for(const b of this.rounds)b.flush();}
}
const billboard=new Quat().setFromEulerAngles(90,0,0),particleRotation=new Quat(),weaponRotation=new Quat(),detachedRotation=new Quat();
