import{S as e}from"./main-CKRGBBe7.js";import"./index-CdXI_nYr.js";import"./flight-math-CTuwkSB0.js";const r="bloomMergePixelShader",t=`varying vUV: vec2f;var textureSamplerSampler: sampler;var textureSampler: texture_2d<f32>;var bloomBlurSampler: sampler;var bloomBlur: texture_2d<f32>;uniform bloomWeight: f32;
#define CUSTOM_FRAGMENT_DEFINITIONS
@fragment
fn main(input: FragmentInputs)->FragmentOutputs {fragmentOutputs.color=textureSample(textureSampler,textureSamplerSampler,input.vUV);var blurred: vec3f=textureSample(bloomBlur,bloomBlurSampler,input.vUV).rgb;fragmentOutputs.color=vec4f(fragmentOutputs.color.rgb+(blurred.rgb*uniforms.bloomWeight),fragmentOutputs.color.a);}
`;e.ShadersStoreWGSL[r]||(e.ShadersStoreWGSL[r]=t);const l={name:r,shader:t};export{l as bloomMergePixelShaderWGSL};
