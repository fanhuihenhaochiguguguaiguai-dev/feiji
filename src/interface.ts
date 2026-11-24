import type { FlightPose } from './flight';
import { TacticalRadar } from './tactical-radar';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import { byAircraft, difficulties, eras, fleet, operation, operations, theatres, upgrades, type FreeFlightPlan, type Operation } from './data';
import { buyItem, buyUpgrade, combatConfiguration, detachWeapon, equipItem, purchaseBlock, sortieBlock, firstClearLoot, resetGear, rewardStatus, saveProfile, unlockAircraft, upgradeCompatible, upgradeLevel, upgradePrice, type Save } from './profile';
import { cannonID, compatible, gearSlot, slotName, gears, itemById, missiles, missileDamage, rewards, type GearSlot } from './items';
import { cannonFor, guidedStrike, gunDamage, gunCycle, gunSight } from './ordnance';
import { icon, icons } from './icons';
import type { CooldownAction,Debrief,FlightEvent,Sortie } from './sortie';
import { lockRadius } from './targeting';
import type { WorldView } from './renderer';
import { clamp } from './terrain';
import { seekerNames } from './defense';
import { countTo, Presentation, type Receipt } from './presentation';
import type { FeedbackTone } from './audio';
import { airframeLevels, levelProgress, levelReward, pilotLevel } from './progression';
import { campaignStage, chapterFor, chapters, objectiveNames } from './campaign';
import { campaignChart, chartMarker, chartPoint } from './campaign-chart';

export const el=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
const money=(n:number)=>n.toLocaleString('zh-CN');
const clock=(v:number)=>Math.floor(v/60).toString().padStart(2,'0')+':'+Math.floor(v%60).toString().padStart(2,'0');
const stationTitles:Record<string,string>={hangar:'战机机库',upgrade:'改装',missions:'战役司令部',
  training:'飞行训练中心',freeprep:'自由空战准备',quests:'任务中心',sortieprep:'出击准备',records:'个人档案',settings:'游戏设置'};
export const studioStations=['home','hangar','upgrade','sortieprep','freeprep'];
const modificationTabs=[
  {id:'weapons',name:'武器',slots:['missile','cannon','bomb'],parts:['warhead','weapons']},
  {id:'performance',name:'性能',slots:['engine','radar'],parts:['engine','maneuver','radar']},
  {id:'defense',name:'防御',slots:['counter'],parts:['armor']},
  {id:'skin',name:'外观',slots:['skin'],parts:[]}
] as const;
type ModificationTab=(typeof modificationTabs)[number];
const picture=(id:string,klass='')=>{
  const asset=itemById[id];
  return asset?'<img class="item-art '+klass+'" src="'+asset.visual.icon+'" alt="" loading="lazy">':'';
};
const rewardChips=(list:[string,number][])=>list.map(([id,n])=>'<span class="prize '+itemById[id]?.grade+'">'+picture(id)+'<span>'+itemById[id]?.name+' <b>×'+n+'</b></span></span>').join('');
const resource=(path:string)=>new URL(path,document.baseURI).href;
const routeIntro=(label:string,headline:string,copy:string,art:string,backdrop:string)=>
  '<header class="route-intro" style="--route-art:url('+resource('briefing/'+backdrop+'.webp')+')">'+
  (label?'<span class="caption">'+label+'</span>':'')+'<h3>'+headline+'</h3><p>'+copy+'</p><img class="route-emblem" src="'+resource('items/'+art+'.webp')+'" alt=""></header>';
const selected=(yes:boolean)=>yes?' selected':'';
const disabled=(yes:boolean)=>yes?' disabled':'';
const metric=(name:string,value:string)=>'<div class="metric"><dt>'+name+'</dt><dd>'+value+'</dd></div>';
const worldPosition=new Vector3(),screenPosition=new Vector3(),localOffset=new Vector3(),cameraForward=new Vector3(),cameraRight=new Vector3(),cameraUp=new Vector3(),
  cameraAxis=new Vector3(0,0,-1),rightAxis=new Vector3(1,0,0),upAxis=new Vector3(0,1,0);
