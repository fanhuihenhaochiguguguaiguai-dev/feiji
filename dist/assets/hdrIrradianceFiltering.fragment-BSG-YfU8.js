import{S as e}from"./main-UlZHdn3C.js";import"./helperFunctions-CI1FBg4h.js";import"./hdrFilteringFunctions-BMrSvBos.js";import"./pbrBRDFFunctions-DtA2DiUr.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const r="hdrIrradianceFilteringPixelShader",i=`#include<helperFunctions>
#include<importanceSampling>
#include<pbrBRDFFunctions>
#include<hdrFilteringFunctions>
uniform samplerCube inputTexture;
#ifdef IBL_CDF_FILTERING
uniform sampler2D icdfTexture;
#endif
uniform vec2 vFilteringInfo;uniform float hdrScale;varying vec3 direction;void main() {vec3 color=irradiance(inputTexture,direction,vFilteringInfo,0.0,vec3(1.0),direction
#ifdef IBL_CDF_FILTERING
,icdfTexture
#endif
);gl_FragColor=vec4(color*hdrScale,1.0);}`;e.ShadersStore[r]||(e.ShadersStore[r]=i);const l={name:r,shader:i};export{l as hdrIrradianceFilteringPixelShader};
