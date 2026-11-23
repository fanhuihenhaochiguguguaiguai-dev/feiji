import { SHADERLANGUAGE_GLSL,SHADERLANGUAGE_WGSL,type StandardMaterial } from 'playcanvas';

function triplanar(gpu:boolean){
  const v3=gpu?'vec3f':'vec3',f=gpu?'f32':'float';
  const declare=(name:string,type:string,value:string)=>gpu?'let '+name+':'+type+'='+value+';':type+' '+name+'='+value+';';
  const sample=(uv:string)=>`{STD_DIFFUSE_TEXTURE_DECODE}(${gpu
    ?'textureSampleBias({STD_DIFFUSE_TEXTURE_NAME},{STD_DIFFUSE_TEXTURE_NAME}Sampler,'+uv+',{STD_TEXTURE_BIAS})'
    :'texture2DBias({STD_DIFFUSE_TEXTURE_NAME},'+uv+',{STD_TEXTURE_BIAS})'}).{STD_DIFFUSE_TEXTURE_CHANNEL}`;
  return `
${gpu?'uniform material_diffuse:vec3f;\nuniform terrainView:f32;uniform terrainRoughness:f32;':'uniform vec3 material_diffuse;\nuniform float terrainView;uniform float terrainRoughness;'}
${gpu?'fn':'void'} getAlbedo(){
  dAlbedo=${gpu?'uniform.':''}material_diffuse.rgb;
  #ifdef STD_DIFFUSE_TEXTURE
    ${declare('normal',v3,'normalize(vNormalW)')}
    ${declare('weights',v3,`pow(abs(normal),${v3}(4.))`)}
    ${declare('point',v3,'vPositionW*.0115')}
    ${declare('mottle',f,'sin(point.x*.17+point.z*.23)*sin(point.z*.12-point.x*.09)')}
    ${declare('x',v3,sample('point.zy+point.xx*.072'))}
    ${declare('y',v3,sample('point.xz+point.zz*.031'))}
    ${declare('z',v3,sample('point.xy+point.zz*.071'))}
    ${declare('coarse',v3,'(x*weights.x+y*weights.y+z*weights.z)/max(.001,weights.x+weights.y+weights.z)')}
    ${declare('footprint',f,`length(${gpu?'abs(dpdx(vPositionW))+abs(dpdy(vPositionW))':'fwidth(vPositionW)'})`)}
    dAlbedo=dAlbedo*mix(coarse,${v3}(.76),smoothstep(7.,66.,footprint))*(1.+mottle*.086);
  #endif
  #ifdef STD_DIFFUSE_VERTEX
    ${declare('surfaceColor',v3,'saturate(vVertexColor.{STD_DIFFUSE_VERTEX_CHANNEL})')}
    ${declare('foliage',f,'smoothstep(.055,.125,surfaceColor.g-surfaceColor.r)*smoothstep(.42,.91,normalize(vNormalW).y)')}
    dAlbedo=dAlbedo*surfaceColor*mix(${v3}(1.),${v3}(1.22,1.43,.92),foliage);
  #endif
  ${declare('inspection',f,(gpu?'uniform.':'')+'terrainView')}
  if(inspection>1.5&&inspection<2.5){dAlbedo=normalize(vNormalW)*.5+${v3}(.5);}
  if(inspection>=2.5){dAlbedo=${v3}(${gpu?'uniform.':''}terrainRoughness);}
}
`;
}
export function bindRockSurface(material:StandardMaterial){
  material.getShaderChunks(SHADERLANGUAGE_GLSL).set('diffusePS',triplanar(false));
  material.getShaderChunks(SHADERLANGUAGE_WGSL).set('diffusePS',triplanar(true));
  material.setParameter('terrainView',0);
  material.setParameter('terrainRoughness',1-material.gloss);
}
