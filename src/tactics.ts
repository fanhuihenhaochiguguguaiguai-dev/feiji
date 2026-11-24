import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Airframe, Controls } from './flight';
import type { Terrain } from './terrain';
import { clamp } from './terrain';

export const enum Tactic { Intercept, Extend, Formation, Evade, Flank, Search }
export const enum Maneuver { Lead, Lag, HighYoYo, LowYoYo, Outside, Inside, Vertical, Bracket }
class Track {
  readonly position=new Vector3();
  readonly velocity=new Vector3();
  readonly acceleration=new Vector3();
  last=-Infinity;
  reset(){this.last=-Infinity;this.acceleration.setAll(0);}
  observe(target:Airframe,now:number){
    const dt=now-this.last;
    if(dt>.05&&dt<.8){
      target.velocity.subtractToRef(this.velocity,this.acceleration).scaleInPlace(1/dt);
      const limit=35/Math.max(35,this.acceleration.length());this.acceleration.scaleInPlace(limit);
    }else this.acceleration.setAll(0);
    this.position.copyFrom(target.position);this.velocity.copyFrom(target.velocity);this.last=now;
  }
  extrapolate(time:number,out:Vector3){
    const dt=clamp(time-this.last,0,7),acceleration=Math.min(2,dt)*dt*.22;
    out.copyFrom(this.position).addInPlaceFromFloats(this.velocity.x*dt+this.acceleration.x*acceleration,
      this.velocity.y*dt+this.acceleration.y*acceleration,this.velocity.z*dt+this.acceleration.z*acceleration);
  }
}
export class SquadronBlackboard {
  private readonly contact=new Track();
  readonly tracks=Array.from({length:4},()=>new Track());
  reset(){this.contact.reset();for(const t of this.tracks)t.reset();}
  observe(e:Airframe,target:Airframe,time:number){
    this.tracks[e.id-1].observe(target,time);
    if(time-this.contact.last>.065)this.contact.observe(target,time);
  }
  read(e:Airframe,leader:Airframe,time:number){
    const known=this.tracks[e.id-1];
    if(time-known.last<1.5)return known;
    if(leader.alive&&leader!==e&&Vector3.DistanceSquared(leader.position,e.position)<2200**2&&time-this.contact.last<1.1)return this.contact;
    return known;
  }
}
export class TacticalPilot {
  private readonly point=new Vector3();
  private readonly forecast=new Vector3();
  private readonly candidate=new Vector3();
  private readonly path=new Vector3();
  private next=-Infinity;
  private maneuver=Maneuver.Lead;
  private lastTactic=Tactic.Search;
  private throttle=.76;
  private boost=false;
  planned=0;
  reset(){this.next=-Infinity;this.maneuver=Maneuver.Lead;this.lastTactic=Tactic.Search;this.planned=0;}

