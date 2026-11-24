import { Color3 } from '@babylonjs/core/Maths/math.color';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { DynamicTexture } from '@babylonjs/core/Materials/Textures/dynamicTexture';
import { rotate,localAngles,findNode } from './scene-runtime';
import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { PlaneSpec } from './data';
import { Airframe, FlightPose, above } from './flight';
import type { Sortie } from './sortie';
import type { CombatConfiguration } from './profile';
import { groundMount } from './items';
import { calibrateAircraft,finishAirframe,type AirframeFinish } from './aircraft-materials';
import { material, primitive, type WorldView } from './renderer';

const zero=new Vector3();
const tones=['#f0b77f','#f09251','#90e0fa','#c9ac68','#d2a550'];
type Gauge={name:string;texture:DynamicTexture;material:PBRMaterial};
export function makeMissile(parent:TransformNode,name:string,shape:number){
  const scene=parent.getScene(),e=new TransformNode(name,scene);e.parent=parent;
  const shell=material(scene,'钛合金弹体',shape===1?'#c5cdd1':shape===2?'#aab4bb':shape===3?'#52614d':'#dfdfda',.54,.39);
  const rear=material(scene,'喷管与尾翼','#56616c',.67,.42);
  const band=material(scene,'识别环',tones[shape]??tones[0],.25,.38);
  const len=[3.8,2.78,3.23,2.56,3.12][shape]??3.63;
  const radius=[.24,.19,.21,.40,.30][shape]??.23;
  rotate(primitive(e,'弹体','cylinder',shell,0,0,0,radius,len-.55,radius),90,0,0);
  rotate(primitive(e,'整流罩','cone',shell,0,0,-(len-.5)*.5,radius,.64,radius),-90,0,0);
  rotate(primitive(e,'引信色环','cylinder',band,0,0,-len*.33,radius*1.045,.13,radius*1.045),90,0,0);
  rotate(primitive(e,'尾喷口','cylinder',rear,0,0,len*.42,radius*.93,.14,radius*.93),90,0,0);
  for(let i=0;i<4;i++){
    const fin=primitive(e,'弹翼','box',rear,0,0,len*.29,i%2?.57:.035,i%2?.035:.57,.31);
    rotate(fin,0,0,shape===1?45:0);
  }
  e.onDisposeObservable.addOnce(()=>{shell.dispose();rear.dispose();band.dispose();});return e;
}

