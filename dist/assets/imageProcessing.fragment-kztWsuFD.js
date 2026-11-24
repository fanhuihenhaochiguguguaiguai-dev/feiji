import{S as r}from"./main-UlZHdn3C.js";import"./imageProcessingFunctions-DdvbS624.js";import"./helperFunctions-CI1FBg4h.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const e="imageProcessingPixelShader",i=`varying vec2 vUV;uniform sampler2D textureSampler;
#include<imageProcessingDeclaration>
#include<helperFunctions>
#include<imageProcessingFunctions>
#define CUSTOM_FRAGMENT_DEFINITIONS
void main(void)
{vec4 result=texture2D(textureSampler,vUV);result.rgb=max(result.rgb,vec3(0.));
#ifdef IMAGEPROCESSING
#ifndef FROMLINEARSPACE
result.rgb=toLinearSpace(result.rgb);
#endif
result=applyImageProcessing(result);
#else
#ifdef FROMLINEARSPACE
result=applyImageProcessing(result);
#endif
#endif
gl_FragColor=result;}`;r.ShadersStore[e]||(r.ShadersStore[e]=i);const l={name:e,shader:i};export{l as imageProcessingPixelShader};
