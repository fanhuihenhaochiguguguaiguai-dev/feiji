import {
  BLEND_ADDITIVEALPHA, BLEND_NORMAL, CULLFACE_NONE, SEMANTIC_ATTR11, SEMANTIC_ATTR12,
  SEMANTIC_ATTR14, SEMANTIC_ATTR15, SEMANTIC_POSITION, SEMANTIC_TEXCOORD0, ShaderMaterial
} from 'playcanvas';

const vertexGLSL=`
  attribute vec3 position;
  attribute vec2 texCoord;
  attribute vec4 partA,partB,partC,partD;
  uniform mat4 matrix_viewProjection;
  uniform mat4 matrix_view;
  varying vec2 vUv;
  varying vec2 vParticle;
  void main(){
    vec4 world=mat4(vec4(partA.xyz,0.),partB,partC,partD)*vec4(position,1.);
    gl_Position=matrix_viewProjection*world;
    vUv=texCoord;
    vParticle=vec2(-(matrix_view*world).z,partA.w);
  }`;
const vertexWGSL=`
  attribute position:vec3f;
  attribute texCoord:vec2f;
  attribute partA:vec4f;
  attribute partB:vec4f;
  attribute partC:vec4f;
  attribute partD:vec4f;
  uniform matrix_viewProjection:mat4x4f;
  uniform matrix_view:mat4x4f;
  varying vUv:vec2f;
  varying vParticle:vec2f;
  @vertex fn vertexMain(input:VertexInput)->VertexOutput{
    var output:VertexOutput;
    let world=mat4x4f(vec4f(input.partA.xyz,0.),input.partB,input.partC,input.partD)*vec4f(input.position,1.);
    output.position=uniform.matrix_viewProjection*world;
    output.vUv=input.texCoord;
    output.vParticle=vec2f(-(uniform.matrix_view*world).z,input.partA.w);
    return output;
  }`;
const fragmentGLSL=`
  #define SCENE_DEPTHMAP_LINEAR
  #define SCENE_DEPTHMAP_RECIPROCAL
  #include "screenDepthPS"
  uniform sampler2D spriteAtlas;
  uniform vec4 spriteTint;
  uniform float spriteFrames;
  varying vec2 vUv;
  varying vec2 vParticle;
  vec2 frameUv(float frame){return vec2((vUv.x*.94+.03+frame)/spriteFrames,vUv.y*.94+.03);}
  void main(){
    float phase=clamp(vParticle.y,0.,1.);
    float frame=phase*(spriteFrames-1.);
    float index=floor(frame);
    vec4 texel=mix(texture2D(spriteAtlas,frameUv(index)),texture2D(spriteAtlas,frameUv(min(index+1.,spriteFrames-1.))),fract(frame));
    float soften=smoothstep(0.,max(.5,vParticle.x*.009),getLinearScreenDepth()-vParticle.x);
    float opacity=texel.a*soften*(1.-smoothstep(.55,1.,phase))*spriteTint.a;
    gl_FragColor=vec4(pow(texel.rgb,vec3(2.2))*spriteTint.rgb,opacity);
  }`;
const fragmentWGSL=`
  #define SCENE_DEPTHMAP_LINEAR
  #define SCENE_DEPTHMAP_RECIPROCAL
  #include "screenDepthPS"
  var spriteAtlas:texture_2d<f32>;
  var spriteAtlasSampler:sampler;
  uniform spriteTint:vec4f;
  uniform spriteFrames:f32;
  varying vUv:vec2f;
  varying vParticle:vec2f;
  fn frameUv(uv:vec2f,frame:f32)->vec2f{return vec2f((uv.x*.94+.03+frame)/uniform.spriteFrames,uv.y*.94+.03);}
  @fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{
    var output:FragmentOutput;
    let phase=clamp(input.vParticle.y,0.,1.);
    let frame=phase*(uniform.spriteFrames-1.);
    let index=floor(frame);
    let texel=mix(textureSample(spriteAtlas,spriteAtlasSampler,frameUv(input.vUv,index)),textureSample(spriteAtlas,spriteAtlasSampler,frameUv(input.vUv,min(index+1.,uniform.spriteFrames-1.))),fract(frame));
    let soften=smoothstep(0.,max(.5,input.vParticle.x*.009),getLinearScreenDepthFrag()-input.vParticle.x);
    let opacity=texel.a*soften*(1.-smoothstep(.55,1.,phase))*uniform.spriteTint.a;
    output.color=vec4f(pow(texel.rgb,vec3f(2.2))*uniform.spriteTint.rgb,opacity);
    return output;
  }`;

export function softSprite(name:string,tint:readonly number[],frames:number,emissive=false){
  const material=new ShaderMaterial({
    uniqueName:'soft-sprite',vertexGLSL,vertexWGSL,fragmentGLSL,fragmentWGSL,
    attributes:{position:SEMANTIC_POSITION,texCoord:SEMANTIC_TEXCOORD0,
      partA:SEMANTIC_ATTR11,partB:SEMANTIC_ATTR12,partC:SEMANTIC_ATTR14,partD:SEMANTIC_ATTR15}
  });
  material.name=name;
  material.cull=CULLFACE_NONE;
  material.depthWrite=false;
  material.blendType=emissive?BLEND_ADDITIVEALPHA:BLEND_NORMAL;
  material.setParameter('spriteTint',new Float32Array(tint));
  material.setParameter('spriteFrames',frames);
  return material;
}
