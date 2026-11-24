import type { Scene } from '@babylonjs/core/scene';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { ShaderLanguage } from '@babylonjs/core/Materials/shaderLanguage';
import { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Vector2,Vector3,Vector4 } from '@babylonjs/core/Maths/math.vector';
import type { BaseTexture } from '@babylonjs/core/Materials/Textures/baseTexture';
import { environmentSource } from './shading';

export function material(scene:Scene,name:string,hex:string,metal=0,rough=.65){
  const m=new PBRMaterial(name,scene);
  m.albedoColor=Color3.FromHexString(hex);
  m.metallic=metal;m.roughness=rough;
  return m;
}
export class WorldMaterial extends ShaderMaterial {
  private readonly vectors=new Map<string,Vector2|Vector3|Vector4>();
  constructor(scene:Scene,gpu:boolean,ocean:boolean,linear:boolean){
    const source=environmentSource(gpu,ocean,linear);
    super(ocean?'真实海面':'分层大气',scene,{vertexSource:source.vertex,fragmentSource:source.fragment},{
      attributes:['position'],uniforms:source.uniforms,samplers:source.samplers,
      shaderLanguage:gpu?ShaderLanguage.WGSL:ShaderLanguage.GLSL,
    });
    this.backFaceCulling=false;this.disableDepthWrite=!ocean;
  }
  setParameter(name:string,value:number|Float32Array|BaseTexture){
    if(typeof value==='number'){this.setFloat(name,value);return;}
    if(!(value instanceof Float32Array)){this.setTexture(name,value);return;}
    let vector=this.vectors.get(name);
    if(!vector){
      vector=value.length===2?new Vector2():value.length===3?new Vector3():new Vector4();
      this.vectors.set(name,vector);
      if(vector instanceof Vector2)this.setVector2(name,vector);
      else if(vector instanceof Vector3)this.setVector3(name,vector);
      else this.setVector4(name,vector);
    }
    if(vector instanceof Vector2)vector.set(value[0],value[1]);
    else if(vector instanceof Vector3)vector.set(value[0],value[1],value[2]);
    else vector.set(value[0],value[1],value[2],value[3]);
  }
}
