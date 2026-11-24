import {
  ADDRESS_CLAMP_TO_EDGE, AutoExposureEffect, CameraFrame, CameraFrameEffect, COMPOSESLOT_SCENE, FRAMERESOURCE_DEPTH,
  PIXELFORMAT_RGBA8, RenderPassShaderQuad, RenderTarget, SEMANTIC_POSITION, ShaderUtils, SmaaEffect,
  Texture, TONEMAP_ACES, type AppBase, type CameraComponent, type GraphicsDevice
} from 'playcanvas';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';

const waveCount=6;
const fieldCount=waveCount+1;
function pressureShader(gpu:boolean){
  const v2=gpu?'vec2f':'vec2',v3=gpu?'vec3f':'vec3',v4=gpu?'vec4f':'vec4';
  const f=gpu?'f32':'float',u=gpu?'uniform.':'';
  const declare=(name:string,type:string,value:string,mutable=false)=>gpu?
    (mutable?'var ':'let ')+name+':'+type+'='+value+';':type+' '+name+'='+value+';';
  const loop=gpu?'var i:i32=0':'int i=0';
  const uv=gpu?'input.uv0':'uv0';
  return `
  #include "screenDepthPS"
  ${gpu?`varying uv0:vec2f;
    uniform pressureCenters:array<vec4f,${fieldCount}>;
    uniform pressureGain:array<vec4f,${fieldCount}>;
    uniform pressureCount:i32;
    uniform pressureLens:vec2f;
    uniform atmosphere:vec4f;
    uniform cloudSample:vec4f;
    var localCloud:texture_2d<f32>;
    var localCloudSampler:sampler;
    @fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{var output:FragmentOutput;`:
    `varying vec2 uv0;
    uniform vec4 pressureCenters[${fieldCount}];
    uniform vec4 pressureGain[${fieldCount}];
    uniform int pressureCount;
    uniform vec2 pressureLens;
    uniform vec4 atmosphere;
    uniform vec4 cloudSample;
    uniform sampler2D localCloud;
    void main(){`}
  ${declare('ndc',v2,`${uv}*2.-${v2}(1.)`)}
  ${declare('ray',v3,`normalize(${v3}(ndc.x*${u}pressureLens.x,ndc.y*${u}pressureLens.y,1.))`)}
  ${declare('offset',v2,`${v2}(0.)`,true)}
  ${declare('opaque',f,`getLinearScreenDepth(${uv})`)}
  for(${loop};i<${fieldCount};i++){
    if(i>=${u}pressureCount){break;}
    ${declare('center',v4,`${u}pressureCenters[i]`)}
    ${declare('gain',v4,`${u}pressureGain[i]`)}
    ${declare('middle',f,'dot(ray,center.xyz)')}
    ${declare('delta',f,'center.w*center.w-dot(center.xyz,center.xyz)+middle*middle')}
    if(delta>0.){
      ${declare('root',f,'sqrt(delta)')}
      ${declare('nearDepth',f,'max(0.,middle-root)*ray.z')}
      ${declare('rim',f,'1.-smoothstep(0.,center.w*.53,root)')}
      ${declare('visible',f,'smoothstep(0.,max(.3,center.w*.12),opaque-nearDepth)')}
      ${declare('n',v3,'(ray*max(0.,middle-root)-center.xyz)/max(.001,center.w)')}
      ${declare('phase',f,'dot(n.xy,'+v2+'(23.,29.))+gain.y*12.')}
      ${declare('turbulence',f,'1.+.23*sin(phase)')}
      if(gain.z>.5){
        offset+=${v2}(sin(phase),cos(phase*1.18))*(1.-rim)*visible*gain.x;
      }else{
        offset+=${v2}(n.x,n.y*sign(${u}pressureLens.y))*rim*visible*turbulence*gain.x;
      }
    }
  }
  ${declare('mist',f,'0.',true)}
  ${declare('shine',f,'0.',true)}
  if(${u}cloudSample.z>.001){
    ${declare('weatherCell',v3,gpu?'textureSampleLevel(localCloud,localCloudSampler,uniform.cloudSample.xy,0.).rgb':'texture2DLod(localCloud,cloudSample.xy,0.).rgb')}
    ${declare('water',f,'weatherCell.r+(weatherCell.g-.48)*.55+(weatherCell.b-.49)*.10')}
    ${declare('cloudFloor',f,`.385+${u}cloudSample.w*.88`)}
    ${declare('cloud',f,`smoothstep(cloudFloor,cloudFloor+.231,water)*${u}cloudSample.z`)}
    ${declare('geometry',f,`1.-smoothstep(${u}camera_params.y*.88,${u}camera_params.y*.99,opaque)`)}
    mist=(1.-exp(-max(0.,opaque-6.)*.00048*cloud))*.28*geometry;
  }
  if(${u}atmosphere.x>.01){
    ${declare('glass',f,'(1.-smoothstep(.75,1.16,abs(ndc.x)*.91+abs(ndc.y)*.44))*smoothstep(.95,.98,opaque/(opaque+3.))')}
    ${declare('dropUV',v2,`${uv}*${v2}(24.,18.)`)}
    ${declare('cell',v2,'floor(dropUV)')}
    ${declare('seed',f,`fract(sin(dot(cell,${v2}(127.1,311.7)))*43758.5453)`)}
    ${declare('jitter',v2,`(${v2}(fract(seed*13.53),fract(seed*49.71))-.5)*.43`)}
    ${declare('track',v2,`fract(dropUV+${v2}(0.,${u}atmosphere.z*(.39+seed*.49)))-${v2}(.50,.48)+jitter`)}
    ${declare('size',f,'mix(.13,.28,seed)')}
    ${declare('shape',f,`length(track*${v2}(1.4,.81))/size`)}
    ${declare('wet',f,`step(.68,seed)*glass*${u}atmosphere.x`)}
    ${declare('drop',f,'(1.-smoothstep(.50,1.05,shape))*wet')}
    offset+=track*drop*1.75;
    shine=(smoothstep(.55,.86,shape)-smoothstep(.89,1.18,shape))*(.4+.6*step(0.,track.y))*wet;
    mist=max(mist,glass*${u}atmosphere.y*(.16+.82*smoothstep(.25,.87,abs(ndc.x))));
  }
  ${gpu?'output.color':'gl_FragColor'}=${v4}(clamp(offset*.5+${v2}(.5),${v2}(0.),${v2}(1.)),mist,shine);
  ${gpu?'return output;':''}
  }`;
}

interface PressureLayer {center:Vector3; age:number; life:number; radius:number; delay:number}
export class PressureField extends CameraFrameEffect {
  private pass?:RenderPassShaderQuad;
  private field?:RenderTarget;
  private readonly layers:PressureLayer[]=Array.from({length:waveCount},()=>({center:new Vector3(),age:0,life:0,radius:0,delay:0}));
  private cursor=0;
  private count=0;
  private readonly centers=new Float32Array(4*fieldCount);
  private readonly amplitudes=new Float32Array(4*fieldCount);
  private readonly lens=new Float32Array(2);
  private readonly planes=new Float32Array(4);
  private readonly relative=new Vector3();
  private readonly atmosphere=new Float32Array(4);
  private readonly cloudSample=new Float32Array(4);
  private readonly heatPosition=new Vector3();
  private heatLength=0;
  private heatStrength=0;
  private wetness=0;
  private cloudTexture?:Texture;
  private visible=false;
  constructor(device:GraphicsDevice){
    super(device,'flightPressure',{
      slot:COMPOSESLOT_SCENE,requires:[FRAMERESOURCE_DEPTH],
      glsl:`uniform sampler2D pressureField;
        uniform int activePressure;
        vec4 applyFlightPressure(vec4 color,vec2 uv){
          if(activePressure==0)return color;
          vec4 field=texture2DLod(pressureField,uv,0.);
          vec2 displacement=(field.rg-vec2(.5019608))*.052;
          vec4 scene=color;
          if(dot(displacement,displacement)>.000000025){
            scene=texture2DLod(sceneTexture,clamp(uv+displacement,vec2(.001),vec2(.999)),0.);
          }
          return vec4(mix(scene.rgb,vec3(.25,.32,.40),field.b)+vec3(.35,.43,.56)*field.a,scene.a);
        }`,
      wgsl:`var pressureField:texture_2d<f32>;
        var pressureFieldSampler:sampler;
        uniform activePressure:i32;
        fn applyFlightPressure(color:vec4f,uv:vec2f)->vec4f{
          if(uniform.activePressure==0){return color;}
          let field=textureSampleLevel(pressureField,pressureFieldSampler,uv,0.);
          let displacement=(field.rg-vec2f(.5019608))*.052;
          var scene=color;
          if(dot(displacement,displacement)>.000000025){
            scene=textureSampleLevel(sceneTexture,sceneTextureSampler,clamp(uv+displacement,vec2f(.001),vec2f(.999)),0.);
          }
          return vec4f(mix(scene.rgb,vec3f(.25,.32,.40),field.b)+vec3f(.35,.43,.56)*field.a,scene.a);
        }`
    });
  }
  clear(){for(const layer of this.layers)layer.life=0;this.count=0;this.wetness=0;this.heatStrength=0;this.visible=false;}
  setWeatherTexture(texture:Texture){this.cloudTexture=texture;}
  exhaust(center:Vector3,length:number,strength:number){
    this.heatPosition.copyFrom(center);this.heatLength=length;this.heatStrength=strength;
  }
  pulse(center:Vector3,scale:number,destroyed:boolean){
    const rings=destroyed?3:2;
    for(let n=0;n<rings;n++){
      const wave=this.layers[this.cursor++%waveCount];
      wave.center.copyFrom(center);wave.age=0;wave.delay=n*.087;
      wave.radius=scale*(destroyed?45:30)*(1-n*.16);
      wave.life=(destroyed?1.07:.88)-n*.051;
    }
  }
  collect(dt:number,eye:Vector3,right:Vector3,up:Vector3,forward:Vector3,fov:number,aspect:number,near:number,far:number,
    time:number,weather:number,canopy:boolean,cover:number,clouds:boolean,speed:number){
    const cloudHeight=(eye.y-930)/1700;
    const cloudBand=clouds&&this.cloudTexture?Math.max(0,Math.min(1,cloudHeight/.22,(1-cloudHeight)/.47)):0;
    const rain=weather===4?.98:weather===3?.77:weather===6?.26:0;
    const moisture=canopy?Math.max(rain,cloudBand*.47):0;
    this.wetness+=(moisture-this.wetness)*(1-Math.exp(-dt*(moisture>this.wetness?1.95:.52)));
    this.cloudSample.set([eye.x*.000105+time*.00014+.175+cloudHeight*.072,
      eye.z*.000105-time*.000085+.286-cloudHeight*.044,cloudBand,cover]);
    this.atmosphere.set([canopy?Math.max(this.wetness,rain*.19):0,canopy?this.wetness*(1-Math.min(.76,speed/650))*.42:0,time,0]);
    let offset=0;
    const maxDistance=9000;
    for(const wave of this.layers){
      if(wave.age>=wave.life||wave.life===0)continue;
      wave.age+=dt;
      if(wave.age<wave.delay||wave.age>=wave.life)continue;
      wave.center.subtractToRef(eye,this.relative);
      if(this.relative.lengthSquared()>maxDistance*maxDistance)continue;
      const phase=(wave.age-wave.delay)/(wave.life-wave.delay);
      const radius=wave.radius*(.14+.86*(1-(1-phase)**2.35));
      const depth=Vector3.Dot(this.relative,forward);
      if(depth<-radius||depth>5600+radius)continue;
      this.centers.set([Vector3.Dot(this.relative,right),Vector3.Dot(this.relative,up),depth,radius],offset);
      this.amplitudes.set([(1-phase)**1.6*Math.min(.7,160/Math.max(depth,1)),phase,0,0],offset);
      offset+=4;
    }
    if(this.heatStrength>0&&!canopy){
      this.heatPosition.subtractToRef(eye,this.relative);
      const x=Vector3.Dot(this.relative,right),y=Vector3.Dot(this.relative,up),z=Vector3.Dot(this.relative,forward);
      if(z>2&&z<76){
        this.centers.set([x,y,z,this.heatLength*.37],offset);
        this.amplitudes.set([this.heatStrength*.089,time*1.1,1,0],offset);
        offset+=4;
      }
    }
    this.count=offset/4;
    this.visible=this.count>0||cloudBand>.001||this.atmosphere[0]>.01;
    const tan=Math.tan(fov*.5);
    this.lens.set([tan*aspect,tan*(this.device.isWebGPU?-1:1)]);
    this.planes.set([1/far,far,near,0]);
    this.setUniform('activePressure',this.visible?1:0);
  }
  override createPasses(resources:Parameters<CameraFrameEffect['createPasses']>[0],passes:Parameters<CameraFrameEffect['createPasses']>[1]){
    const depth=resources.depth;
    if(!depth)return;
    const texture=new Texture(this.device,{name:'Aircraft pressure displacement',width:1,height:1,format:PIXELFORMAT_RGBA8,mipmaps:false,addressU:ADDRESS_CLAMP_TO_EDGE,addressV:ADDRESS_CLAMP_TO_EDGE});
    const target=this.field=new RenderTarget({colorBuffer:texture,depth:false});
    const pass=this.pass=new RenderPassShaderQuad(this.device);
    pass.shader=ShaderUtils.createShader(this.device,{
      uniqueName:'FlightPressure:'+depth.key,attributes:{aPosition:SEMANTIC_POSITION},vertexChunk:'quadVS',
      fragmentGLSL:pressureShader(false),fragmentWGSL:pressureShader(true),fragmentDefines:depth.defines
    });
    pass.init(target,{resizeSource:depth.texture,scaleX:.36,scaleY:.36});
    const execute=pass.execute.bind(pass);
    pass.execute=()=>{
      const scope=this.device.scope;
      for(const [name,value] of [
        ['uSceneDepthMap',depth.texture],['camera_params',this.planes],['pressureCenters[0]',this.centers],
        ['pressureGain[0]',this.amplitudes],['pressureCount',this.count],['pressureLens',this.lens],['atmosphere',this.atmosphere],
        ['cloudSample',this.cloudSample],['localCloud',this.cloudTexture]
      ] as const)scope.resolve(name).setValue(value);
      execute();
    };
    passes.postResolve.push(pass);
    this.setUniform('pressureField',texture);
    this.setUniform('activePressure',0);
  }
  override frameUpdate(){
    if(this.pass)this.pass.enabled=this.visible;
  }
  override destroyPasses(){
    this.pass?.destroy();this.pass=undefined;
    this.field?.destroyTextureBuffers();this.field?.destroy();this.field=undefined;
  }
}

export class FlightGraph {
  private readonly frame:CameraFrame;
  private readonly smaa:SmaaEffect|null;
  private readonly exposure:AutoExposureEffect;
  readonly pressure:PressureField;
  readonly ready:Promise<void>;
  constructor(app:AppBase,camera:CameraComponent){
    const device=app.graphicsDevice;
    this.frame=new CameraFrame(app,camera);
    this.frame.rendering.toneMapping=TONEMAP_ACES;
    this.frame.rendering.sharpness=.15;
    this.exposure=new AutoExposureEffect(device);
    this.exposure.minEv=-.62;this.exposure.maxEv=.57;
    this.exposure.compensation=.08;this.exposure.centerWeight=.64;
    this.frame.addEffect(this.exposure);
    this.smaa=!device.isWebGPU&&typeof DecompressionStream==='function'?new SmaaEffect(device):null;
    this.frame.taa.enabled=!this.smaa;
    this.frame.taa.jitter=.67;
    this.frame.taa.upscale=device.isWebGPU;
    this.pressure=new PressureField(device);
    this.pressure.enabled=false;
    this.frame.addEffect(this.pressure);
    this.ready=(this.smaa?this.smaa._lookupReady:Promise.resolve()).then(()=>{
      if(this.smaa){
        this.smaa.maxSearchSteps=12;
        this.frame.addEffect(this.smaa);
      }
      this.frame.update();
    });
    app.once('destroy',()=>{
      this.frame.destroy();this.pressure.destroy();this.smaa?.destroy();this.exposure.destroy();
    });
  }
  setCombat(inCombat:boolean){
    if(this.pressure.enabled===inCombat)return;
    this.pressure.enabled=inCombat;this.frame.rendering.sceneDepthMap=inCombat;
    this.pressure.clear();this.exposure.reset();
    this.frame.update();
  }
  scale(value:number){
    if(this.frame.rendering.renderTargetScale===value)return;
    this.frame.rendering.renderTargetScale=value;
    this.frame.rendering.sharpness=.15+(1-value)*.52;
    this.frame.update();
  }
}
