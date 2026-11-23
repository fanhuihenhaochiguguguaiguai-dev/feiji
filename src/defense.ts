import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Airframe } from './flight';
import { clamp } from './terrain';
import type { MissileProfile } from './items';

export type Seeker='infrared'|'radar';
export type DefenseKind='flare'|'chaff'|'ecm';
export type DefenseCue='ready'|'cooldown'|'empty'|'clear'|'released'|'diverted'|'resisted';

export const defenseNames:Record<DefenseKind,string>={flare:'热诱饵',chaff:'箔条',ecm:'电子干扰'};
export const seekerNames:Record<Seeker,string>={infrared:'红外',radar:'雷达'};
export interface Decoy {
  readonly position:Vector3;
  readonly velocity:Vector3;
  life:number;
  kind:DefenseKind;
  serial:number;
}
export interface GuidedTrack {
  live:boolean;
  seeker:Seeker;
  profile:MissileProfile;
  guidance:'tracking'|'decoy'|'lost';
  target:Airframe|null;
  generation:number;
  serial:number;
  decoy:Decoy|null;
  decoySerial:number;
  reacquireAt:number;
  age:number;
  readonly position:Vector3;
  readonly velocity:Vector3;
  readonly direction:Vector3;
}
const aim=new Vector3(),axis=new Vector3(),identity=Quaternion.Identity(),rotation=Quaternion.Identity();
const percentile=(n:number)=>{const t=Math.sin(n*58.5347919+.19)*43758.5453;return t-Math.floor(t);};

