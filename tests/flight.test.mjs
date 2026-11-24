import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
const {outputFiles}=await build({stdin:{
  contents:`export { Sortie } from './src/sortie'; export { byAircraft,fleet,operation,operations } from './src/data';
    export { cannonFor,gunDamage,gunSight } from './src/ordnance';
    export { chapters } from './src/campaign'; export { levelProgress,levelThreshold,pilotLevel } from './src/progression';
    export { missiles,missileDamage,minimumEnemyDurability,rewards } from './src/items'; export { freshProfile,normalizeProfile,loadProfile,combatConfiguration,equipItem,detachWeapon,resetGear,sortieBlock,saveProfile,claimReward,claimRewards,rewardStatus,buyItem,research,unlockAircraft,buyUpgrade,recordSortie } from './src/profile';
    export { advanceFlight, FlightPose, Airframe, FLIGHT_STEP, idle, above, right } from './src/flight';
    export { CountermeasureSystem, MissileGuidance, MissileWarningSystem } from './src/defense';
    export { mapRadar } from './src/tactical-radar';
    export { OceanSpectrum, ShallowWake, oceanSize } from './src/ocean-solver';
    export { Terrain,registerTerrain } from './src/terrain';
    export { Vector3,Quaternion } from '@babylonjs/core/Maths/math.vector';`,
  resolveDir:process.cwd(),loader:'ts'
},bundle:true,write:false,platform:'node',format:'esm'});
const {Sortie, chapters, operations, levelProgress, levelThreshold, pilotLevel, byAircraft, fleet, cannonFor, gunDamage, gunSight, operation, advanceFlight, FlightPose, Airframe, FLIGHT_STEP, idle, right, Vector3, Quaternion,
  Terrain, registerTerrain, OceanSpectrum, ShallowWake, oceanSize, CountermeasureSystem, MissileGuidance, MissileWarningSystem,mapRadar,missiles,missileDamage,minimumEnemyDurability,rewards,freshProfile,normalizeProfile,loadProfile,combatConfiguration,equipItem,detachWeapon,resetGear,sortieBlock,saveProfile,claimReward,claimRewards,rewardStatus,buyItem,research,unlockAircraft,buyUpgrade,recordSortie}=await import('data:text/javascript;base64,'+Buffer.from(outputFiles[0].contents).toString('base64'));
for(const [id,seed] of [['sundown',413],['frost',704],['storm',116]]){
  const b=await readFile('public/world/'+id+'.height');
  registerTerrain(seed,b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
}
const dt=FLIGHT_STEP;
const loadout={rank:0,armor:0,engine:0,stores:0,repair:false,radar:false,runway:false,diagnostics:true};
const bombRange={...operation('s03'),kind:'ground',engagement:{...operation('s03').engagement,groups:2,altitude:176}};
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));

function clearWithOrdnance(s){
  const p=s.player;
  let wave=0;
  while(s.active&&wave!==s.wave){
    wave=s.wave;
    const targets=s.enemies.filter(e=>e.alive);
    targets.forEach((e,i)=>e.reset(i*275,3050,450,0,0));
    for(const e of targets){
      p.position.set(e.position.x,3050,1100);p.previous.copyFrom(p.position);
      p.orientation.set(0,0,0,1);p.previousOrientation.copyFrom(p.orientation);p.forward.set(0,0,-1);p.velocity.set(0,0,-160);
      if(p.missiles){
        s.fire(p,'missile',e);
        for(let i=0;i<110&&e.alive&&s.groups.missile.some(q=>q.live);i++){s.time+=dt;s.project(dt);}
      }
      for(let i=0;i<500&&e.alive;i++){
        s.time+=dt;s.fire(p,'gun');s.project(dt);
      }
      assert(!e.alive,'positioned airframe must be hit by live rounds');
      for(const q of s.groups.gun)q.live=false;
    }
    s.step(dt,idle);
    if(s.op.kind==='free')break;
  }
  return s.report();
}

test('distinct structure from 2000, real armor, hostile kills and different acceleration',()=>{
  const type=byAircraft('f16'),a=new Airframe(0,type,0),b=new Airframe(1,type,0),terrain=new Terrain(413);
  a.reset(0,1600,0,0);b.reset(0,1600,0,0);
  for(let i=0;i<270;i++){advanceFlight(a,{...idle,boost:true},dt,terrain,i*dt);advanceFlight(b,idle,dt,terrain,i*dt);}
  assert(a.speed>b.speed+44);
  assert(b.position.z<-540);
  const baseline=new Sortie(operation('free'),type,loadout,()=>{});
  const protectedFrame=new Sortie(operation('free'),type,{...loadout,armor:2},()=>{});
  assert.equal(baseline.player.hp,3200);
  assert.equal(protectedFrame.player.maxHp,3200);
  assert.equal(new Sortie(operation('free'),byAircraft('dr1'),loadout,()=>{}).player.hp,2000);
  assert.equal(new Sortie(operation('free'),byAircraft('j20'),loadout,()=>{}).player.hp,4200);
  baseline.damage(baseline.player,160,1);
  protectedFrame.damage(protectedFrame.player,160,1);
  assert(protectedFrame.player.hp>baseline.player.hp&&baseline.player.hp<3200);
  baseline.damage(baseline.player,99999,1);
  assert(baseline.player.hp===0&&!baseline.active&&!baseline.win);
  assert.equal(baseline.reason,'战机被击落');
  assert(byAircraft('spitfire').trim<type.trim&&byAircraft('spitfire').missiles===0);
});

