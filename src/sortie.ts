import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { byAircraft, difficulties, theatres, type Operation, type PlaneSpec } from './data';
import { advanceFlight, Airframe, FLIGHT_STEP, ahead, above, idle, type Controls } from './flight';
import { base, clamp, Terrain } from './terrain';
import { aircraftContact, ellipsoid, terrainContact } from './contact';
import { cannonFor, guidedStrike, gunCycle, gunDamage, gunSight, missileCycle, releaseDropSpeed, roundCapacity, standardGravity, thrustDuration } from './ordnance';
import { groundMount, missiles, missileDamage, minimumEnemyDurability,type MissileProfile } from './items';
import type { CombatConfiguration } from './profile';
import { choosePass,enemyTuning,planPass,Tactic } from './tactics';
import { CountermeasureSystem, MissileGuidance, MissileWarningSystem, type DefenseCue, type DefenseKind, type GuidedTrack } from './defense';
const delta=new Vector3(),local=new Vector3(),orientation=Quaternion.Identity(),inverted=Quaternion.Identity();
const spreadVector=new Vector3(),leftToRight=new Vector3(),eventAt=new Vector3(),tipNow=new Vector3(),tipBefore=new Vector3(),shotStart=new Vector3(),shotEnd=new Vector3(),localStrike=new Vector3();
const distance=(a:Vector3,b:Vector3)=>Vector3.Distance(a,b);

export type ProjectileKind='gun'|'missile'|'bomb';
export type Surface='water'|'sand'|'rock'|'soil'|'grass'|'runway'|'structure';
export type FlightEvent={kind:'gun'|'missile'|'bomb'|'trail'|'hit'|'breakup'|'impact'|'lock'|'warn'|'wave'|'counter';at:Vector3;side:number;scale?:number;surface?:Surface;weapon?:ProjectileKind|'crash';track?:number;target?:Airframe;strike?:Vector3;terminal?:boolean;direction?:Vector3;profile?:MissileProfile;defense?:DefenseKind;cue?:DefenseCue};
export interface WeaponTrack extends GuidedTrack {
  live:boolean;kind:ProjectileKind;owner:Airframe|null;target:Airframe|null;generation:number;
  guidedGround:boolean;aim:Vector3;
  position:Vector3;previous:Vector3;velocity:Vector3;direction:Vector3;time:number;age:number;smokeAt:number;
}
const tracks=(kind:ProjectileKind,n:number):WeaponTrack[]=>Array.from({length:n},()=>({live:false,kind,owner:null,target:null,generation:0,
  guidedGround:false,aim:new Vector3(),position:new Vector3(),previous:new Vector3(),velocity:new Vector3(),direction:new Vector3(),time:0,age:0,smokeAt:0,
  serial:0,seeker:'radar',profile:missiles.interceptor,guidance:'tracking',decoy:null,decoySerial:0,reacquireAt:0}));
export interface Debrief {
  operation:Operation;win:boolean;reason:string;time:number;distance:number;peak:number;altitude:number;hp:number;
  kills:number;accuracy:number|null;missileAccuracy:number|null;bombAccuracy:number|null;score:number;grade:string;credits:number;xp:number;types:Record<string,number>;evaded:number;
}
interface GroundTarget {position:Vector3;hp:number;alive:boolean}
export interface Loadout {rank:number; armor:number; engine:number; stores:number; repair:boolean; radar:boolean; runway:boolean; configuration?:CombatConfiguration;seed?:number;diagnostics?:boolean}
const flightSets:Record<string,string[]>={ww1:['dr1','camel'],ww2:['p51','zero','bf109','spitfire'],early:['me262','p51','bf109'],
  cold:['mig21','g91','alphajet','me262'],modern:['j10','f16','hornet','gripen','mirage','su35'],stealth:['j10','su35','f16','j20','mirage']};

