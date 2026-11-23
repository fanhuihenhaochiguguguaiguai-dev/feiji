import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Airframe, Controls } from './flight';

export const enum Tactic { Intercept, Extend, Formation, Evade, Defend }
export function choosePass(e:Airframe,time:number,sinceWave:number,range:number,lead:Airframe){
  if(time<e.evadeUntil)return Tactic.Evade;
  const hurt=e.hp<e.maxHp*.39;
  if(e.phase===Tactic.Extend&&time-e.atStage<2.65+e.experience*.13)return Tactic.Extend;
  if(e.phase!==Tactic.Extend&&(range<165+e.experience*44||hurt&&e.experience>=2&&range<530||time-e.atStage>10.4-e.experience*.55||(e.speed<e.type.stall*1.20&&range<690))) {
    e.phase=Tactic.Extend;e.atStage=time;return Tactic.Extend;
  }
  if(e.phase===Tactic.Extend){e.phase=Tactic.Intercept;e.atStage=time;}
  if(e.role>0&&lead.alive&&sinceWave<2.6+e.role*.48)return Tactic.Formation;
  return e.role===2&&range>1660?Tactic.Defend:Tactic.Intercept;
}
export function planPass(e:Airframe,lead:Airframe,victim:Airframe,range:number,move:Tactic,point:Vector3,c:Controls){
  const side=e.role%2?1:-1;
  if(move===Tactic.Extend||move===Tactic.Evade){
    const lateral=move===Tactic.Evade?745:440;
    point.copyFrom(e.position).addInPlaceFromFloats(e.forward.x*420+e.forward.z*lateral*side,
      (move===Tactic.Evade?122:223)+e.role*34,e.forward.z*420-e.forward.x*lateral*side);
    c.throttle=1;c.boost=move===Tactic.Evade;return;
  }
  if(move===Tactic.Formation){
    const breadth=side*(240+e.role*13),offset=345-e.role*47;
    point.copyFrom(lead.position).addInPlaceFromFloats(lead.forward.x*offset-lead.forward.z*breadth,51+e.role*35,lead.forward.z*offset+lead.forward.x*breadth);
    c.throttle=.76;return;
  }
  const seconds=Math.min(2.32,range/(Math.max(90,e.speed)+victim.speed*.62))*(.72+e.experience*.105);
  point.copyFrom(victim.position).addInPlaceFromFloats(victim.velocity.x*seconds,victim.velocity.y*seconds,victim.velocity.z*seconds);
  if(move===Tactic.Defend)point.addInPlaceFromFloats(side*375,208,111);
  else if(range>2100)point.addInPlaceFromFloats(side*115*e.role,e.role*69,0);
  c.throttle=range<340?.52:range<1450?.84:1;c.boost=range>2530;
}

export const enemyProfiles=[
  {armor:1,power:1,engine:.94,handling:.95,radar:3950,lead:.32,reaction:.88,interval:10.2,range:2670,aim:.962,magazine:2,counter:0},
  {armor:1.15,power:1.10,engine:1.01,handling:1.04,radar:4540,lead:.65,reaction:.66,interval:8.9,range:3230,aim:.946,magazine:3,counter:1},
  {armor:1.31,power:1.17,engine:1.09,handling:1.14,radar:5320,lead:.82,reaction:.53,interval:7.6,range:3880,aim:.932,magazine:4,counter:2},
  {armor:1.48,power:1.26,engine:1.18,handling:1.26,radar:6070,lead:.96,reaction:.37,interval:6.3,range:4610,aim:.918,magazine:5,counter:3}
] as const;