test('continuous climb, inverted segment and full roll without teleport',()=>{
  const a=new Airframe(0,byAircraft('f16'),0),terrain=new Terrain(413),r=new Vector3();
  a.reset(0,2670,0,0);
  const command={...idle,roll:.86,assist:false};
  let seen=false,back=false;
  for(let i=0;i<335;i++){
    advanceFlight(a,command,dt,terrain,i*dt);
    right.rotateByQuaternionToRef(a.orientation,r);
    if(r.y>.73)seen=true;
    if(seen&&r.y<-.73)back=true;
    assert(Vector3.Distance(a.previous,a.position)<9);
  }
  assert(seen&&back);
  let initial=a.position.y;
  a.reset(0,initial,0,0);
  for(let i=0;i<110;i++)advanceFlight(a,{...idle,pitch:.42},dt,terrain,i*dt);
  assert(a.position.y>initial+26);
});

test('physical tracer strikes the moving sea and an aircraft collides with water',()=>{
  const events=[],s=new Sortie(operation('free'),byAircraft('f16'),loadout,e=>events.push({kind:e.kind,surface:e.surface,weapon:e.weapon}));
  const p=s.player;
  p.position.set(40,48,2190);p.forward.set(0,-.48,-.877);p.velocity.set(0,-120,-105);
  s.fire(p,'gun');
  for(let i=0;i<130;i++){s.time+=dt;s.project(dt);}
  assert(events.some(e=>e.kind==='impact'&&e.surface==='water'&&e.weapon==='gun'));
  p.position.y=0;
  s.ground(p);assert(!s.active&&!s.win);
  assert(events.some(e=>e.kind==='impact'&&e.surface==='water'&&e.weapon==='crash'));
});

test('infrared flare and radar chaff branch guidance, ECM can break early lock, counter can fail',()=>{
  const p=new Airframe(0,byAircraft('f16'),0);p.reset(0,530,0,0);
  const make=(seeker,serial,distance)=>({live:true,seeker,serial,profile:missiles[seeker==='infrared'?'flarewing':'interceptor'],guidance:'tracking',target:p,generation:p.generation,
    decoy:null,decoySerial:0,reacquireAt:0,age:.3,position:new Vector3(27,530,distance),direction:new Vector3(0,0,-1),velocity:new Vector3(0,0,-450)});
  const infrared=new Set(),radar=new Set();
  for(let serial=1;serial<36;serial++){
    for(const [seeker,cues] of [['infrared',infrared],['radar',radar]]){
      const s=new CountermeasureSystem('modern'),w=new MissileWarningSystem(),shot=make(seeker,serial,860);
      assert(w.update([shot],p,1,false));
      assert.equal(w.stage,3);
      cues.add(s.release(w,[shot],p,1,1));
      const kind=seeker==='infrared'?'flare':'chaff';
      assert.equal(s.stocks[kind],kind==='flare'?7:5);
      assert(s.cloud.some(d=>d.kind===kind&&d.life>0));
      assert.equal(s.release(w,[shot],p,1.1,1),'cooldown');
      if(shot.guidance==='decoy'){
        assert(shot.decoy);
        const before=shot.direction.clone();
        for(let i=0;i<44;i++){s.advance(dt);MissileGuidance.update(shot,dt,1+i*dt,false);}
        assert(Vector3.DistanceSquared(before,shot.direction)>.00001);
        w.update([shot],p,2,false);assert.equal(w.threat,null);
      }
    }
  }
  for(const sample of [infrared,radar]){assert(sample.has('diverted'));assert(sample.has('resisted'));}
  const s=new CountermeasureSystem('modern'),w=new MissileWarningSystem();
  w.lock(6);w.update([],p,6,false);
  assert.equal(s.release(w,[],p,6,0),'released');
  assert.equal(s.stocks.ecm,1);
  assert(s.jamUntil>9);
  assert.equal(new CountermeasureSystem('ww1').reserves,0);
});

function makePilot(s){
  const p=s.player,aim=new Vector3(),dest=new Vector3(),side=new Vector3(),inv=new Quaternion(),command={...idle,assist:false};
  const separation=new Vector3(),closure=new Vector3();
  let target,serial=-1,avoidUntil=0,avoidSide=1,recovering=false;
  return ()=>{
    if(!target?.alive||target.generation!==serial){
      target=s.enemies.filter(e=>e.alive).sort((a,b)=>Vector3.DistanceSquared(a.position,p.position)-Vector3.DistanceSquared(b.position,p.position))[0];
      serial=target?.generation??-1;
    }
    const floor=s.world.at(p.position.x+p.forward.x*370,p.position.z+p.forward.z*370,s.time);
    right.rotateByQuaternionToRef(p.orientation,side);
    if(!target)return {...idle,throttle:.71};
    const danger=p.position.y<floor+145,range=Vector3.Distance(target.position,p.position);
    recovering=p.speed<p.type.trim*(recovering?.80:.61);
    if(recovering){
      Object.assign(command,{yaw:0,roll:clamp(-side.y*1.2,-.55,.55),
        pitch:clamp(-p.forward.y*1.6+(danger?.32:-.09),-.57,.62),throttle:1,boost:true,gun:false,missile:false});
      return command;
    }
    const t=Math.min(.55,range/(cannonFor(p.type)[1]+p.speed));
    dest.copyFrom(target.position).addInPlaceFromFloats(target.velocity.x*t,target.velocity.y*t,target.velocity.z*t);
    for(const e of s.enemies){
      if(!e.alive||Vector3.DistanceSquared(p.position,e.position)>650**2)continue;
      e.position.subtractToRef(p.position,separation);e.velocity.subtractToRef(p.velocity,closure);
      const arrival=-Vector3.Dot(separation,closure)/Math.max(1,closure.lengthSquared());
      if(arrival>0&&arrival<1.4&&separation.addInPlaceFromFloats(closure.x*arrival,closure.y*arrival,closure.z*arrival).lengthSquared()<55**2){
        if(avoidUntil<=s.time)avoidSide=Vector3.Dot(separation,side)>0?-1:1;
        avoidUntil=Math.max(avoidUntil,s.time+.52);
      }
    }
    const avoiding=avoidUntil>s.time;
    if(avoiding)dest.copyFrom(p.position).addInPlaceFromFloats(p.forward.x*280+side.x*400*avoidSide,215,p.forward.z*280+side.z*400*avoidSide);
    dest.y=Math.max(dest.y,floor+155);
    p.orientation.conjugateToRef(inv);
    aim.copyFrom(dest).subtractInPlace(p.position).normalize().rotateByQuaternionToRef(inv,aim);
    const turn=Math.abs(aim.x)<.22&&aim.z>.14?.57:aim.x;
    command.pitch=clamp(aim.y*2,-.86,.92);if(danger)command.pitch=Math.max(command.pitch,.36);
    command.yaw=clamp(-turn*1.63,-.97,.97);
    command.roll=clamp(-turn*.57-side.y*.72,-.65,.65);
    command.throttle=range<300?.46:range<930?.69:.92;
    command.boost=range>2180&&!danger;
    command.gun=range<1000&&aim.z<-.995&&!danger&&!avoiding;
    command.missile=s.lockProgress>=1&&range<2890&&range>133&&
      !s.groups.missile.some(q=>q.live&&q.owner===p&&q.target===s.locked&&q.generation===q.target.generation);
    return command;
  };
}

