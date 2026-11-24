import{S as r}from"./main-CKRGBBe7.js";import"./helperFunctions-Du0G8JsN.js";import"./hdrFilteringFunctions-By2f8ClC.js";import"./pbrBRDFFunctions-BzER9Duu.js";import"./index-CdXI_nYr.js";import"./flight-math-CTuwkSB0.js";const e="hdrIrradianceFilteringPixelShader",i=`#include<helperFunctions>
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