export class AircraftView {
  readonly pivot:TransformNode;
  readonly pose=new FlightPose();
  private readonly center=new Vector3();
  private readonly projectedCenter=new Vector3();
  readonly anchor=new Vector3();
  lod=0;
  loaded='';
  private animations:import('@babylonjs/core/Animations/animationGroup').AnimationGroup[]=[];
  private pending='';
  private requestId=0;
  private root:TransformNode|null=null;
  private high:TransformNode|null=null;
  private combat:TransformNode|null=null;
  private low:TransformNode|null=null;
  private cockpit:TransformNode|null=null;
  private animated:TransformNode[]=[];
  private readonly gears:{node:TransformNode;stowed:Quaternion;down:Quaternion}[]=[];
  private readonly gearPose=new Quaternion();
  private stand:Airframe|null=null;
  private oldPaint='';
  private style=-1;
  private readonly paints=new Map<PBRMaterial,AirframeFinish>();
  private lastDamage=-1;
  private readonly originalPoses=new Map<TransformNode,Vector3>();
  private readonly mounted:TransformNode[]=[];
  private payload:TransformNode|null=null;
  private payloadShape=-1;
  private readonly gauges:Gauge[]=[];
  private readonly rotors:TransformNode[];
  private nextInstrument=0;
  constructor(readonly world:WorldView,readonly slot:number){
    const scene=world.entry.app.scene;
    this.pivot=new TransformNode('飞机位置',scene);
    this.pivot.parent=slot===0?world.entry.app.root:world.vehicles;
    const fire=material(scene,'高温喷焰外层','#bd6942',0,.5);fire.unlit=true;fire.emissiveColor.set(1.78,.44,.15);
    const core=material(scene,'喷焰白炽核心','#e1b7ff',0,.4);core.unlit=true;core.emissiveColor.set(2.8,1.53,2.85);
    this.rotors=Array.from({length:4},()=>{
      const plume=new TransformNode('加力喷口',scene);plume.parent=this.pivot;
      primitive(plume,'扩散喷焰','cone',fire,0,0,0,1,1,1);
      primitive(plume,'白炽核心','cone',core,0,-.21,0,.66,.59,.66);
      return plume;
    });
    this.pivot.onDisposeObservable.addOnce(()=>{fire.dispose();core.dispose();});
    this.pivot.setEnabled(false);
  }
  async request(spec:PlaneSpec){
    if(spec.id===this.loaded){
      if(this.pending&&this.pending!==spec.id){this.requestId++;this.pending='';}
      return;
    }
    const serial=++this.requestId;this.pending=spec.id;
    const path='fleet/'+spec.id+'.glb';
    await this.world.assets.container(path);
    if(serial!==this.requestId)return;
    const {root,animations}=await this.world.assets.model(path);
    if(serial!==this.requestId){root.dispose();for(const clip of animations)clip.dispose();return;}
    const group=(name:string)=>findNode(root,name)??null;
    const high=group('Exterior'),combat=group('Combat'),low=group('LOD'),cockpit=group('Cockpit');
    if(!high||!combat||!low){root.dispose();for(const clip of animations)clip.dispose();throw Error('机型 LOD 缺失 '+spec.id);}
    this.releaseModel();
    this.root=root;this.high=high;this.combat=combat;this.low=low;this.cockpit=cockpit;this.animations=animations;
    const bounds=combat.getHierarchyBoundingVectors(true);
    this.center.copyFrom(bounds.min).addInPlace(bounds.max).scaleInPlace(.5);
    this.lod=0;root.parent=this.pivot;
    for(const mesh of root.getChildMeshes()){
      if(!(mesh instanceof Mesh))continue;
      if(this.slot===0)this.world.castShadow(mesh);
      const m=mesh.material;
      if(!(m instanceof PBRMaterial))continue;
      calibrateAircraft(m,this.world.entry.app.device.getCaps().maxAnisotropy);
      if(/skin|belly|panel/i.test(m.name)){
        let finish=this.paints.get(m);
        if(!finish){
          finish={material:m.clone(m.name),base:m.albedoColor.clone(),coat:m.clearCoat.intensity,roughness:m.roughness??.56};
          this.paints.set(m,finish);
        }
        mesh.material=finish.material;
      }
    }
    if(cockpit){
      cockpit.position.set(spec.eye[0],spec.eye[1],spec.eye[2]);cockpit.setEnabled(false);
      if(this.slot===0)for(const display of cockpit.getChildTransformNodes().filter(n=>/^(Display_|Gauge_)/.test(n.name)))this.instrument(display);
    }
    this.animated=high.getChildTransformNodes().filter(n=>/^(Aileron|Elevator|Canard|Rudder\d|Gear_|Prop_|Bay_|Store_|RadarSpin)/.test(n.name));
    for(const n of this.animated)this.originalPoses.set(n,localAngles(n));
    this.gears.length=0;
    for(const clip of animations)for(const track of clip.targetedAnimations){
      const node=track.target as TransformNode,keys=track.animation.getKeys();
      if(!node||!/^Gear_\d+$/.test(node.name)||track.animation.targetProperty!=='rotationQuaternion'||keys.length<2)continue;
      this.gears.push({node,stowed:keys[0].value as Quaternion,down:keys[keys.length-1].value as Quaternion});
    }
    this.loaded=spec.id;this.pending='';this.oldPaint='';this.style=-1;this.lastDamage=-1;this.nextInstrument=0;
  }
  private releaseModel(){
    if(this.slot===0)for(const mesh of this.root?.getChildMeshes()??[])if(mesh instanceof Mesh)this.world.dropShadow(mesh);
    this.root?.dispose();
    for(const clip of this.animations)clip.dispose();
    for(const {material} of this.paints.values())material.dispose();
    for(const g of this.gauges){g.texture.dispose();g.material.dispose();}
    this.paints.clear();this.gauges.length=this.mounted.length=0;this.originalPoses.clear();
  }
  dispose(){this.releaseModel();this.pivot.dispose();}
  get requested(){return this.pending;}
  preview(spec:PlaneSpec,time:number,configuration:CombatConfiguration,heading:number){
    if(this.stand?.type!==spec)this.stand=new Airframe(0,spec,0);
    const v=this.stand;
    v.position.set(0,Math.max(1.03,spec.gearClearance),0);v.gear=1;v.throttle=.06;v.missiles=configuration.airMissiles;v.bombs=configuration.groundStores;
    Quaternion.RotationAxisToRef(above,-.15+heading,v.orientation);
    this.sync(v,time,configuration.paint,false,true,undefined,configuration.missile.shape,1,configuration.groundWeapon);
  }
  sync(p:Airframe,time:number,paint='',inside=false,preview=false,sortie?:Sortie,style=sortie?.missile.shape??0,alpha=1,groundWeapon=sortie?.groundWeapon??'bomb'){
    this.pivot.setEnabled(!!this.high&&this.loaded===p.type.id&&(p.alive||p.down>0));
    if(!this.pivot.isEnabled()||!this.high||!this.combat||!this.low)return;
    const {position:at,orientation:q}=this.pose.sample(p,alpha);
    this.pivot.position.copyFrom(at);
    (this.pivot.rotationQuaternion??=Quaternion.Identity()).copyFrom(q);
    Vector3.TransformCoordinatesToRef(this.center,this.pivot.computeWorldMatrix(true),this.projectedCenter);
    this.anchor.set(this.projectedCenter.x,this.projectedCenter.y,this.projectedCenter.z);
    const range=Vector3.Distance(at,this.world.camera.position);
    const height=this.world.entry.app.device.getRenderHeight();
    const pixels=Math.max(p.type.span,p.type.length)*height/(2*Math.max(1,range)*Math.tan(this.world.camera.fov*.5));
    const exterior=range<228||pixels>(this.lod===0?45:57);
    const combat=range<(this.lod===1?1950:1700)||pixels>(this.lod===1?5.2:6.8);
    this.lod=preview||this.slot===0||exterior?0:combat?1:2;
    const high=this.lod===0,mid=this.lod===1;
    this.high.setEnabled(high&&!inside);this.combat.setEnabled(mid&&!inside);this.low.setEnabled(!high&&!mid&&!inside);
    if(this.cockpit)this.cockpit.setEnabled(inside);
    const wear=preview?0:p.down?1:Math.max(0,Math.min(1,(1-p.hp/p.maxHp-.12)*1.2));
    if(paint!==this.oldPaint||Math.abs(wear-this.lastDamage)>.04){
      this.oldPaint=paint;this.lastDamage=wear;
      const tint=paint?Color3.FromHexString(paint):null;
      for(const surface of this.paints.values())finishAirframe(surface,tint,wear);
    }
    if(this.slot===0&&style!==this.style){
      this.style=style;
      for(const m of this.mounted)m.dispose();
      this.mounted.length=0;
      for(const mount of this.animated.filter(n=>/^Store_\d+$/.test(n.name))){
        for(const child of mount.getChildren())child.setEnabled(false);
        this.mounted.push(makeMissile(mount,'已装备导弹',style));
      }
    }
    if(this.slot===0&&p.bombs&&p.type.id!=='j20'&&!inside){
      const shape=groundWeapon==='shorebolt'?4:3;
      if(!this.payload||shape!==this.payloadShape){
        this.payload?.dispose();
        this.payload=makeMissile(this.pivot,'对地挂位',shape);this.payloadShape=shape;
      }
      const [x,y,z]=groundMount(p.type);this.payload.position.set(x,y,z);this.payload.setEnabled(true);
    }else if(this.payload)this.payload.setEnabled(false);
    if(high)for(const g of this.gears){Quaternion.SlerpToRef(g.stowed,g.down,p.gear,this.gearPose);(g.node.rotationQuaternion??=Quaternion.Identity()).copyFrom(this.gearPose);}
    if(high)for(const node of this.animated){
      const n=node.name,pose=this.originalPoses.get(node)??zero;
      if(n.startsWith('Aileron')){
        const left=n.endsWith('L'),integrity=1-(left?p.damage.left:p.damage.right);
        node.setEnabled(!(p.down>1.12&&integrity<.33));
        rotate(node,pose.x+p.controls.roll*(left?21:-21)*integrity,pose.y,pose.z);
      }
      else if(n.startsWith('Elevator')||n.startsWith('Canard'))rotate(node,pose.x+p.controls.pitch*20,pose.y,pose.z);
      else if(n.startsWith('Rudder'))rotate(node,pose.x,pose.y+p.controls.yaw*22,pose.z);
      else if(n.startsWith('Prop_'))rotate(node,pose.x,pose.y,pose.z+time*(390+p.throttle*8050));
      else if(/^Store_\d+$/.test(n))node.setEnabled(p.missiles>Number(n.slice(6)));
      else if(n.startsWith('Bay_')&&sortie){
        const fromMissile=sortie.time-p.missileAt+1.05;
        const fromGround=sortie.time-p.bombAt+(sortie.groundWeapon==='shorebolt'?1.45:.61);
        const t=Math.min(fromMissile>=0?fromMissile:1,fromGround>=0?fromGround:1);
        rotate(node,pose.x,pose.y,pose.z+(t>0&&t<.59?Math.sin(t/.59*Math.PI)*43*Math.sign(node.position.x):0));
      }else if(n==='RadarSpin')rotate(node,pose.x,pose.y+time*72,pose.z);
    }
    for(let i=0;i<this.rotors.length;i++){
      const mesh=this.rotors[i],jet=p.type.engine[i];
      mesh.setEnabled(Boolean(jet)&&p.boost>.15&&p.alive&&!inside&&!preview);
      if(!mesh.isEnabled())continue;
      const [x,y,z,r]=jet,length=(3+p.boost*9)*(1-p.damage.engine*.84)*(1+.055*Math.sin(time*75+i*2.9));
      mesh.position.set(x,y,z+length*.5);rotate(mesh,90,0,0);mesh.scaling.set(r*1.32,length,r*1.22);
    }
    if(inside&&sortie&&time>=this.nextInstrument){
      this.nextInstrument=time+.12;
      const stick=this.cockpit&&findNode(this.cockpit,'Stick'),throttle=this.cockpit&&findNode(this.cockpit,'Throttle');
      if(stick)rotate(stick,p.controls.pitch*15,0,-p.controls.roll*25);
      if(throttle)rotate(throttle,0,36-p.throttle*47,0);
      this.draw(p,sortie);
    }
  }
  private instrument(node:TransformNode){
    const scene=node.getScene(),texture=new DynamicTexture(node.name,128,scene,false);
    const m=material(scene,'同步飞行仪','#101d27');m.unlit=true;m.emissiveColor.set(1,1,1);m.emissiveTexture=texture;
    const width=node.name.startsWith('Gauge')?.14:.38;
    rotate(primitive(node,'仪表读数','plane',m,0,0,.015,width,1,width*.8),90,0,180);
    this.gauges.push({name:node.name,texture,material:m});
  }
  private draw(p:Airframe,s:Sortie){
    for(const g of this.gauges){
      const c=g.texture.getContext();
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
      g.texture.update();
    }
  }
}