test('three real combat waves, guidance, ammunition, damage and victory',()=>{
  const events={};
  const s=new Sortie(operation('s01'),byAircraft('f16'),loadout,e=>{const k=e.kind+e.side;events[k]=(events[k]??0)+1;});
  const r=clearWithOrdnance(s);
  assert(s.win,JSON.stringify({reason:s.reason,time:s.time,wave:s.wave,hp:s.player.hp,stats:s.stats,events}));
  assert.equal(s.wave,3);assert(r.kills>=4);assert(s.stats.missileHit>=Math.floor(r.kills*.5));
  assert(r.score>5500);
  console.log(JSON.stringify({seconds:+s.time.toFixed(2),wave:s.wave,kills:r.kills,guns:s.stats.fired,missiles:s.stats.missile,
    missileHits:s.stats.missileHit,enemyLaunches:events.missile1??0,remaining:r.hp}));
});

const memory=new Map();
globalThis.localStorage={getItem:key=>memory.get(key)??null,setItem:(key,value)=>memory.set(key,value)};

test('A–F: combat result, claim, stock, guided loadout, engine, hardware, livery and recovery',()=>{
  memory.clear();
  const p=freshProfile(),type=byAircraft('f16');
  assert(!claimReward(p,'first-win'));
  const source=new Sortie(operation('s01'),type,loadout,()=>{});
  clearWithOrdnance(source);
  assert(source.win);
  assert(recordSortie(p,source.report(),'f16')>0);
  assert(claimReward(p,'first-win'));
  assert.equal(p.inventory.flarewing,1);
  for(let i=0;i<8;i++)assert(!claimReward(p,'first-win'));
  assert.equal(p.inventory.flarewing,1);
  assert.equal(equipItem(p,'f16','flarewing'),'装备配置已保存');
  assert.equal(equipItem(p,'dr1','flarewing'),'装备配置已保存');
  const base=combatConfiguration(p,'f16'),stock=p.inventory.alloy;
  assert.equal(buyUpgrade(p,'f16','engine'),'改装已装配');
  assert.equal(p.inventory.alloy,stock-1);
  const faster=combatConfiguration(p,'f16');
  assert(faster.engine>base.engine);
  const slow=new Sortie(operation('free'),type,{...loadout,configuration:base},()=>{});
  const fast=new Sortie(operation('free'),type,{...loadout,configuration:faster},()=>{});
  for(let i=0;i<190;i++){slow.step(dt,{...idle,boost:true});fast.step(dt,{...idle,boost:true});}
  assert(fast.player.speed>slow.player.speed+2);
  const fire=new Sortie(operation('s01'),type,{...loadout,configuration:faster},()=>{});
  fire.fire(fire.player,'missile',fire.enemies[0]);
  const shot=fire.groups.missile.find(q=>q.live);
  assert.deepEqual(shot.profile,missiles.flarewing);
  assert.equal(shot.time,missiles.flarewing.life);
  assert.equal(shot.seeker,'infrared');
  assert.equal(fire.lastPracticalLaunch,'flarewing');
  for(let i=0;i<440&&fire.stats.missileHit===0;i++)fire.step(dt,idle);
  assert(fire.stats.missileHit>0);
  assert.equal(unlockAircraft(p,'a10'),'该机型已解锁');
  assert.match(unlockAircraft(p,'gripen'),/达到 Lv.7/);
  p.xp=levelThreshold(7);
  assert.equal(unlockAircraft(p,'gripen'),'已解锁');
  assert(combatConfiguration(p,'gripen').aircraft==='gripen');
  p.distance=20100;assert(claimReward(p,'tideline'));
  assert.equal(equipItem(p,'f16','bronze-sky'),'装备配置已保存');
  assert.equal(combatConfiguration(p,'f16').paint,'#af7956');
  assert.equal(research(p,'horizon'),'缺少前置研发');
  assert.match(research(p,'signal'),/研发完成/);
  assert(combatConfiguration(p,'f16').radar>faster.radar);
  const migrated=normalizeProfile({...p,inventory:{...p.inventory,reserve:2}});
  assert.equal(migrated.credits,p.credits+600);
  assert.equal(migrated.inventory.reserve,undefined);
  assert.equal(normalizeProfile(migrated).credits,migrated.credits);
  memory.set('pixel-sky-af-v4','{broken');
  const restored=loadProfile();
  assert.equal(combatConfiguration(restored,'f16').paint,'#af7956');
  assert.equal(combatConfiguration(restored,'f16').missile.id,'flarewing');
  assert.equal(combatConfiguration(restored,'f16').engine,faster.engine);
  assert(restored.unlocked.includes('gripen'));
  assert(!claimReward(restored,'tideline'));
  const old=normalizeProfile({selected:'f16',unlocked:['gripen'],paint:{f16:'navy'},credits:777,
    settings:{quality:'low'},improvements:{'f16:engine':2}});
  assert.equal(combatConfiguration(old,'f16').paint,'#526e91');
  assert.equal(old.credits,777);
  assert.equal(old.settings.quality,'low');
  assert.equal(combatConfiguration(old,'f16').engine,1.12);
});

