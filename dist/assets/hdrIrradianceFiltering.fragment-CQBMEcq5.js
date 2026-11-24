import{S as r}from"./main-UlZHdn3C.js";import"./helperFunctions-bMF5Xg74.js";import"./hdrFilteringFunctions-mbYwVDRX.js";import"./pbrBRDFFunctions-C09JV-IM.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const e="hdrIrradianceFilteringPixelShader",i=`#include<helperFunctions>
#include<importanceSampling>
#include<pbrBRDFFunctions>
#include<hdrFilteringFunctions>
var inputTextureSampler: sampler;var inputTexture: texture_cube<f32>;
#ifdef IBL_CDF_FILTERING
var icdfTextureSampler: sampler;var icdfTexture: texture_2d<f32>;
#endif
uniform vFilteringInfo: vec2f;uniform hdrScale: f32;varying direction: vec3f;@fragment
fn main(input: FragmentInputs)->FragmentOutputs {var color: vec3f=irradiance(inputTexture,inputTextureSampler,input.direction,uniforms.vFilteringInfo,0.0,vec3f(1.0),input.direction
#ifdef IBL_CDF_FILTERING
,icdfTexture,icdfTextureSampler
#endif
);fragmentOutputs.color= vec4f(color*uniforms.hdrScale,1.0);}`;r.ShadersStoreWGSL[e]||(r.ShadersStoreWGSL[e]=i);const d={name:e,shader:i};export{d as hdrIrradianceFilteringPixelShaderWGSL};
