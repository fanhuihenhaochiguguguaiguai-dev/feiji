import{S as r}from"./main-UlZHdn3C.js";import"./index-CxaK8YSc.js";import"./flight-math-CSIaxMwa.js";const t="oitBackBlendPixelShader",e=`var uBackColor: texture_2d<f32>;@fragment
fn main(input: FragmentInputs)->FragmentOutputs {fragmentOutputs.color=textureLoad(uBackColor,vec2i(fragmentInputs.position.xy),0);if (fragmentOutputs.color.a==0.0) {discard;}}
`;r.ShadersStoreWGSL[t]||(r.ShadersStoreWGSL[t]=e);const i={name:t,shader:e};export{i as oitBackBlendPixelShaderWGSL};
