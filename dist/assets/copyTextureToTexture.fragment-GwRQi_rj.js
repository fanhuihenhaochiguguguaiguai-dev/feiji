import{S as r}from"./main-UlZHdn3C.js";import"./helperFunctions-bMF5Xg74.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const e="copyTextureToTexturePixelShader",o=`uniform conversion: f32;
#ifndef NO_SAMPLER
var textureSamplerSampler: sampler;
#endif
var textureSampler: texture_2d<f32>;uniform lodLevel : f32;varying vUV: vec2f;
#include<helperFunctions>
@fragment
fn main(input: FragmentInputs)->FragmentOutputs {
#ifdef NO_SAMPLER
var color: vec4f=textureLoad(textureSampler,vec2u(fragmentInputs.position.xy),u32(uniforms.lodLevel));
#else
var color: vec4f=textureSampleLevel(textureSampler,textureSamplerSampler,input.vUV,uniforms.lodLevel);
#endif
#ifdef DEPTH_TEXTURE
fragmentOutputs.fragDepth=color.r;
#else
if (uniforms.conversion==1.) {color=toLinearSpaceVec4(color);} else if (uniforms.conversion==2.) {color=toGammaSpace(color);}
fragmentOutputs.color=color;
#endif
}
`;r.ShadersStoreWGSL[e]||(r.ShadersStoreWGSL[e]=o);const l={name:e,shader:o};export{l as copyTextureToTexturePixelShaderWGSL};
