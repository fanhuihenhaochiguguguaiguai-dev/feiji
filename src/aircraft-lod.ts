import { SHADERLANGUAGE_GLSL, SHADERLANGUAGE_WGSL, type StandardMaterial } from 'playcanvas';

type Level=0|1|2;

export function screenLod(apparentPixels:number,physicalPixels:number,current:Level):Level{
  if(physicalPixels>(current===0?34:42)&&apparentPixels>52)return 0;
  const silhouette=apparentPixels>(current===1?28:34);
  return silhouette||physicalPixels>(current===1?8:11)&&apparentPixels>24?1:2;
}

export class AircraftLod {
  current:Level=0;
  incoming:Level=0;
  progress=1;

  update(desired:Level,seconds:number,reset:boolean){
    if(reset){this.current=this.incoming=desired;this.progress=1;return;}
    if(this.progress===1&&desired!==this.current){this.incoming=desired;this.progress=0;}
    if(this.progress===1)return;
    if(desired===this.current){
      [this.current,this.incoming]=[this.incoming,this.current];
      this.progress=1-this.progress;
    }
    this.progress=Math.min(1,this.progress+Math.max(0,seconds)/.22);
    if(this.progress===1)this.current=this.incoming;
  }
}

// The same ordered screen mask is complemented on the two meshes. Its phase is
// stable between frames and the visible fragments continue to write normal depth.
export function configureLodMaterial(material:StandardMaterial){
  material.alphaTest=Math.max(.002,material.alphaTest);
  material.setParameter('lodCut',0);
  material.setParameter('lodIn',0);
  material.getShaderChunks(SHADERLANGUAGE_GLSL).set('alphaTestPS',`
    uniform float alpha_ref,lodCut,lodIn;
    void alphaTest(float alpha) {
      if(alpha<alpha_ref)discard;
      if(lodCut<=0.&&lodIn<.5)return;
      vec2 pixel=floor(gl_FragCoord.xy);
      float rank=fract(52.9829189*fract(dot(pixel,vec2(.06711056,.00583715))));
      if(lodIn>.5?rank>=lodCut:rank<lodCut)discard;
    }`);
  material.getShaderChunks(SHADERLANGUAGE_WGSL).set('alphaTestPS',`
    uniform alpha_ref:f32;
    uniform lodCut:f32;
    uniform lodIn:f32;
    fn alphaTest(alpha:f32) {
      if(alpha<uniform.alpha_ref){discard;}
      if(uniform.lodCut<=0.&&uniform.lodIn<.5){return;}
      let pixel=floor(pcPosition.xy);
      let rank=fract(52.9829189*fract(dot(pixel,vec2f(.06711056,.00583715))));
      let below=rank < uniform.lodCut;
      if(select(below,!below,uniform.lodIn > .5)){discard;}
    }`);
  material.update();
}
