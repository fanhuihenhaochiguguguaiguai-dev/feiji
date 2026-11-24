import type { Operation } from './data';

export type Formation='line'|'pincer'|'stack'|'screen'|'ace';
export type Objective='sweep'|'intercept'|'screen'|'pincer'|'low';
export interface Engagement {
  objective:Objective;formation:Formation;tier:number;waves:readonly number[];roster:readonly string[];
  altitude:number;spacing:number;distance:number;heading:number;groups:number;ace?:string;
}
type Chapter={name:string;level:number;roster:readonly string[];stages:readonly Stage[]};
type Stage=[title:string,region:number,objective:Objective,formation:Formation,waves:number[],altitude:number,ace?:string];
export const chapters:Chapter[]=[
  {name:'前哨警报',level:1,roster:['f16','j10','f16','mig21'],stages:[
    ['破晓巡弋',0,'intercept','line',[2,1,1],420],
    ['雪线接敌',1,'screen','screen',[2,2],760],
    ['黄昏反击',0,'low','line',[2,2],176],
    ['穿雷夺空',2,'sweep','stack',[2,2,3],1120],
    ['离岸封锁',0,'pincer','pincer',[2,2,3],515],
    ['峡湾回声',1,'intercept','line',[2,3],1180],
    ['逆风航路',2,'screen','screen',[2,3,2],870],
    ['双岛追击',0,'low','pincer',[2,2],213],
    ['雷隙追迹',2,'intercept','stack',[3,2,2],1500],
    ['守望者',0,'sweep','ace',[2,3,2],630,'mirage']
  ]},
  {name:'破云航线',level:3,roster:['mig21','mirage','j10','f16'],stages:[
    ['北望信标',1,'pincer','stack',[2,3,2],1220],
    ['侧风夹击',0,'sweep','pincer',[3,3],720],
    ['远洋接力',2,'screen','screen',[2,3,3],1130],
    ['临崖截击',0,'low','line',[2,2],195],
    ['风暴眼',2,'intercept','stack',[2,3,3],1680],
    ['雪岭分队',1,'sweep','line',[3,2,3],2120],
    ['归航纵队',1,'screen','pincer',[3,2],1440],
    ['外海断线',0,'pincer','screen',[3,3,2],825],
    ['远岬低空',0,'low','stack',[2,2],250],
    ['云端来客',2,'sweep','ace',[3,3,3],1670,'hornet']
  ]},
  {name:'冰脊对峙',level:6,roster:['f16','mirage','gripen','hornet'],stages:[
    ['冰墙折返',1,'intercept','pincer',[3,3],1820],
    ['两翼火网',1,'sweep','pincer',[3,3,3],1760],
    ['雾谷破阵',1,'screen','screen',[2,4,3],950],
    ['浅湾格斗',0,'low','screen',[3,3],205],
    ['冷锋上缘',1,'pincer','stack',[3,4,2],2260],
    ['峡谷折光',1,'intercept','stack',[3,3,2],1380],
    ['风涌支线',2,'screen','pincer',[3,3,3],1070],
    ['零下空战',1,'sweep','stack',[3,4,3],2570],
    ['雪线安全窗',1,'pincer','screen',[4,3],1970],
    ['白峰王牌',1,'sweep','ace',[3,4,3],2420,'gripen']
  ]},
  {name:'远雷攻防',level:9,roster:['j10','hornet','gripen','su35'],stages:[
    ['低云回廊',2,'screen','stack',[3,4,3],845],
    ['雷幕进场',2,'intercept','line',[3,4,3],1560],
    ['邻岸切入',0,'low','pincer',[2,2],229],
    ['海峡禁飞区',2,'pincer','pincer',[3,4,3],1150],
    ['重叠航迹',2,'sweep','pincer',[4,3,4],1800],
    ['窗口交锋',1,'screen','screen',[4,4,3],1240],
    ['远海预警',2,'intercept','stack',[3,4,4],2110],
    ['短波盲区',0,'pincer','line',[4,3,4],1100],
    ['前线急袭',0,'low','stack',[2,2],246],
    ['雷眼猎手',2,'sweep','ace',[3,4,4],2000,'su35']
  ]},
  {name:'暮色反攻',level:12,roster:['mirage','hornet','su35','j20'],stages:[
    ['暮线回扫',0,'sweep','stack',[4,4,3],965],
    ['峡口突破',0,'low','screen',[3,3],245],
    ['归途拦截',0,'intercept','pincer',[4,3,4],1400],
    ['雪脊中继',1,'screen','screen',[4,4,3],1740],
    ['暗潮守备',2,'pincer','stack',[3,4,4],1810],
    ['交错锋线',0,'sweep','pincer',[4,4,4],1620],
    ['天空走廊',1,'intercept','stack',[4,4,4],2070],
    ['南岛火线',0,'low','line',[2,2],268],
    ['灯塔围猎',2,'screen','pincer',[4,4,4],1070],
    ['余晖之翼',0,'sweep','ace',[4,4,3],1520,'j20']
  ]},
  {name:'苍穹决战',level:16,roster:['hornet','gripen','su35','j20'],stages:[
    ['顶层云界',1,'intercept','stack',[4,4,4],2740],
    ['风切编队',2,'screen','pincer',[4,4,4],1810],
    ['外岛静默',0,'low','stack',[2,2],258],
    ['多轴警戒',0,'pincer','pincer',[4,4,4],1270],
    ['峡口争夺',1,'sweep','line',[4,4,4],1930],
    ['暮雷终段',2,'intercept','pincer',[4,4,4],2010],
    ['疾风斗阵',1,'screen','screen',[4,4,4],1670],
    ['重返前哨',0,'low','pincer',[2,2],270],
    ['会合点守备',2,'pincer','stack',[4,4,4],2190],
    ['苍穹试炼',2,'sweep','ace',[4,4,4],2590,'j20']
  ]}
];
export const objectiveNames:Record<Objective,string>={sweep:'全域歼灭',intercept:'迎头拦截',screen:'编队突围',pincer:'双向夹击',low:'低空格斗'};
const brief:Record<Objective,string>={
  intercept:'正面截击多个敌机分队，击落全部敌机后过关。',
  sweep:'各分队从不同高度和方位接敌，击落全部敌机后过关。',
  screen:'分离掩护与主攻编队，击落全部敌机后过关。',
  pincer:'敌机分两翼切入，击落全部敌机后过关。',
  low:'在沿岸和山间低空接战，击落全部敌机后过关。'
};
export const campaignOperations:Operation[]=chapters.flatMap((chapter,i)=>chapter.stages.map((stage,j)=>{
  const [name,region,objective,formation,waves,altitude,ace]=stage;
  const n=i*10+j+1,tier=Math.min(3,Math.floor((n-1)/15));
  return {id:'s'+String(n).padStart(2,'0'),name,region,kind:'air',
    detail:brief[objective]+(ace?' 末波由王牌 '+(i+1)+' 号带队。':''),threat:tier,campaign:n,level:chapter.level,
    engagement:{objective,formation,waves,altitude,ace,tier,groups:0,roster:chapter.roster,heading:n<5?0:(j%3-1)*.075,
      spacing:185+j*13+i*12,distance:n===1?1260:770+i*115+(j%3)*155}};
}));
export const chapterFor=(n:number)=>Math.min(chapters.length-1,Math.max(0,Math.floor((n-1)/10)));
export const campaignStage=(n:number)=>campaignOperations[Math.min(campaignOperations.length,Math.max(1,Math.floor(n)))-1];
