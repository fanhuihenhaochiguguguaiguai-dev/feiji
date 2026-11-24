import { heightPerByte, oceanSize, type OceanSpectrum } from './ocean-solver';

declare const GPUBufferUsage:{STORAGE:number;COPY_SRC:number;COPY_DST:number;MAP_READ:number;UNIFORM:number};
declare const GPUMapMode:{READ:number};

const cells=oceanSize**2,words=cells*4,reverseShift=32-Math.log2(oceanSize);
const wgsl=`
const Width=${oceanSize}u;
@group(0) @binding(0) var<storage,read> spectrum:array<vec4f>;
@group(0) @binding(1) var<storage,read_write> rowResult:array<vec2f>;
@group(0) @binding(2) var<storage,read_write> height:array<f32>;
@group(0) @binding(3) var<storage,read_write> output:array<u32>;
@group(0) @binding(4) var<uniform> clock:f32;
var<workgroup> ping:array<vec2f,${oceanSize}>;
var<workgroup> pong:array<vec2f,${oceanSize}>;
fn fft(k:u32,value:vec2f)->vec2f {
  ping[k]=value;
  workgroupBarrier();
  for(var batch=2u;batch<=Width;batch*=2u){
    let split=batch/2u;
    let local=k%batch;
    let phase=local%split;
    let a=k-local+phase;
    let v=ping[a+split];
    let angle=6.28318530718*f32(phase)/f32(batch);
    let i=sin(angle);
    let r=cos(angle);
    let product=vec2f(v.x*r-v.y*i,v.y*r+v.x*i);
    pong[k]=ping[a]+select(-product,product,local<split);
    workgroupBarrier();
    ping[k]=pong[k];
    workgroupBarrier();
  }
  return ping[k];
}
@compute @workgroup_size(${oceanSize})
fn horizontal(@builtin(local_invocation_index) k:u32,@builtin(workgroup_id) group:vec3u){
  let base=group.x*Width;
  let data=spectrum[base+(reverseBits(k)>>${reverseShift}u)];
  let theta=data.x-clock*data.y;
  rowResult[base+k]=fft(k,data.z*vec2f(cos(theta),sin(theta)*data.w));
}
@compute @workgroup_size(${oceanSize})
fn vertical(@builtin(local_invocation_index) k:u32,@builtin(workgroup_id) group:vec3u){
  let x=group.x;
  let a=fft(k,rowResult[(reverseBits(k)>>${reverseShift}u)*Width+x]);
  height[k*Width+x]=a.x;
}
fn byte(val:f32)->u32{return u32(clamp(floor(val/${heightPerByte}+128.5),0.,255.));}
@compute @workgroup_size(${oceanSize})
fn prepareTexture(@builtin(local_invocation_index) x:u32,@builtin(workgroup_id) group:vec3u){
  let y=group.x;
  let row=y*Width;
  let z=height[row+x];
  let dx=height[row+(x+1u)%Width]-height[row+(x+Width-1u)%Width];
  let dy=height[((y+1u)%Width)*Width+x]-height[((y+Width-1u)%Width)*Width+x];
  let foam=u32(clamp((z-.25)*160.,0.,150.));
  output[row+x]=byte(z)|(foam<<8u)|(byte(dx*.7)<<16u)|(byte(dy*.7)<<24u);
}`;

export class OceanCompute {
  private readonly queue:GPUQueue;
  private readonly resources:GPUBuffer[]=[];
  private readonly stages:{pipeline:GPUComputePipeline;group:GPUBindGroup}[]=[];
  private readonly clock:GPUBuffer;
  private readonly texture:GPUBuffer;
  private readonly staging:GPUBuffer;
  private constructor(readonly device:GPUDevice,input:Float32Array){
    this.queue=device.queue;
    const buffer=(size:number,usage:number)=>{
      const object=device.createBuffer({size,usage,mappedAtCreation:false});
      this.resources.push(object);return object;
    };
    const coefficients=buffer(cells*16,GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST);
    const rows=buffer(cells*8,GPUBufferUsage.STORAGE),height=buffer(words,GPUBufferUsage.STORAGE);
    this.texture=buffer(words,GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_SRC);
    this.clock=buffer(4,GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST);
    this.staging=buffer(words,GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST);
    this.queue.writeBuffer(coefficients,0,input as Float32Array<ArrayBuffer>);
    const module=device.createShaderModule({label:'Ocean spectral solver',code:wgsl});
    for(const [entryPoint,buffers] of [
      ['horizontal',[[0,coefficients],[1,rows],[4,this.clock]]],
      ['vertical',[[1,rows],[2,height]]],['prepareTexture',[[2,height],[3,this.texture]]]
    ] as const){
      const pipeline=device.createComputePipeline({layout:'auto',compute:{module,entryPoint}});
      const entries=buffers.map(([binding,buffer])=>({binding,resource:{buffer}}));
      this.stages.push({pipeline,group:device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries})});
    }
  }
  async sample(time:number,target:Uint8Array){
    this.queue.writeBuffer(this.clock,0,new Float32Array([time]));
    const commands=this.device.createCommandEncoder();
    for(const {pipeline,group} of this.stages){
      const pass=commands.beginComputePass();
      pass.setPipeline(pipeline);pass.setBindGroup(0,group);
      pass.dispatchWorkgroups(oceanSize,1,1);pass.end();
    }
    commands.copyBufferToBuffer(this.texture,0,this.staging,0,words);
    this.queue.submit([commands.finish()]);
    await this.staging.mapAsync(GPUMapMode.READ);
    target.set(new Uint8Array(this.staging.getMappedRange()));
    this.staging.unmap();
  }
  dispose(){this.resources.forEach(buffer=>buffer.destroy());this.device.destroy();}

  static async qualified(reference:OceanSpectrum,adapter:GPUAdapter|null){
    if(!adapter)return null;
    const device=await adapter.requestDevice();
    let solver:OceanCompute|undefined;
    try{
      device.pushErrorScope('validation');
      solver=new OceanCompute(device,reference.coefficients());
      if(await device.popErrorScope())throw new Error('Ocean compute shader validation failed');
      const a=new Uint8Array(words),b=new Uint8Array(words);
      await solver.sample(0,b);reference.sample(0,a);
      let cpu=0,gpu=0,maxError=0;
      for(let n=0;n<7;n++){
        const t=(n+1)*.117;
        let start=performance.now();reference.sample(t,a);cpu+=performance.now()-start;
        start=performance.now();await solver.sample(t,b);gpu+=performance.now()-start;
        for(let i=0;i<words;i++)maxError=Math.max(maxError,Math.abs(a[i]-b[i]));
      }
      const benchmark={cpuMs:cpu/7,gpuMs:gpu/7,maxError};
      if(maxError<=1&&gpu<cpu*.78)return {solver,benchmark};
      solver.dispose();
      return {solver:null,benchmark};
    }catch{
      if(solver)solver.dispose();else device.destroy();
      return null;
    }
  }
}
