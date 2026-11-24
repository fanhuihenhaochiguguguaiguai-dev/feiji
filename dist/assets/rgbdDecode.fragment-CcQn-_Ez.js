import{S as r}from"./main-UlZHdn3C.js";import"./helperFunctions-CI1FBg4h.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const e="rgbdDecodePixelShader",o=`varying vec2 vUV;uniform sampler2D textureSampler;
#include<helperFunctions>
#define CUSTOM_FRAGMENT_DEFINITIONS
void main(void) 
{gl_FragColor=vec4(fromRGBD(texture2D(textureSampler,vUV)),1.0);}`;r.ShadersStore[e]||(r.ShadersStore[e]=o);const S={name:e,shader:o};export{S as rgbdDecodePixelShader};
