import { fleet, type PlaneSpec } from './data';

export type GearSlot='missile'|'cannon'|'bomb'|'engine'|'radar'|'counter'|'skin';
export type ItemKind=GearSlot|'strike'|'material'|'consumable'|'aircraft'|'currency';
export interface ItemVisualAsset {icon:string;model?:string;effect?:string}
export interface ItemDefinition {
  id:string;name:string;kind:ItemKind;description:string;grade:'standard'|'rare'|'elite';visual:ItemVisualAsset;
  color?:string;tech?:string;price?:number;level?:number;
}
const visual=(id:string,model?:string,effect?:string):ItemVisualAsset=>({icon:'./items/'+id+'.webp',model,effect});
const item=(id:string,name:string,kind:ItemKind,description:string,grade:ItemDefinition['grade']='standard',
  extra:Partial<ItemDefinition>={}):ItemDefinition=>({id,name,kind,description,grade,visual:visual(id),...extra});
export const items:ItemDefinition[]=[
  item('credits','信用点','currency','用于购买机体、设备和研发。'),
  item('xp','飞行经验','currency','通过战斗结算累积，提升等级并获得飞行员嘉奖。'),
  item('alloy','结构合金','material','机身、推力、机动和挂载升级的消耗材料。'),
  item('circuit','航电板','material','火控和雷达升级的消耗材料。','rare'),
  item('reserve','反制补给包','consumable','出击中消耗 1 份，补充已损耗的热诱饵和箔条。','rare',{price:300}),
  item('interceptor','巡星标准弹','missile','兼容机型的原厂弹。雷达制导，适合中距交战。','standard',{visual:visual('interceptor','rack-standard','amber')}),
  item('flarewing','赤尾红外弹','missile','较短锁定距离，较快捕捉与转向。','rare',{price:620,level:3,visual:visual('flarewing','rack-compact','crimson')}),
  item('skylance','苍矛远程弹','missile','雷达制导。速度和有效射程更高，转向较慢。','elite',{tech:'horizon',price:1150,level:8,visual:visual('skylance','rack-long','cyan')}),
  item('vector','稳压推力组件','engine','装配后实际推力提高 12%。','rare',{tech:'power',price:820}),
  item('survey','广域搜索雷达','radar','装配后探测扩大 2000 米，锁定距离扩大 550 米。','rare',{price:920}),
  item('veil','曙幕电子对抗盒','counter','装配后出场增加 2 发热诱饵和 1 发箔条。','rare',{tech:'signal',price:680}),
  item('factory','原厂涂装','skin','使用战机原有航空涂装。','standard',{color:''}),
  item('navy','深海蓝','skin','给机体主要蒙皮应用蓝灰色涂装。','standard',{color:'#526e91'}),
  item('sand','砂岩灰','skin','给机体蒙皮应用砂岩色涂装。','standard',{color:'#908274'}),
  item('night','暗夜黑','skin','给机体蒙皮应用低可视深灰涂装。','rare',{color:'#414755'}),
  item('bronze-sky','余晖铜','skin','深铜色蒙皮配冷灰高光。','elite',{color:'#af7956'}),
  item('cannon-light','轻型机枪','cannon','原厂固定武器。弹量、射速和威力按机型设定。','standard',{visual:visual('cannon-light',undefined,'tracer-gold')}),
  item('cannon-jet','喷气航炮','cannon','原厂固定武器。每次出击自动装填本机配额。','standard',{visual:visual('cannon-jet',undefined,'tracer-gold')}),
  item('cannon-heavy','重型航炮','cannon','A-10 的原厂重型航空机炮，适用于空战与对地。','rare',{visual:visual('cannon-heavy',undefined,'tracer-heavy')}),
  item('bomb','通用航空炸弹','bomb','重力弹道，落地在范围内摧毁训练目标。','standard',{price:340,visual:visual('bomb','rack-bomb','dust')}),
  item('shorebolt','岸隼制导弹','strike','空对地制导武器。对地靶标对准后发射，与炸弹共用对地挂位。','rare',{price:870,level:6,visual:visual('shorebolt','rack-bomb','dust')}),
  ...fleet.map(plane=>item('air-'+plane.id,plane.name,'aircraft',plane.specialty,plane.era==='stealth'?'elite':'standard',{
    visual:{icon:'./cards/'+plane.id+'.webp',model:'./fleet/'+plane.id+'.glb'}}))
];
export const itemById=Object.fromEntries(items.map(value=>[value.id,value])) as Record<string,ItemDefinition|undefined>;
export const gearSlots:GearSlot[]=['missile','cannon','bomb','engine','radar','counter','skin'];
export function gearSlot(kind:ItemKind):GearSlot|undefined{
  return kind==='strike'?'bomb':gearSlots.find(slot=>slot===kind);
}
export const gears=items.filter(i=>gearSlot(i.kind)!==undefined);
export const stockHooks=(plane:PlaneSpec)=>plane.bombs>0||plane.id==='j20';
export const groundMount=(plane:PlaneSpec)=>plane.id==='j20'?[0,-.57,.55]:[plane.span*.13,-.87,.48];
export const slotName=(slot:GearSlot,plane:PlaneSpec)=>({
  missile:plane.id==='j20'?'内置弹舱 · 空空组':'翼下 · 空空挂架',
  bomb:plane.id==='j20'?'内置弹舱 · 中央任务挂位':'翼下 · 对地挂架',
  cannon:'机身 · 固定炮位',engine:'机身 · 推进舱',radar:'机鼻 · 雷达舱',counter:'机身 · 反制舱',skin:'外部 · 涂装'
})[slot];
export const technologies=[
  {id:'signal',name:'电磁感知',prerequisite:'',cost:310,material:1,description:'实际空域探测 +500 米，开放曙幕电子对抗盒。'},
  {id:'horizon',name:'远距截击',prerequisite:'signal',cost:660,material:2,description:'开通苍矛远程弹的购买和挂载。'},
  {id:'power',name:'数字推力控制',prerequisite:'',cost:420,material:1,description:'所有兼容战机推力 +3%，开放稳压推力组件。'},
  {id:'vectoring',name:'协调机动',prerequisite:'power',cost:720,material:2,description:'所有战机的实际操纵响应 +5%。'}
] as const;
export const cannonID=(plane:PlaneSpec)=>plane.props.length?'cannon-light':plane.id==='a10'?'cannon-heavy':'cannon-jet';
export interface MissileProfile {
  id:string;seeker:'infrared'|'radar';acquire:number;range:number;turn:number;
  speed:number;acceleration:number;life:number;damage:number;shape:number;
}
export const missiles:Record<string,MissileProfile>={
  interceptor:{id:'interceptor',seeker:'radar',acquire:.69,range:4950,turn:2.23,speed:1040,acceleration:490,life:8.0,damage:118,shape:0},
  flarewing:{id:'flarewing',seeker:'infrared',acquire:.43,range:3870,turn:3.36,speed:940,acceleration:545,life:6.5,damage:112,shape:1},
  skylance:{id:'skylance',seeker:'radar',acquire:.91,range:6100,turn:1.82,speed:1340,acceleration:635,life:9.5,damage:144,shape:2}
};
export function missileDamage(plane:PlaneSpec,profile:MissileProfile,level:number){
  const airframe=plane.era==='cold'?1.11:plane.era==='stealth'?.96:plane.id==='a10'?1.06:1;
  return profile.damage*airframe*(1+level*.12);
}
// Every stock enemy survives two impacts from any currently available upgraded air-to-air loadout.
export const minimumEnemyDurability=1+Math.ceil(2*Math.max(...fleet.flatMap(plane=>
  Object.values(missiles).filter(weapon=>!plane.support&&compatible(plane,itemById[weapon.id]!))
    .map(weapon=>missileDamage(plane,weapon,3)))));