function placeCue(cue:SVGSVGElement,at:Vector3|null,world:WorldView,w:number,h:number,ox:number,oy:number){
  const inFront=at&&Vector3.Dot(at.subtractToRef(world.camera.position,localOffset),cameraForward)>0;
  if(inFront)world.camera.project(at!,screenPosition,w,h);
  const visible=inFront&&screenPosition.x>=0&&screenPosition.x<=w&&screenPosition.y>=0&&screenPosition.y<=h;
  cue.toggleAttribute('hidden',!visible);
  if(visible){cue.style.left=(screenPosition.x+ox)+'px';cue.style.top=(screenPosition.y+oy)+'px';}
}
interface Actions {amend:()=>void;preview:(id:string)=>void;fly:(id:string,rank:number,runway:boolean,plan:FreeFlightPlan)=>void;restart:()=>void;resume:()=>void;leave:()=>void;previewAward:(model?:string)=>void;feedback:(tone:FeedbackTone)=>void;}
export class Interface {
  station='home';aircraft='j20';selectedMission='s01';mode='campaign';era='';nation='';tier=1;runway=false;region=0;weather=0;lighting=0;gearFilter:GearSlot='missile';
  private modification:ModificationTab=modificationTabs[0];
  private questTab='day';
  private chapter=0;
  private prepared='s01';
  private readonly radar=new TacticalRadar(el('radar'),el('tactical'));
  private readonly aim=document.querySelector<SVGSVGElement>('#aim')!;
  private readonly lockZone=document.querySelector<SVGSVGElement>('#lock-zone')!;
  private readonly leadCue=document.querySelector<SVGSVGElement>('#lead-aim')!;
  private readonly leadPoint=new Vector3();
  private readonly focusPoint=new Vector3();
  private readonly projectionPoint=new Vector3();
  private readonly cooldownButtons=(['counter','turn','boost','evade','missile','bomb'] satisfies CooldownAction[])
    .map(id=>({id,node:el(id),last:-1}));
  private targetView:{world:WorldView;w:number;h:number;radius:number;visible:boolean}|null=null;
  private readonly measureZone=(position:Vector3)=>{
    const view=this.targetView;
    if(!view?.visible)return Infinity;
    const {world,w,h,radius}=view;
    if(Vector3.Dot(position.subtractToRef(world.camera.position,this.projectionPoint),cameraForward)<=0)return Infinity;
    world.camera.project(position,this.projectionPoint,w,h);
    const p=this.projectionPoint;
    if(p.x<0||p.y<0||p.x>w||p.y>h)return Infinity;
    return Math.hypot(p.x-this.focusPoint.x,p.y-this.focusPoint.y)/radius;
  };
  private readonly groundAim=document.querySelector<SVGSVGElement>('#ground-aim')!;
  private readonly pins:{frame:HTMLDivElement;label:HTMLSpanElement}[]=[];
  private readonly presentation:Presentation;
  private readonly purchase=el<HTMLDialogElement>('purchase-confirm');
  private lastHud=-2;
  private nextBombCue=-1;
  private bombCueValid=false;
  private readonly bombCue=new Vector3();
  private killsSeen=0;
  private killUntil=0;
  private strikeUntil=0;
  private toastTimer=0;
  private readonly labelSites=new Float32Array(20);
  constructor(readonly p:Save,readonly commands:Actions){
    this.presentation=new Presentation(commands.previewAward);
    this.aircraft=p.selected;this.selectedMission=campaignStage(p.campaign).id;this.chapter=chapterFor(p.campaign);
    history.replaceState({pixelPage:'home',depth:0},'');
    addEventListener('popstate',event=>{
      if(!el('menu').hidden)this.open(event.state?.pixelPage??'home',false);
    });
    icons();
    for(const card of document.querySelectorAll<HTMLElement>('[data-briefing]')){
      card.style.setProperty('--card-art','url('+resource('briefing/'+card.dataset.briefing+'.webp')+')');
    }
    for(let i=0;i<10;i++){
      const frame=document.createElement('div');frame.className='target-pin';frame.hidden=true;
      const label=document.createElement('span');frame.append(label);el('pins').append(frame);this.pins.push({frame,label});
    }
    document.addEventListener('click',e=>{
      const b=(e.target as Element).closest<HTMLElement>('button');if(!b||b.matches(':disabled'))return;
      const d=b.dataset;
      if(d.exportSave!==undefined){
        const link=document.createElement('a');
        const url=URL.createObjectURL(new Blob([JSON.stringify(p,null,2)],{type:'application/json'}));
        link.href=url;link.download='cangqiong-pilot-v'+p.version+'.json';link.click();
        window.setTimeout(()=>URL.revokeObjectURL(url),1000);return;
      }
      if(d.configure){
        this.aircraft=p.selected;this.chooseModification('weapons',d.configure);this.open('upgrade');return;
      }
      if(d.unmount){
        const prior=p.loadouts[this.aircraft],slot=d.unmount as GearSlot;
        const message=detachWeapon(p,this.aircraft,slot);
        this.result(prior!==p.loadouts[this.aircraft],message,{
          kind:'equip',title:'挂位已清空',detail:'装备已保留，可重新装配'
        },'install');return;
      }
      if(d.nav){
        if(d.mod)this.chooseModification(d.mod);
        this.open(d.nav);
        return;
      }
      if(d.back!==undefined){this.back();return;}
      if(d.mod){this.chooseModification(d.mod);this.render();return;}
      if(d.gear){this.chooseModification(this.modification.id,d.gear);this.render();return;}
      if(d.previewMissile&&missiles[d.previewMissile]){
        const subject=itemById[d.previewMissile];
        if(subject)this.presentation.inspect(subject.name,subject.description,d.previewMissile);
        return;
      }
      if(d.mount){
        const item=itemById[d.mount];
        if(!item)return;
        const previous=p.loadouts[this.aircraft],message=equipItem(p,this.aircraft,d.mount,this.gearFilter as GearSlot);
        this.result(previous!==p.loadouts[this.aircraft],message,{
          kind:item.kind==='skin'?'paint':'equip',title:item.name,detail:'已保存到 '+byAircraft(this.aircraft).name,art:item.visual.icon
        },'install');
        return;
      }
      if(d.resetGear){
        const previous=p.loadouts[this.aircraft],message=resetGear(p,this.aircraft,d.resetGear);
        this.result(previous!==p.loadouts[this.aircraft],message,{
          kind:d.resetGear==='skin'?'paint':'equip',title:'恢复原厂配置',detail:byAircraft(this.aircraft).name
        },'install');return;
      }
      if(d.buy){this.reviewPurchase(d.buy);return;}
      if(d.buyCommit){
        this.purchase.close();
        const old=p.credits,message=buyItem(p,d.buyCommit),item=itemById[d.buyCommit];
        if(item)this.result(p.credits<old,message,{
          kind:'purchase',title:item.name,detail:'已解锁，可直接安装到兼容挂位',prizes:[[item.id,1]],spent:old-p.credits
        },item.grade==='standard'?'supply':'rare',old);
        return;
      }
      if(b.id==='radar-open'){this.radar.open();return;}
      if(d.questTab){this.questTab=d.questTab;this.render();return;}
      if(d.confirmSortie){this.launch(this.prepared);return;}
      if(d.sortie!==undefined){
        this.prepare(campaignStage(p.campaign).id);return;
      }
      if(d.task){
        if(d.task==='free'){this.launch(d.task);return;}
        if(!operations.some(m=>m.id===d.task))return;
        this.prepare(d.task);return;
      }
      if(d.pick||d.stagePick){this.selectedMission=(d.pick??d.stagePick)!;this.updateMissionMap(true);return;}
      if(d.chapter!==undefined){
        this.chapter=Number(d.chapter);
        const active=chapterFor(p.campaign)===this.chapter?p.campaign:this.chapter*10+1;
        this.selectedMission=campaignStage(active).id;this.render();return;
      }
      if(d.chartHome!==undefined){el('mission-chart').classList.remove('zoomed');return;}
      if(d.mode){this.mode=d.mode;this.chapter=chapterFor(p.campaign);this.selectedMission=d.mode==='campaign'?campaignStage(p.campaign).id:'d01';this.render();return;}
      if(d.air){this.aircraft=d.air;this.commands.preview(d.air);this.render();return;}
      if(d.up){
        const part=upgrades.find(u=>u.id===d.up);
        if(!part)return;
        const current=upgradeLevel(p,this.aircraft,part.id),credits=p.credits,before=this.upgradeValue(part.id);
        const message=buyUpgrade(p,this.aircraft,part.id);
        this.result(upgradeLevel(p,this.aircraft,part.id)>current,message,{
          kind:'upgrade',title:part.label,detail:byAircraft(this.aircraft).name+' · '+part.description,
          art:'./items/up-'+part.id+'.webp',before,after:this.upgradeValue(part.id),spent:credits-p.credits
        },'calibrate',credits);
        return;
      }
      if(d.difficulty!==undefined){
        this.tier=Number(d.difficulty);
        for(const level of document.querySelectorAll<HTMLButtonElement>('[data-difficulty]')){
          const active=level.dataset.difficulty===d.difficulty;
          level.classList.toggle('on',active);level.setAttribute('aria-pressed',String(active));
        }
        const award=el('mission-credit-rate');if(award)award.textContent=Math.round(difficulties[this.tier].reward*100)+'%';
        return;
      }
      if(d.do==='equip'){this.equip();return;}
      if(d.do==='resume')commands.resume();
      if(d.do==='restart')commands.restart();
      if(d.do==='leave')commands.leave();
      if(b.id==='prev-plane')this.cycle(-1);
      if(b.id==='next-plane')this.cycle(1);
    });
    document.addEventListener('change',e=>{
      const node=e.target as HTMLInputElement|HTMLSelectElement,id=node.id;
      if(id==='era'||id==='nation'){this[id]=node.value;this.render();return;}
      if(id==='runway'){this.runway=(node as HTMLInputElement).checked;return;}
      if(id==='map-region'||id==='weather'||id==='lighting'){
        if(id==='map-region')this.region=Number(node.value);
        else this[id]=Number(node.value);
        this.render();return;
      }
      if(id==='planned-plane'&&p.unlocked.includes(node.value)){
        if(!saveProfile({...p,selected:node.value})){node.value=p.selected;this.denied('存档失败，出击机型未更换');return;}
        p.selected=this.aircraft=node.value;this.commands.preview(node.value);this.commands.amend();this.render();return;
      }
      const key=node.dataset.setting;
      if(!key)return;
      if(key==='backend'){p.settings.backend=node.value as Save['settings']['backend'];saveProfile(p);try{sessionStorage.removeItem('pixel-sky-webgpu-fallback');}catch{}location.reload();return;}
      if(key==='fps')p.settings.fps=node.value==='90'?90:60;
      if(key==='quality')p.settings.quality=node.value as Save['settings']['quality'];
      if(key==='invert'||key==='mute')p.settings[key]=(node as HTMLInputElement).checked;
      if(key==='sensitivity'||key==='hud'||key==='renderScale')p.settings[key]=Number(node.value);
      this.changed('设置已保存');
    });
    this.render();
  }
  changed(message:string){saveProfile(this.p);this.commands.amend();this.render();this.toast(message);}
  private result(ok:boolean,error:string,receipt:Receipt,tone:FeedbackTone,beforeCredits=this.p.credits){
    if(!ok){this.denied(error);return;}
    clearTimeout(this.toastTimer);el('status-toast').hidden=true;
    this.commands.amend();this.render();
    for(const wallet of [el('credits'),document.querySelector<HTMLElement>('.section-wallet .balance')]){
      if(wallet)countTo(wallet,beforeCredits,this.p.credits);
    }
    this.presentation.show(receipt);this.commands.feedback(tone);
  }
  private reviewPurchase(id:string){
    const item=itemById[id];
    if(!item)return;
    const block=purchaseBlock(this.p,id);
    if(block){this.denied(block);return;}
    this.purchase.innerHTML='<form method="dialog" class="receipt-panel"><header><span class="caption">军需采购</span>'+
      '<h2 id="purchase-title">'+item.name+'</h2><p>'+item.description+'</p></header>'+
      picture(id,'receipt-emblem')+'<span class="reading">支付 '+money(item.price!)+' 信用点</span>'+
      '<button value="cancel">取消</button><button type="button" class="gold" data-buy-commit="'+id+'">确认购入</button></form>';
    this.purchase.showModal();
  }
  private denied(message:string){this.toast(message,true);this.commands.feedback('denied');}
  toast(message:string,failed=false){
    if(!message)return;
    const node=el('status-toast');node.textContent=message;node.hidden=false;node.dataset.failed=String(failed);
    clearTimeout(this.toastTimer);this.toastTimer=window.setTimeout(()=>{node.hidden=true;},2350);
  }
  open(station:string,writeHistory=true){
    if(station!=='home'&&!stationTitles[station])station='home';
    if(writeHistory&&station!==this.station){
      const depth=(history.state?.depth??0)+1;
      history.pushState({pixelPage:station,depth},'');
    }
    this.presentation.clear();
    if(this.purchase.open)this.purchase.close();
    const moving=this.station!==station;
    this.station=station;
    if(station==='home'||station==='sortieprep'||station==='freeprep')this.aircraft=this.p.selected;
    el('application').dataset.screen=station;
    if(studioStations.includes(station))this.commands.preview(this.aircraft);
    this.render();
    if(moving)el('section').querySelector('.route-body')?.animate([{opacity:0,transform:'translateY(5px)'},{opacity:1,transform:'none'}],
      {duration:matchMedia('(prefers-reduced-motion: reduce)').matches?0:210,easing:'ease-out'});
  }
  back(){
    if((history.state?.depth??0)>0)history.back();
    else this.open('home',false);
  }
  cycle(dir:number){
    const current=this.p.unlocked.indexOf(this.p.selected);
    this.aircraft=this.p.unlocked[(current+dir+this.p.unlocked.length)%this.p.unlocked.length];
    this.p.selected=this.aircraft;this.commands.preview(this.aircraft);saveProfile(this.p);this.render();
  }
  equip(){
    const p=this.p,air=byAircraft(this.aircraft),art=itemById['air-'+air.id]?.visual.icon;
    if(!p.unlocked.includes(air.id)){
      const credits=p.credits,message=unlockAircraft(p,air.id);
      this.result(p.unlocked.includes(air.id),message,{
        kind:'aircraft',title:air.name,detail:air.origin+' · '+air.role,art,model:'air-'+air.id,spent:credits-p.credits
      },'ceremony',credits);
      return;
    }
    if(!saveProfile({...p,selected:air.id})){this.denied('存档失败，出击机型未更换');return;}
    p.selected=air.id;this.commands.preview(air.id);
    this.result(true,'',{kind:'equip',title:air.name,detail:'已设为出击机型',art},'install');
  }
  private prepare(id:string){
    this.prepared=id;this.weather=0;this.lighting=0;this.open('sortieprep');
  }
  launch(id:string){
    const mission=operation(id);
    const requirement=sortieBlock(this.p,mission);
    if(requirement){this.denied(requirement);return;}
    this.commands.fly(id,mission.kind==='train'||mission.lesson?0:this.tier,this.runway,id==='free'?{region:this.region,weather:this.weather,lighting:this.lighting}:
      {region:mission.region,weather:this.weather,lighting:this.lighting});
  }
  private filtered(){
    return fleet.filter(a=>(!this.era||a.era===this.era)&&(!this.nation||a.origin.includes(this.nation)));
  }
  render(){
    const p=this.p;
    el('credits').textContent=money(p.credits);
    const level=levelProgress(p.xp),bar=el<HTMLProgressElement>('pilot-xp');
    el('rank').textContent='Lv.'+level.level;
    el('xp-text').textContent=money(level.progress)+' / '+money(level.required)+' EXP';
    bar.max=level.required;bar.value=level.progress;
    el('deck-name').textContent=byAircraft(p.selected).name;
    el('front').hidden=this.station!=='home';el('navigation').hidden=this.station!=='home';
    const shell=el('section');shell.hidden=this.station==='home';
    const scroll=shell.dataset.station===this.station?shell.querySelector(this.station==='upgrade'?'.kit-grid':'.route-body')?.scrollTop??0:0;
    shell.dataset.station=this.station;
    if(shell.hidden)return;
    const title=stationTitles[this.station];
    shell.className='route-page '+this.station+(studioStations.includes(this.station)?' route-studio':' route-terminal');
    shell.setAttribute('aria-label',title);
    shell.innerHTML='<header class="station-heading"><button class="square" data-back aria-label="返回上一层">'+icon('left')+'</button><div><div class="route-crumb">飞行指挥中心</div><h2>'+title+'</h2></div><span class="section-wallet"><img src="./items/credits-wallet.webp" alt="" width="30" height="23"><b class="balance">'+money(p.credits)+'</b><small>信用点</small></span></header><div class="route-body">'+this.page()+'</div>';
    if(this.station==='missions')this.updateMissionMap(false);
    if(scroll)shell.querySelector(this.station==='upgrade'?'.kit-grid':'.route-body')!.scrollTop=scroll;
    for(const button of shell.querySelectorAll<HTMLButtonElement>('button[data-mod],button[data-mode],button[data-difficulty],button[data-quest-tab],button[data-air],button[data-gear]')){
      button.setAttribute('aria-pressed',String(button.classList.contains('on')));
    }
  }
  page(){
    switch(this.station){
      case 'hangar':return this.hangar();
      case 'upgrade':return this.upgrade();
      case 'missions':return this.missions();
      case 'training':return this.training();
      case 'freeprep':return this.freeprep();
      case 'sortieprep':return this.preparation();
      case 'quests':return this.quests();
      case 'records':return this.records();
      case 'settings':return this.settings();
      default:return '';
    }
  }
  hangar(){
    const a=byAircraft(this.aircraft),owned=this.p.unlocked.includes(a.id);
    const needed=airframeLevels[a.id]??1,hasLevel=owned||pilotLevel(this.p.xp)>=needed;
    const fit=combatConfiguration(this.p,a.id);
    const visible=this.filtered().sort((first,second)=>Number(second.id===a.id)-Number(first.id===a.id));
    const filter=(id:string,label:string,items:[string,string][],value:string)=>'<label>'+label+'<select id="'+id+'"><option value="">全部</option>'+items.map(([k,l])=>'<option value="'+k+'"'+selected(k===value)+'>'+l+'</option>').join('')+'</select></label>';
    const options=[...new Set(fleet.flatMap(x=>x.origin.split('／')))].map(value=>[value,value] as [string,string]);
    const details='<aside class="air-spec glass"><div class="caption">'+a.origin+' · '+eras[a.era]+'</div><h3>'+a.name+'</h3><p>'+a.role+'</p><dl>'+
      metric('机体耐久',String(a.durability))+metric('翼展',a.span+' 米')+metric('游戏极速',Math.round(a.maxSpeed*3.6)+' 公里/时')+metric('对地弹药',String(fit.groundStores))+metric('机动响应',Math.round(a.grip*100)+'%')+metric('推力系数',Math.round(a.acceleration*100)+'%')+
      '</dl><p class="note">'+a.specialty+'</p><button class="gold" data-do="equip"'+disabled(a.support||!hasLevel)+'>'+icon(owned?'check':'lock')+(a.support?'任务编队使用':owned?'选作出击战机':hasLevel?'解锁 · 1150':'需要飞行员 Lv.'+needed)+'</button><div class="station-actions"><button data-nav="upgrade" data-mod="skin">战机涂装</button><button data-nav="upgrade" data-mod="weapons">战机改装</button></div></aside>';
    return '<div class="hangar-filters glass">'+filter('nation','研制国家',options,this.nation)+filter('era','航空年代',Object.entries(eras),this.era)+'</div>'+
      details+'<div class="fleet-strip">'+visible.map((p,index)=>'<button class="'+(p.id===a.id?'on':'')+'" data-air="'+p.id+'"><img width="104" height="46" loading="'+(index<8?'eager':'lazy')+'" src="./cards/'+p.id+'.webp" alt=""><b>'+p.name+'</b><small>'+(p.support?'任务支援':this.p.unlocked.includes(p.id)?p.durability+' 耐久':'Lv.'+(airframeLevels[p.id]??1)+' 可解锁')+'</small></button>').join('')+'</div>';
  }
  private upgradeValue(part:string,profile=this.p){
    const c=combatConfiguration(profile,this.aircraft),a=byAircraft(this.aircraft);
    const current:Record<string,string>={armor:(1-c.armor*.065).toFixed(3)+'× 扰动',engine:c.engine.toFixed(2)+'× 推力',
      maneuver:c.grip.toFixed(2)+'× 响应',radar:c.radar+' 米',weapons:gunDamage(a,c.gun).toFixed(1)+' / 发',
      warhead:c.hasAirMissile?c.missile.damage.toFixed(1)+' / 枚':Math.round(c.missilePower*100)+'% 对地制导伤害'};
    return current[part];
  }
  private chooseModification(id:string,slot?:string){
    const tab=modificationTabs.find(t=>t.id===id)??modificationTabs[0];
    const slots:readonly GearSlot[]=tab.slots;
    this.modification=tab;
    this.gearFilter=slots.find(key=>key===(slot??this.gearFilter))??slots[0];
  }
  upgrade(){
    const p=this.p,a=byAircraft(this.aircraft),cfg=combatConfiguration(p,a.id),fit=p.loadouts[a.id]??{};
    const slot=this.gearFilter,tab=this.modification;
    const labels:Record<GearSlot,string>={missile:'空空弹',cannon:'航炮',bomb:'对地武器',engine:'推进',radar:'雷达',counter:'反制',skin:'涂装'};
    const active=slot==='cannon'?(cfg.hasCannon?cannonID(a):''):slot==='missile'?(cfg.hasAirMissile?cfg.missile.id:''):
      slot==='bomb'?(cfg.groundStores?cfg.groundWeapon:''):slot==='skin'?fit.skin??'factory':fit[slot]??'';
    const parts:readonly string[]=slot==='missile'?['warhead']:slot==='cannon'?['weapons']:slot==='bomb'?[]:tab.parts;
    const upgradesForSlot=upgrades.filter(u=>parts.includes(u.id)).map(u=>{
      const level=upgradeLevel(p,a.id,u.id),suitable=upgradeCompatible(a.id,u.id);
      const after=level<3&&suitable?this.upgradeValue(u.id,{...p,improvements:{...p.improvements,[a.id+':'+u.id]:level+1}}):'';
      const price=upgradePrice(level);
      return '<article class="upgrade-item" data-level="'+level+'"><img class="item-art" src="./items/up-'+u.id+'.webp" alt=""><strong>'+u.label+'</strong><span>'+
        (suitable?this.upgradeValue(u.id):'本机不适用')+(after?' <b class="next-stat">→ '+after+'</b>':'')+' · '+u.description+'</span><button data-up="'+u.id+
        '"'+disabled(level>=3||!suitable||p.credits<price)+'>'+(level>=3?'已满级':!suitable?'不适用':price+' 信用点')+'</button><small>等级 '+level+' / 3</small></article>';
    }).join('');
    const choices=slot==='cannon'&&active?'<article class="asset-card cannon-spec">'+picture(active)+'<div><h4>'+itemById[active]?.name+
      '</h4><p>无限弹药，按住连续射击。</p><dl class="mount-counts">'+metric('单发伤害',gunDamage(a,cfg.gun).toFixed(1))+
      metric('射速',(60/gunCycle(a)).toFixed(0)+' 发/分')+metric('弹速',cannonFor(a)[1]+' 米/秒')+'</dl></div></article>':
      gears.filter(it=>gearSlot(it.kind)===slot&&(slot!=='cannon'||compatible(a,it))).map(it=>{
        const owned=p.inventory[it.id]>0,match=compatible(a,it),installed=active===it.id,block=purchaseBlock(p,it.id);
        const stats=missiles[it.id],info=stats?'<small>'+stats.range+' 米 · 伤害 '+missileDamage(a,stats,upgradeLevel(p,a.id,'warhead')).toFixed(1)+
          ' · 极速 '+stats.speed+' 米/秒</small>':it.kind==='strike'?'<small>伤害 '+Math.round(guidedStrike.damage*cfg.missilePower)+'</small>':'';
        const action=!match?'<button disabled>机型或挂位不兼容</button>':installed?'<button disabled>已装配</button>':
          it.id==='interceptor'||it.id==='factory'||it.id==='bomb'&&a.bombs?'<button data-reset-gear="'+slot+'">恢复原厂</button>':
          owned?'<button class="gold" data-mount="'+it.id+'">安装</button>':
          '<button class="gold" data-buy="'+it.id+'"'+disabled(!!block)+'>'+(block||'购买 · '+money(it.price!)+' 信用点')+'</button>';
        return '<article class="asset-card '+it.grade+'">'+picture(it.id)+'<div><h4>'+it.name+'</h4><p>'+it.description+'</p>'+info+
          (stats?'<button class="inspect-link" data-preview-missile="'+it.id+'">3D 检视</button>':'')+'</div>'+action+'</article>';
      }).join('');
    return '<div class="loadout-deck"><aside class="glass kit-spec"><h3>'+a.name+'</h3><div class="mount-station">'+
      icon(slot==='cannon'?'cannon':slot==='bomb'?'bomb':slot==='missile'?'missile':'tools')+
      '<div><strong>'+slotName(slot,a)+'</strong><p>'+(itemById[active]?.name??'原厂配置')+'</p></div></div>'+
      (slot==='bomb'&&active?'<button data-unmount="bomb">拆卸对地武器</button>':'')+
      (fit[slot]&&slot!=='bomb'?'<button data-reset-gear="'+slot+'">恢复原厂</button>':'')+
      '</aside><div class="modification-tabs"><div class="kit-categories">'+modificationTabs.map(t=>
        '<button class="'+(t===tab?'on':'')+'" data-mod="'+t.id+'">'+t.name+'</button>').join('')+'</div>'+
      (tab.slots.length>1?'<div class="kit-categories mount-tabs">'+tab.slots.map(key=>
        '<button class="'+(key===slot?'on':'')+'" data-gear="'+key+'">'+labels[key]+'</button>').join('')+'</div>':'')+
      '</div><div id="kit-list" class="kit-grid">'+upgradesForSlot+choices+'</div></div>';
  }
  private missionState(m:Operation){
    if(m.campaign&&m.campaign>this.p.campaign)return 'locked';
    return this.p.completed.includes(m.id)?'complete':'ready';
  }
  missions(){
    const campaign=this.mode==='campaign';
    const list=operations.filter(m=>campaign?m.campaign&&chapterFor(m.campaign)===this.chapter:!m.campaign&&!m.lesson&&m.id!=='d04'&&m.id!=='free');
    const markerList=campaign?(this.chapter===0?list.slice(0,4):
      [...new Map(list.map(m=>[m.region,m])).values()]):list;
    const chapterList=campaign?'<div class="chapter-picker" role="group" aria-label="战役章节">'+chapters.map((c,i)=>
      '<button data-chapter="'+i+'" aria-pressed="'+(i===this.chapter)+'" title="'+c.name+' · Lv.'+c.level+'">'+
      '<b>'+String(i+1).padStart(2,'0')+'</b><span>'+c.name+'</span></button>').join('')+'</div>':'';
    const stages=campaign?'<div class="stage-picker" role="group" aria-label="章节关卡">'+list.map((m,i)=>
      '<button data-stage-pick="'+m.id+'" data-boss="'+!!m.engagement?.ace+'" title="'+m.name+'">'+
      (m.engagement?.ace?'10 · 王牌':String(i+1).padStart(2,'0'))+'<span>'+m.name+'</span></button>').join('')+'</div>':'';
    return '<div class="mission-grid"><section class="mission-map glass" id="mission-chart" aria-label="全球战役地图">'+
      '<header class="chart-bar"><div class="mission-tabs" aria-label="任务类型"><button data-mode="campaign" class="'+(campaign?'on':'')+'">战役关卡</button>'+
      '<button data-mode="independent" class="'+(!campaign?'on':'')+'">独立任务</button></div>'+
      '<button type="button" data-chart-home>'+icon('target')+'全球视图</button></header>'+
      chapterList+'<div class="chart-window"><div class="chart-world"><img src="./charts/world.webp" alt="太平洋居中的全球地图" fetchpriority="high">'+
      campaignChart(markerList)+markerList.map(chartMarker).join('')+'<i class="chart-sweep" aria-hidden="true"></i></div></div>'+
      stages+'<footer class="chart-key"><span>全球作战态势</span><span><i></i>可挑战</span><span><i></i>已完成</span><span><i></i>未解锁</span></footer></section>'+
      '<article class="mission-brief glass"><div class="mission-details" id="mission-details" aria-live="polite"></div>'+
      '<footer class="mission-launch"><div class="levels" role="group" aria-label="任务难度">'+
      difficulties.map((d,i)=>'<button data-difficulty="'+i+'" class="'+(this.tier===i?'on':'')+'">'+d.name+'</button>').join('')+
      '</div><button class="gold" id="mission-launch"></button></footer></article></div>';
  }
  private updateMissionMap(focus:boolean){
    const m=operation(this.selectedMission),theatre=theatres[m.region];
    const state=this.missionState(m),chart=el('mission-chart'),[x,y]=chartPoint(m.id);
    chart.style.setProperty('--focus-x',x+'%');chart.style.setProperty('--focus-y',y+'%');
    chart.classList.toggle('zoomed',focus);
    for(const button of chart.querySelectorAll<HTMLButtonElement>('[data-pick],[data-stage-pick]')){
      const id=(button.dataset.pick??button.dataset.stagePick)!;
      button.dataset.state=this.missionState(operation(id));
      button.setAttribute('aria-pressed',String(id===m.id));
      button.setAttribute('aria-label',operation(id).name+' · '+({locked:'未解锁',complete:'已完成',ready:'可挑战'})[button.dataset.state as 'locked'|'complete'|'ready']);
    }
    const section=m.engagement?objectiveNames[m.engagement.objective]:m.kind==='escort'?'运输护航':m.kind==='ground'?'对地打靶':'空域拦截';
    const boss=!!m.engagement?.ace;
    const briefing=m.campaign?chapterFor(m.campaign)+1+'章 · 第 '+((m.campaign-1)%10+1)+' 关':theatre.weather;
    const threat=['训练目标','常规编队','高威胁空域','精锐编队'][m.threat];
    el('mission-details').innerHTML='<div class="mission-emblem" style="--mission-image:url('+resource('charts/'+theatre.id+'.webp')+')">'+
      '<div><span class="caption">'+theatre.name+' · '+briefing+'</span><h3>'+m.name+'</h3></div></div>'+
      '<div class="mission-copy"><p>'+m.detail+'</p><dl class="mission-intel">'+metric('作战类别',section)+metric('敌情',boss?'王牌 · '+byAircraft(m.engagement!.ace!).name:threat)+
      (m.campaign?metric('战役强度',m.campaign+' / 60'):'')+
      metric('出击战机',byAircraft(this.p.selected).name)+'</dl><div class="mission-award"><header><b>'+
      (state==='complete'?'首胜奖励已入库':'首胜奖励')+'</b><small>信用点 <strong id="mission-credit-rate">'+
      Math.round(difficulties[this.tier].reward*100)+'%</strong></small></header><div class="prize-tray">'+rewardChips(firstClearLoot)+
      '</div></div></div>';
    const launch=el<HTMLButtonElement>('mission-launch');
    launch.dataset.task=m.id;launch.disabled=state==='locked';
    launch.innerHTML=icon(state==='locked'?'lock':'plane')+(state==='locked'?'先完成前序战役':state==='complete'?'再次出击':'开始任务');
  }
  training(){
    return routeIntro('飞行学院','实战训练课程','选择一门课程进入对应空域。使用机库已选战机。','vector','training')+
      '<div class="route-cards">'+['d04','t02','t03','t04','t05'].map((id,i)=>{
        const mission=operation(id),art=['vector','up-engine','cannon-jet','interceptor','veil'][i];
        return '<article class="asset-card">'+(picture(art)||'<img class="item-art" src="./items/'+art+'.webp" alt="">')+
          '<div><h4>'+mission.name+'</h4><p>'+mission.detail+'</p></div><button data-task="'+id+'">'+(this.p.completed.includes(id)?'再次训练':'开始训练')+'</button></article>';
      }).join('')+'</div>';
  }
  freeprep(){return this.dispatch('free');}
  preparation(){return this.dispatch(this.prepared);}
  private dispatch(id:string){
    const mission=operation(id),free=id==='free',map=theatres[free?this.region:mission.region];
    const plane=byAircraft(this.p.selected),loadout=combatConfiguration(this.p,plane.id,mission.kind==='ground');
    const blocked=sortieBlock(this.p,mission,loadout);
    const slot=mission.kind==='ground'?'bomb':'missile';
    const progressionLocked=this.missionState(mission)==='locked';
    const alternate=this.p.unlocked.filter(id=>id!==plane.id&&!sortieBlock(this.p,mission,combatConfiguration(this.p,id)));

    const pick=(id:string,label:string,values:string[],current:number)=>'<label>'+label+'<select id="'+id+'">'+values.map((v,i)=>'<option value="'+i+'"'+selected(current===i)+'>'+v+'</option>').join('')+'</select></label>';
    const maps=free?pick('map-region','地图',theatres.map(t=>t.name),this.region):'';
    const weather=pick('weather','天气',['场景默认','晴朗通透','阴天','降雨','雷暴','海雾','降雪','夜战'],this.weather);
    const light=pick('lighting','时间',['场景默认','晴日午后','金色黄昏','夜间'],this.lighting);
    const start=free?'data-task="free"':'data-confirm-sortie="true"';
    return '<div class="dispatch-grid"><article class="glass briefing-flight"><div class="caption">'+map.name+'</div><h3>'+mission.name+'</h3><p>'+mission.detail+'</p>'+
      '<div class="prep-chart" role="img" aria-label="'+map.name+'地形图" style="background-image:url('+resource('charts/'+map.id+'.webp')+')"></div>'+
      '<span class="caption">出击机型</span><select id="planned-plane" aria-label="出击机型">'+this.p.unlocked.map(id=>'<option value="'+id+'"'+selected(id===plane.id)+'>'+byAircraft(id).name+'</option>').join('')+'</select>'+
      '<dl>'+metric('机体结构',String(plane.durability))+metric('雷达探测',(loadout.radar/1000).toFixed(1)+' 公里')+
      (loadout.groundStores?metric(loadout.groundWeapon==='shorebolt'?'对地制导弹':'炸弹',String(loadout.groundStores)):'')+'</dl><button data-configure="'+slot+'">检视当前挂载</button></article>'+
      '<article class="glass dispatch-options"><h3>航线条件</h3><p>默认环境 · '+map.weather+'</p>'+maps+weather+light+
      (free?'<label class="runway-option"><input type="checkbox" id="runway" '+(this.runway?'checked':'')+'>从跑道起飞</label>':'<p>任务难度 · '+difficulties[mission.kind==='train'||mission.lesson?0:this.tier].name+'</p>')+
      (blocked?'<section class="sortie-block" role="status"><strong>待补齐任务配置</strong><p>'+blocked+'</p>'+
        (progressionLocked?'<button data-nav="training">进入训练获取经验</button>':
          '<button data-configure="'+slot+'">打开'+(slot==='bomb'?'对地':'空空')+'挂位</button>')+
        (!progressionLocked&&alternate.length?'<p>也可在左侧选择 '+alternate.map(a=>byAircraft(a).name).slice(0,3).join('、')+'</p>':'')+'</section>':'')+
      '<button class="gold" '+start+disabled(!!blocked)+'>'+icon('plane')+(free?'开始连续迎击':'确认出击')+'</button></article></div>';
  }
  quests(){
    const tabs=[['day','每日任务'],['main','主线任务'],['challenge','挑战'],['achievement','成就']];
    const groups:Record<string,string[]>={main:['first','first-win','intercept'],challenge:['flight-wing','tideline']};
    const list=rewards.filter(r=>this.questTab==='day'?r.period==='day':this.questTab==='achievement'?
      r.metric==='xp':groups[this.questTab]?.includes(r.id));
    const links=this.questTab==='main'?'<button class="gold" data-nav="missions">'+icon('target')+'查看战役</button>':
      this.questTab==='challenge'?'<button class="gold" data-task="d05">'+icon('plane')+'雷暴前线</button>':'';
    return routeIntro('','任务中心','任务奖励在达到条件后自动发放。','flarewing','coast')+
      '<div class="quest-tabs">'+tabs.map(([id,name])=>'<button class="'+(this.questTab===id?'on':'')+'" data-quest-tab="'+id+'">'+name+'</button>').join('')+'</div>'+
      (links?'<div class="task-actions">'+links+'</div>':'')+'<div class="route-cards">'+list.map(r=>{
        const {earned,claimed,progress}=rewardStatus(this.p,r);
        return '<article class="asset-card reward-card '+(claimed?'claimed':'')+'">'+picture(r.prize.find(p=>p[0]!=='credits')?.[0]??'credits')+
          '<div><h4>'+r.name+'</h4><p>'+r.criteria+'</p><progress max="'+r.threshold+'" value="'+progress+'"></progress><div class="prize-tray">'+
          rewardChips(r.prize)+'</div></div><small class="award-status">'+(claimed?'已发放':earned?'待入账':'进行中')+'</small></article>';
      }).join('')+'</div>';
  }
  records(){
    const level=levelProgress(this.p.xp);
    return routeIntro('飞行员档案','战绩与收藏','等级 Lv.'+level.level+' · 已累计 '+money(this.p.xp)+' EXP。','xp','training')+
      '<section class="pilot-next glass"><h3>下一级 · Lv.'+(level.level+1)+'</h3><p>'+money(level.progress)+' / '+money(level.required)+' EXP</p>'+
      '<progress max="'+level.required+'" value="'+level.progress+'"></progress><div class="prize-tray">'+rewardChips(levelReward(level.level+1))+'</div></section>'+
      '<dl class="pilot-summary">'+metric('出击次数',String(this.p.sorties))+metric('击落目标',String(this.p.kills))+metric('飞行里程',(this.p.distance/1000).toFixed(1)+' 公里')+
      metric('已解锁机体',String(this.p.unlocked.length))+metric('任务胜利',String(this.p.victories))+'</dl>'+
      '<div class="route-cards">'+this.p.records.map(r=>{
        const aircraft=fleet.find(a=>a.name===r.aircraft);
        const name=operations.find(o=>o.name===r.name)?.name??'历次出击';
        return '<article class="asset-card">'+(aircraft?picture('air-'+aircraft.id):picture('credits'))+'<div><h4>'+name+'</h4><p>'+(aircraft?.name??'战机')+' · '+clock(r.seconds)+' · 击毁 '+r.kills+'</p></div><b>'+(r.win?'完成':'失败')+' · '+money(r.score)+'</b></article>';
      }).join('')+'</div>';
  }
  settings(){
    const ctx=this.p.settings;
    const options=(key:string,caption:string,items:[string,string][])=>'<label>'+caption+'<select data-setting="'+key+'">'+items.map(([id,name])=>'<option value="'+id+'"'+selected(String(ctx[key as keyof typeof ctx])===id)+'>'+name+'</option>').join('')+'</select></label>';
    return '<div class="panel-scroll settings-grid"><article class="glass"><h3>画面与设备</h3><p id="backend-status">当前后端 '+(el('application').dataset.backend==='gpu'?'WebGPU':'WebGL2')+'</p>'+
      options('backend','渲染方式',[['auto','自动 · 优先 WebGPU'],['gpu','优先 WebGPU'],['gl','使用 WebGL2']])+
      options('fps','帧率上限',[['60','60 FPS'],['90','90 FPS']])+options('quality','渲染品质',[['auto','自动 · 1080p'],['ultra','极高 · 1440p'],['high','高 · 1080p'],['medium','中 · 900p'],['low','低 · 720p']])+
      '<label>渲染比例<input type="range" data-setting="renderScale" min=".65" max="1" step=".05" value="'+ctx.renderScale+'"></label><label>仪表大小<input type="range" data-setting="hud" min=".8" max="1.23" step=".03" value="'+ctx.hud+'"></label></article>'+
      '<article class="glass"><h3>飞行控制</h3>' +
      '<label><input type="checkbox" data-setting="invert" '+(ctx.invert?'checked':'')+'>反转俯仰</label>'+
      '<label><input type="checkbox" data-setting="mute" '+(ctx.mute?'checked':'')+'>静音</label>'+
      '<label>滑屏灵敏度<input type="range" data-setting="sensitivity" min=".45" max="1.55" step=".05" value="'+ctx.sensitivity+'"></label><button data-export-save>导出飞行员存档</button>'+
      '<details><summary>飞行操作</summary><p>手机在空白区域滑动转向或升降，另一根手指可同时操作武器。左侧反制键会根据威胁选择热诱饵、箔条或电子干扰。</p><p>方向键或 W/A/S/D 操纵。Q/E 偏航，R/V 调油门，Shift 加力。空格航炮，F 导弹，B 炸弹，U 掉头，J/K/L 向左/自动/向右躲避，Z 反制，G 起落架，C 切视角。</p></details></article></div>';
  }
  flight(s:Sortie){
    this.presentation.clear();
    this.targetView=null;
    el('menu').hidden=true;el('overlay').hidden=true;el('hud').hidden=false;
    el('application').dataset.screen='flight';this.lastHud=-2;this.killsSeen=0;this.killUntil=0;this.strikeUntil=0;el('hit-confirm').hidden=true;el('kill-notice').hidden=true;
    const missileArt=el<HTMLImageElement>('missile-art'),art=itemById[s.missile.id]?.visual.icon;
    if(art)missileArt.src=art;
    missileArt.hidden=!art;
    el('hud-goal').textContent=s.op.name;
    el('gun').hidden=!s.weapons.includes('gun');el('bomb').hidden=!s.weapons.includes('bomb');el('missile').hidden=!s.weapons.includes('missile');
    el('bomb').querySelector('span')!.textContent=s.groundWeapon==='shorebolt'?'对地弹':'炸弹';
    el('gear').hidden=s.type.gearFixed;
  }
  showHangar(){
    el('menu').hidden=false;el('hud').hidden=true;el('overlay').hidden=true;
    history.replaceState({pixelPage:'home',depth:0},'');
    this.open('home',false);
  }
  pause(endless=false){
    this.closeTactical();
    const panel=el('overlay');panel.hidden=false;
    panel.innerHTML='<section class="pause-card glass"><div class="caption">当前任务</div><h2>战场已暂停</h2><div class="dialog-actions"><button class="gold" data-do="resume">继续空战</button><button data-do="restart">重新出击</button><button data-do="leave">'+(endless?'结算并撤离':'返回大厅')+'</button></div></section>';
  }
  finish(r:Debrief,award:number,previousXp=this.p.xp){
    this.closeTactical();
    const overlay=el('overlay');el('hud').hidden=true;overlay.hidden=false;
    el('application').dataset.screen='result';
    const xp=levelProgress(this.p.xp),before=levelProgress(previousXp);
    const earned=this.p.xp-previousXp,promoted=xp.level>before.level;
    const combined=new Map<string,number>();
    for(let i=before.level+1;i<=xp.level;i++)for(const [id,amount] of levelReward(i))combined.set(id,(combined.get(id)??0)+amount);
    const rewards=[...combined];
    const gain=earned>0?'<section class="promotion '+(promoted?'earned':'')+'" aria-label="飞行经验奖励">'+picture('xp')+
      '<div><strong>'+(promoted?'晋升 · ':'')+'Lv.'+xp.level+'</strong><small>+'+money(earned)+' EXP</small>'+
      '<progress value="'+xp.progress+'" max="'+xp.required+'"></progress></div>'+
      (promoted?'<div class="prize-tray">'+rewardChips(rewards)+'</div>':'')+'</section>':'';
    const pct=(v:number|null)=>v!==null?v+'%':'—';
    overlay.innerHTML='<section class="debrief '+(r.win?'won':'lost')+'"><div class="debrief-title"><div class="caption">'+r.operation.name+'</div><h2>'+icon(r.win?'star':'shield')+(r.operation.kind==='free'?'自由空战结算':r.win?'任务胜利':'任务失败')+'</h2><p>'+r.reason+'</p></div>'+
      '<div class="debrief-main glass"><div class="score"><span>综合得分</span><b>'+money(r.score)+'</b><strong>'+r.grade+'</strong></div><dl>'+
      metric('击毁目标',String(r.kills))+metric('任务时长',clock(r.time))+metric('航炮命中',pct(r.accuracy))+metric('导弹命中',pct(r.missileAccuracy))+
      metric('炸弹命中',pct(r.bombAccuracy))+metric('航行里程',(r.distance/1000).toFixed(2)+' 公里')+metric('最高速度',Math.round(r.peak*3.6)+' 公里/时')+
      metric('最高高度',Math.round(r.altitude)+' 米')+metric('机体状态',r.hp>0?money(Math.ceil(r.hp))+' 耐久':'失事')+metric('成功反制',String(r.evaded))+'</dl>'+
      '<div class="result-types">'+Object.entries(r.types).map(([n,v])=>n+' × '+v).join(' · ')+'</div><div class="awards">'+picture('credits')+'<span>+'+money(award)+' 信用点</span>'+picture('xp')+'<span>+'+money(earned)+' EXP</span></div>'+gain+'</div>'+
      '<div class="dialog-actions"><button data-do="leave">返回大厅</button><button class="gold" data-do="restart">'+(r.win?'再次挑战':'再次出击')+'</button></div></section>';
    const score=overlay.querySelector<HTMLElement>('.score b');
    if(score)countTo(score,0,r.score);
  }
  impact(e:FlightEvent,time:number){
    if(e.kind!=='hit'||e.side!==0||!e.target||e.terminal)return;
    const feedback=el('hit-confirm');
    feedback.dataset.strike=e.weapon==='gun'?'cannon':'missile';
    feedback.textContent=e.weapon==='gun'?'航炮命中':'导弹命中';
    this.strikeUntil=time+.40;
    feedback.hidden=false;
  }
  closeTactical(){return this.radar.close();}
  prepareRotation(){
    this.closeTactical();
    if(this.purchase.open)this.purchase.close();
    this.presentation.clear();
  }
  telemetry(game:Sortie,world:WorldView,anchors:ReadonlyMap<number,Vector3>,pose:FlightPose){
    const player=game.player,canvas=world.entry.canvas.getBoundingClientRect(),hud=el('hud').getBoundingClientRect();
    const {width:w,height:h}=canvas;
    if(!w||!h)return;
    const offsetX=canvas.left-hud.left,offsetY=canvas.top-hud.top;
    const update=game.time-this.lastHud>.070;
    if(update){
      this.lastHud=game.time;
      if(game.time>=this.strikeUntil)el('hit-confirm').hidden=true;
      const kill=el('kill-notice');
      if(game.stats.kills>this.killsSeen){
        this.killsSeen=game.stats.kills;this.killUntil=game.time+2.25;
        el('hit-confirm').hidden=true;
        kill.textContent='目标击毁 · 累计 '+this.killsSeen;kill.hidden=false;
      }else if(game.time>=this.killUntil)kill.hidden=true;
      el('speed').textContent=String(Math.round(player.speed*3.6));el('alt').textContent=String(Math.max(0,Math.round(player.position.y)));
      el('heading').textContent=String(Math.round(player.heading())%360).padStart(3,'0')+'°';
      el('flight-time').textContent=clock(game.time);el('throttle').textContent=Math.round(player.throttle*100)+'%';
      el('burn').textContent=player.boost>.13?'加力中':'';
      el('boost').classList.toggle('on',player.controls.boost);
      el('hp').textContent=String(Math.ceil(player.hp));el('hp').title='耐久上限 '+player.maxHp;
      el('hp-bar').style.width=player.hp/player.maxHp*100+'%';
      el('hp-bar').classList.toggle('impact',game.time-player.hitTime<.32);
      el('missile').title=itemById[game.missile.id]?.name??'';
      el('bombs').textContent=String(player.bombs);
      el('gear').classList.toggle('on',player.gearTarget>0);
      const boss=game.enemies.find(e=>e.alive&&e.ace);
      const stock=game.enemies.filter(e=>e.alive).length;
      el('enemy-counter').textContent=game.endless?'第 '+game.wave+' 波 · 敌机 '+stock:game.op.kind==='train'?'航标 '+game.gate+' / 3':
        game.op.kind==='free'?'飞行诊断':game.op.kind==='ground'?'待摧毁 '+(game.total-game.lost):
          '波次 '+game.wave+' / '+game.waves.length+' · 待击落 '+Math.max(0,game.total-game.lost);
      const bossHealth=el('boss-health');
      bossHealth.hidden=!boss;
      if(boss){bossHealth.textContent='王牌 '+Math.ceil(boss.hp/boss.maxHp*100)+'%';bossHealth.style.setProperty('--health',boss.hp/boss.maxHp*100+'%');}
      const w=game.warning,threat=w.threat,defense=game.defense;
      const type=threat?seekerNames[threat.seeker]:'敌方',kind=defense.next(w),cool=Math.max(0,defense.readyAt-game.time);
      const distance=threat?' · '+(w.distance<1000?Math.round(w.distance)+' 米':(w.distance/1000).toFixed(1)+' 公里'):'';
      const alert=w.stage>=3?(w.stage===4?'紧急 · ':'')+type+'导弹来袭'+distance:w.stage===2?type+'导弹发射'+distance:
        w.stage===1?'敌机雷达锁定':player.stall>.49?'失速 · 加大推力':
        player.grounded?'跑道滑行':'';
      const a=el('alerts');a.textContent=alert||(player.bombs>0&&game.groundWeapon==='shorebolt'?(game.groundLock()?'地面目标就绪':'向下瞄准地面目标'):'');a.dataset.danger=String(w.stage>0||player.stall>.49);
      const counter=el('counter');
      counter.classList.toggle('armed',w.stage>=2&&cool<=0&&kind!==null&&defense.stocks[kind]>0);
      counter.title='热诱饵 '+defense.stocks.flare+' · 箔条 '+defense.stocks.chaff+' · 电子干扰 '+defense.stocks.ecm;
      el('touch-guide').hidden=game.time>6;
      this.radar.draw(game);
    }
    world.camera.getDirectionToRef(cameraAxis,cameraForward);
    world.camera.getDirectionToRef(rightAxis,cameraRight);
    world.camera.getDirectionToRef(upAxis,cameraUp);
    const phase=game.targeting.inside?(game.lockProgress===1?'locked':'track'):'search';
    this.lockZone.dataset.state=phase;
    el('missile').dataset.lock=phase==='locked'?'ready':phase==='track'?'tracking':'none';
    for(const button of this.cooldownButtons){
      const value=Math.round(game.cooldown(button.id)*1000);
      if(value===button.last)continue;
      button.last=value;
      button.node.style.setProperty('--cooldown',value*.1+'%');
      button.node.classList.toggle('cooling',value>0);
    }
    gunSight(pose.position,pose.forward,worldPosition);
    placeCue(this.aim,worldPosition,world,w,h,offsetX,offsetY);
    this.aim.dataset.lock=String(phase==='locked');
    placeCue(this.leadCue,game.aimLead(this.leadPoint)?this.leadPoint:null,world,w,h,offsetX,offsetY);
    const radius=lockRadius(world.camera.fov,h),canAcquire=game.op.kind!=='train'&&game.op.kind!=='ground';
    if(!this.targetView){this.targetView={world,w,h,radius,visible:false};game.targeting.projection=this.measureZone;}
    const targetView=this.targetView;
    targetView.w=w;targetView.h=h;targetView.radius=radius;
    targetView.visible=canAcquire&&Vector3.Dot(worldPosition.subtractToRef(world.camera.position,localOffset),cameraForward)>0;
    this.lockZone.toggleAttribute('hidden',!targetView.visible);
    if(targetView.visible){
      world.camera.project(worldPosition,this.focusPoint,w,h);
      this.lockZone.style.width=radius*2+'px';
      this.lockZone.style.left=this.focusPoint.x+offsetX+'px';
      this.lockZone.style.top=this.focusPoint.y+offsetY+'px';
    }
    const camera=world.camera.position;
    const baseItems=game.op.kind==='train'&&game.gates[game.gate]?[{position:game.gates[game.gate],alive:true,id:game.gate+1}]:game.targetPoints;
    const active=game.enemies.filter(enemy=>enemy.alive).sort((a,b)=>{
      if(a===game.locked||a.ace&&!b.ace&&b!==game.locked)return -1;
      if(b===game.locked||b.ace&&!a.ace)return 1;
      return Vector3.DistanceSquared(player.position,a.position)-Vector3.DistanceSquared(player.position,b.position);
    });
    const tagged=[...active,...(game.ally.alive?[game.ally]:[]),...baseItems];
    let assigned=0;
    for(let i=0;i<this.pins.length;i++){
      const node=this.pins[i],target=tagged[i];
      if(!target?.alive){node.frame.hidden=true;continue;}
      const range=Vector3.Distance(player.position,target.position),ally=target===game.ally||game.op.kind==='train';
      if(range>game.radar){node.frame.hidden=true;continue;}
      const anchor='type' in target?anchors.get(target.id):target.position;
      if(!anchor){node.frame.hidden=true;continue;}
      anchor.subtractToRef(camera,localOffset);
      const front=Vector3.Dot(localOffset,cameraForward)>0;
      world.camera.project(anchor,screenPosition,w,h);
      const left=Math.max(50,w*.10),right=w-left,top=Math.max(63,h*.16),bottom=h-Math.min(102,h*.25);
      let x=screenPosition.x,y=screenPosition.y;
      const edge=!front||x<0||x>w||y<0||y>h;
      let degrees=0;
      if(edge){
        let side=Vector3.Dot(localOffset,cameraRight),up=-Vector3.Dot(localOffset,cameraUp);
        if(!front&&Math.abs(side)<10&&Math.abs(up)<10)up=1;
        const k=Math.max(Math.abs(side)/Math.max(4,w*.5-left),Math.abs(up)/Math.max(4,(bottom-top)*.5),.0001);
        x=clamp(w*.5+side/k,left,right);y=clamp((top+bottom)*.5+up/k,top,bottom);
        degrees=Math.atan2(up,side)*180/Math.PI+90;
      }
      const lock=target===game.locked&&phase==='locked';
      node.frame.classList.toggle('tracked',target===game.locked&&phase==='track');
      let label=(i<3||lock)&&(!edge||i===0);
      for(let j=0;j<assigned&&label;j++)if(Math.abs(this.labelSites[j*2]-x)<108&&Math.abs(this.labelSites[j*2+1]-y)<26)label=false;
      if(label){this.labelSites[assigned*2]=x;this.labelSites[assigned*2+1]=y;assigned++;}
      node.frame.hidden=false;node.frame.classList.toggle('locked',lock);
      node.frame.classList.toggle('ace','ace' in target&&target.ace);
      node.frame.classList.toggle('off',edge);node.frame.classList.toggle('ally',ally);
      if(update&&'type' in target){
        const p=anchor;
        node.frame.dataset.obscured=String(world.terrain.terrainMasks(camera.x,camera.y,camera.z,p.x,p.y,p.z));
      }else if(!('type' in target))delete node.frame.dataset.obscured;
      node.frame.dataset.target='type' in target?String(target.id):'';
      node.frame.style.left=(x+offsetX)+'px';node.frame.style.top=(y+offsetY)+'px';node.frame.style.setProperty('--bearing',degrees+'deg');
      node.label.hidden=!label;
      const name='type' in target?target.type.name.split(/ (?:Fighting|Hornet|Gripen|Mustang|Thunderbolt|Prowler|Hawkeye|Hercules|Spirit|Viper)/)[0]:
        game.op.kind==='train'?'航标 '+(game.gate+1):'标靶 '+(i-active.length+1);
      node.label.textContent=name+' · '+(range/1000).toFixed(2)+' 公里'+(node.frame.dataset.obscured==='true'?' · 地形遮挡':'');
    }
    const impact=el('damage-bearing'),hit=game.time-player.hitTime<.48;
    impact.hidden=!hit;
    if(hit){
      const x=Vector3.Dot(cameraRight,player.hitFrom),y=-Vector3.Dot(cameraUp,player.hitFrom);
      const angle=Math.atan2(x,Math.abs(y)>.08?-y:Vector3.Dot(cameraForward,player.hitFrom));
      const r=Math.min(w,h)*.23;
      impact.style.left=w/2+Math.sin(angle)*r+'px';impact.style.top=h/2-Math.cos(angle)*r+'px';
      impact.style.rotate=angle+'rad';
    }
    let drop:Vector3|null=null;
    if(player.bombs>0){
      if(game.groundWeapon==='shorebolt')drop=game.groundLock()?.position??null;
      else{
        if(game.time>=this.nextBombCue||game.time<this.nextBombCue-.12){
          this.nextBombCue=game.time+.065;
          this.bombCueValid=game.bombLanding(this.bombCue);
        }
        if(this.bombCueValid)drop=this.bombCue;
      }
    }else this.nextBombCue=-1;
    placeCue(this.groundAim,drop,world,w,h,offsetX,offsetY);
    this.groundAim.dataset.guided=String(game.groundWeapon==='shorebolt');
    const warn=el('incoming');
    const danger=game.warning.threat;
    warn.hidden=!danger;
    if(danger){
      const threat=danger.position;
      world.camera.project(threat,screenPosition,w,h);
      const alignment=threat.subtractToRef(camera,localOffset);
      const front=Vector3.Dot(alignment,cameraForward)>=0;
      const angle=Math.atan2((screenPosition.x-w/2)*(front?1:-1),front?h/2-screenPosition.y:-h/2);
      const r=Math.min(w,h)*.32;
      warn.style.left=(w/2+Math.sin(angle)*r)+'px';warn.style.top=(h/2-Math.cos(angle)*r)+'px';warn.style.rotate=angle+'rad';
    }
  }
}
