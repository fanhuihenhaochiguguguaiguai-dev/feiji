import { heightPerByte, oceanSize, type OceanSpectrum } from './ocean-solver';

// PlayCanvas declares the GPU interfaces, but omits these WebGPU globals in its public types.
const webgpu=globalThis as typeof globalThis&{
  GPUBufferUsage:Record<'STORAGE'|'COPY_DST'|'COPY_SRC'|'UNIFORM'|'MAP_READ',number>;
  GPUMapMode:{READ:number};
};
const cells=oceanSize**2,bytes=cells*4,bits=Math.log2(oceanSize);
const shader=`
@group(0) @binding(0) var<storage,read> modes:array<vec4f>;
@group(0) @binding(1) var<storage,read_write> rows:array<vec2f>;
@group(0) @binding(2) var<storage,read_write> heights:array<f32>;
@group(0) @binding(3) var<storage,read_write> packed:array<u32>;
@group(0) @binding(4) var<uniform> simTime:f32;
const N=${oceanSize}u;
var<workgroup> line:array<vec2f,${oceanSize}>;
fn butterfly(i:u32,initial:vec2f)->vec2f {
  line[i]=initial;
  workgroupBarrier();
  for(var width=2u;width<=N;width*=2u){
    let halfWidth=width/2u;
    let part=i%width;
    let offset=part%halfWidth;
    let a=i-part+offset;
    let b=line[a+halfWidth];
    let angle=6.28318530718*f32(offset)/f32(width);
    let c=cos(angle);
    let s=sin(angle);
    let wave=vec2f(b.x*c-b.y*s,b.x*s+b.y*c);
    let next=line[a]+select(-wave,wave,part<halfWidth);
    workgroupBarrier();
    line[i]=next;
    workgroupBarrier();
  }
  return line[i];
}
@compute @workgroup_size(${oceanSize})
fn row(@builtin(local_invocation_index) i:u32,@builtin(workgroup_id) group:vec3u){
  let base=group.x*N;
  let mode=modes[base+(reverseBits(i)>>${32-bits}u)];
  let angle=mode.x-mode.y*simTime;
  rows[base+i]=butterfly(i,vec2f(cos(angle),sin(angle)*mode.w)*mode.z);
}
@compute @workgroup_size(${oceanSize})
fn column(@builtin(local_invocation_index) i:u32,@builtin(workgroup_id) group:vec3u){
  let x=group.x;
  let value=butterfly(i,rows[(reverseBits(i)>>${32-bits}u)*N+x]);
  heights[i*N+x]=value.x;
}
fn byte(v:f32)->u32{return u32(clamp(floor(v/${heightPerByte}+128.5),0.,255.));}
@compute @workgroup_size(${oceanSize})
fn encode(@builtin(local_invocation_index) x:u32,@builtin(workgroup_id) group:vec3u){
  let y=group.x;
  let i=y*N+x;
  let h=heights[i];
  let sx=heights[y*N+(x+1u)%N]-heights[y*N+(x+N-1u)%N];
  let sz=heights[((y+1u)%N)*N+x]-heights[((y+N-1u)%N)*N+x];
  let foam=u32(clamp((h-.25)*160.,0.,150.));
  packed[i]=byte(h)|(foam<<8u)|(byte(sx*.7)<<16u)|(byte(sz*.7)<<24u);
}`;

