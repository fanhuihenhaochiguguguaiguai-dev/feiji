import{S as e}from"./index-D4Ofd1-t.js";import"./hdrFilteringFunctions-C1xKd1kQ.js";import"./pbrBRDFFunctions-D2s46BLJ.js";import"./flight-math-CTuwkSB0.js";const r="hdrFilteringPixelShader",i=`#include<helperFunctions>
#include<importanceSampling>
#include<pbrBRDFFunctions>
#include<hdrFilteringFunctions>
uniform float alphaG;uniform samplerCube inputTexture;uniform vec2 vFilteringInfo;uniform float hdrScale;varying vec3 direction;void main() {vec3 color=radiance(alphaG,inputTexture,direction,vFilteringInfo);gl_FragColor=vec4(color*hdrScale,1.0);}`;e.ShadersStore[r]||(e.ShadersStore[r]=i);const l={name:r,shader:i};export{l as hdrFilteringPixelShader};