test('bulk reward receipts report only the committed grants and cannot pay twice',()=>{
  memory.clear();
  const p=freshProfile(),write=localStorage.setItem;
  p.sorties=1;p.victories=1;p.xp=365;
  const before=p.credits;
  try {
    localStorage.setItem=()=>{throw Error('storage denied');};
    assert.deepEqual(claimRewards(p,['first','first-win','pass-1']),[]);
    assert.equal(p.credits,before);
    assert.equal(p.claimed.length,0);
  } finally {
    localStorage.setItem=write;
  }
  const receipts=claimRewards(p,['first','first-win','first-win','pass-1','pass-2','pass-3']);
  assert.deepEqual(receipts.map(r=>r.id),['first','first-win','pass-1','pass-2']);
  assert.equal(p.credits,before+700+545+330);
  assert.equal(p.inventory.flarewing,1);
  assert.deepEqual(claimRewards(p,receipts.map(r=>r.id)),[]);
  assert.deepEqual(loadProfile().claimed,p.claimed);
});

test('the same lattice crosses chunk borders and guards the actual aircraft hangar',()=>{
  const t=new Terrain(413);
  for(const {x,z} of t.blocks){
    for(let n=0;n<64;n+=4){
      assert(Math.abs(t.node(x+n+1,z)-(.75*t.node(x+n,z)+.25*t.node(x+n+4,z)))<=.28);
      assert(Math.abs(t.node(x,z+n+1)-(.75*t.node(x,z+n)+.25*t.node(x,z+n+4)))<=.28);
    }
  }
  assert(Math.abs(t.field(-2970,1295)-32.065)<1e-8);
  assert(t.field(-2753,995)>55&&t.field(-2655,995)<t.field(-2753,995));
  assert(t.terrainMasks(-2753,41,905,-2753,44,1085));
  assert(t.obstruction(-2820,43,995,-2700,43,995,0)<=1);
  assert(t.obstruction(-2820,90,995,-2700,90,995,0)>1);
  const s=new Sortie(operation('free'),byAircraft('f16'),loadout,()=>{});
  s.player.previous.set(-2811,46,995);s.player.position.set(-2804,46,995);
  s.player.orientation.copyFrom(Quaternion.RotationAxis(new Vector3(0,1,0),-Math.PI/2));
  s.ground(s.player);
  assert(!s.player.alive);
});

test('fast opposing flight paths detect a real body contact between simulation samples',()=>{
  const s=new Sortie(operation('t04'),byAircraft('f16'),loadout,()=>{});
  const {player:p}=s,e=s.enemies[0];
  p.previous.set(-9,420,0);p.position.set(9,420,0);
  e.previous.set(9,420,0);e.position.set(-9,420,0);
  assert(s.closePass(p,e));
  e.previous.y=e.position.y=435;
  assert(!s.closePass(p,e));
});


test('graded pitch, real position change and interpolated renderer pose',()=>{
  const type=byAircraft('f16'),world=new Terrain(413);
  const run=(pull,boost=false)=>{
    const p=new Airframe(0,type,0);p.reset(0,2400,0,0,type.trim);
    let peak=0,rate=0,reacted=0;
    for(let i=0;i<135;i++){
      advanceFlight(p,{...idle,pitch:i<90?pull:0,boost},dt,world,i*dt);
      const a=Math.asin(p.forward.y)*180/Math.PI;
      if(!reacted&&a>1)reacted=(i+1)*dt;
      peak=Math.max(peak,a);rate=Math.max(rate,p.angular.x*180/Math.PI);
    }
    return {peak,rate,reacted,climb:p.position.y-2400,vertical:p.velocity.y,speed:p.speed,plane:p};
  };
  const light=run(.14),mid=run(.43),hard=run(.86),boost=run(.86,true);
  const measurements=[light,mid,hard,boost].map(({plane,...numbers})=>Object.fromEntries(Object.entries(numbers).map(([k,n])=>[k,Number(n.toFixed(3))])));
  console.log('climb',JSON.stringify(measurements));
  assert(light.peak>2&&light.peak<mid.peak&&mid.peak<hard.peak);
  assert(hard.peak>68&&hard.climb>60&&hard.vertical>45&&hard.speed>type.stall);
  assert(boost.speed>hard.speed&&boost.climb>hard.climb);
  const pose=new FlightPose().sample(hard.plane,.5),p=hard.plane;
  assert(Vector3.Distance(pose.position,p.position)>0);
  assert(Math.abs(Vector3.Distance(pose.position,p.position)-Vector3.Distance(pose.position,p.previous))<.00001);
  assert(Math.abs(pose.forward.length()-1)<.00001);

});

test('daily rewards reset by local date and use the committed sortie ledger',()=>{
  const pilot=freshProfile(),daily=rewards.find(r=>r.id==='daily-sortie');
  const sortie=new Sortie(operation('t04'),byAircraft('f16'),loadout,()=>{});
  assert(!rewardStatus(pilot,daily).earned&&!claimReward(pilot,daily.id));
  recordSortie(pilot,sortie.report(),'f16');
  assert(rewardStatus(pilot,daily).earned&&claimReward(pilot,daily.id));
  assert(rewardStatus(normalizeProfile(pilot),daily).claimed&&!claimReward(pilot,daily.id));
  pilot.daily.day='1999-1-1';
  assert(!rewardStatus(pilot,daily).earned&&!rewardStatus(pilot,daily).claimed);
  recordSortie(pilot,sortie.report(),'f16');
  assert(claimReward(pilot,daily.id)&&pilot.daily.sorties===1);
});

