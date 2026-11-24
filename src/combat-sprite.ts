import {
  BLEND_ADDITIVEALPHA, BLEND_NORMAL, CULLFACE_NONE, SEMANTIC_ATTR11, SEMANTIC_ATTR12,
  SEMANTIC_ATTR14, SEMANTIC_ATTR15, SEMANTIC_POSITION, SEMANTIC_TEXCOORD0, ShaderMaterial
} from 'playcanvas';

function vertex(gpu:boolean){
  if(gpu)return `
    attribute position:vec3f;
    attribute uv:vec2f;
    attribute basisX:vec4f;
    attribute basisY:vec4f;
    attribute basisZ:vec4f;
    attribute translation:vec4f;
    uniform matrix_view:mat4x4f;
    uniform matrix_viewProjection:mat4x4f;
    varying spriteUv:vec2f;
    varying spriteData:vec2f;
    @vertex fn vertexMain(input:VertexInput)->VertexOutput{
      var result:VertexOutput;
      let world=mat4x4f(vec4f(input.basisX.xyz,0.),input.basisY,input.basisZ,input.translation)*vec4f(input.position,1.);
      result.position=uniform.matrix_viewProjection*world;
      result.spriteUv=input.uv;
      result.spriteData=vec2f(-(uniform.matrix_view*world).z,input.basisX.w);
      return result;
    }`;
  return `
    attribute vec3 position;
    attribute vec2 uv;
    attribute vec4 basisX,basisY,basisZ,translation;
    uniform mat4 matrix_view,matrix_viewProjection;
    varying vec2 spriteUv,spriteData;
    void main(){
      vec4 world=mat4(vec4(basisX.xyz,0.),basisY,basisZ,translation)*vec4(position,1.);
      gl_Position=matrix_viewProjection*world;
      spriteUv=uv;
      spriteData=vec2(-(matrix_view*world).z,basisX.w);
    }`;
}
function shading(gpu:boolean){
  const p=gpu?'uniform.':'';
  const uv=gpu?'input.spriteUv':'spriteUv',data=gpu?'input.spriteData':'spriteData';
  const v2=gpu?'vec2f':'vec2',v3=gpu?'vec3f':'vec3',v4=gpu?'vec4f':'vec4';
  const f=gpu?'f32':'float';
  const let_=(name:string,type:string,value:string)=>gpu?'let '+name+':'+type+'='+value+';':type+' '+name+'='+value+';';
  const sample=(frame:string)=>gpu?`textureSample(spriteFrames,spriteFramesSampler,frameUv(${uv},${frame}))`:
    `texture2D(spriteFrames,frameUv(${uv},${frame}))`;
  return `
    #define SCENE_DEPTHMAP_LINEAR
    #define SCENE_DEPTHMAP_RECIPROCAL
    #include "screenDepthPS"
    ${gpu?`var spriteFrames:texture_2d<f32>;
      var spriteFramesSampler:sampler;
      uniform spriteCount:f32;
      uniform spriteTint:vec4f;
      varying spriteUv:vec2f;
      varying spriteData:vec2f;
      fn frameUv(uv:vec2f,i:f32)->vec2f{return vec2f((uv.x*.94+.03+i)/uniform.spriteCount,uv.y*.94+.03);}
      @fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{
      var output:FragmentOutput;`:
      `uniform sampler2D spriteFrames;
      uniform float spriteCount;
      uniform vec4 spriteTint;
      varying vec2 spriteUv,spriteData;
      vec2 frameUv(vec2 uv,float i){return vec2((uv.x*.94+.03+i)/spriteCount,uv.y*.94+.03);}
      void main(){`}
    ${let_('age',f,`clamp(${data}.y,0.,1.)`)}
    ${let_('frame',f,`age*(${p}spriteCount-1.)`)}
    ${let_('first',f,'floor(frame)')}
    ${let_('texel',v4,`mix(${sample('first')},${sample(`min(first+1.,${p}spriteCount-1.)`)},fract(frame))`)}
    ${let_('depth',f,gpu?'getLinearScreenDepthFrag()':'getLinearScreenDepth()')}
    ${let_('soft',f,`smoothstep(0.,max(.65,${data}.x*.008),depth-${data}.x)`)}
    ${let_('alpha',f,`texel.a*soft*(1.-smoothstep(.58,1.,age))*${p}spriteTint.a`)}
    ${gpu?'output.color':'gl_FragColor'}=${v4}(pow(texel.rgb,${v3}(2.2))*${p}spriteTint.rgb,alpha);
    ${gpu?'return output;':''}
    }`;
}

export function combatSprite(name:string,tint:number[],frames:number,emissive=false){
  const material=new ShaderMaterial({
    uniqueName:'FormationVFXSprite',vertexGLSL:vertex(false),vertexWGSL:vertex(true),
    fragmentGLSL:shading(false),fragmentWGSL:shading(true),
    attributes:{position:SEMANTIC_POSITION,uv:SEMANTIC_TEXCOORD0,basisX:SEMANTIC_ATTR11,basisY:SEMANTIC_ATTR12,
      basisZ:SEMANTIC_ATTR14,translation:SEMANTIC_ATTR15}
  });
  material.name=name;material.depthWrite=false;material.cull=CULLFACE_NONE;
  material.blendType=emissive?BLEND_ADDITIVEALPHA:BLEND_NORMAL;
  material.setParameter('spriteCount',frames);
  material.setParameter('spriteTint',new Float32Array(tint));
  return material;
}
