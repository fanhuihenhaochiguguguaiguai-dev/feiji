import{S as e}from"./main-CKRGBBe7.js";import"./index-CdXI_nYr.js";import"./flight-math-CTuwkSB0.js";const r="extractHighlightsPixelShader",o=`#include<helperFunctions>
varying vec2 vUV;uniform sampler2D textureSampler;uniform float threshold;uniform float exposure;
#define CUSTOM_FRAGMENT_DEFINITIONS
void main(void) 
{gl_FragColor=texture2D(textureSampler,vUV);float luma=dot(LuminanceEncodeApprox,gl_FragColor.rgb*exposure);gl_FragColor.rgb=step(threshold,luma)*gl_FragColor.rgb;}`;e.ShadersStore[r]||(e.ShadersStore[r]=o);const i={name:r,shader:o};export{i as extractHighlightsPixelShader};
