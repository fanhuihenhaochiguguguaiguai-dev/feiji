import { ADDRESS_CLAMP_TO_EDGE, Color, Entity, FILTER_LINEAR, PIXELFORMAT_RGBA8, Quat, StandardMaterial, Texture, Vec3, type ContainerResource, type AnimTrack } from 'playcanvas';
import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { PlaneSpec } from './data';
import { Airframe, FlightPose, above } from './flight';
import type { Sortie } from './sortie';
import type { CombatConfiguration } from './profile';
import { groundMount } from './items';
import { calibrateAircraft,finishAirframe,type AirframeFinish } from './aircraft-materials';
import { material, primitive, type WorldView } from './renderer';

const zero=new Vec3();
const tones=['#f0b77f','#f09251','#90e0fa','#c9ac68','#d2a550'];
type Gauge={name:string;canvas:HTMLCanvasElement;texture:Texture;material:StandardMaterial};
export function makeMissile(parent:Entity,name:string,shape:number){
  const e=new Entity(name);parent.addChild(e);
  const shell=material('钛合金弹体',shape===1?'#c5cdd1':shape===2?'#aab4bb':shape===3?'#52614d':'#dfdfda',.54,.39);
  const rear=material('喷管与尾翼','#56616c',.67,.42);
  const band=material('识别环',tones[shape]??tones[0],.25,.38);
  const len=[3.8,2.78,3.23,2.56,3.12][shape]??3.63;
  const radius=[.24,.19,.21,.40,.30][shape]??.23;
  primitive(e,'弹体','cylinder',shell,0,0,0,radius,len-.55,radius).setLocalEulerAngles(90,0,0);
  primitive(e,'整流罩','cone',shell,0,0,-(len-.5)*.5,radius,.64,radius).setLocalEulerAngles(-90,0,0);
  primitive(e,'引信色环','cylinder',band,0,0,-len*.33,radius*1.045,.13,radius*1.045).setLocalEulerAngles(90,0,0);
  primitive(e,'尾喷口','cylinder',rear,0,0,len*.42,radius*.93,.14,radius*.93).setLocalEulerAngles(90,0,0);
  for(let i=0;i<4;i++){
    const fin=primitive(e,'弹翼','box',rear,0,0,len*.29,i%2?.57:.035,i%2?.035:.57,.31);
    fin.setLocalEulerAngles(0,0,shape===1?45:0);
  }
  e.once('destroy',()=>{shell.destroy();rear.destroy();band.destroy();});return e;
}

