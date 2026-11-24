import {
  BLEND_NORMAL,BUFFER_STATIC,CULLFACE_NONE,SEMANTIC_POSITION,SEMANTIC_TEXCOORD0,ShaderMaterial,VertexBuffer,VertexFormat
} from 'playcanvas';
import type { Quaternion,Vector3 } from '@babylonjs/core/Maths/math.vector';
import { primitive, type WorldView } from './renderer';

function vertex(gpu:boolean){
  const v2=gpu?'vec2f':'vec2',v3=gpu?'vec3f':'vec3',v4=gpu?'vec4f':'vec4';
  const f=gpu?'f32':'float',u=gpu?'uniform.':'',i=gpu?'f32(input.instanceIndex)':'float(gl_InstanceID)';
  const let_=(k:string,t:string,v:string)=>gpu?`let ${k}:${t}=${v};`:`${t} ${k}=${v};`;
  return `
    ${gpu?`attribute aPosition:vec3f;attribute uv:vec2f;
      varying rainUV:vec2f;varying rainDepth:vec2f;
      uniform matrix_view:mat4x4f;
      uniform matrix_viewProjection:mat4x4f;
      uniform precipitation:vec4f;
      uniform weatherEye:vec3f;
      uniform weatherRight:vec3f;
      uniform weatherUp:vec3f;
      @vertex fn vertexMain(input:VertexInput)->VertexOutput{
        var output:VertexOutput;`:
      `attribute vec3 aPosition;attribute vec2 uv;
      varying vec2 rainUV;varying vec2 rainDepth;
      uniform mat4 matrix_view;
      uniform mat4 matrix_viewProjection;
      uniform vec4 precipitation;
      uniform vec3 weatherEye;
      uniform vec3 weatherRight;
      uniform vec3 weatherUp;
      void main(){`}
    ${let_('index',f,i+'+.5')}
    ${let_('seed',v3,`fract(index*${v3}(.75487766,.56984029,.43839019))`)}
    ${let_('t',f,`${u}precipitation.x`)}
    ${let_('snow',f,`${u}precipitation.y`)}
    ${let_('span',v3,`${v3}(112.,72.,112.)`)}
    ${let_('drift',v3,`${v3}(t*(4.+2.*seed.z),-t*mix(22.,4.1,snow),t*1.73)`)}
    ${let_('origin',v3,`${u}weatherEye+(fract((seed*span+drift-${u}weatherEye)/span+.5)-.5)*span`)}
    ${let_('range',f,`length(origin-${u}weatherEye)`)}
    ${let_('position',v3,`origin+${u}weatherRight*(${gpu?'input.':''}aPosition.x*mix(.085,.28,snow)-${gpu?'input.':''}aPosition.z*.14*(1.-snow))+
      ${u}weatherUp*${gpu?'input.':''}aPosition.z*mix(1.85,.28,snow)`)}
    ${let_('world',v4,`${v4}(position,1.)`)}
    ${gpu?'output.position':'gl_Position'}=${u}matrix_viewProjection*world;
    ${gpu?'output.rainUV=input.uv;':'rainUV=uv;'}
    ${gpu?'output.':''}rainDepth=${v2}(-(${u}matrix_view*world).z,smoothstep(3.,9.,range)*(1.-smoothstep(42.,62.,range)));
    ${gpu?'return output;':''}
  }`;
}

function fragment(gpu:boolean){
  const q=gpu?'input.rainUV':'rainUV',d=gpu?'input.rainDepth':'rainDepth';
  const u=gpu?'uniform.':'',v2=gpu?'vec2f':'vec2',v3=gpu?'vec3f':'vec3',v4=gpu?'vec4f':'vec4';
  const let_=(k:string,t:string,v:string)=>gpu?`let ${k}:${t}=${v};`:`${t} ${k}=${v};`;
  const f=gpu?'f32':'float';
  return `
    #include "screenDepthPS"
    ${gpu?`varying rainUV:vec2f;varying rainDepth:vec2f;
      uniform precipitation:vec4f;
      @fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{var output:FragmentOutput;`:
    `varying vec2 rainUV;varying vec2 rainDepth;uniform vec4 precipitation;void main(){`}
    ${let_('q',v2,`${q}*2.-1.`)}
    ${let_('drop',f,'(1.-smoothstep(.10,1.,abs(q.x)))*(1.-q.y*q.y)')}
    ${let_('flake',f,'1.-smoothstep(.12,1.,dot(q,q))')}
    ${let_('depth',f,gpu?'getLinearScreenDepthFrag()':'getLinearScreenDepth()')}
    ${let_('occlusion',f,`smoothstep(0.,2.7,depth-${d}.x)`)}
    ${let_('strength',f,`mix(drop,flake,${u}precipitation.y)*occlusion*${d}.y*${u}precipitation.z`)}
    ${gpu?'output.color':'gl_FragColor'}=${v4}(${v3}(.68,.80,.95),strength);
    ${gpu?'return output;':''}
  }`;
}

export class WeatherParticles {
  private readonly material=new ShaderMaterial({
    uniqueName:'Weather precipitation',vertexGLSL:vertex(false),vertexWGSL:vertex(true),
    fragmentGLSL:fragment(false),fragmentWGSL:fragment(true),
    attributes:{aPosition:SEMANTIC_POSITION,uv:SEMANTIC_TEXCOORD0}
  });
  private readonly entity;
  private readonly instances;
  private readonly state=new Float32Array(4);
  private readonly eye=new Float32Array(3);
  private readonly horizontal=new Float32Array(3);
  private readonly vertical=new Float32Array(3);
  constructor(world:WorldView){
    const m=this.material;m.depthWrite=false;m.blendType=BLEND_NORMAL;m.cull=CULLFACE_NONE;
    m.setParameter('precipitation',this.state);m.setParameter('weatherEye',this.eye);
    m.setParameter('weatherRight',this.horizontal);m.setParameter('weatherUp',this.vertical);
    this.entity=primitive(world.effects,'近景粒子降水','plane',m,0,0,0,1,1,1);
    const device=world.entry.app.graphicsDevice,capacity=92;
    const buffer=new VertexBuffer(device,VertexFormat.getDefaultInstancingFormat(device),capacity,{usage:BUFFER_STATIC,data:new Float32Array(capacity*16).buffer});
    this.instances=this.entity.render!.meshInstances[0];this.instances.setInstancing(buffer);this.instances.cull=false;
    this.entity.once('destroy',()=>{m.destroy();buffer.destroy();});
    this.entity.enabled=false;
  }
  update(weather:number,level:number,eye:Vector3,cam:Quaternion,time:number){
    const snow=weather===6,storm=weather===4,active=snow||storm||weather===3;
    this.entity.enabled=active;
    if(!active)return;
    this.instances.instancingCount=Math.round((storm?92:snow?72:57)*Math.min(1,level));
    this.state.set([time,snow?1:0,storm?.45:snow?.60:.38,0]);
    this.eye.set([eye.x,eye.y,eye.z]);
    const {x,y,z,w}=cam;
    this.horizontal.set([1-2*(y*y+z*z),2*(x*y+w*z),2*(x*z-w*y)]);
    this.vertical.set([2*(x*y-w*z),1-2*(x*x+z*z),2*(y*z+w*x)]);
  }
}