test('radar uses real bearing in the ownship coordinate system',()=>{
  assert.deepEqual(mapRadar(0,-1500,1,0),[0,-1500]);
  assert.deepEqual(mapRadar(1500,950,0,1),[950,-1500]);
});

test('swept shots resolve the first target along the flight path, independent of slot order',()=>{
  const events=[],s=new Sortie(operation('free'),byAircraft('f16'),loadout,e=>events.push({kind:e.kind,id:e.target?.id,at:e.at.clone()}));
  const p=s.player,far=s.enemies[0],near=s.enemies[1];
  p.reset(0,4200,0,0,180);
  far.reset(0,4200,-105,0,0);near.reset(0,4200,-52,0,0);
  far.maxHp=far.hp=130;near.maxHp=near.hp=130;
  s.fire(p,'gun');s.project(.145);
  assert.equal(far.hp,130);
  assert(near.hp<130&&near.alive);
  const impact=events.filter(e=>e.kind==='hit');
  assert.equal(impact.length,1);
  assert.equal(impact[0].id,near.id);
  assert(impact[0].at.z>-60&&impact[0].at.z<-35);
});

test('projectile surface contact prevents detecting an airframe behind the waterline',()=>{
  const events=[],s=new Sortie(operation('free'),byAircraft('f16'),loadout,e=>events.push({kind:e.kind,surface:e.surface}));
  const p=s.player,behind=s.enemies[0];
  p.reset(40,60,2190,0,0);p.forward.set(0,-1,0);
  behind.reset(40,-70,2190,0,0);
  s.fire(p,'gun');s.project(.18);
  assert.equal(behind.hp,behind.maxHp);
  assert(events.some(e=>e.kind==='impact'&&e.surface==='water'));
  assert(!events.some(e=>e.kind==='hit'));
});

test('regional damage, a single breakup signal and continuous wreck descent',()=>{
  const events=[],s=new Sortie(operation('free'),byAircraft('f16'),loadout,e=>events.push({kind:e.kind,y:e.at.y}));
  const target=s.enemies[0];
  target.reset(17,600,2900,0,100);
  const wing=new Vector3(20,600,2900);
  s.damage(target,22,0,undefined,wing);
  assert(target.damage.right>0);
  assert.equal(target.damage.left,0);
  s.damage(target,9999,0,undefined,wing);
  s.damage(target,9999,0,undefined,wing);
  assert.equal(events.filter(e=>e.kind==='breakup').length,1);
  const before=target.position.clone();
  s.advanceWrecks(.16);
  assert(target.previous.equals(before));
  assert(target.position.y<before.y&&target.down>1);
  const middle=new FlightPose().sample(target,.5);
  assert(middle.position.y<before.y&&middle.position.y>target.position.y);
});


test('resetting a flight body leaves the caller input snapshot intact',()=>{
  const plane=new Airframe(0,byAircraft('f16'),0),world=new Terrain(413);
  plane.reset(0,2100,3000,0);
  const command={...idle,pitch:.33,gun:true};
  advanceFlight(plane,command,dt,world,dt);
  plane.reset(0,2100,3000,0);
  assert.equal(command.pitch,.33);
  assert.equal(command.gun,true);
  assert.equal(plane.controls.pitch,0);
});


test('J-20 purchases two-bomb payload, persists the mount and hits both groups on the collision test range',()=>{
  memory.clear();
  const p=freshProfile(),type=byAircraft('j20'),mission=bombRange;
  p.campaign=3;
  assert.equal(p.selected,'j20');
  assert.equal(combatConfiguration(p,'j20').rounds,1200);
  assert.equal(combatConfiguration(p,'j20').airMissiles,20);
  assert.equal(sortieBlock(p,mission),'');
  assert.equal(sortieBlock(p,mission,combatConfiguration(p,'a10')),'');
  const wallet=p.credits,write=globalThis.localStorage.setItem;
  try{
    globalThis.localStorage.setItem=()=>{throw Error('storage unavailable');};
    assert.match(buyItem(p,'bomb'),/存档失败/);
    assert.equal(p.credits,wallet);
    assert.equal(p.inventory.bomb,undefined);
  }finally{globalThis.localStorage.setItem=write;}
  assert.equal(buyItem(p,'bomb'),'已放入仓库');
  assert.equal(p.credits,wallet-340);
  assert.equal(p.inventory.bomb,1);
  assert.equal(buyItem(p,'bomb'),'已经拥有');
  assert.equal(combatConfiguration(p,'j20').groundStores,0);
  assert.match(equipItem(p,'j20','bomb','missile'),/挂位/);
  assert.match(equipItem(p,'dr1','bomb','bomb'),/不支持/);
  assert.equal(equipItem(p,'j20','bomb','bomb'),'装备配置已保存');
  assert.equal(sortieBlock(p,mission),'');
  let loaded=loadProfile(),fit=combatConfiguration(loaded,'j20');
  assert.deepEqual([fit.rounds,fit.airMissiles,fit.groundStores],[1200,20,2]);
  const s=new Sortie(mission,type,{...loadout,configuration:fit},()=>{});
  const pz=s.player,alt=130,fall=(-5+Math.sqrt(25+19.62*alt))/9.81;
  for(const index of [0,3]){
    const goal=s.targetPoints[index].position;
    pz.position.set(goal.x+21,goal.y+alt+.57,goal.z+128*fall-.55);
    pz.forward.set(0,0,-1);pz.velocity.set(0,0,-128);
    pz.orientation.set(0,0,0,1);pz.speed=128;
    s.fire(pz,'bomb');
    for(let i=0;i<600;i++){s.time+=dt;s.project(dt);}
  }
  s.step(dt,idle);
  assert.equal(s.stats.bomb,2);
  assert.equal(s.stats.bombHit,2);
  assert.equal(s.stats.kills,5);
  assert.equal(s.player.bombs,0);
  assert(s.win);
  assert(recordSortie(loaded,s.report(),'j20')>0);
  loaded=loadProfile();
  assert(loaded.completed.includes('s03')&&loaded.campaign===4);
  assert(loaded.rewardedLevel>1);
  assert.equal(detachWeapon(loaded,'j20','bomb'),'已卸下，采购装备保留在仓库');
  assert.equal(loaded.inventory.bomb,1);
  assert.equal(combatConfiguration(loadProfile(),'j20').groundStores,0);
  assert.equal(sortieBlock(loaded,mission),'');
  assert.equal(resetGear(loaded,'j20','bomb'),'已恢复原厂配置');
  assert.equal(equipItem(loaded,'j20','bomb','bomb'),'装备配置已保存');
  assert.equal(combatConfiguration(loadProfile(),'j20').groundStores,2);
});