  private branch(e:Airframe,leader:Airframe,sinceWave:number,range:number,time:number,pressure:number,sensed:boolean){
    if(e.evadeUntil>time)return Tactic.Evade;
    if(e.phase===Tactic.Extend&&time-e.atStage<1.4+pressure*.74)return Tactic.Extend;
    const trim=e.speed/Math.max(1,e.type.trim);
    if(range<155+pressure*70||range<1100&&trim<.62||
      e.ace&&e.hp<e.maxHp*.30&&trim<.91&&range<1400)return Tactic.Extend;
    if(e!==leader&&leader.alive&&sinceWave<1.22+e.role*.42)return Tactic.Formation;
    if(!sensed)return Tactic.Search;
    return e.role>0&&range>630&&range<3100&&pressure>.25?Tactic.Flank:Tactic.Intercept;
  }
  private intercept(e:Airframe,track:Track,terrain:Terrain,range:number,time:number,pressure:number,flank:boolean){
    const bossPhase=e.ace?(e.hp<e.maxHp*.35?3:e.hp<e.maxHp*.68?2:1):0;
    const horizon=3+Math.min(3,pressure*2.45+bossPhase*.27),count=Math.min(8,4+Math.round(pressure*3)+Number(bossPhase>=2));
    const turn=Math.min(horizon,Math.max(.45,range/Math.max(95,e.speed+track.velocity.length()*.48)));
    const mag=Math.hypot(track.velocity.x,track.velocity.z)||1;
    const flankX=track.velocity.z/mag,flankZ=-track.velocity.x/mag,side=e.role%2?1:-1;
    const energy=e.speed/e.type.trim,room=Math.min(680,range*.28);
    let cost=Infinity;
    for(let i=0;i<count;i++){
      const horizonShift=[0,-.52,.31,.24,.46,.48,.75,.79][i];
      const lateral=[0,0,side*.19,side*.13,side*.68,-side*.57,0,side][i]*room;
      const altitude=[0,0,room*.62,-room*.38,room*.22,room*.29,room*.85,room*.52][i];
      track.extrapolate(time+Math.max(.2,turn+horizonShift),this.forecast);
      this.candidate.copyFrom(this.forecast).addInPlaceFromFloats(flankX*lateral,altitude+(bossPhase===2?56:0),flankZ*lateral);
      const floor=terrain.field(this.candidate.x,this.candidate.z)+155;
      this.candidate.y=Math.max(floor,this.candidate.y);
      this.candidate.subtractToRef(e.position,this.path);
      const distance=this.path.length(),alignment=Vector3.Dot(e.forward,this.path)/Math.max(1,distance);
      let clearance=0;
      for(let step=1;step<=3;step++){
        const proportion=Math.min(1,e.speed*horizon*step/(3*Math.max(distance,1)));
        const h=terrain.field(e.position.x+this.path.x*proportion,e.position.z+this.path.z*proportion)+120;
        clearance=Math.max(clearance,h-(e.position.y+this.path.y*proportion));
      }
      const climb=Math.max(0,this.path.y)/Math.max(100,distance);
      const separation=flank?Math.max(0,Math.abs(lateral)-room*.21)*-.00072:Math.abs(lateral)*.00046;
      const turns=(1-alignment)*(1.20-Math.min(1,pressure)*.17);
      const vertical=(energy<.81?1.8:.49)*climb+(i===Maneuver.Lag&&range>650?.16:0);
      const bias=i===this.maneuver?-.045:0;
      const phase=bossPhase>=2&&i===Maneuver.Vertical&&energy>.92?-.29:0;
      const penalty=turns+clearance*.037+separation+vertical+bias+phase+Math.abs(horizonShift)*.074;
      if(penalty<cost){cost=penalty;this.point.copyFrom(this.candidate);this.maneuver=i;}
    }
    this.throttle=range<330?.55:range<1450?.86:1;
    this.boost=range>2500||bossPhase===3&&energy<1.08;
  }
  command(e:Airframe,leader:Airframe,victim:Airframe,sensed:boolean,range:number,pressure:number,time:number,during:number,terrain:Terrain,board:SquadronBlackboard,point:Vector3,c:Controls){
    const tactic=this.branch(e,leader,time-during,range,time,pressure,sensed);
    if(tactic!==e.phase){e.phase=tactic;e.atStage=time;}
    if(time>=this.next||tactic!==this.lastTactic){
      this.next=time+1/(2+3*Math.min(1,pressure));this.lastTactic=tactic;this.planned++;
      if(sensed)board.observe(e,victim,time);
      const track=board.read(e,leader,time),side=e.role%2?1:-1;
      this.boost=false;
      if(tactic===Tactic.Evade||tactic===Tactic.Extend){
        const lateral=tactic===Tactic.Evade?720:390;
        this.point.copyFrom(e.position).addInPlaceFromFloats(e.forward.x*440+e.forward.z*lateral*side,
          (tactic===Tactic.Evade?92:132)+e.role*24,e.forward.z*440-e.forward.x*lateral*side);
        this.throttle=1;this.boost=tactic===Tactic.Evade&&e.speed>e.type.stall;
      }else if(tactic===Tactic.Formation){
        const breadth=side*(230+e.role*18),back=345-e.role*53;
        this.point.copyFrom(leader.position).addInPlaceFromFloats(leader.forward.x*back-leader.forward.z*breadth,47+e.role*44,leader.forward.z*back+leader.forward.x*breadth);
        this.throttle=.81;
      }else if(tactic!==Tactic.Search){
        this.intercept(e,track,terrain,range,time,pressure,tactic===Tactic.Flank);
      }else if(time-track.last<4.2){
        track.extrapolate(time+1.4,this.point);this.point.y+=55;this.throttle=.83;
      }else{
        const scan=Math.sin(time*.39+e.role*1.14)*.57;
        this.point.copyFrom(e.position).addInPlaceFromFloats(e.forward.x*960+e.forward.z*840*scan,62,e.forward.z*960-e.forward.x*840*scan);
        this.throttle=.76;
      }
    }
    point.copyFrom(this.point);c.throttle=this.throttle;c.boost=this.boost;
    return tactic;
  }
}

export const enemyProfiles=[
  {armor:1,power:1,engine:.94,handling:.95,radar:3950,lead:.32,reaction:.88,interval:10.2,range:2670,aim:.962,magazine:2,counter:0},
  {armor:1.15,power:1.10,engine:1.01,handling:1.04,radar:4540,lead:.65,reaction:.66,interval:8.9,range:3230,aim:.946,magazine:3,counter:1},
  {armor:1.31,power:1.17,engine:1.09,handling:1.14,radar:5320,lead:.82,reaction:.53,interval:7.6,range:3880,aim:.932,magazine:4,counter:2},
  {armor:1.48,power:1.26,engine:1.18,handling:1.26,radar:6070,lead:.96,reaction:.37,interval:6.3,range:4610,aim:.918,magazine:5,counter:3}
] as const;

export function enemyTuning(step:number,rank:number){
  const pressure=Math.max(0,Math.min(1.2,(step-1)/59+(rank-1)*.045));
  const tier=Math.min(3,pressure*3);
  const veteran=Math.min(1,Math.log1p(Math.max(0,step-60)/24)*.38);
  const a=enemyProfiles[Math.floor(tier)],b=enemyProfiles[Math.min(3,Math.ceil(tier))];
  const mix=(key:keyof typeof a)=>a[key]+(b[key]-a[key])*(tier%1);
  return {pressure,experience:Math.floor(tier),engine:mix('engine')+veteran*.07,handling:mix('handling')+veteran*.18,power:mix('power'),
    radar:mix('radar'),lead:mix('lead')+veteran*.08,reaction:mix('reaction')-veteran*.13,interval:mix('interval')-veteran*.9,range:mix('range'),
    aim:mix('aim'),magazine:Math.floor(mix('magazine')+.30),counter:Math.min(3,Math.floor(tier+.40))};
}
