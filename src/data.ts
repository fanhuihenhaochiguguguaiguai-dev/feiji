import catalogue from './fleet.generated.json';
import { campaignOperations, type Engagement } from './campaign';
import { balance } from './airframe-balance';

export type Point = [number, number, number];
export interface PlaneSpec {
  id:string; name:string; origin:string; era:string; role:string; cockpit:string; span:number; length:number;
  trim:number; maxSpeed:number; stall:number; roll:number; pitch:number; yaw:number; boost:number;
  ammo:number; missiles:number; bombs:number; support:boolean; feature:string;
  props:number[][]; engine:number[][]; guns:number[][]; rails:number[][]; eye:number[];
  gearClearance:number; gearFixed:boolean;
  durability:number; acceleration:number; grip:number; gunPower:number; safety:number; specialty:string;
}
export const fleet:PlaneSpec[]=catalogue.map(plane=>{
  const [durability,acceleration,grip,gunPower,safety,specialty]=balance[plane.id];
  return {...plane,durability,acceleration,grip,gunPower,safety,specialty};
});
export const byAircraft=(id:string)=>fleet.find(p=>p.id===id)??fleet.find(p=>p.id==='j20')!;
export const eras:Record<string,string>={ww1:'一战',ww2:'二战',early:'早期喷气',cold:'冷战',modern:'现代',stealth:'第五代',support:'支援'};
export const theatres=[
  {id:'sundown',name:'南海前哨',weather:'日落',seed:413,sky:[.24,.40,.62],horizon:[.91,.65,.46],light:[1,.79,.54],sea:[.055,.159,.291],sun:[.69,.135,-.73],snow:false},
  {id:'frost',name:'雪线走廊',weather:'高空晴间云',seed:704,sky:[.21,.35,.57],horizon:[.61,.71,.85],light:[1,.88,.69],sea:[.055,.15,.23],sun:[-.50,.31,-.75],snow:true},
  {id:'storm',name:'远雷海峡',weather:'多云',seed:116,sky:[.115,.182,.29],horizon:[.41,.47,.55],light:[.80,.87,1],sea:[.041,.096,.14],sun:[.51,.17,-.84],snow:false}
];
export interface FreeFlightPlan { region:number; weather:number; lighting:number }
export interface Operation {
  id:string; name:string; kind:'air'|'escort'|'ground'|'train'|'free'; region:number; detail:string; threat:number; campaign?:number; length?:number; lesson?:string; level?:number; engagement?:Engagement;
}
export const operations:Operation[]=[
  ...campaignOperations,
  {id:'d01',name:'岛链拦截',kind:'air',region:0,detail:'自由选择战机和难度，迎击敌方编队。',threat:2},
  {id:'d02',name:'运输护航',kind:'escort',region:1,detail:'在运输机抵达安全区前保护它。',threat:2},
  {id:'d03',name:'对地打靶',kind:'ground',region:0,detail:'在训练场用航炮或炸弹摧毁无人靶。',threat:1},
  {id:'d04',name:'低空训练',kind:'train',region:0,detail:'连续通过三道航标，练习油门、转向和低空飞行。',threat:0},
  {id:'d05',name:'苍穹挑战',kind:'air',region:2,detail:'限时迎击精锐编队，挑战本机最高战绩。',threat:3,length:230},
  {id:'t02',name:'峡湾转向',kind:'train',region:1,detail:'连续通过三个错位航标，练习带坡度的左右转弯。',threat:0,lesson:'turn'},
  {id:'t03',name:'航炮瞄准',kind:'ground',region:0,detail:'沿跑道方向使用航炮或炸弹命中无人靶。',threat:0,lesson:'gun'},
  {id:'t04',name:'锁定与发射',kind:'air',region:0,detail:'锁定并击落一架练习敌机。',threat:0,lesson:'missile'},
  {id:'t05',name:'热诱饵与箔条',kind:'air',region:0,detail:'识别来袭弹种，实际引开一枚训练导弹。',threat:0,lesson:'counter'},
  {id:'free',name:'自由飞行',kind:'free',region:0,detail:'从海面上空或基地跑道出发，自由探索岛屿。',threat:0}
];
export const operation=(id:string)=>operations.find(m=>m.id===id)??operations[0];
export const difficulties=[
  {name:'训练',waves:[3,3,2],enemyPower:.53,reward:.8},
  {name:'标准',waves:[3,3,3],enemyPower:.8,reward:1},
  {name:'精英',waves:[4,4,4],enemyPower:1.10,reward:1.3}
];
export const startingFleet=['j20','f16','dr1','a10','j10','spitfire'];
export const upgrades=[
  {id:'armor',label:'复合装甲',type:'减伤',icon:'shield',description:'每级降低 6.5% 的玩家受击扰动。'},
  {id:'engine',label:'推力管理',type:'推力',icon:'boost',description:'每级提高 6% 的有效推力。'},
  {id:'maneuver',label:'舵面校准',type:'操纵',icon:'wing',description:'每级实际角速率响应 +6%。'},
  {id:'radar',label:'数字雷达',type:'航电',icon:'lock',description:'每级探测 +350 米，锁定距离 +150 米。'},
  {id:'weapons',label:'航炮强化',type:'火控',icon:'cross',description:'每级航炮命中伤害 +7%。'},
  {id:'cadence',label:'供弹与发射节奏',type:'火控',icon:'cross',description:'每级航炮射速 +9%，导弹发射频率 +6%。'},
  {id:'warhead',label:'导弹战斗部',type:'火控',icon:'target',description:'每级空空弹与空对地制导弹伤害 +12%。'},
  {id:'stores',label:'弹仓扩容',type:'携弹',icon:'target',description:'每级追加基础航炮弹量的 10%，已装载的空空弹和对地弹药各 +1。'},
];
export const baseModules=[
  {id:'repair',name:'维修机棚',detail:'每次空战波次之间补充已使用的热诱饵和箔条。',price:1100},
  {id:'radar',name:'岸基雷达',detail:'将出击雷达探测范围扩展至 8.5 公里。',price:850},
  {id:'supply',name:'前线补给',detail:'任务结算额外获得 15% 信用点。',price:980}
];