export class MissileGuidance {
  static update(shot:GuidedTrack,dt:number,time:number,jammed:boolean){
    const target=shot.target;
    if(!target?.alive||target.generation!==shot.generation)shot.guidance='lost';
    if(shot.guidance==='lost'&&shot.reacquireAt>0&&time>=shot.reacquireAt){
      shot.reacquireAt=0;
      if(target?.alive&&target.generation===shot.generation){
        target.position.subtractToRef(shot.position,aim);
        if(aim.lengthSquared()<2600**2&&Vector3.Dot(aim.normalize(),shot.direction)>.82&&!jammed)shot.guidance='tracking';
      }
    }
    const decoy=shot.decoy;
    if(shot.guidance==='decoy'&&(!decoy?.life||decoy.serial!==shot.decoySerial))shot.guidance='lost';
    const speed=shot.velocity.length();
    const tracked=shot.guidance==='tracking'?target:shot.guidance==='decoy'?decoy:null;
    if(tracked){
      const lead=clamp(Vector3.Distance(tracked.position,shot.position)*.41/Math.max(220,speed),.033,.9);
      aim.copyFrom(tracked.position).addInPlaceFromFloats(tracked.velocity.x*lead,tracked.velocity.y*lead,tracked.velocity.z*lead).subtractInPlace(shot.position).normalize();
      const angle=Math.acos(clamp(Vector3.Dot(aim,shot.direction),-1,1));
      if(angle>.0001){
        Quaternion.FromUnitVectorsToRef(shot.direction,aim,rotation);
        Quaternion.SlerpToRef(identity,rotation,Math.min(1,dt*shot.profile.turn/angle),rotation);
        shot.direction.rotateByQuaternionToRef(rotation,shot.direction).normalize();
      }
    }
    shot.velocity.copyFrom(shot.direction).scaleInPlace(Math.min(shot.profile.speed,speed+dt*shot.profile.acceleration));
  }
}
export class MissileWarningSystem {
  threat:GuidedTrack|null=null;
  distance=0;
  stage:0|1|2|3|4=0;
  private lockedAt=-5;
  private firedAt=-5;
  private serial=0;
  lock(now:number){this.lockedAt=now;}
  fired(now:number){this.firedAt=now;}
  update(tracks:GuidedTrack[],p:Airframe,time:number,jammed:boolean){
    this.threat=null;
    let min=3600**2;
    for(const shot of tracks){
      if(!shot.live||shot.target!==p||shot.generation!==p.generation||shot.guidance!=='tracking')continue;
      const range=Vector3.DistanceSquared(shot.position,p.position);
      if(range>=min)continue;
      p.position.subtractToRef(shot.position,aim);
      if(shot.age>.24&&Vector3.Dot(aim,shot.direction)<0)continue;
      min=range;this.threat=shot;
    }
    this.distance=this.threat?Math.sqrt(min):0;
    const stage=this.threat?(this.distance<720?4:this.distance<1920?3:2):time-this.firedAt<1.10?2:!jammed&&time-this.lockedAt<.76?1:0;
    const nextSerial=this.threat?.serial??0;
    const changed=stage>this.stage||(stage>=2&&nextSerial!==this.serial);
    this.stage=stage;this.serial=nextSerial;
    return changed;
  }
}
export class CountermeasureSystem {
  readonly stocks:Record<DefenseKind,number>;
  readonly capacity:Record<DefenseKind,number>;
  readonly cloud:Decoy[]=Array.from({length:24},()=>({position:new Vector3(),velocity:new Vector3(),life:0,kind:'flare',serial:0}));
  readonly totalCooldown=2.65;
  readyAt=0;
  jamUntil=0;
  count=0;
  successes=0;
  last:DefenseKind|null=null;
  cue:DefenseCue='ready';
  private cursor=0;
  constructor(era:string,grade=2,pod=0){
    const modern=['modern','stealth','support'].includes(era);
    this.capacity={flare:modern?6+grade+pod*2:era==='cold'?4+grade+pod*2:0,
      chaff:modern?4+grade+pod:era==='cold'?3+grade+pod:0,ecm:modern?grade:0};
    this.stocks={...this.capacity};
  }
  canReplenish(){return this.stocks.flare<this.capacity.flare||this.stocks.chaff<this.capacity.chaff;}
  replenish(){
    this.stocks.flare=Math.min(this.capacity.flare,this.stocks.flare+2);
    this.stocks.chaff=Math.min(this.capacity.chaff,this.stocks.chaff+2);
  }
  get reserves(){return this.stocks.flare+this.stocks.chaff+this.stocks.ecm;}
  next(warning:MissileWarningSystem){
    if(warning.threat?.seeker==='infrared')return 'flare';
    if(warning.threat?.seeker==='radar')return this.stocks.ecm>0&&(warning.distance>1710||!this.stocks.chaff)?'ecm':'chaff';
    if(warning.stage>0&&this.stocks.ecm)return 'ecm';
    return null;
  }
  release(warning:MissileWarningSystem,shots:GuidedTrack[],p:Airframe,time:number,rank:number):DefenseCue{
    if(time<this.readyAt)return this.cue='cooldown';
    if(!this.reserves)return this.cue='empty';
    const type=this.next(warning);
    if(!type)return this.cue='clear';
    if(!this.stocks[type])return this.cue='empty';
    this.stocks[type]--;this.last=type;this.readyAt=time+this.totalCooldown;this.count++;
    if(type==='ecm')this.jamUntil=time+3.1;
    let cloud:Decoy|null=null;
    if(type!=='ecm'){
      for(let i=0;i<(type==='flare'?6:4);i++){
        const d=this.cloud[this.cursor++%this.cloud.length];
        const side=i%2===0?-1:1,reach=type==='flare'?1.4:1.1;
        axis.set(side*(2.2+i*.57),-.58,.98+i*.36).rotateByQuaternionToRef(p.orientation,axis);
        d.position.copyFrom(p.position).addInPlace(axis);
        axis.set(side*(22+i*2.3)*reach,-10-i*1.3,29+i*5.7).rotateByQuaternionToRef(p.orientation,axis);
        d.velocity.copyFrom(p.velocity).scaleInPlace(type==='flare'?.39:.57).addInPlace(axis);
        d.serial++;d.kind=type;d.life=type==='flare'?1.95+i*.10:3.65;
        if(i===2)cloud=d;
      }
    }
    let applicable=0,diverted=0;
    for(const q of shots){
      if(!q.live||q.guidance!=='tracking'||q.target!==p||q.generation!==p.generation)continue;
      if((type==='flare')!==(q.seeker==='infrared'))continue;
      applicable++;
      const range=Vector3.Distance(q.position,p.position);
      q.position.subtractToRef(p.position,aim).normalize();
      const heading=Vector3.Dot(aim,p.forward);
      const optimal=clamp((range-82)/315,0,1)*clamp((3700-range)/1100,0,1);
      const score=clamp(.18+optimal*.47+(rank===0?.28:rank===1?.14:0)+(type==='ecm'?.075:heading<.25?.095:0),.06,.95);
      if(range<74||percentile(q.serial+this.count*31.71+rank*.091)>score)continue;
      if(cloud){
        q.decoy=cloud;q.decoySerial=cloud.serial;q.guidance='decoy';
      }else{
        q.guidance='lost';q.reacquireAt=time+3.6;
      }
      diverted++;
    }
    this.successes+=diverted;
    return this.cue=diverted?'diverted':applicable?'resisted':'released';
  }
  advance(dt:number){
    for(const d of this.cloud){
      if(d.life<=0)continue;
      d.life=Math.max(0,d.life-dt);
      d.velocity.y-=dt*(d.kind==='flare'?23:3);
      d.position.addInPlaceFromFloats(d.velocity.x*dt,d.velocity.y*dt,d.velocity.z*dt);
    }
  }
}
