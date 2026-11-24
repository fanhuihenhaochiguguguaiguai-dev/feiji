import{S as r}from"./main-CKRGBBe7.js";import"./imageProcessingFunctions-I7R7GmNv.js";import"./helperFunctions-Du0G8JsN.js";import"./index-CdXI_nYr.js";import"./flight-math-CTuwkSB0.js";const e="imageProcessingPixelShader",t=`varying vUV: vec2f;var textureSamplerSampler: sampler;var textureSampler: texture_2d<f32>;
#include<imageProcessingDeclaration>
#include<helperFunctions>
#include<imageProcessingFunctions>
#define CUSTOM_FRAGMENT_DEFINITIONS
@fragment
fn main(input: FragmentInputs)->FragmentOutputs {var result: vec4f=textureSample(textureSampler,textureSamplerSampler,input.vUV);result=vec4f(max(result.rgb,vec3f(0.)),result.a);
#ifdef IMAGEPROCESSING
#ifndef FROMLINEARSPACE
result=vec4f(toLinearSpaceVec3(result.rgb),result.a);
#endif
result=applyImageProcessing(result);
#else
#ifdef FROMLINEARSPACE
result=applyImageProcessing(result);
#endif
#endif
fragmentOutputs.color=result;}`;r.ShadersStoreWGSL[e]||(r.ShadersStoreWGSL[e]=t);const u={name:e,shader:t};export{u as imageProcessingPixelShaderWGSL};
