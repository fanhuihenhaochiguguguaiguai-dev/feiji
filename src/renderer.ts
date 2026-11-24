import { ADDRESS_CLAMP_TO_EDGE, Application, Asset, BLEND_NORMAL, CULLFACE_NONE, Color, ContainerResource, DEVICETYPE_WEBGPU, Entity, EnvLighting, FOG_EXP2, Mesh, MeshInstance, SEMANTIC_POSITION, ShaderMaterial, StandardMaterial, Texture, Vec2, type Material, Vec3, calculateNormals, createGraphicsDevice, basisInitialize, meshoptInitialize, SHADOWUPDATE_REALTIME } from 'playcanvas';
import { MeshoptDecoder } from 'meshoptimizer';
import { Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { airfield, base } from './airfield-layout';
import { theatres, type PlaneSpec } from './data';
import { Airframe } from './flight';
import { FlightCamera } from './flight-camera';
import { FlightGraph } from './flight-graph';
import { Vegetation } from './vegetation';
import { bindRockSurface } from './terrain-material';
import { environmentSource } from './shading';
import { OceanRender } from './ocean-render';
import { wakeCeiling } from './ocean-solver';
import { Terrain, clamp, chunkCells, gridSize, gridStep, noise, worldExtent } from './terrain';
import type { Backend } from './profile';

export const asset=(path:string)=>new URL(path,document.baseURI).href;
export interface OpenEngine { app:Application; canvas:HTMLCanvasElement; backend:'gpu'|'gl'; fallback:boolean }
meshoptInitialize({decoder:MeshoptDecoder});

export async function openEngine(canvas:HTMLCanvasElement,mode:Backend):Promise<OpenEngine>{
  basisInitialize({glueUrl:asset('codec/basis/basis.wasm.js'),wasmUrl:asset('codec/basis/basis.wasm.wasm'),
    fallbackUrl:asset('codec/basis/basis.js'),numWorkers:1,lazyInit:true});
  const device=await createGraphicsDevice(canvas,{
    deviceTypes:mode==='gl'||!navigator.gpu?['webgl2']:[DEVICETYPE_WEBGPU,'webgl2'],
    antialias:false,alpha:false,stencil:false,powerPreference:'high-performance',
  });
  if(device.deviceType!=='webgl2'&&!device.isWebGPU){
    device.destroy();
    throw new Error('需要 WebGPU 或 WebGL2');
  }
  if(device.isWebGPU){
    const native=(device as unknown as {wgpu?: GPUDevice}).wgpu;
    if(native){
      const reported=new Set<string>();
      native.addEventListener('uncapturederror',event=>{
        const message=(event as GPUUncapturedErrorEvent).error.message;
        if(reported.size<12&&!reported.has(message)){
          reported.add(message);console.error('WebGPU '+message);
        }
      });
    }
  }
  const backend=device.isWebGPU?'gpu':'gl';
  const app=new Application(canvas,{graphicsDevice:device});
  app.scene.exposure=1.04;
  return {app,canvas,backend,fallback:mode==='gpu'&&backend==='gl'};
}

export class Assets {
  private readonly pending=new Map<string,Promise<Asset>>();
  private pinnedFleet:ReadonlySet<string>=new Set();
  constructor(readonly app:Application){}
  load(path:string,type:string):Promise<Asset>{
    const existing=this.pending.get(path);
    if(existing){this.pending.delete(path);this.pending.set(path,existing);return existing;}
    const handle=new Asset(path,type,{url:asset(path)});
    const request=new Promise<Asset>((resolve,reject)=>{
      handle.once('load',resolve);
      handle.once('error',(err:unknown)=>{this.drop(path,handle);reject(err);});
      this.app.assets.add(handle);this.app.assets.load(handle);
    });
    this.pending.set(path,request);
    return request;
  }
  private drop(path:string,handle:Asset){
    this.app.assets.remove(handle);handle.unload();this.pending.delete(path);
  }
  async model(path:string):Promise<Entity>{return ((await this.load(path,'container')).resource as ContainerResource).instantiateRenderEntity();}
  async texture(path:string):Promise<Texture>{return (await this.load(path,'texture')).resource as Texture;}
  trimFleet(keep:ReadonlySet<string>){
    this.pinnedFleet=keep;
    const aircraft=[...this.pending.entries()].filter(([file])=>file.startsWith('fleet/'));
    for(const [file,promise] of aircraft.filter(([file])=>!keep.has(file.slice(6,-4))).slice(0,Math.max(0,aircraft.length-5))){
      void promise.then(a=>{
        if(this.pending.get(file)===promise&&!this.pinnedFleet.has(file.slice(6,-4)))this.drop(file,a);
      }).catch(()=>{});
    }
  }
}

export function material(name:string,hex:string,metal=0,rough=.65){
  const m=new StandardMaterial();
  m.name=name;m.diffuse.fromString(hex);m.useMetalness=true;m.metalness=metal;m.gloss=1-rough;m.update();
  return m;
}
export type Primitive='plane'|'box'|'cone'|'torus'|'sphere'|'cylinder'|'capsule';
export function primitive(parent:Entity,name:string,type:Primitive,mat:Material,x:number,y:number,z:number,w:number,h:number,l:number){
  const e=new Entity(name);
  parent.addChild(e);e.setLocalPosition(x,y,z);e.setLocalScale(w,h,l);
  e.addComponent('render',{type,material:mat,castShadows:false});
  return e;
}
function meshEntity(app:Application,parent:Entity,name:string,vertices:number[],indices:number[],mat:StandardMaterial|ShaderMaterial,normals?:number[],colors?:number[],uv?:number[]){
  const mesh=new Mesh(app.graphicsDevice);
  mesh.setPositions(vertices);mesh.setIndices(indices);
  if(normals)mesh.setNormals(normals);
  if(colors)mesh.setColors32(colors);
  if(uv)mesh.setUvs(0,uv);
  mesh.update();
  const ent=new Entity(name);parent.addChild(ent);
  ent.addComponent('render',{meshInstances:[new MeshInstance(mesh,mat)],castShadows:false});
  ent.once('destroy',()=>mesh.destroy());
  return ent;
}

class Camera {
  readonly position=new Vector3();
  readonly upVector=new Vector3(0,1,0);
  private readonly up=new Vec3();
  private readonly local=new Vec3();
  private readonly screen=new Vec3();
  readonly rotationQuaternion=new Quaternion();
  target:Vector3|null=null;
  fov=1;minZ=.5;
  constructor(readonly entity:Entity,readonly canvas:HTMLCanvasElement){}
  setTarget(target:Vector3){this.target=target;}
  commit(){
    const p=this.position;this.entity.setPosition(p.x,p.y,p.z);
    if(this.target){
      const t=this.target;this.entity.lookAt(this.local.set(t.x,t.y,t.z),this.up.set(this.upVector.x,this.upVector.y,this.upVector.z));
      const q=this.entity.getRotation();this.rotationQuaternion.set(q.x,q.y,q.z,q.w);
    }else{
      const q=this.rotationQuaternion;this.entity.setRotation(q.x,q.y,q.z,q.w);
    }
    const camera=this.entity.camera!;camera.fov=this.fov*180/Math.PI;camera.nearClip=this.minZ;
  }
  getDirectionToRef(axis:Vector3,out:Vector3){axis.rotateByQuaternionToRef(this.rotationQuaternion,out);}
  project(point:Vector3,out:Vector3,width?:number,height?:number){
    // PlayCanvas reads the source coordinates again for the perspective divide.
    const s=this.entity.camera!.worldToScreen(this.local.set(point.x,point.y,point.z),this.screen,width,height);
    out.set(s.x,s.y,s.z);
  }
}

const palette=[[49,80,52],[46,63,58],[46,68,57]];
const skyVectors=(t:(typeof theatres)[number])=>({horizon:new Float32Array(t.horizon),zenith:new Float32Array(t.sky),
  sunDir:new Float32Array(t.sun),sunColor:new Float32Array(t.light),sea:new Float32Array(t.sea)});
type Tile={x:number;z:number;step:number;entity:Entity};
export class WorldView {
  readonly camera:Camera;
  readonly assets:Assets;
  readonly hangar=new Entity('前沿机库');
  readonly field=new Entity('机场设施');
  readonly effects=new Entity('战场特效');
  readonly vehicles=new Entity('作战载具');
  readonly props=new Entity('训练目标');
  readonly terrainRoot=new Entity('海岸地貌');
  readonly sky:Entity;
  readonly sea:Entity;
  readonly sun=new Entity('太阳主光');
  readonly rim=new Entity('机库轮廓光');
  readonly terrainMaterial=material('分层地表','#ffffff',0,.91);
  private readonly ridgeMaterial=material('临海岩壁','#ffffff',.04,.86);
  readonly terrainTiles=new Map<number,Tile>();
  readonly targets:Entity[];
  readonly rings:Entity[];
  readonly ready:Promise<void>;
  readonly skyMat:ShaderMaterial;
  readonly seaMat:ShaderMaterial;
  readonly seaFields:OceanRender;
  readonly graph:FlightGraph;
  private readonly vegetation:Vegetation;
  readonly hullMark=material('命中受损表面','#ffffff',.14,.84);
  private readonly impactLamp=new Entity('空战闪光');
  private glow=0;
  private glowEnds=0;
  private readonly camRight=new Vector3();
  private readonly camUp=new Vector3();
  private readonly camForward=new Vector3();
  private pressureTime=-1;
  terrain=new Terrain(theatres[0].seed);
  theme=theatres[0];
  level=.94;view=0;orbit=.72;tilt=.16;cameraReset=true;fixed=false;
  clouds=true;ocean=true;ground=true;
  private weather=0;
  private cloudCover=0;
  private airspeed=0;
  private readonly hotAir=new Vector3();
  private lighting=0;
  private indoors=true;
  private readonly rig=new FlightCamera();
  private readonly eye=new Float32Array(3);
  private readonly look=new Vector3();
  private readonly pose={position:this.cameraPosition(),upVector:new Vector3(0,1,0),rotationQuaternion:null as Quaternion|null,
    fov:1,minZ:.5,setTarget:(t:Vector3)=>{this.camera.setTarget(t);}};
  private cameraPosition(){return new Vector3();}
  private tileClock=-Infinity;
  private microTile?:Entity;
  private themeSequence=0;
  private edgeDepth:Texture|null=null;
  private probeName='';
  private readonly probes=new Map<string,Promise<Texture>>();
  private waveHeight=1;
  private readonly contact:Entity;
  private readonly climateDensities=[.000027,.000029,.000066,.000058,.000092,.000108,.000080,.000046];
  constructor(readonly entry:OpenEngine){
    const {app,canvas}=entry;
    // Terrain visibility test: use native PBR on the combat terrain; retain hangar shading.
    bindRockSurface(this.ridgeMaterial);
    this.terrainMaterial.cull=CULLFACE_NONE;
    this.terrainMaterial.depthWrite=true;
    this.assets=new Assets(app);
    for(const e of [this.hangar,this.field,this.effects,this.vehicles,this.props,this.terrainRoot,this.sun,this.rim])app.root.addChild(e);
    const hangarFloor=material('磨损停机坪混凝土','#bcbbb7',.08,.62);
    hangarFloor.clearCoat=.18;hangarFloor.clearCoatGloss=.70;
    const floor=primitive(this.hangar,'整体现浇机坪','plane',hangarFloor,0,0,23,140,1,191);
    floor.render!.receiveShadows=true;
    const texC=document.createElement('canvas');
    texC.width=texC.height=128;
    const paint=texC.getContext('2d')!;
    const shadow=paint.createRadialGradient(64,64,3,64,64,64);
    shadow.addColorStop(0,'#172030bb');shadow.addColorStop(.53,'#1720308f');shadow.addColorStop(1,'#17203000');
    paint.fillStyle=shadow;paint.fillRect(0,0,128,128);
    const shadowMap=new Texture(app.graphicsDevice,{name:'机库接触遮蔽',width:128,height:128});shadowMap.setSource(texC);
    const shade=material('地面接触遮蔽','#18202b');
    shade.useLighting=false;shade.blendType=BLEND_NORMAL;shade.depthWrite=false;shade.opacityMap=shadowMap;shade.opacityMapChannel='a';shade.update();
    this.contact=primitive(this.hangar,'机身接触暗部','plane',shade,0,.021,0,9,1,19);
    this.hangar.setEulerAngles(0,-57,0);
    this.hangarExterior();

    const gold=material('机库黄漆','#c5a466',.2,.57);
    const concreteSeam=material('机坪收缩缝','#343743');
    for(const sign of [-1,1])primitive(this.hangar,'滑入导向线','box',gold,sign*7.5,.013,3,.11,.017,114);
    for(let k=-60;k<=100;k+=8)primitive(this.hangar,'混凝土分仓缝','box',concreteSeam,0,.008,k,134,.008,.022);
    const cameraEntity=new Entity('主镜头');app.root.addChild(cameraEntity);
    cameraEntity.addComponent('camera',{fov:56,nearClip:.15,farClip:100000,clearColor:new Color(.13,.22,.31)});
    this.camera=new Camera(cameraEntity,canvas);
    this.vegetation=new Vegetation(this);
    this.graph=new FlightGraph(app,cameraEntity.camera!);
    this.effects.addChild(this.impactLamp);
    this.impactLamp.addComponent('light',{type:'omni',color:new Color(1,.51,.19),range:175,intensity:0});
    this.impactLamp.enabled=false;
    this.sun.addComponent('light',{type:'directional',color:new Color(1,.81,.62),intensity:2.3,castShadows:true,
      shadowDistance:95,shadowResolution:2048,shadowUpdateMode:SHADOWUPDATE_REALTIME,normalOffsetBias:.045,shadowBias:.15});
    this.rim.addComponent('light',{type:'directional',color:new Color(.59,.74,.96),intensity:1.32});
    this.rim.setPosition(13,17,-24);this.rim.lookAt(Vec3.ZERO);this.rim.rotateLocal(90,0,0);
    app.scene.ambientLight.set(.45,.49,.57);
    app.scene.fog.type=FOG_EXP2;
    this.skyMat=this.environment('sky');this.seaMat=this.environment('sea');
    this.seaFields=new OceanRender(app.graphicsDevice,this.seaMat);
    this.sky=new Entity('分层大气');app.root.addChild(this.sky);
    this.sky.setLocalScale(155000,155000,155000);
    this.sky.addComponent('render',{type:'sphere',material:this.skyMat,castShadows:false});
    this.sea=this.buildSea();
    this.terrainMaterial.diffuseVertexColor=true;this.terrainMaterial.update();
    const marker=material('航路标记','#95e1d3',.2,.39);marker.emissive.set(.28,.56,.49);marker.update();
    this.rings=Array.from({length:4},(_,i)=>primitive(this.props,'训练航标 '+i,'torus',marker,0,0,0,155,145,155));
    this.rings.forEach(e=>{e.setLocalEulerAngles(90,0,0);e.enabled=false;});
    const target=material('训练标靶','#748777',.12);
    this.targets=Array.from({length:8},(_,i)=>primitive(this.props,'地面目标 '+i,'box',target,0,0,0,28,12,26));
    this.resetMarkers();
    const facilities={
      runway:material('机场铺装','#3e474d'),apron:material('机坪混凝土','#58686e'),
      hangar:material('机库钢构','#637071',.21),roof:material('机库顶板','#8b9896',.45),
      tower:material('指挥塔','#686f66'),glass:material('观察室','#3d6478',.33,.24),signal:marker,
    };
    for(const a of airfield)primitive(this.field,a.kind,'box',facilities[a.kind],a.x,a.y,a.z,a.w,a.h,a.l);
    for(let z=base.near+48;z<base.far-40;z+=53)primitive(this.field,'中心线','box',marker,base.x,32.1,z,1.7,.09,23);
    this.ready=Promise.all([
      this.graph.ready,
      Promise.all([this.assets.texture('studio/tarmac.webp'),this.assets.texture('studio/tarmac-orm.png'),
        this.assets.texture('studio/tarmac-normal.png'),this.assets.texture('studio/apron-light.webp')]).then(([color,detail,norm,lamps])=>{
        for(const t of [color,detail,norm])t.anisotropy=Math.min(12,app.graphicsDevice.maxAnisotropy);
        hangarFloor.diffuseMap=color;hangarFloor.aoMap=detail;hangarFloor.aoMapChannel='r';
        hangarFloor.metalnessMap=detail;hangarFloor.metalnessMapChannel='b';
        hangarFloor.glossMap=detail;hangarFloor.glossMapChannel='g';hangarFloor.glossInvert=true;
        hangarFloor.normalMap=norm;hangarFloor.bumpiness=.46;
        hangarFloor.emissiveMap=lamps;hangarFloor.emissive.set(1,1,1);hangarFloor.emissiveIntensity=.48;
        hangarFloor.update();
        const runway=facilities.runway;
        runway.diffuse.set(.65,.64,.62);
        runway.diffuseMap=color;runway.diffuseMapTiling=new Vec2(3,19);
        runway.normalMap=norm;runway.normalMapTiling.copy(runway.diffuseMapTiling);runway.bumpiness=.30;runway.update();

      }),
      this.assets.model('studio/hangar-dusk.glb').then(e=>{
        this.hangar.addChild(e);
        e.setLocalPosition(34,0,44);
        for(const part of e.findComponents('render'))part.receiveShadows=true;
      }),
      this.assets.texture('surface/impact-mark.webp').then(texture=>{
        const mark=this.hullMark;
        mark.diffuseMap=texture;mark.opacityMap=texture;mark.opacityMapChannel='a';
        mark.blendType=BLEND_NORMAL;mark.depthWrite=false;mark.cull=CULLFACE_NONE;mark.update();
      }),
      this.assets.texture('surface/dusk-panorama.webp').then(t=>this.skyMat.setParameter('deckDome',t)),
      this.assets.texture('surface/air-scattering.png').then(t=>{
        t.addressU=t.addressV=ADDRESS_CLAMP_TO_EDGE;
        this.skyMat.setParameter('airLut',t);this.seaMat.setParameter('airLut',t);
      }),
      this.assets.texture('surface/cloud-density.png').then(t=>{
        this.skyMat.setParameter('weatherTex',t);this.seaMat.setParameter('weatherTex',t);
        this.ridgeMaterial.setParameter('terrainWeather',t);
        this.graph.pressure.setWeatherTexture(t);
      }),
      this.assets.texture('surface/wave-field.png').then(t=>this.seaMat.setParameter('waveTex',t)),
      this.assets.texture('world/sundown-surface.png').then(t=>{this.edgeDepth=t;this.seaMat.setParameter('depthTex',t);}),
      Promise.all([
        this.assets.texture('surface/stone-color.ktx2'),
        this.assets.texture('surface/stone-relief.ktx2'),
        this.assets.texture('surface/stone-response.ktx2')
      ]).then(([color,normal,response])=>{
        for(const texture of [color,normal,response])texture.anisotropy=Math.min(12,app.graphicsDevice.maxAnisotropy);
        for(const surface of [this.terrainMaterial,this.ridgeMaterial]){
          surface.diffuseMap=color;surface.normalMap=normal;surface.bumpiness=.73;
          surface.aoMap=response;surface.aoMapChannel='r';
          surface.glossMap=response;surface.glossMapChannel='g';surface.glossInvert=true;
          surface.update();
        }
      }),
      this.lightingProbe('deck'),
    ]).then(()=>undefined);
    this.showDeck(true);
  }
  private lightingProbe(name:string){
    this.probeName=name;
    let pending=this.probes.get(name);
    if(!pending){
      pending=this.assets.texture('surface/probe-'+(name==='deck'?'airbase-atlas':name)+'.hdr').then(t=>{
        const cube=EnvLighting.generateSkyboxCubemap(t,64);
        const atlas=EnvLighting.generateAtlas(cube);cube.destroy();
        return atlas;
      });
      this.probes.set(name,pending);
    }
    return pending.then(atlas=>{
      if(this.probeName===name)this.entry.app.scene.envAtlas=atlas;
    }).catch(error=>{
      this.probes.delete(name);
      console.warn('环境反射资源不可用',error);
    });
  }
  private hangarExterior(){
    const n=53;
    this.ridgeMaterial.diffuseVertexColor=true;
    this.ridgeMaterial.update();
    const heights=(x:number,z:number,layer:number)=>{
      const local=layer?this.terrain.elevation(x*12+7210,(z-910)*10+5020):
        this.terrain.elevation(x*13-12450,(z-180)*11-4880);
      return Math.max(0,local-(layer?82:106));
    };
    for(const layer of [0,1]){
      const p:number[]=[],indices:number[]=[],colors:number[]=[],uv:number[]=[];
      for(let j=0;j<n;j++)for(let i=0;i<n;i++){
        const x=(i-26)*(layer?64:29),z=(layer?980:315)+j*(layer?48:16);
        const verge=clamp(j/8,0,1)*clamp(Math.min(i,n-1-i)/8,0,1);
        const ridge=heights(x,z,layer),slope=Math.hypot(heights(x+15,z,layer)-ridge,heights(x,z+15,layer)-ridge)/95;
        const h=ridge*(layer?.050:.031)*verge-1.4;
        p.push(x,h,z);uv.push(x/110,z/110);
        const rock=clamp(.12+slope*.49+ridge*.00018,0,1);
        const pale=clamp((ridge-(layer?1330:2400))/760,0,.92)*(1-clamp(slope*.24,0,.72));
        const grain=(noise(x*.014,z*.019)-.50)*28;
        colors.push(48+rock*71+pale*74+grain,57+rock*62+pale*68+grain,59+rock*70+pale*75+grain,255);
      }
      for(let j=0;j<n-1;j++)for(let i=0;i<n-1;i++){
        const a=j*n+i;indices.push(a,a+n,a+1,a+1,a+n,a+n+1);
      }
      meshEntity(this.entry.app,this.hangar,layer?'海雾外分水岭':'近岸岩脊',p,indices,this.ridgeMaterial,calculateNormals(p,indices),colors,uv);
    }
    const water=material('机场外侧海面','#46586c',.26,.37);
    primitive(this.hangar,'远处泊地','plane',water,0,-.98,420,1400,1,1000);
  }
  private environment(name:'sky'|'sea'){
    const gl=environmentSource(false,name==='sea'),gpu=environmentSource(true,name==='sea');
    const m=new ShaderMaterial({uniqueName:'world-forge-'+name,attributes:{position:SEMANTIC_POSITION},
      vertexGLSL:gl.vertex,fragmentGLSL:gl.fragment,vertexWGSL:gpu.vertex,fragmentWGSL:gpu.fragment});
    m.cull=CULLFACE_NONE;m.depthWrite=name==='sea';
    for(const [key,v] of Object.entries(skyVectors(this.theme)))m.setParameter(key,v);
    for(const [key,v] of Object.entries({quality:.94,cover:0,clouds:1,exposure:1.04,clock:0,atmosphereClock:0,eye:this.eye,waveHeight:1}))m.setParameter(key,v);
    return m;
  }
  private buildSea(){
    const splits=[[-60000,-18000,2250],[-18000,-2200,650],[-2200,-340,124],[-340,-135,17],[-135,135,5],[135,340,17],[340,2200,124],[2200,18000,650],[18000,60000,2250]];
    const axis:number[]=[];
    for(const [a,b,size] of splits){const count=Math.ceil((b-a)/size);for(let i=0;i<count;i++)axis.push(a+(b-a)*i/count);}
    axis.push(60000);
    const p:number[]=[],idx:number[]=[],n=axis.length;
    for(const z of axis)for(const x of axis)p.push(x,0,z);
    for(let z=0;z<n-1;z++)for(let x=0;x<n-1;x++){const a=z*n+x;idx.push(a,a+n,a+1,a+1,a+n,a+n+1);}
    return meshEntity(this.entry.app,this.entry.app.root,'动态深水与海岸',p,idx,this.seaMat);
  }
  async setTheme(region:number){
    const theme=theatres[region],revision=++this.themeSequence;
    const t=await this.assets.texture('world/'+theme.id+'-surface.png');
    if(revision!==this.themeSequence)return;
    this.edgeDepth=t;this.seaMat.setParameter('depthTex',t);
    if(this.theme!==theme){
      this.theme=theme;this.terrain=new Terrain(theme.seed);
      for(const tile of this.terrainTiles.values())tile.entity.destroy();
      this.terrainTiles.clear();this.microTile?.destroy();this.microTile=undefined;this.tileClock=-Infinity;
    }
    this.configureFlightWeather(this.weather,this.lighting);
  }
  configureFlightWeather(weather:number,lighting:number){
    this.weather=weather;this.lighting=lighting;
    this.waveHeight=[1,.79,.92,1.27,1.92,.78,.95,1.1][weather]??1;
    this.terrain.wavesScale=this.waveHeight;
    const vector=skyVectors(this.theme),scene=this.entry.app.scene;
    const sunlight=[1.86,1.54,.92,.64,.55,.83,.81,.22][weather]??1.86;
    const sunHeight=lighting===1?.57:lighting===2?.076:lighting===3?-.085:vector.sunDir[1];
    vector.sunDir[1]=sunHeight;

    if(lighting===1){vector.horizon.set([.57,.70,.80]);vector.zenith.set([.16,.38,.66]);vector.sunColor.set([1,.95,.81]);}
    if(lighting===2){vector.horizon.set([.78,.45,.30]);vector.zenith.set([.17,.24,.39]);vector.sunColor.set([1,.70,.43]);}
    if(lighting===3||weather===7){vector.horizon.set([.17,.24,.38]);vector.zenith.set([.057,.103,.21]);vector.sunColor.set([.36,.54,.84]);vector.sea.set([.047,.119,.201]);}
    const dim=weather>=2&&weather<=6;
    if(dim){vector.horizon[0]*=.81;vector.zenith[2]*=.83;}
    if(this.indoors){
      vector.sunDir.set([-.88,.23,.42]);vector.horizon.set([.75,.52,.42]);
      vector.zenith.set([.22,.35,.59]);vector.sunColor.set([1,.80,.61]);
    }
    const n=Math.hypot(...vector.sunDir);vector.sunDir.forEach((v,i)=>vector.sunDir[i]=v/n);
    this.sun.setPosition(...vector.sunDir as unknown as [number,number,number]);
    this.sun.lookAt(Vec3.ZERO);
    // Directional lights emit along local -Y rather than the camera's -Z.
    this.sun.rotateLocal(90,0,0);
    this.sun.light!.color.set(...vector.sunColor as unknown as [number,number,number]);
    this.sun.light!.intensity=this.indoors?2.75:lighting===3?.33:sunlight;
    this.sun.light!.castShadows=this.indoors||sunHeight>0;
    this.sun.light!.numCascades=this.indoors?1:3;
    this.sun.light!.shadowDistance=this.indoors?95:1880;
    this.rim.enabled=this.indoors;
    scene.skyboxIntensity=this.indoors?1.02:dim?.61:.76;
    const probe=this.indoors?'deck':lighting===3||weather===7?'night':dim?'storm':lighting===1||this.theme.id==='frost'?'day':'dusk';
    if(probe!==this.probeName)void this.lightingProbe(probe);
    scene.fog.density=this.indoors?.00040:this.climateDensities[weather]??.000045;
    scene.fog.color.set(vector.horizon[0]*.87,vector.horizon[1]*.91,vector.horizon[2]*.96);
    if(!this.indoors)scene.ambientLight.set(dim?.40:.43,dim?.46:.49,dim?.55:.57);
    else scene.ambientLight.set(.32,.40,.54);
    const cover=[.006,.026,-.055,-.10,-.16,-.015,-.077,.087][weather]??.006;
    this.cloudCover=cover;
    this.ridgeMaterial.setParameter('terrainCloudCover',-.115);
    for(const m of [this.skyMat,this.seaMat]){
      for(const [key,value] of Object.entries(vector))m.setParameter(key,value);
      m.setParameter('cover',this.indoors?-.115:cover);
      m.setParameter('cloudBase',this.indoors?325:930);
      m.setParameter('exposure',this.indoors?1.02:dim?1.07:1.09);
      m.setParameter('waveHeight',this.waveHeight);
    }
  }
  showDeck(active:boolean){
    this.indoors=active;this.hangar.enabled=active;
    this.graph.setCombat(!active);this.pressureTime=-1;this.impactLamp.enabled=false;this.glowEnds=0;
    this.seaFields.reset(active?null:this.terrain.bathymetry());
    this.terrain.extraWater=active?null:(x,z,scale)=>this.seaFields.height(x,z,scale);
    for(const node of [this.field,this.terrainRoot,this.props,this.sea,this.effects])node.enabled=!active;
    this.configureFlightWeather(this.weather,this.lighting);this.cameraReset=true;
  }
  updateWater(plane:Airframe,time:number){
    const {x,y,z}=plane.position;
    const altitude=y-this.terrain.water(x,z,time);
    this.seaFields.advance({time,x,z,altitude,speed:plane.speed,water:altitude<wakeCeiling&&this.terrain.classify(x,z)==='water'},plane.forward.x,plane.forward.z);
  }
  renderScale(scale:number){
    this.graph.scale(scale);
    const resolution=this.level>1.10?4096:2048;
    if(this.sun.light!.shadowResolution!==resolution)this.sun.light!.shadowResolution=resolution;
  }
  impactPressure(point:Vector3,magnitude:number,terminal:boolean,time:number){
    this.graph.pressure.pulse(point,magnitude,terminal);
    if(Vector3.DistanceSquared(this.camera.position,point)>950**2)return;
    this.impactLamp.setPosition(point.x,point.y,point.z);
    this.impactLamp.light!.range=(terminal?155:103)*magnitude;
    this.glow=(terminal?15:8)*magnitude;
    this.glowEnds=time+(terminal?.38:.23);
    this.impactLamp.enabled=true;
  }
  resetMarkers(){for(const m of [...this.targets,...this.rings])m.enabled=false;}
  setAwardLighting(on:boolean){this.rim.light!.intensity=on?1.55:1.32;}
  preview(plane:PlaneSpec,t:number,mode:string,zoom=1){
    const hero=mode==='home',size=Math.max(plane.length,plane.span);
    const yaw=this.orbit+(hero?.15:0)+Math.sin(t*.19)*.016;
    const aspect=this.entry.canvas.clientWidth/Math.max(1,this.entry.canvas.clientHeight);
    const fit=hero?clamp(1.91/aspect,.86,1.25):1;
    const d=Math.max(hero?10:15,size*(hero?.99:mode==='reveal'?1.19:1.28)*fit*zoom);
    const y=plane.gearClearance||1.45;
    this.contact.setLocalScale(plane.span*.91,1,plane.length*.96);
    this.camera.position.set(Math.sin(yaw)*d,y+d*((hero?.073:.110)+this.tilt*.25),-Math.cos(yaw)*d);
    this.look.set(hero?1.05:0,y+(hero?.76:.43),0);
    this.camera.fov=hero?.80:.91;this.camera.minZ=.14;this.camera.setTarget(this.look);
  }

  previewOrdnance(at:Vector3,t:number){
    const angle=.75+Math.sin(t*.5)*.15,d=7.7;
    this.camera.position.set(at.x+Math.sin(angle)*d,at.y+1.22,at.z-Math.cos(angle)*d);
    this.look.set(at.x,at.y-.62,at.z);this.camera.setTarget(this.look);this.camera.fov=.84;
  }
  flight(plane:Airframe,dt:number,time:number,target:Airframe|null,pose?:import('./flight').FlightPose){
    this.pose.position=this.camera.position;
    this.camera.target=null;
    this.rig.update(this.pose,plane,target,this.terrain,dt,time,this.view===1,this.cameraReset,pose);
    this.camera.upVector.copyFrom(this.pose.upVector);
    if(this.pose.rotationQuaternion)this.camera.rotationQuaternion.copyFrom(this.pose.rotationQuaternion);
    this.camera.fov=this.pose.fov;this.camera.minZ=this.pose.minZ;this.cameraReset=false;
    this.airspeed=plane.speed;
    const nozzle=plane.type.engine[0],visual=pose??plane;
    if(nozzle&&plane.alive&&this.view===0&&plane.throttle>.65){
      const length=4+plane.boost*10;
      this.hotAir.set(0,nozzle[1],nozzle[2]+length*.63).rotateByQuaternionToRef(visual.orientation,this.hotAir).addInPlace(visual.position);
      this.graph.pressure.exhaust(this.hotAir,length,plane.throttle*.28+plane.boost*.52);
    }else this.graph.pressure.exhaust(this.hotAir,0,0);
    this.followEnvironment(time,plane.velocity.x*3.5,plane.velocity.z*3.5);
  }
  private followEnvironment(time:number,leadX:number,leadZ:number){
    const p=this.camera.position;
    this.sea.setPosition(Math.round(p.x/16)*16,0,Math.round(p.z/16)*16);
    this.updateTiles(p.x,p.z,time,leadX,leadZ);
    this.vegetation.update(this.terrain,p.x,p.z,this.level,time);
  }
  private tile(x:number,z:number,step:number,cells=chunkCells){
    const p:number[]=[],c:number[]=[],uv:number[]=[],idx:number[]=[],normals:number[]=[];
    const count=cells/step+1,patch=this.terrain.priorityArea;
    for(let iz=0;iz<count;iz++)for(let ix=0;ix<count;ix++){
      const i=x+ix*step,j=z+iz*step,px=i*gridStep-worldExtent/2,pz=j*gridStep-worldExtent/2,h=this.terrain.sampleNode(i,j);
      p.push(px,h,pz);uv.push(px/87,pz/87);
      const left=this.terrain.sampleNode(Math.max(0,i-1),j),right=this.terrain.sampleNode(Math.min(gridSize-1,i+1),j);
      const near=this.terrain.sampleNode(i,Math.max(0,j-1)),far=this.terrain.sampleNode(i,Math.min(gridSize-1,j+1));
      const sx=right-left,sz=far-near;
      const valley=clamp((left+right+near+far-4*h)/145,0,.24);
      const slope=Math.hypot(sx,sz)/(gridStep*2);
      const length=Math.hypot(sx,sz,gridStep*2);
      normals.push(-sx/length,gridStep*2/length,-sz/length);
      const baseColor=palette[theatres.indexOf(this.theme)];
      const canopy=noise(px*.00054,pz*.00072)*.77+noise(px*.00177-3.3,pz*.00135+6.1)*.23;
      const vegetation=(canopy-.5)*.48;
      const erosion=noise(px*.0029+h*.004,pz*.0013-h*.003)-.5;
      const strata=noise(pz*.0024+h*.016,px*.0015)-.5;
      const rock=clamp((slope-.31)*1.83+Math.max(0,h-1200)*.00027+vegetation-valley*.43,0,1);
      const beach=clamp((22+erosion*18-h)/34,0,1)*(1-clamp(slope*1.48,0,1));
      const snow=this.theme.id==='frost'?clamp((h-920+vegetation*710+erosion*160)/455,0,.97)*(1-clamp((slope-.47)*.71,0,.74)):0;
      const sunSlope=clamp((sz-sx)/(gridStep*6),-.26,.26);
      const meadow=noise(px*.003,pz*.004);
      [142,137,111].forEach((sand,k)=>{
        const soil=baseColor[k]+meadow*17+erosion*19+sunSlope*[13,14,5][k]+(canopy-.53)*[16,29,3][k];
        const r=soil*(1-rock)+([117,120,122][k]+strata*39+erosion*15)*rock;
        c.push(Math.round((r*(1-valley)*(1-beach)+sand*beach)*(1-snow)+[208,224,230][k]*snow));
      });
      c.push(255);
    }
    for(let j=0;j<count-1;j++)for(let i=0;i<count-1;i++){
      const bx=x+i*step,bz=z+j*step;
      if(cells===chunkCells&&patch&&bx>=patch.i&&bx<patch.i+patch.cells&&bz>=patch.j&&bz<patch.j+patch.cells)continue;
      const a=j*count+i;idx.push(a,a+count,a+1,a+1,a+count,a+count+1);
    }
    // Skirts stay submerged or hidden behind the neighbouring higher detail surface.
    const border=[...Array.from({length:count},(_,i)=>i),...Array.from({length:count-1},(_,i)=>(i+1)*count+count-1),
      ...Array.from({length:count-1},(_,i)=>(count-1)*count+count-2-i),...Array.from({length:count-2},(_,i)=>(count-2-i)*count)];
    const first=p.length/3;
    for(const i of border){p.push(p[i*3],p[i*3+1]-160,p[i*3+2]);uv.push(uv[i*2],uv[i*2+1]);c.push(c[i*4],c[i*4+1],c[i*4+2],255);}
    for(const i of border)normals.push(normals[i*3],normals[i*3+1],normals[i*3+2]);
    border.forEach((a,i)=>{const j=(i+1)%border.length,b=border[j];idx.push(a,b,first+i,b,first+j,first+i);});
    const tile=meshEntity(this.entry.app,this.terrainRoot,'高程块 '+x+' '+z,p,idx,this.terrainMaterial,normals,c,uv);
    tile.render!.receiveShadows=true;
    return tile;
  }
  // Ensure the original mountain silhouettes exist before the first combat frame.
  // Coarse tiles are refined by the existing LOD budget, never replaced with an empty frame.
  prepareTerrain(){
    const patch=this.terrain.priorityArea;
    if(patch&&!this.microTile){
      this.microTile=this.tile(patch.i,patch.j,16,patch.cells);
      this.microTile.name='priority-16';
    }
    for(const block of this.terrain.blocks){
      const key=block.z*gridSize+block.x;
      if(this.terrainTiles.has(key))continue;
      const step=16;
      this.terrainTiles.set(key,{...block,step,entity:this.tile(block.x,block.z,step)});
    }
    this.tileClock=-Infinity;
  }
  private updateTiles(x:number,z:number,time:number,leadX:number,leadZ:number){
    if(time-this.tileClock<.38&&time>=this.tileClock)return;
    this.tileClock=time;
    const patch=this.terrain.priorityArea;
    if(patch){
      const range=Math.hypot((patch.i+32)*gridStep-worldExtent*.5-x,(patch.j+32)*gridStep-worldExtent*.5-z);
      const step=range<1750&&this.level>.83?.5:range<6500?2:16;
      if(!this.microTile||this.microTile.name!=='priority-'+step){
        const replacement=this.tile(patch.i,patch.j,step,patch.cells);
        replacement.name='priority-'+step;
        this.microTile?.destroy();this.microTile=replacement;
      }
    }
    let built=0;
    const initial=this.terrainTiles.size===0;
    const blocks=this.terrain.blocks.map(block=>{
      const dx=(block.x+chunkCells/2)*gridStep-worldExtent/2-x,dz=(block.z+chunkCells/2)*gridStep-worldExtent/2-z;
      const range=Math.hypot(dx,dz);
      return {block,range,next:Math.min(range,Math.hypot(dx-leadX,dz-leadZ))};
    }).sort((a,b)=>a.next-b.next);
    for(const {block,range,next} of blocks){
      const key=block.z*gridSize+block.x,tile=this.terrainTiles.get(key);
      if(tile&&range>55000&&next>51000){tile.entity.destroy();this.terrainTiles.delete(key);continue;}
      if(!tile&&next>50000)continue;
      const detail=Math.max(.79,this.level);
      const near=(tile?.step===2?2500:1950)*detail;
      const mid=(tile?.step===4?7800:6700)*detail;
      const close=next<(tile?.step===1?1590:1300)*detail&&this.level>.98;
      const step=close?1:next<near?2:next<mid?4:next<13000?8:16;
      if(tile?.step===step)continue;
      if(built>=(initial?24:6))continue;
      const replacement=this.tile(block.x,block.z,step);
      this.terrainTiles.set(key,{...block,step,entity:replacement});
      tile?.entity.destroy();built++;
    }
  }
  inspectTerrain(mode:number){
    for(const material of [this.terrainMaterial,this.ridgeMaterial]){
      material.setParameter('terrainView',mode);material.useLighting=mode===0;material.update();
    }
  }
  updateShaders(time:number,ambientTime=time){
    this.camera.commit();
    const p=this.camera.position;this.sky.setPosition(p.x,p.y,p.z);
    if(!this.indoors){
      const step=this.pressureTime<0?0:Math.max(0,Math.min(.2,time-this.pressureTime));
      this.pressureTime=time;
      this.camRight.set(1,0,0).rotateByQuaternionToRef(this.camera.rotationQuaternion,this.camRight);
      this.camUp.set(0,1,0).rotateByQuaternionToRef(this.camera.rotationQuaternion,this.camUp);
      this.camForward.set(0,0,-1).rotateByQuaternionToRef(this.camera.rotationQuaternion,this.camForward);
      this.graph.pressure.collect(step,p,this.camRight,this.camUp,this.camForward,this.camera.fov,
        this.entry.canvas.width/Math.max(1,this.entry.canvas.height),this.camera.minZ,this.camera.entity.camera!.farClip,
        time,this.weather,this.view===1,this.cloudCover,this.clouds,this.airspeed);
      if(this.impactLamp.enabled){
        const remain=this.glowEnds-time;
        this.impactLamp.enabled=remain>0;
        this.impactLamp.light!.intensity=this.glow*Math.min(1,remain*3.9)**2;
      }
    }
    this.sea.enabled=!this.indoors&&this.ocean&&!!this.edgeDepth;
    this.terrainRoot.enabled=!this.indoors&&this.ground;
    this.eye.set([p.x,p.y,p.z]);
    this.ridgeMaterial.setParameter('terrainClock',ambientTime);
    for(const m of [this.skyMat,this.seaMat]){
      m.setParameter('clock',m===this.seaMat?time:ambientTime);m.setParameter('atmosphereClock',ambientTime);
      m.setParameter('quality',this.level);m.setParameter('clouds',this.clouds?1:0);
    }
  }
}
