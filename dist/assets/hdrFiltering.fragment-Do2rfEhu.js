import{S as i}from"./main-UlZHdn3C.js";import"./helperFunctions-CI1FBg4h.js";import"./hdrFilteringFunctions-BMrSvBos.js";import"./pbrBRDFFunctions-DtA2DiUr.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const r="hdrFilteringPixelShader",e=`#include<helperFunctions>
#include<importanceSampling>
#include<pbrBRDFFunctions>
#include<hdrFilteringFunctions>
uniform float alphaG;uniform samplerCube inputTexture;uniform vec2 vFilteringInfo;uniform float hdrScale;varying vec3 direction;void main() {vec3 color=radiance(alphaG,inputTexture,direction,vFilteringInfo);gl_FragColor=vec4(color*hdrScale,1.0);}`;i.ShadersStore[r]||(i.ShadersStore[r]=e);const d={name:r,shader:e};export{d as hdrFilteringPixelShader};
