(function(){"use strict";const C=.012598425196850395,$=34,w=4096,g=(c,t,a)=>Math.max(t,Math.min(a,c)),y=c=>g(Math.round(c/C)+128,0,255),_=Array.from({length:64/2},(c,t)=>2*Math.PI*t/64),D=_.map(c=>Math.cos(c)),W=_.map(c=>Math.sin(c));function G(c,t,a,e){for(let i=1,s=0;i<64;i++){let o=32;for(;s&o;o>>=1)s^=o;if(s^=o,i>=s)continue;const n=a+i*e,l=a+s*e,r=c[n],h=t[n];c[n]=c[l],c[l]=r,t[n]=t[l],t[l]=h}for(let i=2;i<=64;i*=2){const s=64/i,o=i>>1;for(let n=0;n<64;n+=i)for(let l=0;l<o;l++){const r=a+(n+l)*e,h=r+o*e,f=D[s*l],p=W[s*l],d=c[h]*f-t[h]*p,u=c[h]*p+t[h]*f;c[h]=c[r]-d,t[h]=t[r]-u,c[r]+=d,t[r]+=u}}}const N=(c,t)=>{const a=Math.sin(c*124.17+t*513.47)*43758.5453;return a-Math.floor(a)};function I(){const c=[];for(let t=0;t<64/2;t++)for(let a=-64/2+1;a<64/2;a++){if(t===0&&a<=0)continue;const e=Math.hypot(a,t)*2*Math.PI/512,i=(a*.81+t*.59)/Math.hypot(a,t),s=.011*Math.exp(-(((e-.102)/.056)**2))*(.27+.73*i**2),o=.0031*Math.exp(-(((e-.213)/.085)**2))*(.4+.6*i**2),n=(s+o)*(.36+N(a+302,t-19)*.9);if(n<12e-5)continue;const l=(a+64)%64+t*64,r=(64-a)%64+(64-t)%64*64;c.push({i:l,j:r,phase:N(a,t)*Math.PI*2,omega:Math.sqrt(9.81*e),amplitude:n*.5})}return c}class T{re=new Float32Array(w);im=new Float32Array(w);modes=I();coefficients(){const t=new Float32Array(w*4);for(const{i:a,j:e,phase:i,omega:s,amplitude:o}of this.modes)t.set([i,s,o,1],a*4),t.set([i,s,o,-1],e*4);return t}sample(t,a){this.re.fill(0),this.im.fill(0);for(const e of this.modes){const i=e.phase-t*e.omega;this.re[e.i]=this.re[e.j]=Math.cos(i)*e.amplitude,this.im[e.i]=Math.sin(i)*e.amplitude,this.im[e.j]=-this.im[e.i]}for(let e=0;e<64;e++)G(this.re,this.im,e*64,1);for(let e=0;e<64;e++)G(this.re,this.im,e,64);for(let e=0;e<64;e++)for(let i=0;i<64;i++){const s=e*64+i,o=this.re[s],n=s*4,l=this.re[e*64+(i+1)%64]-this.re[e*64+(i+64-1)%64],r=this.re[(e+1)%64*64+i]-this.re[(e+64-1)%64*64+i];a[n]=y(o),a[n+1]=g((o-.25)*160,0,150),a[n+2]=y(l*.7),a[n+3]=y(r*.7)}}}const Y=c=>c.water?g(($-c.altitude)/31,0,1)**.68*g((c.speed-48)/97,0,1):0;class L{h=new Float32Array(w);dh=new Float32Array(w);foam=new Float32Array(w);spare=new Float32Array(w);bed=null;previous=null;depth=new Float32Array(w);x=0;z=0;active=!1;setBed(t){this.bed=t,this.active=!1,this.previous=null,this.h.fill(0),this.dh.fill(0),this.foam.fill(0)}floor(t,a){const e=Math.floor((t+24e3)*.021333333333333333),i=Math.floor((a+24e3)*(1024/48e3));return this.bed&&e>=0&&e<1025&&i>=0&&i<1025?this.bed[i*1025+e]*.25:-40}shift(t,a){const e=this.active?(t-this.x)/5:64,i=this.active?(a-this.z)/5:64;for(const s of[this.h,this.dh,this.foam]){if(this.spare.fill(0),Math.abs(e)<64&&Math.abs(i)<64)for(let o=0;o<64;o++)for(let n=0;n<64;n++){const l=n+e,r=o+i;l>=0&&l<64&&r>=0&&r<64&&(this.spare[o*64+n]=s[r*64+l])}s.set(this.spare)}this.x=t,this.z=a,this.active=!0;for(let s=0;s<64;s++)for(let o=0;o<64;o++)this.depth[s*64+o]=g(-this.floor(t+o*5,a+s*5),0,24)}step(t,a){const e=this.previous??t,i=g(t.time-e.time,0,.3),s=Y(t),o=(Math.floor(t.x/5)-64/2)*5,n=(Math.floor(t.z/5)-64/2)*5;(!this.active||Math.abs(o-this.x)+Math.abs(n-this.z)>=15)&&this.shift(o,n);const l=Math.max(1,Math.ceil(i*45)),r=i/l;for(let h=0;h<l;h++){const f=(h+1)/l,p=(e.x+(t.x-e.x)*f-this.x)/5,d=(e.z+(t.z-e.z)*f-this.z)/5;for(let u=1;u<63;u++)for(let S=1;S<63;S++){const m=u*64+S,O=this.depth[m];if(O<=0){this.spare[m]=0,this.dh[m]=0,this.foam[m]=0;continue}const A=this.h[m],J=this.h[m-1]+this.h[m+1]+this.h[m-64]+this.h[m+64]-4*A,q=(p-S)**2+(d-u)**2,R=s&&q<20?Math.exp(-q*.34)*s:0,K=Math.min(S,u,63-S,63-u)<5?3.1:.78;this.dh[m]=(this.dh[m]+(9.81*O*J/25-22*R)*r)/(1+r*K),this.spare[m]=g(A+this.dh[m]*r,-1.55,1.55),this.foam[m]=Math.max(this.foam[m]*(1-r*.53),R*.93,g(Math.max(0,A-.09)*2.1,0,.83))}[this.h,this.spare]=[this.spare,this.h]}for(let h=0;h<64;h++)for(let f=0;f<64;f++){const p=h*64+f,d=p*4,u=Math.min(f,h,63-f,63-h),S=g(u*.2,0,1);a[d]=y(this.h[p]*S),a[d+1]=255*S*this.foam[p],a[d+2]=y((this.h[p+(f<63?1:0)]-this.h[p-(f>0?1:0)])*S),a[d+3]=y((this.h[p+(h<63?64:0)]-this.h[p-(h>0?64:0)])*S)}this.previous=t}}const z=globalThis,M=64**2,b=M*4,F=Math.log2(64),H=`
@group(0) @binding(0) var<storage,read> modes:array<vec4f>;
@group(0) @binding(1) var<storage,read_write> rows:array<vec2f>;
@group(0) @binding(2) var<storage,read_write> heights:array<f32>;
@group(0) @binding(3) var<storage,read_write> packed:array<u32>;
@group(0) @binding(4) var<uniform> simTime:f32;
const N=64u;
var<workgroup> line:array<vec2f,64>;
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
@compute @workgroup_size(64)
fn row(@builtin(local_invocation_index) i:u32,@builtin(workgroup_id) group:vec3u){
  let base=group.x*N;
  let mode=modes[base+(reverseBits(i)>>${32-F}u)];
  let angle=mode.x-mode.y*simTime;
  rows[base+i]=butterfly(i,vec2f(cos(angle),sin(angle)*mode.w)*mode.z);
}
@compute @workgroup_size(64)
fn column(@builtin(local_invocation_index) i:u32,@builtin(workgroup_id) group:vec3u){
  let x=group.x;
  let value=butterfly(i,rows[(reverseBits(i)>>${32-F}u)*N+x]);
  heights[i*N+x]=value.x;
}
fn byte(v:f32)->u32{return u32(clamp(floor(v/${C}+128.5),0.,255.));}
@compute @workgroup_size(64)
fn encode(@builtin(local_invocation_index) x:u32,@builtin(workgroup_id) group:vec3u){
  let y=group.x;
  let i=y*N+x;
  let h=heights[i];
  let sx=heights[y*N+(x+1u)%N]-heights[y*N+(x+N-1u)%N];
  let sz=heights[((y+1u)%N)*N+x]-heights[((y+N-1u)%N)*N+x];
  let foam=u32(clamp((h-.25)*160.,0.,150.));
  packed[i]=byte(h)|(foam<<8u)|(byte(sx*.7)<<16u)|(byte(sz*.7)<<24u);
}`;class k{constructor(t,a){this.device=t;const e=(l,r)=>{const h=t.createBuffer({size:l,usage:r,mappedAtCreation:!1});return this.buffers.push(h),h},i=e(M*16,z.GPUBufferUsage.STORAGE|z.GPUBufferUsage.COPY_DST),s=e(M*8,z.GPUBufferUsage.STORAGE),o=e(b,z.GPUBufferUsage.STORAGE);this.packed=e(b,z.GPUBufferUsage.STORAGE|z.GPUBufferUsage.COPY_SRC),this.time=e(4,z.GPUBufferUsage.UNIFORM|z.GPUBufferUsage.COPY_DST),this.readback=e(b,z.GPUBufferUsage.MAP_READ|z.GPUBufferUsage.COPY_DST),t.queue.writeBuffer(i,0,a);const n=t.createShaderModule({label:"Ocean inverse FFT",code:H});for(const[l,r]of[["row",[[0,i],[1,s],[4,this.time]]],["column",[[1,s],[2,o]]],["encode",[[2,o],[3,this.packed]]]]){const h=t.createComputePipeline({layout:"auto",compute:{module:n,entryPoint:l}}),f=t.createBindGroup({layout:h.getBindGroupLayout(0),entries:r.map(([p,d])=>({binding:p,resource:{buffer:d}}))});this.passes.push({pipeline:h,bindings:f})}}buffers=[];passes=[];time;packed;readback;async sample(t,a){const{device:e}=this;e.queue.writeBuffer(this.time,0,new Float32Array([t]));const i=e.createCommandEncoder();for(const{pipeline:s,bindings:o}of this.passes){const n=i.beginComputePass();n.setPipeline(s),n.setBindGroup(0,o),n.dispatchWorkgroups(64),n.end()}i.copyBufferToBuffer(this.packed,0,this.readback,0,b),e.queue.submit([i.finish()]),await this.readback.mapAsync(z.GPUMapMode.READ),a.set(new Uint8Array(this.readback.getMappedRange())),this.readback.unmap()}dispose(){for(const t of this.buffers)t.destroy();this.device.destroy()}static async qualify(t){const a=await navigator.gpu?.requestAdapter();if(!a)return{path:"cpu",reason:"no-adapter"};const e=await a.requestDevice();let i;try{if(e.pushErrorScope("validation"),i=new k(e,t.coefficients()),await e.popErrorScope())throw new Error("GPU FFT pipeline validation failed");const s=new Uint8Array(b),o=new Uint8Array(b);await i.sample(0,o);let n=0,l=0,r=0;for(let f=0;f<8;f++){const p=f*.113;let d=performance.now();t.sample(p,s),n+=performance.now()-d,d=performance.now(),await i.sample(p,o),l+=performance.now()-d;for(let u=0;u<b;u++)r=Math.max(r,Math.abs(o[u]-s[u]))}const h={cpuMs:n/8,gpuMs:l/8,maxError:r};return r<=1&&l<n*.8?{path:"gpu",benchmark:h,gpu:i}:(i.dispose(),{path:"cpu",reason:r>1?"parity":"no-net-gain",benchmark:h})}catch{return i?i.dispose():e.destroy(),{path:"cpu",reason:"validation"}}}}const j=new T,U=new L;let B=-1,E=!1,P=!1,v,x={path:"cpu",reason:"compatible"};self.onmessage=async({data:c})=>{const{cycle:t,water:a}=c;if(t!==B&&(B=t,U.setBed(c.bed??null)),!a)return;c.compute&&!E&&(E=!0,k.qualify(new T).then(({path:n,benchmark:l,...r})=>{x={path:n,benchmark:l,reason:"reason"in r?r.reason:void 0},"gpu"in r&&(v=r.gpu)}).catch(()=>{x={path:"cpu",reason:"unavailable"}}));const e=new Uint8Array(64**2*4),i=new Uint8Array(64**2*4);U.step(a,i);const{x:s,z:o}=U;if(v&&!P){P=!0;try{await v.sample(a.time,e)}catch{v.dispose(),v=void 0,x={path:"cpu",reason:"device-lost"},j.sample(a.time,e)}finally{P=!1}}else j.sample(a.time,e);t===B&&self.postMessage({cycle:t,time:a.time,swell:e,pressure:i,x:s,z:o,fft:x},{transfer:[e.buffer,i.buffer]})}})();
