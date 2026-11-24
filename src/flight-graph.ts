import {
  ADDRESS_CLAMP_TO_EDGE, AutoExposureEffect, CameraFrame, CameraFrameEffect, COMPOSESLOT_SCENE, FRAMERESOURCE_DEPTH,
  PIXELFORMAT_RGBA8, RenderPassShaderQuad, RenderTarget, SEMANTIC_POSITION, ShaderUtils, SmaaEffect,
  Texture, TONEMAP_ACES, type AppBase, type CameraComponent, type GraphicsDevice
} from 'playcanvas';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';

const waveCount=6;
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
    uniform pressureCenters:array<vec4f,${waveCount}>;
    uniform pressureGain:array<vec4f,${waveCount}>;
    uniform pressureCount:i32;
    uniform pressureLens:vec2f;
    @fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{var output:FragmentOutput;`:
    `varying vec2 uv0;
    uniform vec4 pressureCenters[${waveCount}];
    uniform vec4 pressureGain[${waveCount}];
    uniform int pressureCount;
    uniform vec2 pressureLens;
    void main(){`}
  ${declare('ndc',v2,`${uv}*2.-${v2}(1.)`)}
  ${declare('ray',v3,`normalize(${v3}(ndc.x*${u}pressureLens.x,ndc.y*${u}pressureLens.y,1.))`)}
  ${declare('offset',v2,`${v2}(0.)`,true)}
  ${declare('opaque',f,`getLinearScreenDepth(${uv})`)}
  for(${loop};i<${waveCount};i++){
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
      ${declare('turbulence',f,'1.+.23*sin(dot(n.xy,'+v2+'(23.,29.))+gain.y*12.)')}
      offset+=${v2}(n.x,n.y*sign(${u}pressureLens.y))*rim*visible*turbulence*gain.x;
    }
  }
  ${gpu?'output.color':'gl_FragColor'}=${v4}(clamp(offset*.5+${v2}(.5),${v2}(0.),${v2}(1.)),0.,1.);
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
  private readonly centers=new Float32Array(4*waveCount);
  private readonly amplitudes=new Float32Array(4*waveCount);
  private readonly lens=new Float32Array(2);
  private readonly planes=new Float32Array(4);
  private readonly relative=new Vector3();
  constructor(device:GraphicsDevice){
    super(device,'flightPressure',{
      slot:COMPOSESLOT_SCENE,requires:[FRAMERESOURCE_DEPTH],
      glsl:`uniform sampler2D pressureField;
        uniform int activePressure;
        vec4 applyFlightPressure(vec4 color,vec2 uv){
          if(activePressure==0)return color;
          vec2 displacement=(texture2DLod(pressureField,uv,0.).rg-vec2(.5019608))*.052;
          return texture2DLod(sceneTexture,clamp(uv+displacement,vec2(.001),vec2(.999)),0.);
        }`,
      wgsl:`var pressureField:texture_2d<f32>;
        var pressureFieldSampler:sampler;
        uniform activePressure:i32;
        fn applyFlightPressure(color:vec4f,uv:vec2f)->vec4f{
          if(uniform.activePressure==0){return color;}
          let displacement=(textureSampleLevel(pressureField,pressureFieldSampler,uv,0.).rg-vec2f(.5019608))*.052;
          return textureSampleLevel(sceneTexture,sceneTextureSampler,clamp(uv+displacement,vec2f(.001),vec2f(.999)),0.);
        }`
    });
  }
  clear(){for(const layer of this.layers)layer.life=0;this.count=0;}
  pulse(center:Vector3,scale:number,destroyed:boolean){
    const rings=destroyed?3:2;
    for(let n=0;n<rings;n++){
      const wave=this.layers[this.cursor++%waveCount];
      wave.center.copyFrom(center);wave.age=0;wave.delay=n*.087;
      wave.radius=scale*(destroyed?45:30)*(1-n*.16);
      wave.life=(destroyed?1.07:.88)-n*.051;
    }
  }
  collect(dt:number,eye:Vector3,right:Vector3,up:Vector3,forward:Vector3,fov:number,aspect:number,near:number,far:number){
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
    this.count=offset/4;
    const tan=Math.tan(fov*.5);
    this.lens.set([tan*aspect,tan*(this.device.isWebGPU?-1:1)]);
    this.planes.set([1/far,far,near,0]);
    this.setUniform('activePressure',this.count);
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
        ['pressureGain[0]',this.amplitudes],['pressureCount',this.count],['pressureLens',this.lens]
      ] as const)scope.resolve(name).setValue(value);
      execute();
    };
    passes.postResolve.push(pass);
    this.setUniform('pressureField',texture);
    this.setUniform('activePressure',0);
  }
  override frameUpdate(){
    if(this.pass)this.pass.enabled=this.count>0;
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