test('playable airframes have free fixed ammunition, early aircraft hit harder, and legacy empty guns recover',()=>{
  const p=normalizeProfile({...freshProfile(),version:7,loadouts:{j20:{cannon:'none',missile:'none',bomb:'none'}}});
  assert.deepEqual(p.loadouts.j20,{bomb:'none'});
  const playable=fleet.filter(a=>!a.support);
  for(const type of playable){
    const fit=combatConfiguration(p,type.id);
    assert(fit.rounds>0&&type.guns.length>0,type.id);
    assert.equal(fit.rounds,1200,type.id);
    assert.equal(fit.airMissiles,20,type.id);
  }
  const ty=byAircraft('dr1'),jet=byAircraft('f16');
  assert(gunDamage(ty)/cannonFor(ty)[0]>gunDamage(jet)/cannonFor(jet)[0]);
  assert.equal(detachWeapon(p,'j20','cannon'),'固定航炮随战机自动配发');
  assert.notEqual(buyItem(p,'cannon-jet'),'已放入仓库');
  assert.equal(p.credits,2600);
  const sortie=new Sortie(operation('s01'),jet,loadout,()=>{});
  sortie.player.cannon=27;sortie.player.missiles=1;
  sortie.spawn();
  assert.deepEqual([sortie.player.cannon,sortie.player.missiles],[27,1]);
});

test('FFT swells evolve and low flight leaves pressure ripples beyond the aircraft',()=>{
  const sea=new OceanSpectrum(),wake=new ShallowWake(),a=new Uint8Array(oceanSize**2*4),b=a.slice();
  sea.sample(0,a);sea.sample(2,b);
  assert.notDeepEqual(a,b);
  assert(a.some((v,i)=>i%4===0&&Math.abs(v-128)>12));
  const pose={time:0,x:0,z:0,altitude:65,speed:172,water:true};
  wake.step(pose,a);wake.step({...pose,time:.1,z:-17},a);
  assert(a.every((v,i)=>i%4!==1||v===0));
  for(let i=2;i<=18;i++)wake.step({...pose,time:i/10,z:-i*17,altitude:9},a);
  const foam=a.filter((_,i)=>i%4===1);
  assert(foam.some(v=>v>120));
  assert(foam.filter(v=>v>40).length>20);
  assert(a.some((v,i)=>i%4===0&&Math.abs(v-128)>20));
});

test('chapter three drone flights remain airborne and animated ground fixtures stay diagnostic-only',()=>{
  for(const id of ['s23','s24','s27','s28','s30']){
    const s=new Sortie(operation(id),byAircraft('j20'),{...loadout,rank:1,diagnostics:false},()=>{});
    assert.equal(s.op.kind,'air');assert.equal(s.targetPoints.length,0);
    assert(s.enemies.filter(e=>e.alive&&e.type.id==='shade-drone').length>=1,id);
  }
  assert.throws(()=>new Sortie(bombRange,byAircraft('j20'),{...loadout,diagnostics:false},()=>{}),/正式任务/);
});

test('empty airframe slots never become radar contacts in navigation or ground-only missions',()=>{
  for(const fixture of [operation('free'),bombRange]){
    const s=new Sortie(fixture,byAircraft('j20'),loadout,()=>{});
    assert(s.enemies.every(e=>!e.alive),fixture.id);
    s.step(dt,idle);
    assert.equal(s.locked,null,fixture.id);
    assert(s.enemies.every(e=>!e.alive),fixture.id);
  }
});

test('shared sight converges off-axis muzzles, upgrades change real firing cadence and swept impact damage',()=>{
  memory.clear();
  const p=freshProfile(),jet=byAircraft('j20'),base=combatConfiguration(p,jet.id);
  p.credits=4500;p.inventory.circuit=7;
  for(const id of ['weapons','cadence','warhead','stores'])assert.equal(buyUpgrade(p,jet.id,id),'改装已装配');
  const fit=combatConfiguration(loadProfile(),jet.id);
  assert.deepEqual([base.rounds,fit.rounds,base.airMissiles,fit.airMissiles],[1200,1320,20,21]);
  const sample=(configuration,id)=>{
    const s=new Sortie(operation('s01'),jet,{...loadout,configuration},()=>{});
    const p=s.player,target=s.enemies[0];
    s.enemies.slice(1).forEach(e=>e.alive=false);
    p.reset(10,2700,500,0,240);
    target.reset(10,2700,500-650,0,0);target.hp=500;
    gunSight(p.position,p.forward,target.position);target.previous.copyFrom(target.position);
    s.fire(p,'gun');
    const shot=s.groups.gun.find(q=>q.live),speed=shot.velocity.length();
    assert(Math.abs(shot.position.x-p.position.x)>.5);
    assert(speed>1750);
    const gunWait=p.gunsAt-s.time;
    for(let i=0;i<120&&shot.live;i++){s.time+=dt;s.project(dt);}
    const damage=500-target.hp;
    assert(damage>0&&s.stats.hit===1&&s.time<.5);
    target.reset(10,2700,500-1050,0,0);target.hp=500;
    s.fire(p,'missile',target);
    const projectile=s.groups.missile.find(q=>q.live),start=s.time;
    const missileWait=p.missileAt-start;
    for(let i=0;i<260&&projectile.live;i++){s.time+=dt;s.project(dt);}
    assert(s.stats.missileHit===1&&s.time-start<1.5,id);
    return {damage,gunWait,missileWait,missileDamage:500-target.hp,flight:s.time-start};
  };
  const before=sample(base,'stock'),after=sample(fit,'upgraded');
  assert(after.damage>before.damage&&after.gunWait<before.gunWait);
  assert(after.missileDamage>before.missileDamage&&after.missileWait<before.missileWait);
  console.log('ordnance calibration',JSON.stringify({before,after}));
});

