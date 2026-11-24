import { Color3 } from '@babylonjs/core/Maths/math.color';
import type { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { clamp } from './terrain';

const calibrated=new WeakSet<PBRMaterial>();
const coldShadow=Color3.FromHexString('#2d2b29');
export function calibrateAircraft(source:PBRMaterial,maxAnisotropy:number){
  if(calibrated.has(source))return;
  calibrated.add(source);
  for(const texture of [source.albedoTexture,source.bumpTexture,source.metallicTexture])
    if(texture)texture.anisotropicFilteringLevel=Math.min(8,maxAnisotropy);
  const category=source.name.toLowerCase();
  if(/skin|belly|panel/.test(category)){
    if(source.bumpTexture)source.bumpTexture.level=.51;
    source.clearCoat.isEnabled=true;
    source.clearCoat.intensity=category.includes('belly')?.10:.24;
    source.clearCoat.roughness=.24;
    source.environmentIntensity=.91;
  }else if(/glass/.test(category)){
    source.clearCoat.isEnabled=true;source.clearCoat.intensity=.66;
    source.clearCoat.roughness=.09;source.environmentIntensity=.89;
  }else if(/titanium/.test(category)){
    source.metallic=Math.max(.71,source.metallic??0);
    source.roughness=Math.min(.51,source.roughness??.51);
  }else if(/rubber|intake/.test(category))source.environmentIntensity*=.52;
}
export type AirframeFinish={material:PBRMaterial;base:Color3;coat:number;roughness:number};
export function finishAirframe(finish:AirframeFinish,livery:Color3|null,damage:number){
  const {material,base,coat,roughness}=finish;
  if(livery)Color3.LerpToRef(base,livery,.63,material.albedoColor);
  else material.albedoColor.copyFrom(base);
  Color3.LerpToRef(material.albedoColor,coldShadow,clamp(damage*.60,0,.56),material.albedoColor);
  material.clearCoat.intensity=coat*(1-damage*.76);
  material.roughness=roughness+(1-roughness)*damage*.46;
}
