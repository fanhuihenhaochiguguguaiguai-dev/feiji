import { Color,StandardMaterial } from 'playcanvas';
import { clamp } from './terrain';

const calibrated=new WeakSet<StandardMaterial>();
const coldShadow=new Color().fromString('#2d2b29');
export function calibrateAircraft(source:StandardMaterial,maxAnisotropy:number){
  if(calibrated.has(source))return;
  calibrated.add(source);
  for(const texture of [source.diffuseMap,source.normalMap,source.metalnessMap,source.glossMap])
    if(texture)texture.anisotropy=Math.min(12,maxAnisotropy);
  const category=source.name.toLowerCase();
  if(/skin|belly|panel/.test(category)){
    source.bumpiness=source.normalMap?.51:source.bumpiness;
    source.clearCoat=category.includes('belly')?.10:.24;
    source.clearCoatGloss=.76;
    source.reflectivity=.91;
  }else if(/glass/.test(category)){
    source.clearCoat=.66;
    source.clearCoatGloss=.91;
    source.useMetalness=true;
    source.reflectivity=.89;
  }else if(/titanium/.test(category)){
    source.metalness=Math.max(.71,source.metalness);
    source.gloss=Math.max(.49,source.gloss);
  }else if(/rubber|intake/.test(category)){
    source.reflectivity*=.52;
  }
  source.update();
}
export type AirframeFinish={material:StandardMaterial;base:Color;coat:number;gloss:number};
export function finishAirframe(finish:AirframeFinish,livery:Color|null,damage:number){
  const {material,base,coat,gloss}=finish;
  if(livery)material.diffuse.lerp(base,livery,.63);
  else material.diffuse.copy(base);
  material.diffuse.lerp(material.diffuse,coldShadow,clamp(damage*.60,0,.56));
  material.clearCoat=coat*(1-damage*.76);
  material.gloss=gloss*(1-damage*.46);
  material.update();
}