function pursuit(actor:Airframe,target:Vector3,command:Controls){
  target.subtractToRef(actor.position,delta);
  delta.normalize();
  actor.orientation.conjugateToRef(inverted);
  delta.rotateByQuaternionToRef(inverted,local);
  const back=local.z>.16&&Math.abs(local.x)<.13?Math.sign(actor.role-1.5)*.49:local.x;
  command.yaw=clamp(-back*1.89,-.93,.93);
  command.pitch=clamp(local.y*2.15,-.76,.83);
  const bank=rightTilt(actor);
  command.roll=clamp(-back*.65-bank*.90,-.78,.78);
}
function rightTilt(p:Airframe){leftToRight.set(1,0,0).rotateByQuaternionToRef(p.orientation,leftToRight);return leftToRight.y;}
export class Sortie {
  readonly player:Airframe;
  readonly enemies=Array.from({length:4},(_,i)=>{
    const slot=new Airframe(i+1,byAircraft('f16'),1);
    slot.alive=false;
    return slot;
  });
  readonly ally=new Airframe(9,byAircraft('c130'),2);
  readonly friendlies:Airframe[];
  readonly world:Terrain;
  readonly projectiles=[...tracks('gun',162),...tracks('missile',24),...tracks('bomb',14)];
  readonly groups={gun:this.projectiles.slice(0,162),missile:this.projectiles.slice(162,186),bomb:this.projectiles.slice(186)};
  readonly targetPoints:GroundTarget[]=[];
  readonly warning=new MissileWarningSystem();
  readonly defense:CountermeasureSystem;
  private readonly shields:(CountermeasureSystem|null)[]=Array.from({length:4},()=>null);
  private readonly enemyWarning=new MissileWarningSystem();
  private readonly gunLead=new Vector3();
  readonly waves:readonly number[];
  readonly endless:boolean;
  readonly seed:number;
  readonly opening:number;
  private readonly pilots=Array.from({length:4},()=>enemyTuning(1,1));
  readonly safeLine;
  readonly weapons:ProjectileKind[];
  readonly missile:MissileProfile;
  readonly groundWeapon:'bomb'|'shorebolt';
  spares:number;
  lastPracticalLaunch='';
  private nextThreat=2.3;
  weapon:ProjectileKind='gun';
  private shotSerial=0;
  readonly gates:Vector3[]=[];
  readonly stats={kills:0,fired:0,hit:0,missile:0,missileHit:0,bomb:0,bombHit:0,distance:0,peak:0,altitude:0,types:{} as Record<string,number>};
  time=0; wave=0; during=0; cleared=0; lost=0; gate=0; lockProgress=0;
  total=0; active=true; win=false; reason=''; manual:Airframe|null=null; locked:Airframe|null=null;
  readonly difficulty;
  readonly radar;
  readonly loadout;
  readonly aiPoint=new Vector3();
  readonly fireCursor={gun:0,missile:0,bomb:0};
  readonly enemyKit;
  constructor(readonly op:Operation,readonly type:PlaneSpec,loadout:Loadout,readonly notify:(event:FlightEvent)=>void,world?:Terrain){
    const config=loadout.configuration;
    this.missile=config?.missile??{...missiles.interceptor,damage:missileDamage(type,missiles.interceptor,0)};
    this.spares=config?.spares??0;this.groundWeapon=config?.groundWeapon??'bomb';
    this.defense=new CountermeasureSystem(type.era,type.safety,config?.defense??0);
    this.weapons=[];
    if(config?.rounds??type.ammo)this.weapons.push('gun');
    if(config?.airMissiles??type.missiles)this.weapons.push('missile');
    if(config?.groundStores??type.bombs)this.weapons.push('bomb');
    this.weapon=op.kind==='ground'&&this.weapons.includes('bomb')?'bomb':this.weapons[0]??'gun';
    this.loadout=loadout;this.difficulty=difficulties[loadout.rank]??difficulties[1];
    this.endless=op.kind==='free'&&!loadout.diagnostics;
    this.seed=(loadout.seed??0)>>>0;this.opening=2+this.seed%9;
    const engagement=op.engagement;
    this.waves=op.lesson?[1]:engagement?engagement.waves.map(n=>clamp(n+(loadout.rank===2?1:loadout.rank===0&&n>2?-1:0),1,4)):this.difficulty.waves;
    this.safeLine=-5100-(op.campaign??0)*53;

    this.world=world??new Terrain(theatres[op.region].seed);this.radar=config?.radar??(loadout.radar?8500:6400);
    const p=this.player=new Airframe(0,type,0);
    this.friendlies=[p,this.ally];
    p.roundsLimit=config?.rounds??roundCapacity(type,loadout.stores);p.missilesLimit=config?.airMissiles;p.bombsLimit=config?.groundStores;
    p.maxHp=type.durability;p.enginePower=config?.engine??(1+loadout.engine*.06);
    p.handling=config?.grip??1;p.firepower=config?.gun??1;p.storesBonus=config?.stores??loadout.stores;
    const original=type.props.length?Math.max(128,type.trim*2.1):390;
    const h=engagement?Math.max(engagement.objective==='low'?148:original,engagement.altitude):original;
    if(op.kind==='ground'){
      const groups=op.engagement?.groups??2;
      const shift=engagement&&op.campaign!==3?(op.campaign??0)%5*34:0;
      const approach=engagement?.formation==='line'?0:engagement?.formation==='stack'?88:-64;
      const origin=base.x+104+shift;
      p.reset(origin,Math.max(170,engagement?.altitude??176),2600,-.018,Math.max(type.stall*1.4,type.trim*.76));
      for(let i=0;i<groups;i++){
        const count=i===0?3:2;
        const center=origin+(i%2?approach:-approach),along=1730-i*(engagement?.spacing??345)-i*98;
        for(let j=0;j<count;j++){
          const x=center+(j-1)*25,z=along+(j%2?37:-17);
          this.targetPoints.push({position:new Vector3(x,this.world.field(x,z)+3,z),hp:100,alive:true});
        }
      }
      this.total=this.targetPoints.length;
    }else if(op.kind==='free'&&loadout.runway){
      p.reset(base.x,32.05+Math.max(.8,type.gearClearance),2010,0,0);
      p.gear=p.gearTarget=1;p.grounded=true;p.throttle=.13;
    }else {
      const offset=engagement?(op.campaign??0)%5*96:0;
      const z=2610+offset;
      p.reset(18+offset,Math.max(h,this.world.at(18+offset,z,0)+230),z,engagement?.heading??.015);
      if(op.kind==='train'){
        const turn=op.lesson==='turn';
        this.gates.push(new Vector3(turn?315:18, h-19,1350),new Vector3(turn?-475:144,h-52,195),new Vector3(turn?410:25,h-86,-970));this.total=3;
      }
    }
    this.ally.alive=op.kind==='escort';
    if(this.ally.alive){
      this.ally.maxHp=185+(engagement?.tier??0)*33;
      this.ally.reset(285,Math.max(238,h+51,this.world.at(285,2130,0)+150),2130,-.015);
    }
    const mixed=type.props.length||type.era==='early';
    const roster=mixed?flightSets[type.era]:engagement?.roster;
    this.enemyKit=[...new Set([...(roster??flightSets[type.era]??flightSets.modern),...(engagement?.ace?[engagement.ace]:[])])];
    if(op.kind==='air'||op.kind==='escort'){
      this.total=this.waves.reduce((a,b)=>a+b,0);this.spawn();
    }else if(this.endless)this.spawn();
  }
  spawn(){
    const p=this.player,plan=this.op.engagement;
    const count=this.endless?Math.min(4,2+Math.floor((this.wave+this.seed%3)/2)):this.waves[this.wave]??0;
    if(!count)return;
    const step=this.endless?this.opening+this.wave*3:this.op.campaign??(this.op.lesson?1:3+this.op.threat*9);
    const boss=this.endless?(this.wave+1)%10===0:this.wave+1===this.waves.length&&!!plan?.ace;
    const rosterShift=this.endless?(this.seed>>>4)+this.wave*3:this.wave;
    const normal=enemyTuning(step,this.loadout.rank),aceSkill=boss?enemyTuning(step+6,this.loadout.rank):normal;
    const formation=plan?.formation??(this.endless?['line','stack','screen','pincer'][((this.seed>>>2)+this.wave)%4]:'line');
    this.wave++;this.during=this.time;
    if(this.endless)this.total+=count;
    const k=Math.hypot(p.forward.x,p.forward.z),x=k>.66?p.forward.x/k:0,z=k>.66?p.forward.z/k:-1;
    const distance=plan?Math.max(465,Math.min(plan.distance+210*(this.wave-1),p.type.trim*6.5)):
      Math.max(465,Math.min(this.wave===1?1170:1670,p.type.trim*5.65));
    for(let i=0;i<this.enemies.length;i++){
      const e=this.enemies[i];e.alive=i<count;e.down=0;
      if(!e.alive)continue;
      e.type=byAircraft(this.enemyKit[(i+rosterShift)%this.enemyKit.length]);
      const ace=boss&&i===count-1;
      if(ace)e.type=byAircraft(plan?.ace??this.enemyKit[(rosterShift+this.enemyKit.length-1)%this.enemyKit.length]);
      const skill=this.pilots[i]=ace?aceSkill:normal;
      e.ace=ace;e.experience=skill.experience;
      e.maxHp=minimumEnemyDurability+Math.round(2.3*(Math.min(60,step)-1)+64*Math.log1p(Math.max(0,step-60)/18)+
        this.loadout.rank*10+(ace?92+step*1.25:0));
      e.enginePower=skill.engine;e.handling=skill.handling;e.firepower=skill.power;e.role=i;
      const defense=skill.counter&&e.type.safety?new CountermeasureSystem(e.type.era,ace?1:0):null;
      if(defense){
        defense.stocks.flare=Math.min(defense.stocks.flare,1);
        defense.stocks.chaff=Math.min(defense.stocks.chaff,e.experience===3?2:1);
      }
      this.shields[i]=defense;
      const wing=formation==='pincer'?1.55:formation==='screen'?.73:1;
      const r=distance+i*Math.min(205,p.type.trim*.94),offset=i===0?94:(i%2?1:-1)*(155+i*169)*wing;
      const enterX=p.position.x+x*r-z*offset,enterZ=p.position.z+z*r+x*offset;
      const bx=this.endless?enterX:clamp(enterX,-22500,22500),bz=this.endless?enterZ:clamp(enterZ,-22500,22500);
      // The lead intercepts the player on the initial pass while the wingmen peel away.
      const facing=!this.op.lesson&&i===0&&this.wave===1?
        Math.atan2(p.position.x-bx,bz-p.position.z):Math.atan2(x,-z)+(i%2?.17:-.09);
      e.reset(bx,Math.max(this.world.at(bx,bz,this.time)+150,p.position.y+38+i*(formation==='stack'?138:54)),bz,facing,e.type.trim*.82);
      e.cooldown=this.time+2.1-skill.pressure*.62+i*.54;e.missiles=Math.min(e.missiles,skill.magazine);
    }
    this.locked=null;this.manual=null;this.lockProgress=0;
    if(this.wave>1){
      if(this.endless){
        const rounds=p.roundsLimit??p.type.ammo;
        const air=p.missilesLimit??p.type.missiles;
        p.cannon=Math.min(rounds,p.cannon+Math.ceil(rounds*.54));
        p.missiles=Math.min(air,p.missiles+Math.ceil(air*.60));
      }
      if(this.endless||this.loadout.repair)this.defense.replenish();
      this.notify({kind:'wave',at:p.position,side:0});
    }
  }
  acquire(manual=false){
    const p=this.player;
    if(manual){
      const available=this.enemies.filter(e=>e.alive&&distance(e.position,p.position)<this.radar);
      this.manual=available[available.indexOf(this.manual??this.locked!)+1]??null;
    }
    let chosen:Airframe|null=null,score=.83;
    for(const e of this.enemies){
      if(!e.alive||this.manual&&this.manual!==e)continue;
      e.position.subtractToRef(p.position,delta);
      const range=delta.length();
      if(range>Math.min(this.radar,this.missile.range+(this.loadout.configuration?.lockRange??0))||range<70)continue;
      const direction=Vector3.Dot(delta,p.forward)/range;
      const rank=direction+(e===this.locked?.085:0)-range*.000008;
      if(direction>(e===this.locked?.747:.807)&&rank>score&&!this.world.terrainMasks(
        p.position.x,p.position.y,p.position.z,e.position.x,e.position.y,e.position.z)){score=rank;chosen=e;}
    }
    if(this.manual&&!this.manual.alive)this.manual=null;
    if(this.locked!==chosen)this.lockProgress=0;
    this.locked=chosen;
  }
  nextWeapon(){
    if(!this.weapons.length)return;
    this.weapon=this.weapons[(this.weapons.indexOf(this.weapon)+1)%this.weapons.length];
  }
  counter(){
    if(!this.active||!this.player.alive)return;
    const result=this.defense.release(this.warning,this.groups.missile,this.player,this.time,this.loadout.rank);
    this.notify({kind:'counter',at:this.player.position,side:0,defense:this.defense.last??undefined,cue:result});
  }
  bombLanding(out:Vector3){
    const p=this.player,[x,y,z]=groundMount(p.type);
    local.set(x,y,z).rotateByQuaternionToRef(p.orientation,local).addInPlace(p.position);
    const pointAt=(t:number)=>out.set(local.x+p.velocity.x*t,
      local.y+(p.velocity.y-releaseDropSpeed)*t-.5*standardGravity*t*(t+FLIGHT_STEP),local.z+p.velocity.z*t);
    for(let t=.2;t<=13.8;t+=.2){
      pointAt(t);
      if(out.y>this.world.at(out.x,out.z,this.time+t))continue;
      let above=t-.2,below=t;
      for(let i=0;i<7;i++){
        const middle=(above+below)*.5;
        pointAt(middle);
        if(out.y>this.world.at(out.x,out.z,this.time+middle))above=middle;
        else below=middle;
      }
      pointAt(below);out.y=this.world.at(out.x,out.z,this.time+below);return true;
    }
    return false;
  }
  groundLock(){
    if(this.groundWeapon!=='shorebolt'||!this.player.bombs)return null;
    let best:GroundTarget|null=null,score=.77;
    const p=this.player;
    for(const g of this.targetPoints){
      if(!g.alive)continue;
      g.position.subtractToRef(p.position,delta);
      const range=delta.length();
      if(range<130||range>3900)continue;
      const aim=Vector3.Dot(p.forward,delta)/range-range*.00002;
      if(aim>score&&!this.world.terrainMasks(p.position.x,p.position.y,p.position.z,g.position.x,g.position.y,g.position.z)){
        score=aim;best=g;
      }
    }
    return best;
  }
  fire(p:Airframe,weapon:ProjectileKind,target:Airframe|null=null){
    const t=p.type;
    if(!p.alive)return;
    if(weapon==='gun'&&(!p.cannon||this.time<p.gunsAt||!t.guns.length))return;
    if(weapon==='missile'&&(!p.missiles||!target?.alive||this.time<p.missileAt||!t.rails.length))return;
    if(weapon==='bomb'&&(!p.bombs||this.time<p.bombAt))return;
    const guided=weapon==='bomb'&&p.side===0&&this.groundWeapon==='shorebolt';
    const ground=guided?this.groundLock():null;
    if(guided&&!ground)return;
    if(p.side===0)this.weapon=weapon;
    const group=this.groups[weapon],q=group[this.fireCursor[weapon]++%group.length];
    q.live=true;q.owner=p;q.target=target;q.generation=target?.generation??0;q.age=0;q.smokeAt=0;
    q.serial=++this.shotSerial;q.guidance='tracking';q.decoy=null;q.decoySerial=0;q.reacquireAt=0;
    q.profile=p.side===0?this.missile:p.type.era==='cold'||(q.serial+p.role)%3===0?missiles.flarewing:
      p.experience===3&&p.type.safety?missiles.skylance:missiles.interceptor;
    q.seeker=q.profile.seeker;q.guidedGround=guided;
    if(ground)q.aim.copyFrom(ground.position);
    q.direction.copyFrom(p.forward);
    let hardpoint:number[];
    if(weapon==='gun'){
      const interval=gunCycle(t,p.side===0?this.loadout.configuration?.gunRate:1)*(p.side===0?1:1.81-p.experience*.19);
      p.gunsAt=Math.max(p.gunsAt,this.time-FLIGHT_STEP)+interval;p.cannon--;
      hardpoint=t.guns[p.cannon%t.guns.length];q.time=1.3;
      if(p.side===0)this.stats.fired++;
    }else if(weapon==='missile'){
      p.missileAt=this.time+(p.side===0?missileCycle(this.loadout.configuration?.missileRate):6.4);p.missiles--;
      hardpoint=t.rails[p.missiles%t.rails.length];q.time=q.profile.life;
      q.velocity.copyFrom(q.direction).scaleInPlace(q.profile.speed*.39);
      if(p.side===0){this.stats.missile++;this.lastPracticalLaunch=q.profile.id;}
      else if(target===this.player)this.warning.fired(this.time);
    }else{
      p.bombAt=this.time+(guided?1.45:.61);p.bombs--;q.time=guided?10.5:13.8;
      hardpoint=groundMount(t);
      q.velocity.set(0,-releaseDropSpeed,0);
      if(guided)q.velocity.copyFrom(q.direction).scaleInPlace(285);if(p.side===0)this.stats.bomb++;
    }
    local.set(hardpoint[0],hardpoint[1],hardpoint[2]).rotateByQuaternionToRef(p.orientation,local);
    q.position.copyFrom(p.position).addInPlace(local);q.previous.copyFrom(q.position);
    if(weapon==='gun'){
      const [,speed,error]=cannonFor(t);
      gunSight(p.position,p.forward,delta).subtractInPlace(q.position).normalize();
      const phase=q.serial*2.39996323,scatter=error*(.15+.85*(q.serial%7)/7)*(p.side===0?1:1.65-p.experience*.14);
      spreadVector.set(Math.cos(phase)*scatter,Math.sin(phase)*scatter,0).rotateByQuaternionToRef(p.orientation,spreadVector);
      q.direction.copyFrom(delta).addInPlace(spreadVector).normalize();
      q.velocity.copyFrom(q.direction).scaleInPlace(speed+Vector3.Dot(p.velocity,q.direction));
    }else q.velocity.addInPlace(p.velocity);
    this.notify({kind:weapon,at:q.position,side:p.side,track:q.serial,direction:q.direction,profile:weapon==='missile'?q.profile:undefined});
  }
  impact(point:Vector3,side:number,weapon:ProjectileKind|'crash',scale=1,direction?:Vector3){
    this.notify({kind:'impact',at:point,surface:this.world.classify(point.x,point.z) as Surface,weapon,side,scale,direction});
  }
  project(dt:number){
    const jammed=this.time<this.defense.jamUntil;
    for(const q of this.projectiles){
      const owner=q.owner;
      if(!q.live||!owner)continue;
      q.age+=dt;q.previous.copyFrom(q.position);
      const missile=q.kind==='missile',bomb=q.kind==='bomb';
      if(missile&&q.age>thrustDuration)MissileGuidance.update(q,dt,this.time,q.target===this.player?jammed:!!q.target&&this.time<(this.shields[q.target.id-1]?.jamUntil??0));
      else if(q.guidedGround&&q.age>.14){
        q.aim.subtractToRef(q.position,delta).normalize();
        q.direction.addInPlaceFromFloats(delta.x*dt*1.82,delta.y*dt*1.82,delta.z*dt*1.82).normalize();
        const speed=Math.min(guidedStrike.speed,q.velocity.length()+dt*370);
        q.velocity.copyFrom(q.direction).scaleInPlace(speed);
        if(q.age>q.smokeAt){q.smokeAt=q.age+.072;this.notify({kind:'trail',at:q.position,side:owner.side,track:q.serial,direction:q.direction});}
      }
      else if(bomb||missile)q.velocity.y-=(bomb?standardGravity:15)*dt;
      q.position.addInPlaceFromFloats(q.velocity.x*dt,q.velocity.y*dt,q.velocity.z*dt);
      const floor=terrainContact(this.world,q.previous,q.position,this.time);
      let fraction=floor;
      let struck:Airframe|null=null,ground:GroundTarget|null=null;
      let decoy=false;
      if(missile&&q.guidance==='decoy'&&q.decoy){
        q.previous.subtractToRef(q.decoy.position,shotStart);q.position.subtractToRef(q.decoy.position,shotEnd);
        const entry=ellipsoid(shotStart,shotEnd,22,22,22);
        if(entry<fraction){fraction=entry;decoy=true;}
      }
      if(!bomb)for(const target of owner.side===1?this.friendlies:this.enemies){
        if(!target.alive)continue;
        const entry=aircraftContact(q.previous,q.position,target,missile);
        if(entry<fraction){fraction=entry;struck=target;decoy=false;}
      }
      const player=owner.side===0;
      if(player&&this.targetPoints.length&&(!bomb&&!missile||q.guidedGround))for(const target of this.targetPoints){
        if(!target.alive)continue;
        q.previous.subtractToRef(target.position,shotStart);q.position.subtractToRef(target.position,shotEnd);
        const entry=ellipsoid(shotStart,shotEnd,q.guidedGround?30:14,q.guidedGround?21:8,q.guidedGround?29:13);
        if(entry<fraction){fraction=entry;ground=target;struck=null;decoy=false;}
      }
      if(!Number.isFinite(fraction)){
        if(missile&&q.age>q.smokeAt){q.smokeAt=q.age+.058;this.notify({kind:'trail',at:q.position,side:owner.side,track:q.serial,direction:q.direction});}
        if(q.age>q.time)q.live=false;
        continue;
      }
      Vector3.LerpToRef(q.previous,q.position,fraction,q.position);
      q.live=false;
      const scale=missile?1.40+q.profile.shape*.26:.51;
      if(struck){
        if(player){if(missile)this.stats.missileHit++;else this.stats.hit++;}
        // Resolve the contact on the body for cues, even when the fuse went off outside it.
        q.position.subtractToRef(struck.position,delta);delta.normalize();
        eventAt.copyFrom(struck.position).addInPlaceFromFloats(delta.x*struck.type.span*.24,delta.y*struck.type.span*.12,delta.z*struck.type.length*.28);
        const strength=missile?(player?q.profile.damage:missileDamage(owner.type,q.profile,0)*.61*owner.firepower):
          gunDamage(owner.type,owner.firepower)*(player?1:.87);
        const terminal=struck!==this.player&&struck.hp<=strength*(owner.side===1?this.difficulty.enemyPower:1);
        this.notify({kind:'hit',at:q.position,strike:eventAt,side:owner.side,track:q.serial,weapon:q.kind,profile:missile?q.profile:undefined,scale,target:struck,terminal,direction:q.direction});
        this.damage(struck,strength,owner.side,owner.position,eventAt);
      }else if(decoy){
        this.notify({kind:'hit',at:q.position,side:owner.side,track:q.serial,weapon:'missile',scale:.53});
      }else{
        if(fraction===floor)q.position.y=this.world.at(q.position.x,q.position.z,this.time);
        if(player&&bomb&&!q.guidedGround){
          for(const target of this.targetPoints){
            if(!target.alive||Vector3.DistanceSquared(q.position,target.position)>81**2)continue;
            this.damageTarget(target,125);
            ground=target;
          }
        }else if(ground)this.damageTarget(ground,q.guidedGround?guidedStrike.damage*(this.loadout.configuration?.missilePower??1):gunDamage(owner.type,owner.firepower));
        if(ground){
          if(bomb)this.stats.bombHit++;else if(missile)this.stats.missileHit++;else this.stats.hit++;
          this.notify({kind:'impact',at:q.position,side:0,track:q.serial,weapon:q.kind,surface:'structure',scale:bomb?1.35:.73,direction:q.direction});
        }else this.impact(q.position,owner.side,q.kind,bomb?1.6:missile?1.38:.48,q.direction);
      }
    }
  }
  private damageTarget(target:GroundTarget,amount:number){
    target.hp=Math.max(0,target.hp-amount);
    if(target.hp>0)return;
    target.alive=false;this.lost++;this.stats.kills++;
    this.stats.types['地面目标']=(this.stats.types['地面目标']??0)+1;
  }
  damage(p:Airframe,raw:number,from:number,source?:Vector3,point?:Vector3){
    if(!p.alive)return;
    const armor=p===this.player?1-.065*this.loadout.armor:1;
    if(p!==this.player)p.hp=Math.max(0,p.hp-raw*(from===1?this.difficulty.enemyPower:1));
    if(p!==this.player&&point){
      point.subtractToRef(p.position,localStrike);
      p.orientation.conjugateToRef(inverted);
      localStrike.rotateByQuaternionToRef(inverted,localStrike);
      const zone=Math.abs(localStrike.x)>p.type.span*.135?localStrike.x>0?'right':'left':localStrike.z>0?'engine':'body';
      p.damage[zone]=clamp(p.damage[zone]+raw/p.maxHp*1.3,0,1);
    }
    p.hitTime=this.time;
    p.hitIntensity=clamp(raw/72,.28,1)*armor;
    if(source)source.subtractToRef(p.position,p.hitFrom).normalize();
    if(!p.hp)this.destroy(p,from,false,p.id===9?'运输机未能抵达安全区':'机体失去控制');
  }
  destroy(p:Airframe,from:number,ground:boolean,reason:string){
    if(!p.alive)return;
    p.alive=false;p.hp=0;p.down=ground?0:1;
    if(p.side===1){
      this.lost++;
      if(from===0){this.stats.kills++;this.stats.types[p.type.name]=(this.stats.types[p.type.name]??0)+1;}
    }else if(p.side===0||this.op.kind==='escort')this.end(false,reason);
    if(ground)this.impact(p.position,p.side,'crash',clamp(p.speed/114+p.type.length*.036,.8,2.8));
    else this.notify({kind:'breakup',at:p.position,side:p.side,weapon:'crash',scale:1.25,target:p});
  }
  ground(p:Airframe){
    if(p.grounded)return;
    const h=this.world.at(p.position.x,p.position.z,this.time),clearance=Math.max(.85,p.type.gearClearance);
    const nearAirfield=p.position.y<105&&Math.abs(p.position.x-base.x)<340&&Math.abs(p.position.z-base.z)<920;
    const close=nearAirfield||p.position.y-h<p.type.span*.78+18;
    const p0=p.previous,p1=p.position;
    if(close){
      const crossing=terrainContact(this.world,p0,p1,this.time,clearance+.13);
      if(crossing<=1){
        if(p===this.player&&p.gear>.85&&this.world.runway(p1.x,p1.z)&&Math.abs(p.forward.x)<.36&&p.velocity.y>-11&&
          Math.abs(rightTilt(p))<.21&&p.speed<p.type.trim*1.05){
          p1.y=h+clearance;p.grounded=true;p.velocity.y=0;return;
        }
        Vector3.LerpToRef(p0,p1,crossing,p1);p1.y=this.world.at(p1.x,p1.z,this.time);
        this.destroy(p,2,true,p1.y<1?'战机坠入海面':'机体撞击地面');return;
      }
      const half=.48*p.type.span;
      for(let i=0;i<4;i++){
        tipNow.set(i===0?-half:i===1?half:0,-.04,i===2?-.45*p.type.length:i===3?.43*p.type.length:.08*p.type.length);
        tipNow.rotateByQuaternionToRef(p.previousOrientation,tipBefore).addInPlace(p0);
        tipNow.rotateByQuaternionToRef(p.orientation,tipNow).addInPlace(p1);
        const hit=terrainContact(this.world,tipBefore,tipNow,this.time,.09);
        if(hit>1)continue;
        Vector3.LerpToRef(tipBefore,tipNow,hit,p1);p1.y=this.world.at(p1.x,p1.z,this.time);
        this.destroy(p,2,true,i<2?(p1.y<1?'机翼触及海面':'机翼撞击地形'):'机体擦碰障碍');return;
      }
    }
    if(p===this.player&&this.op.kind!=='free'&&Math.hypot(p.position.x,p.position.z)>23900)this.end(false,'已超出任务空域');
  }
  enemy(e:Airframe,dt:number){
    if(!e.alive)return;
    const p=this.player,o=this.op,t=this.time;
    const victim=this.ally.alive&&o.kind==='escort'&&e.role===2?this.ally:p;
    const range=distance(e.position,victim.position);
    if(o.lesson==='counter'){
      victim.position.subtractToRef(e.position,delta).normalize();
      if(t>=this.nextThreat&&range>470&&range<3100&&Vector3.Dot(delta,e.forward)>.82){
        this.fire(e,'missile',p);this.nextThreat=t+4.5;
      }
      const controls=e.controls;controls.assist=false;controls.throttle=.60;
      pursuit(e,p.position,controls);
      advanceFlight(e,controls,dt,this.world,t);this.ground(e);return;
    }
    const skill=this.pilots[e.id-1],shield=this.shields[e.id-1];
    if(shield)shield.advance(dt);
    for(const q of this.groups.missile){
      if(!q.live||q.target!==e||q.guidance!=='tracking'||q.generation!==e.generation)continue;
      const warningRange=510+e.experience*330;
      if(Vector3.DistanceSquared(q.position,e.position)>warningRange**2)continue;
      e.evadeUntil=Math.max(e.evadeUntil,t+.54+e.experience*.31);
      if(shield&&t>=shield.readyAt&&q.age>skill.reaction){
        this.enemyWarning.update(this.groups.missile,e,t,t<shield.jamUntil);
        const cue=shield.release(this.enemyWarning,this.groups.missile,e,t,3-e.experience);
        if(cue==='diverted'||cue==='resisted'||cue==='released')
          this.notify({kind:'counter',at:e.position,side:1,defense:shield.last??undefined,cue});
      }
      break;
    }
    const sensed=range<skill.radar&&!this.world.terrainMasks(e.position.x,e.position.y,e.position.z,victim.position.x,victim.position.y,victim.position.z);
    if(range<850){
      victim.velocity.subtractToRef(e.velocity,shotStart);
      victim.position.subtractToRef(e.position,delta);
      const closest=-Vector3.Dot(delta,shotStart)/Math.max(1,shotStart.lengthSquared());
      if(closest>0&&closest<1.7&&delta.addInPlaceFromFloats(shotStart.x*closest,shotStart.y*closest,shotStart.z*closest).lengthSquared()<120**2)
        e.evadeUntil=Math.max(e.evadeUntil,t+1.35);
    }
    if(sensed&&e.experience>=2&&this.locked===e&&this.lockProgress>.68&&this.time-e.hitTime<2.7)
      e.evadeUntil=Math.max(e.evadeUntil,t+.65);
    const c=e.controls;
    c.assist=false;c.boost=false;c.gun=false;
    const leader=this.enemies.find(unit=>unit.alive)??e;
    const tactic=choosePass(e,t,t-this.during,range,leader,skill.pressure);
    if(sensed||tactic===Tactic.Formation||tactic===Tactic.Evade||tactic===Tactic.Extend){
      planPass(e,leader,victim,range,tactic,this.aiPoint,c);
    }else{
      const sweeping=Math.sin(t*.39+e.role*1.14)*.66;
      this.aiPoint.copyFrom(e.position).addInPlaceFromFloats(e.forward.x*880+e.forward.z*840*sweeping,58,
        e.forward.z*880-e.forward.x*840*sweeping);
      c.throttle=.76;
    }
    const attack=sensed&&(tactic===Tactic.Intercept||tactic===Tactic.Flank);
    const missileType=e.type.era==='cold'||(this.shotSerial+1+e.role)%3===0?missiles.flarewing:
      e.experience===3&&e.type.safety?missiles.skylance:missiles.interceptor;
    let locking=false;
    if(attack){
      const gun=cannonFor(e.type),lead=range/gun[1]*skill.lead;
      this.gunLead.copyFrom(victim.position).addInPlaceFromFloats(victim.velocity.x*lead,victim.velocity.y*lead,victim.velocity.z*lead).subtractInPlace(e.position);
      const aim=Vector3.Dot(e.forward,this.gunLead.normalize());
      if(t-this.during>.83&&range<900+e.experience*120&&aim>.987-e.experience*.003){
        c.gun=true;
      }else if(range<1030&&e.cannon&&e.experience>=1){
        this.aiPoint.copyFrom(e.position).addInPlaceFromFloats(this.gunLead.x*range,this.gunLead.y*range,this.gunLead.z*range);
      }
      victim.position.subtractToRef(e.position,delta).normalize();
      const align=Vector3.Dot(e.forward,delta);
      const jammed=victim===p&&missileType.seeker==='radar'&&t<this.defense.jamUntil;
      locking=!!e.missiles&&range>580&&range<Math.min(skill.range,missileType.range)&&align>skill.aim&&!jammed&&t>e.cooldown-skill.reaction;
      if(locking){
        e.lockAt??=t;
        if(victim===p)this.warning.lock(t);
        if(t>=e.cooldown&&t-e.lockAt>=skill.reaction){
          e.cooldown=t+skill.interval+e.role*.98;e.lockAt=null;
          this.fire(e,'missile',victim);
        }
      }
    }
    if(!locking)e.lockAt=null;
    const h=this.world.at(e.position.x+e.forward.x*390,e.position.z+e.forward.z*390,t);
    this.aiPoint.y=Math.max(this.aiPoint.y,h+139);
    if(e.ace&&e.hp<e.maxHp*.5&&tactic===Tactic.Intercept&&e.speed<e.type.trim*1.08){
      c.throttle=1;c.boost=!!e.type.boost;
    }
    if(!this.endless&&Math.hypot(e.position.x,e.position.z)>22900)this.aiPoint.set(0,960,0);
    pursuit(e,this.aiPoint,c);
    if(e.position.y<this.world.at(e.position.x,e.position.z,t)+66)c.pitch=Math.max(.34,c.pitch);
    advanceFlight(e,c,dt,this.world,t);this.ground(e);if(c.gun)this.fire(e,'gun');
  }
  closePass(a:Airframe,b:Airframe){
    if(!a.alive||!b.alive)return false;
    return aircraftContact(a.previous,a.position,b,false,true)<Infinity||
      aircraftContact(b.previous,b.position,a,false,true)<Infinity;
  }
  step(dt:number,input:Controls){
    if(!this.active)return;
    this.time+=dt;
    const p=this.player;
    advanceFlight(p,input,dt,this.world,this.time);this.ground(p);
    this.defense.advance(dt);
    this.stats.distance+=distance(p.position,p.previous);this.stats.peak=Math.max(this.stats.peak,p.speed);this.stats.altitude=Math.max(this.stats.altitude,p.position.y);
    if(!this.active)return;
    this.acquire();
    if(this.locked&&p.missiles){
      const previous=this.lockProgress;
      this.lockProgress=Math.min(1,previous+dt/(this.missile.acquire*(this.enemies.some(x=>x.alive&&x.type.id==='ea6b')?1.86:1)));
      if(previous<1&&this.lockProgress===1)this.notify({kind:'lock',at:p.position,side:0});
    }
    if(input.gun)this.fire(p,'gun');
    if(input.missile&&this.lockProgress===1)this.fire(p,'missile',this.locked);
    if(input.bomb)this.fire(p,'bomb');
    for(const e of this.enemies)this.enemy(e,dt);
    if(this.ally.alive){
      this.aiPoint.set(-180+Math.sin(this.time*.068)*360,Math.max(224,this.world.at(this.ally.position.x,this.ally.position.z-300,this.time)+140),this.ally.position.z-650);
      const c=this.ally.controls;c.assist=true;c.throttle=.62;pursuit(this.ally,this.aiPoint,c);
      advanceFlight(this.ally,c,dt,this.world,this.time);this.ground(this.ally);
      if(this.ally.alive&&this.ally.position.z<(this.op.engagement?this.safeLine:-7800))this.end(true,'运输机已脱离交战区');
    }
    for(const e of this.enemies)if(this.closePass(p,e)){
      this.destroy(e,2,false,'空中碰撞');this.destroy(p,2,false,'空中碰撞');return;
    }
    this.project(dt);
    if(this.warning.update(this.groups.missile,p,this.time,this.time<this.defense.jamUntil))this.notify({kind:'warn',at:p.position,side:1,scale:this.warning.stage});
    this.advanceWrecks(dt);
    if(this.op.kind==='train'){
      if(distance(p.position,this.gates[this.gate])<185){
        this.gate++;
        if(this.gate>=this.gates.length)this.end(true,'三个航标均已通过');
      }
    }
    if(this.op.length&&this.time>this.op.length)this.end(false,'已超出挑战时限');
    if(this.active&&(this.endless||this.op.kind==='air'||this.op.kind==='escort')&&this.enemies.every(e=>!e.alive)){
      this.cleared=this.wave;
      if(this.endless||this.wave<this.waves.length)this.spawn();
      else this.end(true,'全部敌机已击落');
    }
    if(this.op.kind==='ground'&&this.lost>=this.total)this.end(true,'训练靶全部摧毁');
  }
  advanceWrecks(dt:number){
    for(const e of this.enemies){
      if(!e.down)continue;
      e.previous.copyFrom(e.position);e.previousOrientation.copyFrom(e.orientation);
      e.down+=dt;
      e.velocity.y-=19*dt;e.position.addInPlaceFromFloats(e.velocity.x*dt,e.velocity.y*dt,e.velocity.z*dt);
      Quaternion.RotationAxisToRef(ahead,(.53+(e.damage.right-e.damage.left)*1.8)*dt,orientation);e.orientation.multiplyInPlace(orientation).normalize();
      const floor=terrainContact(this.world,e.previous,e.position,this.time);
      if(floor<=1||e.down>16){
        if(floor<=1){
          Vector3.LerpToRef(e.previous,e.position,floor,e.position);
          e.position.y=this.world.at(e.position.x,e.position.z,this.time);
          this.impact(e.position,e.side,'crash',1.35);
        }
        e.down=0;
      }
    }
  }
  end(win:boolean,reason:string){
    if(!this.active)return;
    this.active=false;this.win=win;this.reason=reason;
  }
  report():Debrief{
    const s=this.stats,win=this.win,progress=clamp((this.op.kind==='train'?this.gate:this.lost)/Math.max(1,this.total),0,1);
    const accuracy=(h:number,n:number)=>n?Math.round(h/n*100):null;
    const precision=(s.hit+s.missileHit*9+s.bombHit*8)/Math.max(1,s.fired+s.missile*9+s.bomb*8);
    const score=Math.round((win?3600:450)+progress*3100+s.kills*180+this.player.hp/this.player.maxHp*1650+Math.min(1,precision)*1850);
    return {operation:this.op,win,reason:this.reason,time:this.time,distance:s.distance,peak:s.peak,altitude:s.altitude,hp:this.player.hp,
      kills:s.kills,accuracy:accuracy(s.hit,s.fired),missileAccuracy:accuracy(s.missileHit,s.missile),bombAccuracy:accuracy(s.bombHit,s.bomb),
      score,evaded:this.defense.successes,grade:score>=10800?'王牌':score>=8300?'优秀':score>=5100?'合格':'待精进',
      credits:Math.round((score*.105+(win?450:60))*this.difficulty.reward),xp:Math.round(48+s.kills*20+progress*112+(win?88:0)+score/57+(this.op.engagement?.tier??0)*13),types:{...s.types}};
  }
}
