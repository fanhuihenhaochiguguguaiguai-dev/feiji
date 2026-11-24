import {
  CameraFrame, CameraFrameEffect, COMPOSESLOT_HDR, FRAMERESOURCE_SCENECOLORHALF,
  RenderPassShaderQuad, RenderTarget, ShaderUtils, SEMANTIC_POSITION,
  SmaaEffect, Texture, TONEMAP_ACES, type AppBase, type CameraComponent, type GraphicsDevice
} from 'playcanvas';

class HighlightPass extends RenderPassShaderQuad {
  constructor(device:GraphicsDevice,readonly source:Texture){
    super(device);
    this.shader=ShaderUtils.createShader(device,{
      uniqueName:'FlightHighlightPass',attributes:{aPosition:SEMANTIC_POSITION},vertexChunk:'quadVS',
      ...(device.isWebGPU?{
        fragmentWGSL:`
          varying uv0: vec2f;
          var highlightsSource: texture_2d<f32>;
          var highlightsSourceSampler: sampler;
          fn hot(uv: vec2f) -> vec3f {
            return max(textureSampleLevel(highlightsSource,highlightsSourceSampler,uv,0.).rgb-vec3f(1.25),vec3f(0.));
          }
          @fragment fn fragmentMain(input: FragmentInput) -> FragmentOutput {
            var output: FragmentOutput;
            let d=vec2f(2.)/vec2f(textureDimensions(highlightsSource,0));
            let uv=input.uv0;
            output.color=vec4f((hot(uv)*2.+hot(uv+d)+hot(uv-d)+hot(uv+vec2f(d.x,-d.y))+hot(uv+vec2f(-d.x,d.y)))/6.,1.);
            return output;
          }`
      }:{
        fragmentGLSL:`
          varying vec2 uv0;
          uniform sampler2D highlightsSource;
          vec3 hot(vec2 uv) {return max(texture2DLod(highlightsSource,uv,0.).rgb-vec3(1.25),vec3(0.));}
          void main() {
            vec2 d=2./vec2(textureSize(highlightsSource,0));
            gl_FragColor=vec4((hot(uv0)*2.+hot(uv0+d)+hot(uv0-d)+hot(uv0+vec2(d.x,-d.y))+hot(uv0+vec2(-d.x,d.y)))/6.,1.);
          }`
      })
    });
  }
  override execute(){
    this.device.scope.resolve('highlightsSource').setValue(this.source);
    super.execute();
  }

}

class FlightHighlights extends CameraFrameEffect {
  private pass?:HighlightPass;
  private target?:RenderTarget;
  constructor(device:GraphicsDevice){
    super(device,'flightHighlights',{
      slot:COMPOSESLOT_HDR,requires:[FRAMERESOURCE_SCENECOLORHALF],
      glsl:`uniform sampler2D flightGlow;
        vec3 applyFlightHighlights(vec3 color,vec2 uv){return color+.21*texture2DLod(flightGlow,uv,0.).rgb;}`,
      wgsl:`var flightGlow:texture_2d<f32>;
        var flightGlowSampler:sampler;
        fn applyFlightHighlights(color:vec3f,uv:vec2f)->vec3f{return color+.21*textureSampleLevel(flightGlow,flightGlowSampler,uv,0.).rgb;}`
    });
  }
  override createPasses(resources:Parameters<CameraFrameEffect['createPasses']>[0],passes:Parameters<CameraFrameEffect['createPasses']>[1]){
    const source=resources.sceneColorHalf;
    if(!source)return;
    const color=new Texture(this.device,{name:'Flight highlights',width:1,height:1,format:source.format,mipmaps:false});
    const target=this.target=new RenderTarget({colorBuffer:color,depth:false});
    const pass=this.pass=new HighlightPass(this.device,source);
    pass.init(target,{resizeSource:source,scaleX:.5,scaleY:.5});
    passes.postResolve.push(pass);
    this.setUniform('flightGlow',color);
  }
  override destroyPasses(){
    this.pass?.destroy();this.pass=undefined;
    this.target?.destroyTextureBuffers();
    this.target?.destroy();this.target=undefined;
  }
}

export async function configureFlightGraph(app:AppBase,camera:CameraComponent){
  const frame=new CameraFrame(app,camera),highlights=new FlightHighlights(app.graphicsDevice);
  frame.rendering.toneMapping=TONEMAP_ACES;
  frame.rendering.sharpness=.18;

  const smaa=!app.graphicsDevice.isWebGPU&&typeof DecompressionStream!=='undefined'?new SmaaEffect(app.graphicsDevice):null;
  frame.taa.enabled=!smaa;
  if(smaa){
    smaa.maxSearchSteps=8;smaa.maxSearchStepsDiag=0;
    await smaa._lookupReady;
    frame.addEffect(smaa);
  }
  frame.addEffect(highlights);
  frame.update();
  app.once('destroy',()=>{frame.destroy();highlights.destroy();smaa?.destroy();});
  return frame;
}
