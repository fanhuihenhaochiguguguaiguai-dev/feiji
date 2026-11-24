import { byAircraft, fleet, startingFleet, upgrades, type Operation } from './data';
import { gearSlot, gearSlots, compatible, itemById, missiles, missileDamage, minimumPlayerMissiles, rewards, stockHooks, technologies, type GearSlot, type MissileProfile, type RewardDefinition } from './items';
import { roundCapacity } from './ordnance';
import { airframeLevels, levelReward, pilotLevel } from './progression';
import { persistSnapshot, readSnapshots, type PilotSnapshot } from './save-store';
import type {Debrief} from './sortie';

export type Backend='auto'|'gpu'|'gl';
export type Quality='auto'|'high'|'medium'|'low';
interface Settings {backend:Backend;quality:Quality;mute:boolean;assist:boolean;invert:boolean;sensitivity:number;hud:number;renderScale:number;}
interface RecordRow {date:number;name:string;aircraft:string;grade:string;score:number;kills:number;seconds:number;win:boolean;}
export type InventoryState=Record<string,number>;
export type AircraftLoadout=Partial<Record<GearSlot,string>>;
interface DailyState {day:string;sorties:number;kills:number;victories:number;claimed:string[]}
const dayKey=()=>{const d=new Date();return [d.getFullYear(),d.getMonth()+1,d.getDate()].join('-');};
const blankDay=(day=dayKey()):DailyState=>({day,sorties:0,kills:0,victories:0,claimed:[]});
export interface Save {
  daily:DailyState;
  version:number;savedAt:number;credits:number;xp:number;rewardedLevel:number;selected:string;unlocked:string[];campaign:number;completed:string[];
  improvements:Record<string,number>;bases:string[];claimed:string[];records:RecordRow[];
  inventory:InventoryState;loadouts:Record<string,AircraftLoadout>;technology:string[];
  sorties:number;kills:number;distance:number;victories:number;settings:Settings;
}
export interface CombatConfiguration {
  missile:MissileProfile;paint:string;engine:number;grip:number;radar:number;lockRange:number;
  rounds:number;airMissiles:number;groundStores:number;groundWeapon:'bomb'|'shorebolt';
  defense:number;gun:number;gunRate:number;missileRate:number;missilePower:number;armor:number;stores:number;spares:number;aircraft:string;
}
const key='pixel-sky-af-v4',backup=key+'-recovery';
const retiredOperations=new Set(['armor','fleet','joint','铁幕突围','海门警戒','三军协同']);
const defaults:InventoryState={alloy:6,circuit:3,reserve:1,interceptor:1,factory:1,navy:1,sand:1,night:1};
export const freshProfile=():Save=>({
  version:9,savedAt:0,rewardedLevel:1,daily:blankDay(),credits:2600,xp:0,selected:'j20',unlocked:[...startingFleet],campaign:1,completed:[],improvements:{},
  bases:[],claimed:[],records:[],inventory:{...defaults},loadouts:{},technology:[],
  sorties:0,kills:0,distance:0,victories:0,
  settings:{backend:'auto',quality:'auto',mute:false,assist:true,invert:false,sensitivity:1,hud:1,renderScale:1}
});
const object=(v:unknown):Record<string,unknown>=>v&&typeof v==='object'&&!Array.isArray(v)?v as Record<string,unknown>:{};
const ids=(v:unknown):string[]=>Array.isArray(v)?[...new Set(v.filter(x=>typeof x==='string').slice(0,128))]:[];
const number=(v:unknown,fallback:number,ceil=1e9)=>typeof v==='number'&&Number.isFinite(v)?Math.min(ceil,Math.max(0,v)):fallback;
export function normalizeProfile(raw:unknown):Save{
  const input=object(raw),d=freshProfile();
  if(!Object.keys(input).length)return d;
  d.savedAt=number(input.savedAt,0,Number.MAX_SAFE_INTEGER);
  for(const n of ['credits','xp','campaign','sorties','kills','distance','victories'] as const)d[n]=number(input[n],d[n]);
  d.rewardedLevel=Math.floor(Math.max(1,number(input.rewardedLevel,1,pilotLevel(d.xp))));
  const daily=object(input.daily);
  if(daily.day===d.daily.day){
    for(const metric of ['sorties','kills','victories'] as const)d.daily[metric]=Math.floor(number(daily[metric],0,9999));
    d.daily.claimed=ids(daily.claimed).filter(id=>rewards.some(r=>r.period==='day'&&r.id===id));
  }
  const owned=ids(input.unlocked).filter(id=>fleet.some(x=>x.id===id&&!x.support));
  d.unlocked=[...new Set([...startingFleet,...owned])];
  if(typeof input.selected==='string'&&d.unlocked.includes(input.selected))d.selected=input.selected;
  d.completed=ids(input.completed).filter(id=>!retiredOperations.has(id));d.claimed=ids(input.claimed);d.bases=ids(input.bases).filter(x=>['repair','radar','supply'].includes(x));
  d.technology=ids(input.technology).filter(x=>technologies.some(t=>t.id===x));
  const settings=object(input.settings);
  if(['auto','gpu','gl'].includes(String(settings.backend)))d.settings.backend=settings.backend as Backend;
  if(['auto','low','medium','high'].includes(String(settings.quality)))d.settings.quality=settings.quality as Quality;
  for(const k of ['mute','assist','invert'] as const)if(typeof settings[k]==='boolean')d.settings[k]=settings[k];
  d.settings.sensitivity=Math.max(.45,number(settings.sensitivity,1,1.55));d.settings.hud=Math.max(.8,number(settings.hud,1,1.23));d.settings.renderScale=Math.max(.65,number(settings.renderScale,1,1));
  if(Array.isArray(input.records))d.records=input.records.filter(r=>r&&typeof r.name==='string'&&!retiredOperations.has(r.name)&&typeof r.aircraft==='string'&&Number.isFinite(r.score)).slice(0,36);
  if(!input.version)d.victories=Math.max(d.completed.length,d.records.filter(r=>r.win).length);
  const serial=object(input.inventory);
  for(const [id,amount] of Object.entries(serial))if(itemById[id]&&itemById[id]!.kind!=='currency')d.inventory[id]=Math.floor(number(amount,0,9999));
  for(const [id,amount] of Object.entries(object(input.improvements))){
    const [plane,part]=id.split(':');
    if(d.unlocked.includes(plane)&&upgrades.some(u=>u.id===part))d.improvements[id]=Math.floor(number(amount,0,3));
  }
  const oldPaint=object(input.paint);
  for(const plane of d.unlocked){
    const saved=object(object(input.loadouts)[plane]);
    const config:AircraftLoadout={};
    for(const slot of gearSlots){
      const id=saved[slot]??(slot==='skin'?oldPaint[plane]:undefined);
      if(typeof id!=='string')continue;
      if(slot==='cannon'||slot==='missile'&&(id==='none'||id==='interceptor'))continue;
      if(id==='none'&&slot==='bomb'){config[slot]=id;continue;}
      const entry=itemById[id];
      if(slot==='skin'&&entry?.kind==='skin'&&!input.version)d.inventory[id]=1;
      if(entry&&gearSlot(entry.kind)===slot&&d.inventory[id]>0&&(!entry.tech||d.technology.includes(entry.tech))&&compatible(byAircraft(plane),entry))config[slot]=id;
    }
    if(Object.keys(config).length)d.loadouts[plane]=config;
  }
  return d;
}
function decodeProfile(raw:string|null):Save|null{
  if(!raw)return null;
  try{
    const value=JSON.parse(raw);
    return value&&typeof value==='object'&&Array.isArray(value.unlocked)?normalizeProfile(value):null;
  }catch{return null;}
}
function journalProfile():Save|null{
  for(const name of [key,backup])try{
    const p=decodeProfile(localStorage.getItem(name));
    if(p)return p;
  }catch{/* Attempt the independent recovery copy. */}
  return null;
}
export function loadProfile():Save{
  const p=journalProfile()??freshProfile(),next=awardLevels(p);
  return next!==p&&saveProfile(next)?next:p;
}
export async function loadPersistentProfile():Promise<Save>{
  let timeout:ReturnType<typeof setTimeout>|undefined;
  const snapshots=await Promise.race([readSnapshots(),new Promise<PilotSnapshot[]>(resolve=>{timeout=setTimeout(()=>resolve([]),650);})]);
  clearTimeout(timeout);
  const journal=journalProfile();
  const stored=snapshots.map(row=>decodeProfile(row.data)).find(row=>row!==null);
  const p=stored&&(!journal||stored.savedAt>journal.savedAt)?stored:journal??freshProfile();
  const next=awardLevels(p);
  if(next!==p&&saveProfile(next))return next;
  if(!stored||stored.savedAt<p.savedAt){
    if(!p.savedAt)p.savedAt=Date.now();
    void persistSnapshot({savedAt:p.savedAt,data:JSON.stringify(p)});
  }
  return p;
}
export function saveProfile(p:Save){
  try{
    const savedAt=Math.max(Date.now(),p.savedAt+1);
    const text=JSON.stringify({...p,savedAt});
    localStorage.setItem(key,text);
    try{localStorage.setItem(backup,text);}catch{/* The primary write is already valid. */}
    p.savedAt=savedAt;
    void persistSnapshot({savedAt,data:text});
    return true;
  }catch{return false;}
}
function commit(p:Save,next:Save){
  if(!saveProfile(next))return false;
  Object.assign(p,next);return true;
}
export const upgradeLevel=(p:Save,id:string,u:string)=>p.improvements[id+':'+u]??0;
export function requirements(part:string,level:number):[string,number]{return [['radar','weapons','cadence','warhead'].includes(part)?'circuit':'alloy',1+level];}
export const upgradeCompatible=(id:string,part:string)=>{
  const plane=byAircraft(id);
  return !plane.support;
};
export function buyUpgrade(p:Save,id:string,u:string){
  if(!p.unlocked.includes(id)||!upgrades.some(value=>value.id===u))return '此战机或改装项目未解锁';
  const at=upgradeLevel(p,id,u),amount=560+at*360;
  if(at>=3)return '已达到最高等级';
  if(!upgradeCompatible(id,u))return '该机不支持对应部件';
  if(p.credits<amount)return '信用点不足';
  const [material,quantity]=requirements(u,at);
  if((p.inventory[material]??0)<quantity)return '升级材料不足';
  return commit(p,{...p,credits:p.credits-amount,inventory:{...p.inventory,[material]:p.inventory[material]-quantity},
    improvements:{...p.improvements,[id+':'+u]:at+1}})?'改装已装配':'存档失败，未扣除材料';
}
export function unlockAircraft(p:Save,id:string){
  if(byAircraft(id).support||byAircraft(id).id!==id)return '该机型由任务编队使用';
  if(p.unlocked.includes(id))return '该机型已解锁';
  const level=airframeLevels[id]??1;
  if(pilotLevel(p.xp)<level)return '飞行员达到 Lv.'+level+' 后解锁';
  if(p.credits<1150)return '需要 1150 信用点';
  return commit(p,{...p,credits:p.credits-1150,unlocked:[...p.unlocked,id]})?'已解锁':'存档失败，未扣除信用点';
}
export function equipItem(p:Save,aircraft:string,id:string,mount?:GearSlot){

  const item=itemById[id],plane=byAircraft(aircraft);
  if(!item||!p.unlocked.includes(aircraft)||!compatible(plane,item))return '当前飞机不支持该装备';
  if(!(p.inventory[id]>0))return '仓库没有该装备';
  if(item.tech&&!p.technology.includes(item.tech))return '请先研发所需科技';
  const slot=gearSlot(item.kind);
  if(!slot||mount&&mount!==slot)return '所选挂位与武器类型不符';
  if(slot==='cannon'||id==='interceptor')return resetGear(p,aircraft,slot);
  return commit(p,{...p,loadouts:{...p.loadouts,[aircraft]:{...p.loadouts[aircraft],[slot]:id}}})?'装备配置已保存':'存档失败，配置未改动';
}
export function detachWeapon(p:Save,aircraft:string,slot:GearSlot){
  if(!p.unlocked.includes(aircraft)||slot==='cannon')return '固定航炮随战机自动配发';
  if(slot==='missile')return resetGear(p,aircraft,slot);
  if(slot!=='bomb'||!stockHooks(byAircraft(aircraft)))return '该挂位不可拆卸';
  if(p.loadouts[aircraft]?.[slot]==='none')return '挂位已经清空';
  return commit(p,{...p,loadouts:{...p.loadouts,[aircraft]:{...p.loadouts[aircraft],[slot]:'none'}}})?'已卸下，采购装备保留在仓库':'存档失败，配置未改动';
}
export function resetGear(p:Save,aircraft:string,slot:string){
  const fit=p.loadouts[aircraft];
  if(!fit||!Object.hasOwn(fit,slot))return '当前已使用原厂配置';
  const next={...fit};
  delete next[slot as GearSlot];
  return commit(p,{...p,loadouts:{...p.loadouts,[aircraft]:next}})?'已恢复原厂配置':'存档失败，配置未改动';
}
export function purchaseBlock(p:Save,id:string){
  const entry=itemById[id];
  if(!entry?.price)return '此装备通过任务与活动获得';
  if((entry.level??1)>pilotLevel(p.xp))return '需要飞行员 Lv.'+entry.level;
  if(entry.tech&&!p.technology.includes(entry.tech))return '需要前置研发';
  if(entry.kind!=='consumable'&&p.inventory[id]>0)return '已经拥有';
  if(p.credits<entry.price)return '信用点不足';
  return '';
}
export function buyItem(p:Save,id:string){
  const reason=purchaseBlock(p,id);
  if(reason)return reason;
  const entry=itemById[id]!;
  return commit(p,{...p,credits:p.credits-entry.price!,inventory:{...p.inventory,[id]:(p.inventory[id]??0)+1}})?'已放入仓库':'存档失败，未扣除信用点';
}
export function research(p:Save,id:string){
  const t=technologies.find(value=>value.id===id);
  if(!t||p.technology.includes(id))return '已完成研发';
  if(t.prerequisite&&!p.technology.includes(t.prerequisite))return '缺少前置研发';
  if(p.credits<t.cost||(p.inventory.circuit??0)<t.material)return '研发材料或信用点不足';
  return commit(p,{...p,credits:p.credits-t.cost,technology:[...p.technology,id],
    inventory:{...p.inventory,circuit:p.inventory.circuit-t.material}})?'研发完成，已写入出击配置':'存档失败，研发未扣款';
}
function currentDay(p:Save){return p.daily.day===dayKey()?p.daily:blankDay();}
export function rewardStatus(p:Save,r:RewardDefinition){
  const group=r.period==='day'?currentDay(p):p;
  const metric=r.metric;
  const progress=metric==='xp'||metric==='distance'?p[metric]:group[metric];
  return {progress,earned:progress>=r.threshold,claimed:group.claimed.includes(r.id)};
}
export function claimRewards(p:Save,ids:readonly string[]){
  const requested=new Set(ids);
  const eligible=rewards.filter(r=>{const state=rewardStatus(p,r);return requested.has(r.id)&&!state.claimed&&state.earned;});
  if(!eligible.length)return [];
  const inventory={...p.inventory},unlocked=[...p.unlocked];let credits=p.credits;
  for(const r of eligible)for(const [item,amount] of r.prize){
    if(!itemById[item]||amount<=0)return [];
    if(item==='credits')credits+=amount;
    else if(itemById[item]?.kind==='aircraft'){
      const plane=byAircraft(item.slice(4));
      if(plane.support)return [];
      if(!unlocked.includes(plane.id))unlocked.push(plane.id);
    }else inventory[item]=(inventory[item]??0)+amount;
  }
  const claimed=[...p.claimed,...eligible.filter(r=>!r.period).map(r=>r.id)];
  const today=currentDay(p),daily={...today,claimed:[...today.claimed,...eligible.filter(r=>r.period==='day').map(r=>r.id)]};
  return commit(p,{...p,credits,inventory,unlocked,claimed,daily})?eligible:[];
}
export const claimReward=(p:Save,id:string)=>claimRewards(p,[id]).length===1;
export function consumeReserve(p:Save){
  if(!(p.inventory.reserve>0))return false;
  return commit(p,{...p,inventory:{...p.inventory,reserve:p.inventory.reserve-1}});
}
export function combatConfiguration(p:Save,id:string,groundEnabled=true):CombatConfiguration{
  const plane=byAircraft(id),owned=p.unlocked.includes(id),choices=owned?p.loadouts[id]??{}:{};
  const get=(slot:GearSlot)=>{
    const key=choices[slot],value=key&&itemById[key];
    return value&&p.inventory[value.id]>0&&compatible(plane,value)&&(!value.tech||p.technology.includes(value.tech))?value:undefined;
  };
  const level=(component:string)=>upgradeLevel(p,plane.id,component);
  const stores=level('stores');
  const warhead=level('warhead'),cadence=level('cadence');
  const payload=get('bomb');
  const groundStock=!groundEnabled||choices.bomb==='none'?0:payload?(plane.bombs||2):plane.bombs;
  const airStock=plane.support?0:Math.max(minimumPlayerMissiles,plane.missiles-(plane.id==='j20'&&groundStock?4:0));
  const missile=missiles[get('missile')?.id??'interceptor'];
  return {aircraft:plane.id,missile:{...missile,damage:missileDamage(plane,missile,warhead)},paint:get('skin')?.color??'',
    rounds:roundCapacity(plane,stores),
    airMissiles:airStock?airStock+stores:0,
    groundStores:groundStock?groundStock+stores:0,
    groundWeapon:payload?.kind==='strike'?'shorebolt':'bomb',
    engine:1+level('engine')*.06+(get('engine')?.id==='vector'?.12:0)+(p.technology.includes('power')?.03:0),
    grip:1+level('maneuver')*.06+(p.technology.includes('vectoring')?.05:0),
    radar:(p.bases.includes('radar')?8500:6400)+level('radar')*350+(get('radar')?2000:0)+(p.technology.includes('signal')?500:0),
    lockRange:(get('radar')?550:0)+level('radar')*150, defense:get('counter')?1:0,
    gun:1+level('weapons')*.07,gunRate:1+cadence*.09,missileRate:1+cadence*.06,missilePower:1+warhead*.12,
    armor:level('armor'),stores:level('stores'),spares:p.inventory.reserve??0};
}
export function sortieBlock(p:Save,op:Operation,loadout=combatConfiguration(p,p.selected,op.kind==='ground')){
  if(op.campaign&&op.campaign>p.campaign)return '完成前序战役后解锁';
  if(!op.campaign&&(op.level??1)>pilotLevel(p.xp))return '需要飞行员 Lv.'+op.level+'，可完成训练或已解锁任务获得经验';
  if(op.kind==='ground'&&!loadout.rounds&&!loadout.groundStores)return '缺少对地武器。请安装航炮、炸弹或空对地制导弹';
  if(op.engagement?.groups&&!loadout.rounds&&loadout.groundStores<op.engagement.groups)
    return '本关有 '+op.engagement.groups+' 处目标群。请换用航炮或装载更多对地弹药';
  if(op.engagement&&op.kind==='ground'&&!loadout.rounds&&loadout.groundWeapon==='shorebolt'&&loadout.groundStores<op.engagement.groups*2)
    return '对地弹药不足以清扫分散目标。请选择重力炸弹或装备航炮';
  if(op.lesson==='missile'&&!loadout.airMissiles)return '缺少空空导弹。请安装空空弹或更换战机';
  if(op.lesson==='counter'&&!byAircraft(loadout.aircraft).safety)return '请更换配备反制设备的战机';
  if((op.kind==='air'||op.kind==='escort'||op.kind==='free')&&!loadout.rounds&&!loadout.airMissiles)
    return '缺少空战武器。请恢复原厂航炮、空空弹或更换战机';
  return '';
}
function awardLevels(p:Save):Save{
  const level=pilotLevel(p.xp);
  if(level<=p.rewardedLevel)return p;
  const next={...p,rewardedLevel:level,inventory:{...p.inventory},unlocked:[...p.unlocked]};
  for(let at=p.rewardedLevel+1;at<=level;at++)for(const [id,amount] of levelReward(at)){
    if(id==='credits')next.credits+=amount;
    else if(id.startsWith('air-')){
      if(!next.unlocked.includes(id.slice(4)))next.unlocked.push(id.slice(4));
    }else next.inventory[id]=(next.inventory[id]??0)+amount;
  }
  return next;
}
export const firstClearLoot:[string,number][]=[['alloy',2],['circuit',1]];
export function recordSortie(p:Save,result:Debrief,aircraft:string){
  const credits=Math.round(result.credits*(p.bases.includes('supply')?1.15:1));
  const completed=[...p.completed],inventory={...p.inventory};
  if(result.win&&!completed.includes(result.operation.id)){
    completed.push(result.operation.id);
    for(const [id,amount] of firstClearLoot)inventory[id]=(inventory[id]??0)+amount;
  }
  const record={date:Date.now(),name:result.operation.name,aircraft:byAircraft(aircraft).name,grade:result.grade,
    score:result.score,kills:result.kills,seconds:result.time,win:result.win};
  const today=currentDay(p),daily={...today,sorties:today.sorties+1,kills:today.kills+result.kills,victories:today.victories+Number(result.win)};
  const next={...p,daily,credits:p.credits+credits,xp:p.xp+result.xp,sorties:p.sorties+1,completed,inventory,
    campaign:Math.max(p.campaign,result.win&&result.operation.campaign?result.operation.campaign+1:1),
    victories:p.victories+(result.win?1:0),kills:p.kills+result.kills,distance:p.distance+result.distance,records:[record,...p.records].slice(0,36)};
  return commit(p,awardLevels(next))?credits:0;
}
