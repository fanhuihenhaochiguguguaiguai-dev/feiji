import type { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { MaterialPluginBase } from '@babylonjs/core/Materials/materialPluginBase';
import { ShaderLanguage } from '@babylonjs/core/Materials/shaderLanguage';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import type { UniformBuffer } from '@babylonjs/core/Materials/uniformBuffer';

export class RockSurface extends MaterialPluginBase {
  grain:Texture|null=null;
  view=0;
  constructor(material:PBRMaterial){super(material,'RockSurface',110,undefined,true,true);}
  override isCompatible(){return true;}
  override getSamplers(samplers:string[]){samplers.push('rockGrain');}
  override getUniforms(){return {ubo:[{name:'rockView',size:1,type:'float'},{name:'rockRoughness',size:1,type:'float'}],
    fragment:'uniform float rockView; uniform float rockRoughness;'};}
  override bindForSubMesh(ubo:UniformBuffer){
    if(this.grain)ubo.setTexture('rockGrain',this.grain);
    ubo.updateFloat('rockView',this.view);ubo.updateFloat('rockRoughness',.91);
  }
  override getCustomCode(stage:string,language=ShaderLanguage.GLSL){
    if(stage!=='fragment')return null;
    const gpu=language===ShaderLanguage.WGSL,v=gpu?'vec3f':'vec3',d=gpu?'let':'vec3';
    const tex=(uv:string)=>gpu?`textureSample(rockGrain,rockGrainSampler,${uv}).rgb`:`texture2D(rockGrain,${uv}).rgb`;
    const world=gpu?'fragmentInputs.vPositionW':'vPositionW',uniform=gpu?'uniforms.':'';
    return {
      CUSTOM_FRAGMENT_DEFINITIONS:gpu?'var rockGrain:texture_2d<f32>; var rockGrainSampler:sampler;':'uniform sampler2D rockGrain;',
      CUSTOM_FRAGMENT_BEFORE_LIGHTS:`
        ${d} point=${world}*.0115;
        ${d} weights=pow(abs(normalize(normalW)),${v}(4.));
        ${d} grain=(${tex('point.zy+point.xx*.072')}*weights.x+${tex('point.xz+point.zz*.031')}*weights.y+${tex('point.xy+point.zz*.071')}*weights.z)/max(.001,weights.x+weights.y+weights.z);
        ${gpu?'let':'float'} footprint=length(${gpu?'abs(dpdx(point))+abs(dpdy(point))':'fwidth(point)'});
        surfaceAlbedo*=mix(grain,${v}(.76),smoothstep(.08,.72,footprint));
        if(${uniform}rockView>1.5&&${uniform}rockView<2.5){surfaceAlbedo=normalW*.5+${v}(.5);}
        if(${uniform}rockView>=2.5){surfaceAlbedo=${v}(${uniform}rockRoughness);}
      `,
    };
  }
}