test('late air-to-ground guidance consumes only its own station and physically reaches an aimed target',()=>{
  memory.clear();
  const p=freshProfile(),type=byAircraft('a10');p.xp=levelThreshold(6);
  assert.equal(buyItem(p,'shorebolt'),'已放入仓库');
  assert.match(equipItem(p,'a10','shorebolt','missile'),/挂位/);
  assert.equal(equipItem(p,'a10','shorebolt','bomb'),'装备配置已保存');
  const s=new Sortie(bombRange,type,{...loadout,configuration:combatConfiguration(p,'a10')},()=>{});
  const target=s.targetPoints[0],jet=s.player,g=target.position;
  jet.reset(g.x-1,g.y+188,g.z+880,0,145);
  assert(s.groundLock());
  s.fire(jet,'bomb');
  assert(s.groups.bomb.some(q=>q.live&&q.guidedGround));
  for(let i=0;i<500&&target.alive;i++){s.time+=dt;s.project(dt);}
  assert(s.stats.bombHit===1);
  assert.equal(s.stats.missileHit,0);
});

test('all 60 ordered campaigns are launchable with starter airframes when their gates are met',()=>{
  const line=operations.filter(o=>o.campaign),p=freshProfile();
  p.campaign=60;p.xp=levelThreshold(16);
  assert.equal(line.length,60);
  assert.equal(chapters.length,6);
  assert.equal(new Set(line.map(o=>o.id)).size,60);
  assert.equal(new Set(line.map(o=>JSON.stringify(o.engagement))).size,60);
  const types=new Set(line.map(o=>o.engagement.objective));
  assert.deepEqual([...types].sort(),['intercept','low','pincer','screen','sweep']);
  let previousHp=0,previousHandling=0;
  for(const op of line){
    const id='f16';
    const config=combatConfiguration(p,id);
    assert.equal(sortieBlock(p,op,config),'',op.id);
    const s=new Sortie(op,byAircraft(id),{...loadout,configuration:config},()=>{});
    assert(op.kind==='air'&&s.total>0&&s.enemies.some(e=>e.alive)&&s.targetPoints.length===0,op.id);
    assert(s.enemies[0].maxHp>previousHp&&s.enemies[0].handling>=previousHandling,op.id);
    previousHp=s.enemies[0].maxHp;previousHandling=s.enemies[0].handling;
    const starter=byAircraft('a10'),two=missileDamage(starter,missiles.skylance,3);
    const check=s.enemies.find(e=>e.alive);
    assert(check.maxHp>=minimumEnemyDurability&&check.maxHp>2*two,op.id);
    s.damage(check,two,0);s.damage(check,two,0);
    assert(check.alive,op.id);
    while(s.active){
      const wave=s.wave;
      const ace=s.enemies.filter(e=>e.alive&&e.ace);
      assert.equal(ace.length,op.campaign%10===0&&wave===s.waves.length?1:0,op.id);
      for(const e of s.enemies)if(e.alive)s.damage(e,e.hp,0);
      s.step(dt,idle);
      if(s.active)assert(s.wave===wave+1&&s.enemies.some(e=>e.alive)&&!s.win,op.id);
    }
    assert(s.win&&s.stats.kills===s.total,op.id);
  }
  const stats=['s01','s21','s60'].map(id=>new Sortie(operation(id),byAircraft('f16'),loadout,()=>{}));
  assert(stats[0].enemies[0].maxHp<stats[1].enemies[0].maxHp);
  assert(stats[1].enemies[0].handling<stats[2].enemies[0].handling);
  const last=stats[2];
  last.wave=last.waves.length-1;last.spawn();
  assert(last.enemies.some(e=>e.alive&&e.type.id==='j20'&&e.experience===3));
});

test('endless sessions vary by seed, restock only at wave boundaries, and keep generating enemies beyond the final campaign',()=>{
  const stage=operation('free'),p=byAircraft('j20'),start={...loadout,diagnostics:false,seed:342};
  const a=new Sortie(stage,p,start,()=>{}),b=new Sortie(stage,p,{...start,seed:343},()=>{});
  assert.notEqual(a.opening,b.opening);
  assert.notEqual(a.enemies[0].hp,b.enemies[0].hp);
  const ammo=a.player.cannon,missile=a.player.missiles;
  a.player.cannon=0;a.player.missiles=0;
  const known=[];
  for(let i=0;i<120;i++){
    known.push(a.enemies[0].hp);
    assert.equal(a.enemies.some(e=>e.alive&&e.ace),(i+1)%10===0);
    assert(a.enemies.some(e=>e.alive)&&a.active&&!a.win);
    for(const e of a.enemies)if(e.alive)a.damage(e,e.hp,0);
    a.step(dt,idle);
  }
  assert(known.every((hp,i)=>!i||hp>=known[i-1]));
  assert.equal(a.wave,121);assert.equal(a.cleared,120);
  assert.equal(a.player.cannon,ammo);assert.equal(a.player.missiles,missile);
});

