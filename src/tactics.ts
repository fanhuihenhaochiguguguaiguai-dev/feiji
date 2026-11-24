import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Airframe, Controls } from './flight';

export const enum Tactic { Intercept, Extend, Formation, Evade, Flank }
export function choosePass(e:Airframe,time:number,sinceWave:number,range:number,lead:Airframe,pressure:number){
  if(time<e.evadeUntil)return Tactic.Evade;
  const energy=e.speed/Math.max(1,e.type.trim),hurt=1-e.hp/e.maxHp;
  const age=time-e.atStage;
  if(e.phase===Tactic.Extend&&age<2.0+pressure*.68)return Tactic.Extend;
  const extension=(range<170+pressure*55?1.15:0)+(energy<.63&&range<970?.68:0)+
    (hurt>.55&&range<540&&!e.ace?.44:0)+Math.min(.59,age/(18-pressure*4));
  const flank=e.role>0&&range>610&&range<2500?.31+pressure*.34+(e.role===2?.10:0):0;
  if(e.phase!==Tactic.Extend&&extension>Math.max(.71,flank)){
    e.phase=Tactic.Extend;e.atStage=time;return Tactic.Extend;
  }
  if(e.phase===Tactic.Extend){e.phase=Tactic.Intercept;e.atStage=time;}
  if(e!==lead&&lead.alive&&sinceWave<1.25+e.role*.42)return Tactic.Formation;
  return flank>.56&&!e.ace?Tactic.Flank:Tactic.Intercept;
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
  if(move===Tactic.Flank){
    const edge=side*Math.min(410,range*.23);
    point.addInPlaceFromFloats(-victim.forward.z*edge,90+e.role*42,victim.forward.x*edge);
  }
  else if(range>2100)point.addInPlaceFromFloats(side*115*e.role,e.role*69,0);
  c.throttle=range<340?.52:range<1450?.84:1;c.boost=range>2530;
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
