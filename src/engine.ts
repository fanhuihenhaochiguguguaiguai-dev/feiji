import { rotate } from './scene-runtime';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import { byAircraft,operation,theatres,type PlaneSpec,type FreeFlightPlan } from './data';
import { FlightPose, FLIGHT_STEP } from './flight';
import { Sortie,type FlightEvent } from './sortie';
import { AircraftView, makeMissile } from './aircraft-view';
import { CombatArt } from './combat-art';
import { WorldView,asset,type OpenEngine } from './renderer';
export { openEngine } from './renderer';
import { loadTerrain } from './terrain';
import { RenderBudget } from './render-budget';
import { el,Interface,studioStations } from './interface';
import { FlightInput } from './inputs';
import { HangarOrbit } from './hangar-control';
import { FlightAudio } from './audio';
import { combatConfiguration,consumeReserve,recordSortie,saveProfile,sortieBlock,type Backend,type Save } from './profile';
import { pilotLevel } from './progression';
import { defenseNames } from './defense';
import { missiles } from './items';
import { openWreckPhysics,type WreckPhysics } from './wreck-physics';

const small=()=>matchMedia('(any-pointer: coarse)').matches;
const direction=new Vector3(),soundRight=new Vector3(),rightward=new Vector3(1,0,0),soundUp=new Vector3(),upward=new Vector3(0,1,0);
export class Game {
  readonly root=el('application');
  readonly engine:OpenEngine['app'];
  readonly world:WorldView;
  readonly art:CombatArt;
  readonly pilot:AircraftView;
  readonly support:AircraftView;
  readonly foes:AircraftView[];
  readonly input:FlightInput;
  readonly hangar:HangarOrbit;
  readonly ui:Interface;
  readonly audio=new FlightAudio();
  private readonly portrait=matchMedia('(orientation: portrait)');
  readonly budget:RenderBudget;
  sortie:Sortie|null=null;
  preview:PlaneSpec;
  state:'loading'|'home'|'flight'|'settling'|'pause'|'result'='loading';
  private busy=false;
  private last=0;
  private acc=0;
  private readonly playerPose=new FlightPose();
  private readonly targetAnchors=new Map<number,Vector3>();
  private clock=0;
  private settleFor=0;
  private frameId=0;
  private notion={id:'s01',rank:1,runway:false,plan:{region:0,weather:0,lighting:0}};
  private meshChange=new Set<string>();
  private timeSinceImpact=0;
  private readonly seaMist=new Vector3();
  private awardPlane:PlaneSpec|null=null;
  private awardMissile:ReturnType<typeof makeMissile>|null=null;
  private readonly awardPosition=new Vector3(0,2.28,0);
  private awardClock=0;
  private labSortie=false;
  private freeSeed=crypto.getRandomValues(new Uint32Array(1))[0];
  qualityOverride:import('./profile').Quality|null=null;
  constructor(readonly entry:OpenEngine,readonly p:Save){
    this.engine=entry.app;
    this.root.dataset.backend=entry.backend;this.root.dataset.touch=String(small());
    this.world=new WorldView(entry);
    this.art=new CombatArt(this.world);
    this.pilot=new AircraftView(this.world,0);
    this.foes=[1,2,3,4].map(i=>new AircraftView(this.world,i));
    this.support=new AircraftView(this.world,5);
    this.preview=byAircraft(this.p.selected);
    this.budget=new RenderBudget(this.engine.device,small());
    this.input=new FlightInput(entry.canvas,command=>this.action(command));
    this.ui=new Interface(this.p,{
      amend:()=>this.settings(),preview:(id)=>void this.previewAircraft(id),
      fly:(id,rank,runway,plan)=>void this.begin(id,rank,runway,plan),
      restart:()=>void this.begin(this.notion.id,this.notion.rank,this.notion.runway,this.notion.plan,this.labSortie),
      resume:()=>this.resume(),leave:()=>this.leave(),
      previewAward:id=>this.presentAward(id),feedback:tone=>this.audio.play(tone)
    });
    this.settings();
    const fullscreen=el('fullscreen'),rotate=el('orientation-fullscreen');
    const orientation=screen.orientation as ScreenOrientation&{lock?:(value:'landscape')=>Promise<void>};
    fullscreen.hidden=!document.fullscreenEnabled;
    rotate.hidden=!document.fullscreenEnabled||!orientation?.lock;
    const enterFullscreen=async()=>{
      if(!document.fullscreenElement)await this.root.requestFullscreen({navigationUI:'hide'});
      if(orientation?.lock)await orientation.lock('landscape').catch(()=>{});
    };
    fullscreen.addEventListener('click',()=>{
      const change=document.fullscreenElement?document.exitFullscreen():enterFullscreen();
      void change.catch(()=>this.ui.toast('当前浏览器无法进入全屏'));
    });
    rotate.addEventListener('click',()=>{void enterFullscreen().catch(()=>{});});
    this.portrait.addEventListener('change',event=>{
      this.last=this.acc=0;this.world.cameraReset=true;
      if(!event.matches)return;
      this.ui.prepareRotation();
      this.audio.update(false,0,0,0,false);
      if(this.state==='flight')this.pause();
    });
    document.addEventListener('fullscreenchange',()=>{
      const active=!!document.fullscreenElement;
      fullscreen.classList.toggle('on',active);
      fullscreen.setAttribute('aria-label',active?'退出全屏':'进入全屏');
      this.world.cameraReset=true;
    });
    this.root.addEventListener('pointerdown',()=>this.audio.activate(),{once:true});
    this.root.addEventListener('click',event=>{
      if(this.state==='home'&&(event.target as Element).closest('button'))this.audio.play('switch');
    });
    for(const [id,cmd] of [['pause','pause'],['gear','gear'],['view','view'],['next-target','lock'],['weapon-mode','weapon'],['counter','counter'],['spares','spares'],['assist','assist']]){
      const button=el(id);
      button.addEventListener('pointerdown',e=>{
        if(e.pointerType==='mouse')return;
        e.preventDefault();this.action(cmd);
      });
      button.addEventListener('click',e=>{
        const source=(e as PointerEvent).pointerType;
        if(source==='touch'||source==='pen')return;
        this.action(cmd);
      });
    }
    this.hangar=new HangarOrbit(entry.canvas,()=>this.state==='home'&&studioStations.includes(this.ui.station));
    addEventListener('resize',()=>{this.world.cameraReset=true;this.root.dataset.touch=String(small());});
    document.addEventListener('visibilitychange',()=>{if(document.hidden&&this.state==='flight')this.pause();this.last=0;this.acc=0;});
  }
  settings(){
    this.audio.mute=this.p.settings.mute;
    this.root.style.setProperty('--hud',this.p.settings.hud.toFixed(2));
  }
  async init(){
    await Promise.all([this.world.ready,this.pilot.request(this.preview)]);
    this.pilot.preview(this.preview,this.clock,combatConfiguration(this.p,this.preview.id),0);
    this.state='home';
    el('boot').hidden=true;el('menu').hidden=false;this.ui.open('home');
    if(this.entry.fallback)this.ui.toast('已使用 WebGL2');
    this.engine.on('update',()=>this.frame(performance.now()));
    this.engine.on('postrender',()=>{
      if(this.state==='flight'&&this.sortie)this.ui.telemetry(this.sortie,this.world,this.targetAnchors,this.playerPose);
    });
    this.engine.start();
  }
  presentAward(id?:string){
    const aircraftWasActive=this.awardPlane!==null;
    this.awardPlane=null;
    this.awardMissile?.dispose();this.awardMissile=null;
    this.awardClock=this.clock;
    this.root.dataset.reveal=id?'model':'none';
    this.world.setAwardLighting(Boolean(id));
    if(!id){
      if(aircraftWasActive)void this.previewAircraft(this.ui.aircraft);
      return;
    }
    if(id.startsWith('air-')){
      const subject=this.awardPlane=byAircraft(id.slice(4));
      void this.pilot.request(subject).catch(e=>{
        if(this.awardPlane!==subject)return;
        this.root.dataset.reveal='flat';
        document.getElementById('acquisition')?.classList.remove('show-model');
        console.error(e);
      });
    }else{
      const subject=missiles[id];
      if(!subject)return;
      const model=this.awardMissile=makeMissile(this.engine.root,'入库展示 '+id,subject.shape);
      model.position.set(0,2.28,0);
    }
  }
  async previewAircraft(id:string){
    this.preview=byAircraft(id);
    try {await this.pilot.request(this.preview);}
    catch(e){if(this.state!=='loading')this.ui.toast('该机型资源未能读取');console.error(e);}
    this.world.assets.trimFleet(new Set([this.preview.id,this.p.selected,...this.foes.map(f=>f.loaded),this.support.loaded]));
  }
  async begin(id:string,rank:number,runway:boolean,plan:FreeFlightPlan,lab=false){
    if(this.busy)return;
    if(!lab){
      const blocked=sortieBlock(this.p,operation(id));
      if(blocked){this.ui.toast(blocked,true);return;}
    }
    this.busy=true;this.audio.activate();
    const type=byAircraft(lab?'f16':this.p.selected),old=this.state;
    this.input.on=false;
    this.state='loading';
    el('boot').hidden=false;el('boot-text').textContent='正在准备出击';
    const request=operation(id),op=lab?{...request,region:plan.region,name:'地貌验收空域'}:id==='free'?{...request,region:plan.region}:request;
    const configuration=combatConfiguration(this.p,type.id,lab||op.kind==='ground');
    let rigid:WreckPhysics|null=null;
    try {
      const theatre=theatres[op.region];
      await loadTerrain(theatre.seed,asset('world/'+theatre.id+'.height'));
      await this.world.setTheme(op.region);
      rigid=await openWreckPhysics(FLIGHT_STEP);
      const mission=new Sortie(op,type,{rank,runway,armor:configuration.armor,engine:0,
      stores:configuration.stores,repair:this.p.bases.includes('repair'),radar:this.p.bases.includes('radar'),configuration,
      seed:op.kind==='free'&&!lab?++this.freeSeed:undefined,diagnostics:lab
    },e=>this.event(e),this.world.terrain,rigid);
      await this.pilot.request(type);
      await Promise.all(mission.enemies.map((e,i)=>e.alive?this.foes[i].request(e.type):null));
      if(mission.enemies.some(e=>e.alive)){
        for(const id of mission.enemyKit)void this.world.assets.container('fleet/'+id+'.glb').catch(()=>{});
      }
      if(mission.ally.alive)await this.support.request(mission.ally.type);
      this.sortie?.releaseRigidBodies();
      this.labSortie=lab;this.notion={id,rank,runway,plan};this.sortie=mission;rigid=null;this.acc=0;
      this.world.showDeck(false);this.world.resetMarkers();this.world.configureFlightWeather(plan.weather,plan.lighting);this.art.weather=plan.weather;this.world.view=0;
      this.input.reset(runway&&op.kind==='free'?.12:.74);this.input.on=true;
      this.art.clear();this.meshChange.clear();
      this.state='flight';this.ui.flight(mission);el('boot').hidden=true;
    }catch(e){
      rigid?.dispose();
      this.state=old;el('boot').hidden=true;
      if(old==='flight')this.input.on=true;
      this.ui.toast('出击资源读取失败，请重试');console.error(e);
    }finally{this.busy=false;}
  }
  resume(){
    if(this.state!=='pause')return;
    this.state='flight';this.input.on=true;this.acc=0;el('overlay').hidden=true;
    this.audio.activate();
  }
  pause(){
    if(this.state!=='flight')return;
    this.state='pause';this.input.on=false;this.input.reset(false);this.ui.pause(!!this.sortie?.endless);
  }
  leave(){
    const active=this.sortie;
    if(this.state==='pause'&&active?.endless&&active.active&&active.stats.kills>0){
      active.end(active.cleared>0,'已撤离 · 击落 '+active.stats.kills+' 架 · 完成 '+active.cleared+' 波');
      this.finish(active);return;
    }
    active?.releaseRigidBodies();this.sortie=null;this.input.on=false;this.art.clear();this.state='home';this.world.showDeck(true);this.world.view=0;
    for(const other of [...this.foes,this.support])other.pivot.setEnabled(false);
    void this.previewAircraft(this.p.selected);this.ui.showHangar();
  }
  action(name:string){
    if(this.portrait.matches)return;
    if(name==='pause'){if(this.ui.closeTactical())return;if(this.state==='flight')this.pause();else this.resume();return;}
    if(!this.sortie||this.state!=='flight')return;
    if(name==='view'){
      this.world.view=1-this.world.view;this.world.cameraReset=true;
      this.ui.toast(['跟随视角','第一人称座舱'][this.world.view]);this.audio.play('switch');
    }
    if(name==='lock')this.sortie.acquire(true);
    if(name==='weapon'){this.sortie.nextWeapon();this.input.selected=this.sortie.weapon;this.audio.play('switch');}
    if(name==='counter')this.sortie.counter();
    if(name==='spares'){
      const mission=this.sortie;
      if(mission.spares<=0||!mission.defense.canReplenish()){this.ui.toast('反制弹仍满载');return;}
      if(!this.labSortie&&!consumeReserve(this.p)){this.ui.toast('补给未消耗');return;}
      mission.spares--;mission.defense.replenish();this.ui.toast('已消耗一个补给包');
    }
    if(name==='assist'){
      this.p.settings.assist=!this.p.settings.assist;saveProfile(this.p);
      this.ui.toast(this.p.settings.assist?'飞行辅助开启':'飞行辅助关闭');this.audio.play('switch');
    }
    if(name==='gear'){
      if(this.sortie.player.gearChange())this.ui.toast(this.sortie.player.gearTarget?'起落架放下':'起落架收起');
      else this.ui.toast(this.sortie.player.grounded?'请起飞后收起':'当前状态无法切换起落架');
    }
  }
  event(e:FlightEvent){
    this.art.event(e);
    this.ui.impact(e,this.sortie?.time??0);
    if(e.kind==='counter'){
      if(e.side!==0){this.engine.fire('sortie-event',e);return;}
      const kind=e.defense?defenseNames[e.defense]:'反制';
      const message=e.cue==='diverted'?kind+'生效 · 来袭导弹偏离':e.cue==='resisted'?kind+'已释放 · 导弹仍在追踪':
        e.cue==='released'?kind+'已释放':e.cue==='cooldown'?'反制冷却中':e.cue==='empty'?'适用的反制措施已用尽':'当前没有可反制的来袭威胁';
      if(e.cue==='diverted'||e.cue==='released'||e.cue==='resisted')this.audio.play(e.cue==='diverted'?'deflected':'counter');
      this.ui.toast(message);return;
    }
    const p=this.sortie?.player;
    const range=p?e.at.subtractToRef(p.position,direction).length():0;
    let pan=0,elevation=0;
    if(p&&range>2){
      rightward.rotateByQuaternionToRef(p.orientation,soundRight);
      upward.rotateByQuaternionToRef(p.orientation,soundUp);
      pan=Math.atan2(Vector3.Dot(soundRight,direction),Vector3.Dot(p.forward,direction));
      elevation=Vector3.Dot(soundUp,direction)/range;
    }
    this.audio.battle(e,range,pan,elevation);
    this.engine.fire('sortie-event',e);
    if(e.kind==='wave'){
      const ready=this.sortie;if(!ready)return;
      this.ui.toast(ready.endless?'第 '+ready.wave+' 波来袭 · 弹药已补给':
        ready.loadout.repair?'下一批目标进入空域 · 已补充反制弹':'下一批目标进入空域');
    }
  }
  finish(s:Sortie){
    s.releaseRigidBodies();
    this.state='result';this.input.on=false;this.input.reset(false);
    const previousXp=this.p.xp,report=s.report(),credits=this.labSortie||s.endless&&!report.kills?0:recordSortie(this.p,report,s.type.id);
    if(pilotLevel(this.p.xp)>pilotLevel(previousXp))this.audio.play('ceremony');
    else if(report.win)this.audio.play('victory');
    if(report.win){this.world.showDeck(true);this.preview=s.type;}
    this.ui.finish(report,credits,previousXp);
  }
  frame(now:number){
    const span=this.last?Math.max(0,(now-this.last)/1000):1/60;
    const dt=Math.min(.14,span);this.last=now;
    if(document.hidden||this.portrait.matches){this.engine.renderNextFrame=false;return;}
    const s=this.sortie,home=this.state==='home'||this.state==='result'&&s?.win===true;
    if(this.state!=='pause')this.clock+=dt;
    this.engine.renderNextFrame=true;
    if(this.state==='home'&&!this.awardPlane&&!this.awardMissile&&!studioStations.includes(this.ui.station)){
      this.audio.update(false,0,0,0,false,true);
      this.engine.renderNextFrame=false;return;
    }
    const level=this.budget.apply(this.qualityOverride??this.p.settings.quality,span,this.p.settings.renderScale);
    this.world.level=level;this.world.applyQuality(level);
    const player=s?.player;
    if(this.state==='flight'&&s){
      this.acc=Math.min(.25,this.acc+span);
      while(this.acc>=FLIGHT_STEP&&s.active){
        const cfg=this.p.settings;
        this.input.selected=s.weapon;
        s.step(FLIGHT_STEP,this.input.read(FLIGHT_STEP,cfg.assist,cfg.invert,cfg.sensitivity));this.acc-=FLIGHT_STEP;
      }
      if(!s.active){
        this.state='settling';this.settleFor=.87;this.input.on=false;this.input.reset(false);
      }
    }else if(this.state==='settling'&&s){
      this.settleFor-=dt;
      this.acc+=dt;
      while(this.acc>=FLIGHT_STEP){s.advanceWrecks(FLIGHT_STEP);this.acc-=FLIGHT_STEP;}
      if(this.settleFor<=0)this.finish(s);
    }
    const result=this.state==='result';
    if(home&&this.awardMissile){
      this.pilot.pivot.setEnabled(false);
      const age=this.clock-this.awardClock;
      rotate(this.awardMissile,31,age*35-47,-52);
      this.world.previewOrdnance(this.awardPosition,age);
    }else if(home&&this.awardPlane){
      const plane=this.awardPlane;
      this.world.preview(plane,this.clock,'reveal');
      this.pilot.preview(plane,this.clock,combatConfiguration(this.p,plane.id),.26-(this.clock-this.awardClock)*.34);
    }else if(home||result&&s?.win){
      this.hangar.update(dt);
      this.world.tilt=this.hangar.elevation;
      this.world.preview(this.preview,this.clock,result?'result':this.ui.station,this.hangar.distance);
      this.pilot.preview(this.preview,this.clock,combatConfiguration(this.p,this.preview.id),this.hangar.angle);
      for(const a of [...this.foes,this.support])a.pivot.setEnabled(false);
    }else if(s&&player&&!this.world.fixed){
      const alpha=this.state==='flight'?this.acc/FLIGHT_STEP:1;
      this.playerPose.sample(player,alpha);
      this.world.flight(player,dt,s.time,s.locked??s.manual,this.playerPose);
      this.pilot.sync(player,this.clock,s.loadout.configuration?.paint??'',this.world.view===1,false,s,undefined,alpha);
      this.targetAnchors.clear();
      for(let i=0;i<s.enemies.length;i++){
        const enemy=s.enemies[i],view=this.foes[i];
        if(enemy.alive&&enemy.type.id!==view.loaded&&!this.meshChange.has(i+':'+enemy.type.id)){
          const key=i+':'+enemy.type.id;this.meshChange.add(key);
          void view.request(enemy.type).finally(()=>this.meshChange.delete(key)).catch(console.error);
        }
        view.sync(enemy,this.clock,'',false,false,undefined,undefined,alpha);
        if(view.pivot.isEnabled()&&enemy.alive)this.targetAnchors.set(enemy.id,view.anchor);
      }
      this.support.sync(s.ally,this.clock,'',false,false,undefined,undefined,alpha);
      if(this.support.pivot.isEnabled()&&s.ally.alive)this.targetAnchors.set(s.ally.id,this.support.anchor);
      for(const [i,t] of s.targetPoints.entries()){
        const m=this.world.targets[i];if(!m)continue; m.position.copyFrom(t.position);m.setEnabled(t.alive);m.scaling.set(28,Math.max(4,12*t.hp/100),26);
      }
      for(const [i,g] of s.gates.entries()){
        const mesh=this.world.rings[i];mesh.position.copyFrom(g);mesh.setEnabled(i===s.gate);
      }
      const effectTime=this.state==='pause'?0:dt;
      if(this.state==='flight'){
        this.world.updateWater(player,s.time);
        const p=player.position,h=s.world.water(p.x,p.z,s.time),altitude=p.y-h;
        const low=altitude<27&&player.speed>95&&s.world.classify(p.x,p.z)==='water';
        if(low)this.seaMist.set(p.x-player.forward.x*10,h+.5,p.z-player.forward.z*10);
        const hardware=this.art.skim(low?this.seaMist:null,low?Math.max(0,1-altitude/27):0,level);
        this.timeSinceImpact+=dt;
        if(this.timeSinceImpact>.097){
          this.timeSinceImpact=0;
          if(low&&!hardware)this.art.burst(this.seaMist,2,'mist',.65);
        }
      }
      this.world.updateShaders(s.time,this.clock);
      this.art.update(s,effectTime,this.world.camera.position,this.world.camera.rotationQuaternion,level,this.clock,this.playerPose,alpha);
      this.art.flush();
      this.root.dataset.hit=String(s.time-player.hitTime<.35);
    }
    if(this.frameId++%4===0&&(!player||this.state!=='flight'))this.root.dataset.hit='false';
    this.audio.update(this.state==='flight',player?.throttle??.05,player?.speed??0,player?.boost??0,!!player?.type.props.length,home);
    if(home||!s||this.world.fixed)this.world.updateShaders(this.clock,this.clock);

  }
}