export class GpuOceanSpectrum {
  private readonly buffers:GPUBuffer[]=[];
  private readonly passes:{pipeline:GPUComputePipeline;bindings:GPUBindGroup}[]=[];
  private readonly time:GPUBuffer;
  private readonly packed:GPUBuffer;
  private readonly readback:GPUBuffer;
  private constructor(private readonly device:GPUDevice,coefficients:Float32Array){
    const make=(size:number,usage:number)=>{
      const buffer=device.createBuffer({size,usage,mappedAtCreation:false});
      this.buffers.push(buffer);return buffer;
    };
    const modes=make(cells*16,webgpu.GPUBufferUsage.STORAGE|webgpu.GPUBufferUsage.COPY_DST);
    const rows=make(cells*8,webgpu.GPUBufferUsage.STORAGE);
    const heights=make(bytes,webgpu.GPUBufferUsage.STORAGE);
    this.packed=make(bytes,webgpu.GPUBufferUsage.STORAGE|webgpu.GPUBufferUsage.COPY_SRC);
    this.time=make(4,webgpu.GPUBufferUsage.UNIFORM|webgpu.GPUBufferUsage.COPY_DST);
    this.readback=make(bytes,webgpu.GPUBufferUsage.MAP_READ|webgpu.GPUBufferUsage.COPY_DST);
    device.queue.writeBuffer(modes,0,coefficients as Float32Array<ArrayBuffer>);
    const module=device.createShaderModule({label:'Ocean inverse FFT',code:shader});
    for(const [entryPoint,entries] of [
      ['row',[[0,modes],[1,rows],[4,this.time]]],
      ['column',[[1,rows],[2,heights]]],
      ['encode',[[2,heights],[3,this.packed]]]
    ] as const){
      const pipeline=device.createComputePipeline({layout:'auto',compute:{module,entryPoint}});
      const bindings=device.createBindGroup({
        layout:pipeline.getBindGroupLayout(0),entries:entries.map(([binding,buffer])=>({binding,resource:{buffer}}))
      });
      this.passes.push({pipeline,bindings});
    }
  }
  async sample(time:number,out:Uint8Array){
    const {device}=this;
    device.queue.writeBuffer(this.time,0,new Float32Array([time]));
    const commands=device.createCommandEncoder();
    for(const {pipeline,bindings} of this.passes){
      const pass=commands.beginComputePass();
      pass.setPipeline(pipeline);pass.setBindGroup(0,bindings);pass.dispatchWorkgroups(oceanSize);pass.end();
    }
    commands.copyBufferToBuffer(this.packed,0,this.readback,0,bytes);
    device.queue.submit([commands.finish()]);
    await this.readback.mapAsync(webgpu.GPUMapMode.READ);
    out.set(new Uint8Array(this.readback.getMappedRange()));
    this.readback.unmap();
  }
  dispose(){
    for(const buffer of this.buffers)buffer.destroy();
    this.device.destroy();
  }
  static async qualify(cpu:OceanSpectrum){
    const adapter=await navigator.gpu?.requestAdapter();
    if(!adapter)return {path:'cpu',reason:'no-adapter'} as const;
    const device=await adapter.requestDevice();
    let gpu:GpuOceanSpectrum|undefined;
    try{
      device.pushErrorScope('validation');
      gpu=new GpuOceanSpectrum(device,cpu.coefficients());
      if(await device.popErrorScope())throw new Error('GPU FFT pipeline validation failed');
      const expected=new Uint8Array(bytes),actual=new Uint8Array(bytes);
      await gpu.sample(0,actual);
      let cpuTime=0,gpuTime=0,maxError=0;
      for(let i=0;i<8;i++){
        const time=i*.113;
        let start=performance.now();cpu.sample(time,expected);cpuTime+=performance.now()-start;
        start=performance.now();await gpu.sample(time,actual);gpuTime+=performance.now()-start;
        for(let j=0;j<bytes;j++)maxError=Math.max(maxError,Math.abs(actual[j]-expected[j]));
      }
      const benchmark={cpuMs:cpuTime/8,gpuMs:gpuTime/8,maxError};
      // Include submission and readback because flight/sea contact uses the same surface.
      if(maxError<=1&&gpuTime<cpuTime*.8)return {path:'gpu',benchmark,gpu} as const;
      gpu.dispose();
      return {path:'cpu',reason:maxError>1?'parity':'no-net-gain',benchmark} as const;
    }catch{
      if(gpu)gpu.dispose();else device.destroy();
      return {path:'cpu',reason:'validation'} as const;
    }
  }
}