export class AircraftView {
  readonly pivot=new Entity('飞机位置');
  readonly pose=new FlightPose();
  private readonly center=new Vec3();
  private readonly projectedCenter=new Vec3();
  readonly anchor=new Vector3();
  lod=0;
  loaded='';
  private pending='';
  private requestId=0;
  private root:Entity|null=null;
  private high:Entity|null=null;
  private combat:Entity|null=null;
  private low:Entity|null=null;
  private cockpit:Entity|null=null;
  private animated:Entity[]=[];
  private readonly gears:{node:Entity;stowed:Quat;down:Quat}[]=[];
  private readonly gearPose=new Quat();
  private stand:Airframe|null=null;
  private oldPaint='';
  private style=-1;
  private readonly paints=new Map<StandardMaterial,AirframeFinish>();
  private lastDamage=-1;
  private readonly originalPoses=new Map<Entity,Vec3>();
  private readonly mounted:Entity[]=[];
  private payload:Entity|null=null;
  private payloadShape=-1;
  private readonly gauges:Gauge[]=[];
  private readonly rotors:Entity[];
  private nextInstrument=0;
  constructor(readonly world:WorldView,readonly slot:number){
    (slot===0?world.entry.app.root:world.vehicles).addChild(this.pivot);
    const fire=material('高温喷焰外层','#bd6942',0,.5);fire.useLighting=false;fire.emissive.set(1.78,.44,.15);fire.update();
    const core=material('喷焰白炽核心','#e1b7ff',0,.4);core.useLighting=false;core.emissive.set(2.8,1.53,2.85);core.update();
    this.rotors=Array.from({length:4},()=>{
      const plume=new Entity('加力喷口');this.pivot.addChild(plume);
      primitive(plume,'扩散喷焰','cone',fire,0,0,0,1,1,1);
      primitive(plume,'白炽核心','cone',core,0,-.21,0,.66,.59,.66);
      return plume;
    });
    this.pivot.once('destroy',()=>{fire.destroy();core.destroy();});
    this.pivot.enabled=false;
  }
  async request(spec:PlaneSpec){
    if(spec.id===this.loaded){
      if(this.pending&&this.pending!==spec.id){this.requestId++;this.pending='';}
      return;
    }
    const serial=++this.requestId;this.pending=spec.id;
    const resource=(await this.world.assets.load('fleet/'+spec.id+'.glb','container')).resource as ContainerResource;
    if(serial!==this.requestId)return;
    const root:Entity=resource.instantiateRenderEntity();
    const group=(name:string)=>root.findByName(name) as Entity|null;
    const high=group('Exterior'),combat=group('Combat'),low=group('LOD'),cockpit=group('Cockpit');
    if(!high||!combat||!low){root.destroy();throw new Error('机型 LOD 缺失 '+spec.id);}
    this.root?.destroy();
    for(const {material} of this.paints.values())material.destroy();
    for(const g of this.gauges){g.texture.destroy();g.material.destroy();}
    this.paints.clear();this.gauges.length=this.mounted.length=0;this.originalPoses.clear();
    this.root=root;this.high=high;this.combat=combat;this.low=low;this.cockpit=cockpit;
    // Read the authored mesh bounds while the container is still in model coordinates.
    let bounds:import('playcanvas').BoundingBox|undefined;
    for(const render of combat.findComponents('render'))for(const mesh of render.meshInstances){
      if(bounds)bounds.add(mesh.aabb);else bounds=mesh.aabb.clone();
    }
    this.center.copy(bounds?.center??zero);
    this.lod=0;
    this.pivot.addChild(root);
    for(const mesh of root.findComponents('render')){
      mesh.castShadows=this.slot===0;
      for(const instance of mesh.meshInstances){
        const m=instance.material;
        if(!(m instanceof StandardMaterial))continue;
        calibrateAircraft(m,this.world.entry.app.graphicsDevice.maxAnisotropy);
        if(/skin|belly|panel/i.test(m.name)){
          let entry=this.paints.get(m);
          if(!entry){
            const clone=m.clone();
            entry={material:clone,base:m.diffuse.clone(),coat:m.clearCoat,gloss:m.gloss};
            this.paints.set(m,entry);
          }
          instance.material=entry.material;
        }
      }
    }
    const displayNames=/^(Display_|Gauge_)/;
    if(cockpit){
      cockpit.setLocalPosition(spec.eye[0],spec.eye[1],spec.eye[2]);
      cockpit.enabled=false;
      if(this.slot===0)for(const display of cockpit.find(n=>displayNames.test(n.name)) as Entity[])this.instrument(display);
    }
    this.animated=high.find(n=>/^(Aileron|Elevator|Canard|Rudder\d|Gear_|Prop_|Bay_|Store_|RadarSpin)/.test(n.name)) as Entity[];
    for(const n of this.animated)this.originalPoses.set(n,n.getLocalEulerAngles().clone());
    this.gears.length=0;
    for(const {resource:clip} of (resource.animations as {resource:AnimTrack}[]|undefined)??[]){
      const node=group(clip.name),data=clip.outputs[0]?.data;
      if(!node||!data||!/^Gear_\d+$/.test(clip.name)||data.length<8)continue;
      const n=data.length;
      this.gears.push({node,stowed:new Quat(data[0],data[1],data[2],data[3]),down:new Quat(data[n-4],data[n-3],data[n-2],data[n-1])});
    }
    this.loaded=spec.id;this.pending='';this.oldPaint='';this.style=-1;this.lastDamage=-1;this.nextInstrument=0;
  }
  dispose(){
    for(const {material} of this.paints.values())material.destroy();
    for(const g of this.gauges){g.texture.destroy();g.material.destroy();}
    this.pivot.destroy();
  }
  get requested(){return this.pending;}
  preview(spec:PlaneSpec,time:number,configuration:CombatConfiguration,heading:number){
    if(this.stand?.type!==spec)this.stand=new Airframe(0,spec,0);
    const v=this.stand;
    v.position.set(0,Math.max(1.03,spec.gearClearance),0);v.gear=1;v.throttle=.06;v.missiles=configuration.airMissiles;v.bombs=configuration.groundStores;
    Quaternion.RotationAxisToRef(above,-.15+heading,v.orientation);
    this.sync(v,time,configuration.paint,false,true,undefined,configuration.missile.shape,1,configuration.groundWeapon);
  }
  sync(p:Airframe,time:number,paint='',inside=false,preview=false,sortie?:Sortie,style=sortie?.missile.shape??0,alpha=1,groundWeapon=sortie?.groundWeapon??'bomb'){
    this.pivot.enabled=!!this.high&&this.loaded===p.type.id&&(p.alive||p.down>0);
    if(!this.pivot.enabled||!this.high||!this.combat||!this.low)return;
    const {position:at,orientation:q}=this.pose.sample(p,alpha);
    this.pivot.setPosition(at.x,at.y,at.z);
    this.pivot.setRotation(q.x,q.y,q.z,q.w);
    this.pivot.getWorldTransform().transformPoint(this.center,this.projectedCenter);
    this.anchor.set(this.projectedCenter.x,this.projectedCenter.y,this.projectedCenter.z);
    const range=Vector3.Distance(at,this.world.camera.position);
    const height=this.world.entry.canvas.clientHeight;
    const pixels=Math.max(p.type.span,p.type.length)*height/(2*Math.max(1,range)*Math.tan(this.world.camera.fov*.5));
    const exterior=range<228||pixels>(this.lod===0?45:57);
    const combat=range<(this.lod===1?1950:1700)||pixels>(this.lod===1?5.2:6.8);
    this.lod=preview||this.slot===0||exterior?0:combat?1:2;
    const high=this.lod===0,mid=this.lod===1;
    this.high.enabled=high&&!inside;this.combat.enabled=mid&&!inside;this.low.enabled=!high&&!mid&&!inside;
    if(this.cockpit)this.cockpit.enabled=inside;
    const wear=preview?0:p.down?1:Math.max(0,Math.min(1,(1-p.hp/p.maxHp-.12)*1.2));
    if(paint!==this.oldPaint||Math.abs(wear-this.lastDamage)>.04){
      this.oldPaint=paint;this.lastDamage=wear;
      const tint=paint?new Color().fromString(paint):null;
      for(const surface of this.paints.values())finishAirframe(surface,tint,wear);
    }
    if(this.slot===0&&style!==this.style){
      this.style=style;
      for(const m of this.mounted)m.destroy();
      this.mounted.length=0;
      for(const mount of this.animated.filter(n=>/^Store_\d+$/.test(n.name))){
        for(const child of mount.children)child.enabled=false;
        this.mounted.push(makeMissile(mount,'已装备导弹',style));
      }
    }
    if(this.slot===0&&p.bombs&&p.type.id!=='j20'&&!inside){
      const shape=groundWeapon==='shorebolt'?4:3;
      if(!this.payload||shape!==this.payloadShape){
        this.payload?.destroy();
        this.payload=makeMissile(this.pivot,'对地挂位',shape);this.payloadShape=shape;
      }
      const [x,y,z]=groundMount(p.type);this.payload.setLocalPosition(x,y,z);this.payload.enabled=true;
    }else if(this.payload)this.payload.enabled=false;
    if(high)for(const g of this.gears)g.node.setLocalRotation(this.gearPose.slerp(g.stowed,g.down,p.gear));
    if(high)for(const node of this.animated){
      const n=node.name,pose=this.originalPoses.get(node)??zero;
      if(n.startsWith('Aileron')){
        const left=n.endsWith('L'),integrity=1-(left?p.damage.left:p.damage.right);
        node.enabled=!(p.down>1.12&&integrity<.33);
        node.setLocalEulerAngles(pose.x+p.controls.roll*(left?21:-21)*integrity,pose.y,pose.z);
      }
      else if(n.startsWith('Elevator')||n.startsWith('Canard'))node.setLocalEulerAngles(pose.x+p.controls.pitch*20,pose.y,pose.z);
      else if(n.startsWith('Rudder'))node.setLocalEulerAngles(pose.x,pose.y+p.controls.yaw*22,pose.z);
      else if(n.startsWith('Prop_'))node.setLocalEulerAngles(pose.x,pose.y,pose.z+time*(390+p.throttle*8050));
      else if(/^Store_\d+$/.test(n))node.enabled=p.missiles>Number(n.slice(6));
      else if(n.startsWith('Bay_')&&sortie){
        const fromMissile=sortie.time-p.missileAt+1.05;
        const fromGround=sortie.time-p.bombAt+(sortie.groundWeapon==='shorebolt'?1.45:.61);
        const t=Math.min(fromMissile>=0?fromMissile:1,fromGround>=0?fromGround:1);
        node.setLocalEulerAngles(pose.x,pose.y,pose.z+(t>0&&t<.59?Math.sin(t/.59*Math.PI)*43*Math.sign(node.getLocalPosition().x):0));
      }else if(n==='RadarSpin')node.setLocalEulerAngles(pose.x,pose.y+time*72,pose.z);
    }
    for(let i=0;i<this.rotors.length;i++){
      const mesh=this.rotors[i],jet=p.type.engine[i];
      mesh.enabled=Boolean(jet)&&p.boost>.15&&p.alive&&!inside&&!preview;
      if(!mesh.enabled)continue;
      const [x,y,z,r]=jet,length=(3+p.boost*9)*(1-p.damage.engine*.84)*(1+.055*Math.sin(time*75+i*2.9));
      mesh.setLocalPosition(x,y,z+length*.5);mesh.setLocalEulerAngles(90,0,0);mesh.setLocalScale(r*1.32,length,r*1.22);
    }
    if(inside&&sortie&&time>=this.nextInstrument){
      this.nextInstrument=time+.12;
      this.cockpit?.findByName('Stick')?.setLocalEulerAngles(p.controls.pitch*15,0,-p.controls.roll*25);
      this.cockpit?.findByName('Throttle')?.setLocalEulerAngles(0,36-p.throttle*47,0);
      this.draw(p,sortie);
    }
  }
  private instrument(node:Entity){
    const canvas=document.createElement('canvas');canvas.width=canvas.height=128;
    const texture=new Texture(this.world.entry.app.graphicsDevice,{name:node.name,width:128,height:128,format:PIXELFORMAT_RGBA8,mipmaps:false,
      minFilter:FILTER_LINEAR,magFilter:FILTER_LINEAR,addressU:ADDRESS_CLAMP_TO_EDGE,addressV:ADDRESS_CLAMP_TO_EDGE});
    texture.setSource(canvas);
    const m=material('同步飞行仪','#101d27');m.useLighting=false;m.emissive.set(1,1,1);m.emissiveMap=texture;m.update();
    const width=node.name.startsWith('Gauge')?.14:.38;
    primitive(node,'仪表读数','plane',m,0,0,.015,width,1,width*.8).setLocalEulerAngles(90,0,180);
    this.gauges.push({name:node.name,canvas,texture,material:m});
  }
  private draw(p:Airframe,s:Sortie){
    for(const g of this.gauges){
      const c=g.canvas.getContext('2d')!;
      c.fillStyle='#0b2026';c.fillRect(0,0,128,128);
      c.strokeStyle='#5cb59b';c.strokeRect(4,4,120,120);c.fillStyle='#aeeacb';c.font='12px monospace';
      if(g.name.endsWith('_1')&&g.name.includes('Display')){
        c.beginPath();c.arc(64,70,43,0,Math.PI*2);c.stroke();
        c.fillText('RADAR',12,19);c.fillText(String(Math.round(p.heading()))+'°',89,19);
        const yaw=p.heading()*Math.PI/180;
        for(const a of s.enemies){
          if(!a.alive)continue;
          const x=(a.position.x-p.position.x)/s.radar*43,z=(a.position.z-p.position.z)/s.radar*43;
          if(x*x+z*z<43**2)c.fillRect(62+x*Math.cos(yaw)+z*Math.sin(yaw),68-x*Math.sin(yaw)+z*Math.cos(yaw),4,4);
        }
      }else{
        c.fillText('SPD '+Math.round(p.speed*3.6),12,29);c.fillText('ALT '+Math.round(p.position.y),12,53);
        c.fillText('THR '+Math.round(p.throttle*100)+'%',12,77);c.fillText('MSL '+p.missiles,12,101);
      }
      g.texture.upload();
    }
  }
}
