import "@babylonjs/core/Lights/Shadows/shadowGeneratorSceneComponent";
import { LoadAssetContainerAsync } from '@babylonjs/core/Loading/sceneLoader';
import type { AssetContainer } from '@babylonjs/core/assetContainer';
import '@babylonjs/loaders/glTF';
import { KhronosTextureContainer2 } from '@babylonjs/core/Misc/khronosTextureContainer2';
import { MeshoptCompression } from '@babylonjs/core/Meshes/Compression/meshoptCompression';
import decoderUrl from 'meshoptimizer/meshopt_decoder.js?url';
import { AnimationGroup } from '@babylonjs/core/Animations/animationGroup';
import { Matrix, Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { Color3,Color4 } from '@babylonjs/core/Maths/math.color';
import { Viewport } from '@babylonjs/core/Maths/math.viewport';
import { FreeCamera } from '@babylonjs/core/Cameras/freeCamera';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import { CreateBox } from '@babylonjs/core/Meshes/Builders/boxBuilder';
import { CreateGround } from '@babylonjs/core/Meshes/Builders/groundBuilder';
import { CreateSphere } from '@babylonjs/core/Meshes/Builders/sphereBuilder';
import { CreateCylinder } from '@babylonjs/core/Meshes/Builders/cylinderBuilder';
import { CreateTorus } from '@babylonjs/core/Meshes/Builders/torusBuilder';
import { DirectionalLight } from '@babylonjs/core/Lights/directionalLight';
import { HemisphericLight } from '@babylonjs/core/Lights/hemisphericLight';
import { CascadedShadowGenerator } from '@babylonjs/core/Lights/Shadows/cascadedShadowGenerator';
import { ShadowGenerator } from '@babylonjs/core/Lights/Shadows/shadowGenerator';
import { SSAO2RenderingPipeline } from '@babylonjs/core/PostProcesses/RenderPipeline/Pipelines/ssao2RenderingPipeline';
import { DefaultRenderingPipeline } from '@babylonjs/core/PostProcesses/RenderPipeline/Pipelines/defaultRenderingPipeline';
import { ImageProcessingConfiguration } from '@babylonjs/core/Materials/imageProcessingConfiguration';
import { HDRCubeTexture } from '@babylonjs/core/Materials/Textures/hdrCubeTexture';
import { DynamicTexture } from '@babylonjs/core/Materials/Textures/dynamicTexture';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import { Material } from '@babylonjs/core/Materials/material';
import type { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { Scene } from '@babylonjs/core/scene';
import { airfield, base } from './airfield-layout';
import { theatres, type PlaneSpec } from './data';
import { Airframe } from './flight';
import { FlightCamera } from './flight-camera';
import { RockSurface } from './terrain-material';
import { WorldMaterial,material } from './world-material';
import { edgeNode, keyOf, partition, streamBlocks } from './terrain-stream';
import { OceanRender } from './ocean-render';
import { wakeCeiling } from './ocean-solver';
import { Terrain, clamp, chunkCells, gridStep, noise, worldExtent } from './terrain';
import { rotate,type OpenEngine } from './scene-runtime';
export { openEngine,type OpenEngine } from './scene-runtime';
export { material } from './world-material';

export const asset=(path:string)=>new URL(path,document.baseURI).href;
MeshoptCompression.Configuration.decoder.url=asset(decoderUrl);
KhronosTextureContainer2.DefaultNumWorkers=1;
Object.assign(KhronosTextureContainer2.URLConfig,{
  jsDecoderModule:asset('runtime/ktx2-decoder.js'),
  jsMSCTranscoder:asset('runtime/msc_basis_transcoder.js'),
  wasmMSCTranscoder:asset('runtime/msc_basis_transcoder.wasm'),
});
const compressedTexture=new Map([['studio/tarmac.webp','studio/tarmac.ktx2'],['surface/rock-grain.png','surface/rock-grain.ktx2']]);

export interface LoadedModel {root:TransformNode;animations:AnimationGroup[]}
export class Assets {
  private readonly models=new Map<string,Promise<AssetContainer>>();
  private readonly textures=new Map<string,Promise<Texture>>();
  private readonly textureFootprints=new WeakMap<Texture,number>();
  private loadedTextureBytes=0;
  private readonly compressed=new Set<string>();
  private pinnedFleet:ReadonlySet<string>=new Set();
  constructor(readonly scene:Scene){}
  private reuse<T>(cache:Map<string,Promise<T>>,key:string,load:()=>Promise<T>){
    let pending=cache.get(key);
    cache.delete(key);
    if(!pending)pending=load().catch(error=>{cache.delete(key);throw error;});
    cache.set(key,pending);return pending;
  }
  container(path:string){
    return this.reuse(this.models,path,()=>LoadAssetContainerAsync(asset(path),this.scene,{
      pluginExtension:'.glb',pluginOptions:{gltf:{animationStartMode:0}},
    }));
  }
  async model(path:string):Promise<LoadedModel>{
    const container=await this.container(path);
    const result=container.instantiateModelsToScene(name=>name,false,{doNotInstantiate:true});
    const root=new TransformNode(path,this.scene);
    for(const node of result.rootNodes){node.parent=root;node.setEnabled(true);}
    return {root,animations:result.animationGroups};
  }
  texture(path:string){
    const choice=compressedTexture.get(path);
    if(!choice)return this.readTexture(path);
    return this.readTexture(choice).catch(()=>this.readTexture(path));
  }
  private readTexture(path:string){
    return this.reuse(this.textures,path,()=>new Promise<Texture>((resolve,reject)=>{
      const t=new Texture(asset(path),this.scene,{noMipmap:path.startsWith('world/'),invertY:false,
        samplingMode:path.startsWith('world/')?Texture.NEAREST_SAMPLINGMODE:Texture.TRILINEAR_SAMPLINGMODE,
        onLoad:()=>{
          const {width,height}=t.getSize();
          const bytes=Math.ceil(width*height*4*(path.startsWith('world/')?1:4/3));
          this.loadedTextureBytes+=bytes;this.textureFootprints.set(t,bytes);
          if(path.endsWith('.ktx2'))this.compressed.add(path);
          t.onDisposeObservable.addOnce(()=>{this.loadedTextureBytes-=this.textureFootprints.get(t)??0;});
          resolve(t);
        },onError:reason=>{t.dispose();reject(Error(reason??path));}});
    }));
  }
  estimatedTextureBytes(){return this.loadedTextureBytes;}
  compressedCount(){return this.compressed.size;}
  trimFleet(keep:ReadonlySet<string>){
    this.pinnedFleet=keep;
    const aircraft=[...this.models].filter(([key])=>key.startsWith('fleet/'));
    for(const [key,pending] of aircraft.filter(([key])=>!keep.has(key.slice(6,-4))).slice(0,Math.max(0,aircraft.length-9))){
      void pending.then(container=>{
        if(this.models.get(key)!==pending||this.pinnedFleet.has(key.slice(6,-4)))return;
        this.models.delete(key);container.dispose();
      }).catch(()=>{});
    }
  }
}

export type Primitive='plane'|'box'|'cone'|'torus'|'sphere'|'cylinder';
export function primitive(parent:TransformNode,name:string,type:Primitive,mat:Material,x:number,y:number,z:number,w:number,h:number,l:number){
  const scene=parent.getScene();
  const mesh=type==='plane'?CreateGround(name,{width:1,height:1},scene):type==='box'?CreateBox(name,{size:1},scene):
    type==='torus'?CreateTorus(name,{diameter:1,thickness:.052,tessellation:32},scene):type==='sphere'?CreateSphere(name,{segments:24,diameter:1},scene):
    CreateCylinder(name,{height:1,diameterBottom:1,diameterTop:type==='cone'?0:1,tessellation:18},scene);
  mesh.parent=parent;mesh.position.set(x,y,z);mesh.scaling.set(w,h,l);mesh.material=mat;return mesh;
}
function meshEntity(parent:TransformNode,name:string,positions:number[],indices:number[],mat:Material,normals?:number[],colors?:number[],uv?:number[]){
  const mesh=new Mesh(name,parent.getScene()),data=new VertexData();
  data.positions=positions;data.indices=indices;data.normals=normals??null;data.uvs=uv??null;
  if(colors)data.colors=colors.map(v=>clamp(v/255,0,1));
  data.applyToMesh(mesh);mesh.parent=parent;mesh.material=mat;
  mesh.receiveShadows=true;
  return mesh;
}

class Camera {
  readonly position=new Vector3();
  readonly upVector=new Vector3(0,1,0);
  readonly rotationQuaternion=Quaternion.Identity();
  private readonly view=Matrix.Identity();
  private readonly viewport=new Viewport(0,0,1,1);
  target:Vector3|null=null;
  fov=1;minZ=.5;
  constructor(readonly native:FreeCamera,readonly canvas:HTMLCanvasElement){native.rotationQuaternion=Quaternion.Identity();}
  setTarget(target:Vector3){this.target=target;}
  commit(){
    this.native.position.copyFrom(this.position);
    if(this.target){
      Matrix.LookAtRHToRef(this.position,this.target,this.upVector,this.view);
      this.view.invert();Quaternion.FromRotationMatrixToRef(this.view,this.rotationQuaternion);
    }
    this.native.rotationQuaternion!.copyFrom(this.rotationQuaternion);
    this.native.fov=this.fov;this.native.minZ=this.minZ;
    this.native.getViewMatrix(true);
  }
  getDirectionToRef(axis:Vector3,out:Vector3){axis.rotateByQuaternionToRef(this.rotationQuaternion,out);}
  project(point:Vector3,out:Vector3,width=this.canvas.clientWidth,height=this.canvas.clientHeight){
    this.viewport.width=width;this.viewport.height=height;
    const view=this.native.getViewMatrix(),m=view.m;
    const depth=-(point.x*m[2]+point.y*m[6]+point.z*m[10]+m[14]);
    Vector3.ProjectToRef(point,Matrix.IdentityReadOnly,this.native.getTransformationMatrix(),this.viewport,out);
    out.z=depth;
  }
}

const palette=[[49,80,52],[46,63,58],[46,68,57]];
const skyVectors=(t:(typeof theatres)[number])=>({horizon:new Float32Array(t.horizon),zenith:new Float32Array(t.sky),
  sunDir:new Float32Array(t.sun),sunColor:new Float32Array(t.light),sea:new Float32Array(t.sea)});
type Tile={x:number;z:number;layout:string;entity:TransformNode;triangles:number};
export class WorldView {
  readonly camera:Camera;
  readonly assets:Assets;
  readonly hangar:TransformNode;
  readonly field:TransformNode;
  readonly effects:TransformNode;
  readonly vehicles:TransformNode;
  readonly props:TransformNode;
  readonly terrainRoot:TransformNode;
  readonly sky:Mesh;
  readonly sea:Mesh;
  readonly sun:DirectionalLight;
  readonly rim:DirectionalLight;
  private readonly fill:HemisphericLight;
  private readonly shadows:ShadowGenerator;
  private readonly pipeline:DefaultRenderingPipeline;
  private ambientOcclusion:SSAO2RenderingPipeline|null=null;
  private readonly terrainMaterial:PBRMaterial;
  private readonly ridgeMaterial:PBRMaterial;
  private readonly rock:RockSurface;
  private readonly ridge:RockSurface;
  readonly terrainTiles=new Map<string,Tile>();
  readonly targets:Mesh[];
  readonly rings:Mesh[];
  readonly ready:Promise<void>;
  readonly skyMat:WorldMaterial;
  readonly seaMat:WorldMaterial;
  readonly seaFields:OceanRender;
  terrain=new Terrain(theatres[0].seed);
  theme=theatres[0];
  level=.94;view=0;orbit=.72;tilt=.16;cameraReset=true;fixed=false;
  clouds=true;ocean=true;ground=true;
  private weather=0;
  private lighting=0;
  private indoors=true;
  private readonly rig=new FlightCamera();
  private readonly eye=new Float32Array(3);
  private readonly look=new Vector3();
  private readonly pose={position:this.cameraPosition(),upVector:new Vector3(0,1,0),rotationQuaternion:null as Quaternion|null,
    fov:1,minZ:.5,setTarget:(t:Vector3)=>{this.camera.setTarget(t);}};
  private cameraPosition(){return new Vector3();}
  private tileClock=-Infinity;
  private themeSequence=0;
  private edgeDepth:Texture|null=null;
  private probeName='';
  private readonly probes=new Map<string,Promise<HDRCubeTexture>>();
  private waveHeight=1;
  private readonly contact:Mesh;
  private readonly climateDensities=[.000027,.000029,.000066,.000058,.000092,.000108,.000080,.000046];
  constructor(readonly entry:OpenEngine){
    const {app,canvas}=entry,scene=app.scene;
    const group=(name:string)=>{const node=new TransformNode(name,scene);node.parent=app.root;return node;};
    this.hangar=group('前沿机库');this.field=group('机场设施');this.effects=group('战场特效');
    this.vehicles=group('作战载具');this.props=group('训练目标');this.terrainRoot=group('海岸地貌');
    this.assets=new Assets(scene);
    this.terrainMaterial=material(scene,'分层地表','#ffffff',0,.91);
    this.ridgeMaterial=material(scene,'临海岩壁','#ffffff',.04,.86);
    this.rock=new RockSurface(this.terrainMaterial);this.ridge=new RockSurface(this.ridgeMaterial);
    const native=new FreeCamera('主镜头',Vector3.Zero(),scene);
    native.maxZ=100000;native.minZ=.15;scene.activeCamera=native;
    this.camera=new Camera(native,canvas);
    scene.clearColor=new Color4(.13,.22,.31,1);
    scene.fogMode=Scene.FOGMODE_EXP2;
    scene.imageProcessingConfiguration.toneMappingEnabled=true;
    scene.imageProcessingConfiguration.toneMappingType=ImageProcessingConfiguration.TONEMAPPING_ACES;
    this.pipeline=new DefaultRenderingPipeline('航空成像',true,scene,[native]);
    // The sky and sea already apply the same film curve in their own shaders.
    this.pipeline.imageProcessingEnabled=false;
    this.pipeline.bloomThreshold=.84;this.pipeline.bloomWeight=.14;this.pipeline.bloomKernel=24;
    this.pipeline.samples=app.device.getCaps().maxMSAASamples>=2?2:1;
    this.pipeline.fxaaEnabled=this.pipeline.samples===1;
    this.sun=new DirectionalLight('太阳主光',new Vector3(.88,-.43,-.22),scene);
    this.sun.shadowMinZ=1;this.sun.shadowMaxZ=250;
    this.rim=new DirectionalLight('机库轮廓光',new Vector3(-.57,-.32,.75),scene);
    this.rim.diffuse.set(.52,.68,.91);this.rim.intensity=1.22;
    this.fill=new HemisphericLight('天空与地面补光',new Vector3(.1,1,.15),scene);
    this.fill.groundColor.set(.22,.25,.32);this.fill.intensity=.72;
    if(CascadedShadowGenerator.IsSupported){
      const csm=new CascadedShadowGenerator(1024,this.sun);
      csm.numCascades=2;csm.shadowMaxZ=110;csm.lambda=.61;csm.usePercentageCloserFiltering=true;
      this.shadows=csm;
    }else this.shadows=new ShadowGenerator(1024,this.sun);
    this.shadows.normalBias=.045;this.shadows.bias=.0007;
    const hangarFloor=material(scene,'水磨混凝土','#c4b9a9',.11,.47);
    hangarFloor.clearCoat.isEnabled=true;hangarFloor.clearCoat.intensity=.47;hangarFloor.clearCoat.roughness=.18;
    primitive(this.hangar,'整体现浇机坪','plane',hangarFloor,0,0,23,140,1,191).receiveShadows=true;
    const shadowMap=new DynamicTexture('机库接触遮蔽',128,scene,false);
    shadowMap.hasAlpha=true;
    const paint=shadowMap.getContext(),shadow=paint.createRadialGradient(64,64,3,64,64,64);
    shadow.addColorStop(0,'#172030bb');shadow.addColorStop(.53,'#1720308f');shadow.addColorStop(1,'#17203000');
    paint.fillStyle=shadow;paint.fillRect(0,0,128,128);shadowMap.update();
    const shade=material(scene,'地面接触暗部','#18202b');
    shade.unlit=true;shade.disableDepthWrite=true;shade.opacityTexture=shadowMap;shade.transparencyMode=Material.MATERIAL_ALPHABLEND;
    this.contact=primitive(this.hangar,'机身接触暗部','plane',shade,0,.021,0,9,1,19);
    rotate(this.hangar,0,-57,0);this.hangarExterior();
    const gold=material(scene,'机库黄漆','#c5a466',.2,.57),seam=material(scene,'机坪收缩缝','#343743');
    for(const sign of [-1,1])primitive(this.hangar,'滑入导向线','box',gold,sign*7.5,.013,3,.11,.017,114);
    for(let k=-60;k<=100;k+=8)primitive(this.hangar,'混凝土分仓缝','box',seam,0,.008,k,134,.008,.022);
    this.skyMat=this.environment('sky');this.seaMat=this.environment('sea');
    this.seaFields=new OceanRender(scene,this.seaMat);
    this.sky=primitive(app.root,'分层大气','sphere',this.skyMat,0,0,0,155000,155000,155000);
    this.sky.renderingGroupId=0;this.sky.alwaysSelectAsActiveMesh=true;this.sky.alphaIndex=-10;
    this.sea=this.buildSea();
    const marker=material(scene,'航路标记','#95e1d3',.2,.39);marker.emissiveColor.set(.28,.56,.49);
    this.rings=Array.from({length:4},(_,i)=>primitive(this.props,'训练航标 '+i,'torus',marker,0,0,0,155,145,155));
    this.rings.forEach(e=>rotate(e,90,0,0));
    const target=material(scene,'训练标靶','#748777',.12);
    this.targets=Array.from({length:8},(_,i)=>primitive(this.props,'地面目标 '+i,'box',target,0,0,0,28,12,26));
    this.resetMarkers();
    const facilities={
      runway:material(scene,'机场铺装','#3e474d'),apron:material(scene,'机坪混凝土','#58686e'),
      hangar:material(scene,'机库钢构','#637071',.21),roof:material(scene,'机库顶板','#8b9896',.45),
      tower:material(scene,'指挥塔','#686f66'),glass:material(scene,'观察室','#3d6475',.33,.24),signal:marker,
    };
    for(const a of airfield)primitive(this.field,a.kind,'box',facilities[a.kind],a.x,a.y,a.z,a.w,a.h,a.l);
    for(let z=base.near+48;z<base.far-40;z+=53)primitive(this.field,'中心线','box',marker,base.x,32.1,z,1.7,.09,23);
    this.ready=Promise.all([
      Promise.all([this.assets.texture('studio/tarmac.webp'),this.assets.texture('studio/tarmac-orm.png'),
        this.assets.texture('studio/tarmac-normal.png'),this.assets.texture('studio/apron-light.webp')]).then(([color,detail,norm,lamps])=>{
        for(const t of [color,detail,norm])t.anisotropicFilteringLevel=Math.min(8,app.device.getCaps().maxAnisotropy);
        hangarFloor.albedoTexture=color;hangarFloor.metallicTexture=detail;
        hangarFloor.useAmbientOcclusionFromMetallicTextureRed=true;
        hangarFloor.useRoughnessFromMetallicTextureGreen=true;hangarFloor.useRoughnessFromMetallicTextureAlpha=false;
        hangarFloor.useMetallnessFromMetallicTextureBlue=true;
        norm.level=.29;hangarFloor.bumpTexture=norm;hangarFloor.emissiveTexture=lamps;hangarFloor.emissiveColor.set(.74,.74,.74);
        const runway=facilities.runway;
        runway.albedoTexture=color.clone();runway.bumpTexture=norm.clone();runway.albedoColor.set(.65,.64,.62);
        for(const t of [runway.albedoTexture,runway.bumpTexture] as Texture[]){t.uScale=3;t.vScale=19;}
      }),
      this.assets.model('studio/hangar-dusk.glb').then(({root,animations})=>{
        root.parent=this.hangar;root.position.set(34,0,44);
        for(const part of root.getChildMeshes())part.receiveShadows=true;
        for(const clip of animations)clip.dispose();
      }),
      this.assets.texture('surface/dusk-panorama.webp').then(t=>this.skyMat.setTexture('deckDome',t)),
      this.assets.texture('surface/cloud-density.png').then(t=>{this.skyMat.setTexture('weatherTex',t);this.seaMat.setTexture('weatherTex',t);}),
      this.assets.texture('surface/wave-field.png').then(t=>this.seaMat.setTexture('waveTex',t)),
      this.assets.texture('world/sundown-surface.png').then(t=>{this.edgeDepth=t;this.seaMat.setTexture('depthTex',t);}),
      this.assets.texture('surface/rock-grain.png').then(t=>{t.anisotropicFilteringLevel=8;this.rock.grain=this.ridge.grain=t;}),
      this.assets.texture('surface/terrain-normal.png').then(t=>{t.anisotropicFilteringLevel=8;t.level=.34;
        this.terrainMaterial.bumpTexture=this.ridgeMaterial.bumpTexture=t;}),
      this.lightingProbe('deck'),
    ]).then(()=>undefined);
    this.showDeck(true);
  }
  castShadow(mesh:Mesh){this.shadows.addShadowCaster(mesh,false);}
  dropShadow(mesh:Mesh){this.shadows.removeShadowCaster(mesh,false);}
  private lightingProbe(name:string){
    this.probeName=name;
    let pending=this.probes.get(name);
    if(!pending){
      pending=new Promise<HDRCubeTexture>((resolve,reject)=>{
        const file=name==='deck'?'airbase-atlas':name,scene=this.entry.app.scene;
        const t=new HDRCubeTexture(asset('surface/probe-'+file+'.hdr'),scene,64,false,true,false,true,()=>resolve(t),
          reason=>{t.dispose();reject(Error(reason??file));});
      });
      this.probes.set(name,pending);
    }
    return pending.then(probe=>{
      if(this.probeName===name)this.entry.app.scene.environmentTexture=probe;
    }).catch(error=>{this.probes.delete(name);console.warn('环境反射资源不可用',error);});
  }
  private hangarExterior(){
    const n=53;
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
      const normals:number[]=[];VertexData.ComputeNormals(p,indices,normals);
      meshEntity(this.hangar,layer?'海雾外分水岭':'近岸岩脊',p,indices,this.ridgeMaterial,normals,colors,uv);
    }
    const water=material(this.entry.app.scene,'机场外侧海面','#46586c',.26,.37);
    primitive(this.hangar,'远处泊地','plane',water,0,-.98,420,1400,1,1000);
  }
  private environment(name:'sky'|'sea'){
    const m=new WorldMaterial(this.entry.app.scene,this.entry.backend==='gpu',name==='sea');
    for(const [key,v] of Object.entries(skyVectors(this.theme)))m.setParameter(key,v);
    for(const [key,v] of Object.entries({quality:.94,cover:0,clouds:1,exposure:1.04,clock:0,eye:this.eye,waveHeight:1}))m.setParameter(key,v);
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
    return meshEntity(this.entry.app.root,'动态深水与海岸',p,idx,this.seaMat);
  }
  async setTheme(region:number){
    const theme=theatres[region],revision=++this.themeSequence;
    const t=await this.assets.texture('world/'+theme.id+'-surface.png');
    if(revision!==this.themeSequence)return;
    this.edgeDepth=t;this.seaMat.setTexture('depthTex',t);
    if(this.theme!==theme){
      this.theme=theme;this.terrain=new Terrain(theme.seed);
      for(const tile of this.terrainTiles.values())tile.entity.dispose();
      this.terrainTiles.clear();this.tileClock=-Infinity;
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
      vector.sunDir.set([-.93,.19,.37]);vector.horizon.set([.89,.52,.37]);
      vector.zenith.set([.22,.33,.61]);vector.sunColor.set([1,.72,.49]);
    }
    const n=Math.hypot(...vector.sunDir);vector.sunDir.forEach((v,i)=>vector.sunDir[i]=v/n);
    this.sun.direction.set(-vector.sunDir[0],-vector.sunDir[1],-vector.sunDir[2]);
    this.sun.diffuse.set(vector.sunColor[0],vector.sunColor[1],vector.sunColor[2]);
    this.sun.intensity=this.indoors?2.35:lighting===3?.27:sunlight*.90;
    this.sun.shadowEnabled=this.indoors;
    this.rim.setEnabled(this.indoors);
    scene.environmentIntensity=this.indoors?.91:dim?.56:.72;
    const probe=this.indoors?'deck':lighting===3||weather===7?'night':dim?'storm':lighting===1||this.theme.id==='frost'?'day':'dusk';
    if(probe!==this.probeName)void this.lightingProbe(probe);
    scene.fogDensity=this.indoors?.00040:this.climateDensities[weather]??.000045;
    scene.fogColor.set(vector.horizon[0]*.87,vector.horizon[1]*.91,vector.horizon[2]*.96);
    this.fill.diffuse.set(this.indoors?.51:.62,this.indoors?.59:.71,this.indoors?.79:.85);
    this.fill.intensity=this.indoors?.66:dim?.81:.72;
    const cover=[.006,.026,-.055,-.10,-.16,-.015,-.077,.087][weather]??.006;
    for(const m of [this.skyMat,this.seaMat]){
      for(const [key,value] of Object.entries(vector))m.setParameter(key,value);
      m.setParameter('cover',this.indoors?-.115:cover);
      m.setParameter('cloudBase',this.indoors?325:930);
      m.setParameter('exposure',this.indoors?1.02:dim?1.07:1.09);
      m.setParameter('waveHeight',this.waveHeight);
    }
  }
  showDeck(active:boolean){
    this.indoors=active;this.hangar.setEnabled(active);
    this.seaFields.reset(active?null:this.terrain.bathymetry());
    this.terrain.extraWater=active?null:(x,z,scale)=>this.seaFields.height(x,z,scale);
    for(const node of [this.field,this.terrainRoot,this.props,this.sea,this.effects])node.setEnabled(!active);
    this.configureFlightWeather(this.weather,this.lighting);this.cameraReset=true;
  }
  updateWater(plane:Airframe,time:number){
    const {x,y,z}=plane.position;
    const altitude=y-this.terrain.water(x,z,time);
    this.seaFields.advance({time,x,z,altitude,speed:plane.speed,water:altitude<wakeCeiling&&this.terrain.classify(x,z)==='water'},plane.forward.x,plane.forward.z);
  }
  resetMarkers(){for(const m of [...this.targets,...this.rings])m.setEnabled(false);}
  setAwardLighting(on:boolean){this.rim.intensity=on?1.55:1.22;}
  preview(plane:PlaneSpec,t:number,mode:string,zoom=1){
    const hero=mode==='home',size=Math.max(plane.length,plane.span);
    const yaw=this.orbit+(hero?.09:0)+Math.sin(t*.19)*.016;
    const aspect=this.entry.canvas.clientWidth/Math.max(1,this.entry.canvas.clientHeight);
    const fit=hero?clamp(1.91/aspect,.86,1.25):1;
    const d=Math.max(hero?10:15,size*(hero?.97:mode==='reveal'?1.19:1.28)*fit*zoom);
    const y=plane.gearClearance||1.45;
    this.contact.scaling.set(plane.span*.91,1,plane.length*.96);
    this.camera.position.set(Math.sin(yaw)*d,y+d*((hero?.079:.110)+this.tilt*.25),-Math.cos(yaw)*d);
    this.look.set(hero?-1.67:0,y+(hero?.72:.43),0);
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
    this.followEnvironment(time,plane.velocity.x*3.5,plane.velocity.z*3.5);
  }
  private followEnvironment(time:number,leadX:number,leadZ:number){
    const p=this.camera.position;
    this.sea.position.set(Math.round(p.x/16)*16,0,Math.round(p.z/16)*16);
    this.updateTiles(p.x,p.z,time,leadX,leadZ);
  }
  private tile(parent:TransformNode,x:number,z:number,step:number,size=chunkCells){
    const p:number[]=[],c:number[]=[],uv:number[]=[],idx:number[]=[],normals:number[]=[];
    const count=size/step+1;
    const node=(i:number,j:number)=>this.terrain.node(i,j);
    for(let iz=0;iz<count;iz++)for(let ix=0;ix<count;ix++){
      const i=x+ix*step,j=z+iz*step,px=i*gridStep-worldExtent/2,pz=j*gridStep-worldExtent/2;
      const edgeX=ix===0||ix===count-1,edgeZ=iz===0||iz===count-1;
      const h=edgeX||edgeZ?edgeNode(i,j,edgeZ,node):node(i,j);
      p.push(px,h,pz);uv.push(px/87,pz/87);
      const left=this.terrain.node(i-1,j),right=this.terrain.node(i+1,j);
      const near=this.terrain.node(i,j-1),far=this.terrain.node(i,j+1);
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
    for(let z=0;z<count-1;z++)for(let x=0;x<count-1;x++){const a=z*count+x;idx.push(a,a+count,a+1,a+1,a+count,a+count+1);}
    return meshEntity(parent,'高程块 '+x+' '+z,p,idx,this.terrainMaterial,normals,c,uv);
  }
  private updateTiles(x:number,z:number,time:number,leadX:number,leadZ:number){
    if(time-this.tileClock<.34&&time>=this.tileClock)return;
    this.tileClock=time;
    const initial=this.terrainTiles.size===0,detail=Math.max(.78,this.level);
    const blocks=streamBlocks(x,z,leadX,leadZ,this.terrain.blocks).map(block=>{
      const dx=(block.x+32)*gridStep-worldExtent/2-x,dz=(block.z+32)*gridStep-worldExtent/2-z;
      const range=Math.hypot(dx,dz);
      return {block,range,next:Math.min(range,Math.hypot(dx-leadX,dz-leadZ))};
    }).sort((a,b)=>a.next-b.next);
    const active=new Set<string>();let built=0;
    for(const {block,range,next} of blocks){
      const key=keyOf(block.x,block.z),tile=this.terrainTiles.get(key);
      if(next>(tile?40500:37500))continue;
      active.add(key);
      if(built>=(initial?24:5))continue;
      const split=(tile?.layout.includes('|')?4200:3650)*detail;
      const patches=next<split?partition(block,x+leadX,z+leadZ,2400*detail):[{...block,size:chunkCells,stride:range<10500*detail?2:4}];
      const layout=patches.map(p=>`${p.x},${p.z},${p.stride}`).join('|');
      if(tile?.layout===layout)continue;
      const parent=new TransformNode('地貌区块 '+key,this.entry.app.scene);parent.parent=this.terrainRoot;
      let triangles=0;
      for(const patch of patches){
        const mesh=this.tile(parent,patch.x,patch.z,patch.stride,patch.size);triangles+=mesh.getTotalIndices()/3;
      }
      tile?.entity.dispose();this.terrainTiles.set(key,{...block,layout,entity:parent,triangles});built++;
    }
    for(const [key,tile] of this.terrainTiles)if(!active.has(key)){tile.entity.dispose();this.terrainTiles.delete(key);}
  }
  terrainStats(){
    let triangles=0,leaves=0;
    for(const tile of this.terrainTiles.values()){triangles+=tile.triangles;leaves+=tile.layout.split('|').length;}
    return {roots:this.terrainTiles.size,leaves,triangles};
  }
  inspectTerrain(mode:number){
    this.rock.view=this.ridge.view=mode;
    this.terrainMaterial.unlit=this.ridgeMaterial.unlit=mode!==0;
  }
  applyQuality(level:number){
    const enhanced=level>=1.07;
    const ambient=enhanced&&this.indoors&&SSAO2RenderingPipeline.IsSupported;
    if(ambient&&!this.ambientOcclusion){
      const ao=new SSAO2RenderingPipeline('机库接触遮蔽',this.entry.app.scene,{ssaoRatio:.45,blurRatio:.55},[this.camera.native],true);
      ao.radius=.85;ao.totalStrength=.55;ao.samples=8;ao.maxZ=100;this.ambientOcclusion=ao;
    }else if(!ambient&&this.ambientOcclusion){this.ambientOcclusion.dispose(true);this.ambientOcclusion=null;}
    if(this.pipeline.bloomEnabled!==enhanced)this.pipeline.bloomEnabled=enhanced;
    this.shadows.filteringQuality=enhanced?ShadowGenerator.QUALITY_HIGH:ShadowGenerator.QUALITY_MEDIUM;
    this.sun.shadowEnabled=this.indoors||enhanced;
  }
  updateShaders(time:number,ambientTime=time){
    this.camera.commit();
    const p=this.camera.position;this.sky.position.set(p.x,p.y,p.z);
    this.sea.setEnabled(!this.indoors&&this.ocean&&!!this.edgeDepth);
    this.terrainRoot.setEnabled(!this.indoors&&this.ground);
    this.eye.set([p.x,p.y,p.z]);
    for(const m of [this.skyMat,this.seaMat]){
      m.setParameter('clock',m===this.seaMat?time:ambientTime);m.setParameter('quality',this.level);m.setParameter('clouds',this.clouds?1:0);
    }
  }
}
