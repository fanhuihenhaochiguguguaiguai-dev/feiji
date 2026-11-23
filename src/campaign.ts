import type { Operation } from './data';

export type Formation='line'|'pincer'|'stack'|'screen'|'ace';
export type Objective='sweep'|'intercept'|'escort'|'defend'|'strike';
export interface Engagement {
  objective:Objective;formation:Formation;tier:number;waves:readonly number[];roster:readonly string[];
  altitude:number;spacing:number;distance:number;heading:number;groups:number;ace?:string;
}
type Chapter={name:string;level:number;roster:readonly string[];stages:readonly Stage[]};
type Stage=[title:string,region:number,objective:Objective,formation:Formation,waves:number[],altitude:number,time:number,ace?:string];
export const chapters:Chapter[]=[
  {name:'前哨警报',level:1,roster:['f16','j10','f16','mig21'],stages:[
    ['破晓巡弋',0,'intercept','line',[2,2,2],420,240],
    ['雪线护航',1,'escort','screen',[2,2],760,270],
    ['黄昏反击',0,'strike','line',[],176,230],
    ['穿雷夺空',2,'sweep','stack',[2,2,3],1120,265],
    ['离岸封锁',0,'defend','pincer',[2,2,3],515,265],
    ['峡湾回声',1,'intercept','line',[2,3],1180,220],
    ['逆风航路',2,'escort','screen',[2,3,2],870,285],
    ['双岛标靶',0,'strike','pincer',[],213,240],
    ['雷隙追迹',2,'intercept','stack',[3,2,2],1500,215],
    ['守望者',0,'sweep','ace',[2,3,2],630,275,'mirage']
  ]},
  {name:'破云航线',level:3,roster:['mig21','mirage','j10','f16'],stages:[
    ['北望信标',1,'defend','stack',[2,3,2],1220,285],
    ['侧风夹击',0,'sweep','pincer',[3,3],720,250],
    ['远洋接力',2,'escort','screen',[2,3,3],1130,300],
    ['临崖投弹',0,'strike','line',[],195,212],
    ['风暴眼',2,'intercept','stack',[2,3,3],1680,240],
    ['雪岭分队',1,'sweep','line',[3,2,3],2120,300],
    ['归航纵队',1,'escort','pincer',[3,2],1440,280],
    ['外海断线',0,'defend','screen',[3,3,2],825,280],
    ['远岬哨塔',0,'strike','stack',[],250,245],
    ['云端来客',2,'sweep','ace',[3,3,3],1670,290,'hornet']
  ]},
  {name:'冰脊对峙',level:6,roster:['f16','mirage','gripen','hornet'],stages:[
    ['冰墙折返',1,'intercept','pincer',[3,3],1820,235],
    ['两翼火网',1,'sweep','pincer',[3,3,3],1760,285],
    ['雾谷输送',1,'escort','screen',[2,4,3],950,290],
    ['浅湾哨所',0,'strike','screen',[],205,228],
    ['冷锋上缘',1,'defend','stack',[3,4,2],2260,290],
    ['峡谷折光',1,'intercept','stack',[3,3,2],1380,210],
    ['风涌支线',2,'escort','pincer',[3,3,3],1070,278],
    ['零下空战',1,'sweep','stack',[3,4,3],2570,278],
    ['雪线安全窗',1,'defend','screen',[4,3],1970,250],
    ['白峰王牌',1,'sweep','ace',[3,4,3],2420,300,'gripen']
  ]},
  {name:'远雷攻防',level:9,roster:['j10','hornet','gripen','su35'],stages:[
    ['低云回廊',2,'escort','stack',[3,4,3],845,311],
    ['雷幕进场',2,'intercept','line',[3,4,3],1560,232],
    ['邻岸切入',0,'strike','pincer',[],229,212],
    ['海峡禁飞区',2,'defend','pincer',[3,4,3],1150,278],
    ['重叠航迹',2,'sweep','pincer',[4,3,4],1800,313],
    ['窗口护航',1,'escort','screen',[4,4,3],1240,298],
    ['远海预警',2,'intercept','stack',[3,4,4],2110,245],
    ['短波盲区',0,'defend','line',[4,3,4],1100,285],
    ['前线压制',0,'strike','stack',[],246,236],
    ['雷眼猎手',2,'sweep','ace',[3,4,4],2000,335,'su35']
  ]},
  {name:'暮色反攻',level:12,roster:['mirage','hornet','su35','j20'],stages:[
    ['暮线回扫',0,'sweep','stack',[4,4,3],965,300],
    ['峡口突破',0,'strike','screen',[],245,211],
    ['归途拦截',0,'intercept','pincer',[4,3,4],1400,241],
    ['雪脊中继',1,'escort','screen',[4,4,3],1740,302],
    ['暗潮守备',2,'defend','stack',[3,4,4],1810,295],
    ['交错锋线',0,'sweep','pincer',[4,4,4],1620,325],
    ['天空走廊',1,'intercept','stack',[4,4,4],2070,247],
    ['南岛火线',0,'strike','line',[],268,225],
    ['灯塔护送',2,'escort','pincer',[4,4,4],1070,310],
    ['余晖之翼',0,'sweep','ace',[4,4,3],1520,325,'j20']
  ]},
  {name:'苍穹决战',level:16,roster:['hornet','gripen','su35','j20'],stages:[
    ['顶层云界',1,'intercept','stack',[4,4,4],2740,253],
    ['风切编队',2,'escort','pincer',[4,4,4],1810,330],
    ['外岛静默',0,'strike','stack',[],258,219],
    ['多轴警戒',0,'defend','pincer',[4,4,4],1270,310],
    ['峡口争夺',1,'sweep','line',[4,4,4],1930,310],
    ['暮雷终段',2,'intercept','pincer',[4,4,4],2010,245],
    ['撤离窗口',1,'escort','screen',[4,4,4],1670,300],
    ['重返前哨',0,'strike','pincer',[],270,206],
    ['会合点守备',2,'defend','stack',[4,4,4],2190,298],
    ['苍穹试炼',2,'sweep','ace',[4,4,4],2590,338,'j20']
  ]}
];
export const objectiveNames:Record<Objective,string>={sweep:'歼灭',intercept:'拦截',escort:'护航',defend:'空域防御',strike:'对地突袭'};
const brief:Record<Objective,string>={
  intercept:'在拦截编队撤离前将其击退，超时视为拦截失败。',
  sweep:'肃清全部来袭编队。各分队从不同高度与方位接敌。',
  escort:'掩护运输机穿越指定走廊，优先拦截正在咬尾的敌机。',
  defend:'防止敌机突破警戒线，并肃清来袭编队。',
  strike:'按简报所示摧毁前方无人靶群。重力炸弹对成组目标有效。'
};
export const campaignOperations:Operation[]=chapters.flatMap((chapter,i)=>chapter.stages.map((stage,j)=>{
  const [name,region,objective,formation,waves,altitude,limit,ace]=stage;
  const n=i*10+j+1;
  const groups=objective==='strike'?1+(j%3===0&&n!==3?2:1):0;
  const tier=ace?3:Math.min(3,Math.floor((i*2+(j>5?1:0))/3));
  return {id:'s'+String(n).padStart(2,'0'),name,region,kind:objective==='strike'?'ground':objective==='escort'?'escort':'air',
    detail:brief[objective],threat:Math.min(3,1+tier),campaign:n,level:chapter.level,length:limit,
    engagement:{objective,formation,waves,altitude,ace,tier,groups,roster:chapter.roster,heading:n<5?0:(j%3-1)*.075,
      spacing:185+j*13+i*12,distance:n===1?1260:770+i*115+(j%3)*155}};
}));
export const chapterFor=(n:number)=>Math.min(5,Math.max(0,Math.floor((n-1)/10)));
export const campaignStage=(n:number)=>campaignOperations[Math.min(campaignOperations.length,Math.max(1,Math.floor(n)))-1];