export function compatible(plane:PlaneSpec,entry:ItemDefinition){
  if(plane.support)return false;
  if(entry.kind==='skin')return true;
  if(entry.kind==='cannon')return plane.ammo>0&&plane.guns.length>0&&entry.id===cannonID(plane);
  if(entry.kind==='bomb')return stockHooks(plane);
  if(entry.kind==='strike')return stockHooks(plane)&&['a10','f16','hornet','j10','j20','su35','mirage','gripen'].includes(plane.id);
  if(entry.kind==='missile')return plane.missiles>0&&plane.rails.length>0&&(entry.id!=='skylance'||plane.era==='modern'||plane.era==='stealth');
  return (entry.kind==='radar'||entry.kind==='engine'||entry.kind==='counter')&&!(plane.props.length||plane.era==='early');
}
export interface RewardDefinition { id:string;name:string;criteria:string;period?:'day';threshold:number; metric:'sorties'|'kills'|'distance'|'xp'|'victories'; prize:[string,number][]}
export const rewards:RewardDefinition[]=[
  {id:'daily-sortie',name:'今日首航',criteria:'今天结算一次出击',period:'day',threshold:1,metric:'sorties',prize:[['credits',150],['alloy',1]]},
  {id:'daily-kills',name:'今日空域清扫',criteria:'今天击毁三个任务目标',period:'day',threshold:3,metric:'kills',prize:[['credits',280],['circuit',1]]},
  {id:'first',name:'首次升空',criteria:'完成一次出击',threshold:1,metric:'sorties',prize:[['credits',400],['alloy',3],['reserve',1]]},
  {id:'first-win',name:'赤尾试射许可',criteria:'完成一次任务并取胜',threshold:1,metric:'victories',prize:[['flarewing',1],['circuit',3]]},
  {id:'intercept',name:'岛链守望',criteria:'累计击落八个目标',threshold:8,metric:'kills',prize:[['survey',1],['credits',750]]},
  {id:'flight-wing',name:'编队荣誉',criteria:'取得三场任务胜利',threshold:3,metric:'victories',prize:[['air-gripen',1],['credits',470]]},
  {id:'tideline',name:'长航余晖',criteria:'累计飞行二十公里',threshold:20000,metric:'distance',prize:[['bronze-sky',1],['alloy',4]]},
  ...Array.from({length:8},(_,i):RewardDefinition=>({id:'pass-'+(i+1),name:'第 '+(i+1)+' 阶 · 空勤嘉奖',
    criteria:'达到 '+((i+1)*180)+' 飞行经验',threshold:(i+1)*180,metric:'xp',
    prize:[['credits',245+i*85],[i%3===0?'reserve':i%3===1?'alloy':'circuit',i%2+1]]}))
];