test('XP awards and threshold rewards persist once through reload, and ignore a failed save',()=>{
  memory.clear();
  const p=freshProfile(),stage=operation('d01'),s=new Sortie(stage,byAircraft('f16'),loadout,()=>{});
  const report={...s.report(),xp:levelThreshold(4),credits:500};
  const starting=p.credits;
  assert.equal(pilotLevel(p.xp),1);
  assert.equal(recordSortie(p,report,'f16'),500);
  assert.equal(pilotLevel(p.xp),4);
  assert(p.credits>starting+500&&p.unlocked.includes('mirage'));
  assert.equal(levelProgress(p.xp).progress,0);
  assert.equal(loadProfile().credits,p.credits);
  assert.equal(loadProfile().rewardedLevel,4);
  const store=globalThis.localStorage.setItem;
  try{
    globalThis.localStorage.setItem=()=>{throw Error('storage unavailable');};
    assert.equal(recordSortie(p,report,'f16'),0);
    assert.equal(pilotLevel(p.xp),4);
  }finally{globalThis.localStorage.setItem=store;}
});

test('representative chapter 1, 3 and 6 sorties exercise the escalation with finite ammunition',()=>{
  for(const id of ['s01','s21','s60']){
    const events={gun:0,missile:0,counter:0,evades:0};
    const type=byAircraft(id==='s60'?'a10':'j20');
    const profile=freshProfile();
    if(id==='s60'){
      profile.xp=levelThreshold(12);profile.technology.push('power','vectoring','signal','horizon');
      profile.improvements={'a10:engine':3,'a10:maneuver':3,'a10:weapons':3};
      assert.equal(buyItem(profile,'vector'),'已放入仓库');
      assert.equal(buyItem(profile,'skylance'),'已放入仓库');
      assert.equal(equipItem(profile,'a10','vector'),'装备配置已保存');
      assert.equal(equipItem(profile,'a10','skylance'),'装备配置已保存');
    }
    const configuration=combatConfiguration(profile,type.id);
    const s=new Sortie(operation(id),type,{...loadout,rank:1,configuration},e=>{
      if(e.side===1&&(e.kind==='gun'||e.kind==='missile'||e.kind==='counter'))events[e.kind]++;
    });
    const control=makePilot(s);
    const aircraft=s.enemies[0];
    const initial={hp:aircraft.hp,handling:aircraft.handling,thrust:aircraft.enginePower,
      magazines:s.enemies.filter(a=>a.alive).map(a=>a.missiles)};
    for(let i=0;i<90*30&&s.active;i++){
      if(s.warning.stage===4&&s.defense.readyAt<s.time)s.counter();
      s.step(dt,control());
      assert(s.enemies.every(e=>e.missiles>=0&&e.cannon>=0));
      if(s.enemies.some(e=>e.alive&&e.evadeUntil>s.time))events.evades++;
    }
    assert(events.gun+events.missile>0,id);
    const course=new Sortie(operation(id),type,{...loadout,rank:1,configuration},()=>{});
    const r=clearWithOrdnance(course);
    assert(r.win&&r.kills===course.total,id);
    console.log('campaign balance',JSON.stringify({id,initial,outcome:r.reason,finished:r.win,
      seconds:+r.time.toFixed(2),kills:r.kills,projectileFixture:true,gunRate:r.accuracy,missileRate:r.missileAccuracy,events}));
  }
});

test('weapon upgrades debit credits independently and persist without materials',()=>{
  memory.clear();
  const profile=freshProfile(),id=profile.selected;
  profile.inventory={};
  profile.credits=1200;
  const initial=combatConfiguration(profile,id);
  assert.equal(buyUpgrade(profile,id,'cannon'),'改装已装配');
  const first=combatConfiguration(loadProfile(),id);
  assert.equal(first.rounds,1320);
  assert(first.gun>initial.gun&&first.gunRate>initial.gunRate);
  assert.deepEqual(first.missile,initial.missile);
  assert.equal(first.airMissiles,20);
  assert.equal(buyUpgrade(profile,id,'missile'),'改装已装配');
  const saved=loadProfile(),both=combatConfiguration(saved,id);
  assert.equal(saved.credits,80);
  assert.equal(both.airMissiles,22);
  assert(both.missile.speed>initial.missile.speed&&both.missile.damage>initial.missile.damage);
  assert.equal(both.rounds,first.rounds);
  assert.equal(buyUpgrade(saved,id,'cannon'),'信用点不足');
  assert.equal(saved.credits,80);
});

test('directional avoidance steers briefly without reversing or granting invulnerability',()=>{
  for(const side of [1,-1]){
    const s=new Sortie(operation('free'),byAircraft('j20'),{...loadout,diagnostics:true},()=>{});
    s.player.reset(0,3300,2600,0);
    assert(s.evade(side));
    assert(!s.evade(-side));
    for(let i=0;i<97;i++)s.step(dt,idle);
    assert(s.player.position.x*side<-12);
    assert(s.player.forward.z<-.5);
    const hp=s.player.hp;
    s.damage(s.player,55,1);
    assert(s.player.hp<hp);
  }
});

test('chapter three reinforcements converge toward the player and waves reach a victory',()=>{
  for(let chapterStage=21;chapterStage<=30;chapterStage++){
    const s=new Sortie(operation('s'+chapterStage),byAircraft('j20'),loadout,()=>{});
    for(let w=1;w<=s.waves.length;w++){
      assert.equal(s.wave,w,s.op.id);
      const active=s.enemies.filter(e=>e.alive);
      assert.equal(active.length,s.waves[w-1],s.op.id);
      assert(active.some(e=>e.type.id!=='shade-drone'),s.op.id);
      for(const e of active){
        const heading=s.player.position.subtract(e.position);
        heading.y=0;heading.normalize();
        assert(Vector3.Dot(e.forward,heading)>.985,s.op.id);
        assert(!s.world.terrainMasks(e.position.x,e.position.y,e.position.z,s.player.position.x,s.player.position.y,s.player.position.z),s.op.id);
        s.damage(e,e.hp,0);
      }
      s.step(dt,idle);
    }
    assert(s.win&&s.cleared===s.waves.length,s.op.id);
  }
});
