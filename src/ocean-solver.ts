export const oceanSize=64;
export const swellPeriod=512;
export const wakeCell=5;
export const wakeExtent=oceanSize*wakeCell;
export const heightPerByte=1.6/127;
export const wakeCeiling=34;
const total=oceanSize*oceanSize;
const clamp=(n:number,a:number,b:number)=>Math.max(a,Math.min(b,n));
const encode=(height:number)=>clamp(Math.round(height/heightPerByte)+128,0,255);
const angles=Array.from({length:oceanSize/2},(_,i)=>2*Math.PI*i/oceanSize);
const cosines=angles.map(x=>Math.cos(x)),sines=angles.map(x=>Math.sin(x));

function fftLine(re:Float32Array,im:Float32Array,start:number,stride:number){
  for(let i=1,j=0;i<oceanSize;i++){
    let bit=oceanSize>>1;
    for(;j&bit;bit>>=1)j^=bit;
    j^=bit;
    if(i>=j)continue;
    const a=start+i*stride,b=start+j*stride,r=re[a],q=im[a];
    re[a]=re[b];re[b]=r;im[a]=im[b];im[b]=q;
  }
  for(let size=2;size<=oceanSize;size*=2){
    const strideInCircle=oceanSize/size,half=size>>1;
    for(let i=0;i<oceanSize;i+=size)for(let j=0;j<half;j++){
      const a=start+(i+j)*stride,b=a+half*stride;
      const cos=cosines[strideInCircle*j],sin=sines[strideInCircle*j];
      const r=re[b]*cos-im[b]*sin,q=re[b]*sin+im[b]*cos;
      re[b]=re[a]-r;im[b]=im[a]-q;re[a]+=r;im[a]+=q;
    }
  }
}

const random=(x:number,z:number)=>{const n=Math.sin(x*124.17+z*513.47)*43758.5453;return n-Math.floor(n);};
function spectralModes(){
  const modes:{i:number;j:number;phase:number;omega:number;amplitude:number}[]=[];
  for(let z=0;z<oceanSize/2;z++)for(let x=-oceanSize/2+1;x<oceanSize/2;x++){
    if(z===0&&x<=0)continue;
    const k=Math.hypot(x,z)*2*Math.PI/swellPeriod;
    const direction=(x*.81+z*.59)/Math.hypot(x,z);
    const broad=.011*Math.exp(-(((k-.102)/.056)**2))*(.27+.73*direction**2);
    const wind=.0031*Math.exp(-(((k-.213)/.085)**2))*(.40+.60*direction**2);
    const energy=(broad+wind)*(.36+random(x+302,z-19)*.90);
    if(energy<.00012)continue;
    const i=(x+oceanSize)%oceanSize+z*oceanSize;
    const j=(oceanSize-x)%oceanSize+(oceanSize-z)%oceanSize*oceanSize;
    modes.push({i,j,phase:random(x,z)*Math.PI*2,omega:Math.sqrt(9.81*k),amplitude:energy*.5});
  }
  return modes;
}

export class OceanSpectrum {
  private readonly re=new Float32Array(total);
  private readonly im=new Float32Array(total);
  private readonly modes=spectralModes();
  coefficients(){
    const packed=new Float32Array(total*4);
    for(const {i,j,phase,omega,amplitude} of this.modes){
      packed.set([phase,omega,amplitude,1],i*4);
      packed.set([phase,omega,amplitude,-1],j*4);
    }
    return packed;
  }
  sample(time:number,out:Uint8Array){
    this.re.fill(0);this.im.fill(0);
    for(const m of this.modes){
      const phase=m.phase-time*m.omega;
      this.re[m.i]=this.re[m.j]=Math.cos(phase)*m.amplitude;
      this.im[m.i]=Math.sin(phase)*m.amplitude;this.im[m.j]=-this.im[m.i];
    }
    for(let i=0;i<oceanSize;i++)fftLine(this.re,this.im,i*oceanSize,1);
    for(let i=0;i<oceanSize;i++)fftLine(this.re,this.im,i,oceanSize);
    for(let z=0;z<oceanSize;z++)for(let x=0;x<oceanSize;x++){
      const i=z*oceanSize+x,h=this.re[i],at=i*4;
      const sx=this.re[z*oceanSize+(x+1)%oceanSize]-this.re[z*oceanSize+(x+oceanSize-1)%oceanSize];
      const sz=this.re[((z+1)%oceanSize)*oceanSize+x]-this.re[((z+oceanSize-1)%oceanSize)*oceanSize+x];
      out[at]=encode(h);out[at+1]=clamp((h-.25)*160,0,150);
      out[at+2]=encode(sx*.7);out[at+3]=encode(sz*.7);
    }
  }
}

export interface WaterMotion {time:number;x:number;z:number;altitude:number;speed:number;water:boolean;}
export const pressureStrength=(s:WaterMotion)=>s.water?clamp((wakeCeiling-s.altitude)/31,0,1)**.68*clamp((s.speed-48)/97,0,1):0;

export class ShallowWake {
  private h=new Float32Array(total);
  private dh=new Float32Array(total);
  private foam=new Float32Array(total);
  private spare=new Float32Array(total);
  private bed: Int16Array|null=null;
  private previous:WaterMotion|null=null;
  readonly depth=new Float32Array(total);
  x=0;z=0;
  active=false;
  setBed(bed:Int16Array|null){this.bed=bed;this.active=false;this.previous=null;this.h.fill(0);this.dh.fill(0);this.foam.fill(0);}
  private floor(x:number,z:number){
    const i=Math.floor((x+24000)*(1024/48000)),j=Math.floor((z+24000)*(1024/48000));
    return this.bed&&i>=0&&i<1025&&j>=0&&j<1025?this.bed[j*1025+i]*.25:-40;
  }
  private shift(x:number,z:number){
    const dx=this.active?(x-this.x)/wakeCell:oceanSize,dz=this.active?(z-this.z)/wakeCell:oceanSize;
    for(const field of [this.h,this.dh,this.foam]){
      this.spare.fill(0);
      if(Math.abs(dx)<oceanSize&&Math.abs(dz)<oceanSize){
        for(let j=0;j<oceanSize;j++)for(let i=0;i<oceanSize;i++){
          const u=i+dx,v=j+dz;
          if(u>=0&&u<oceanSize&&v>=0&&v<oceanSize)this.spare[j*oceanSize+i]=field[v*oceanSize+u];
        }
      }
      field.set(this.spare);
    }
    this.x=x;this.z=z;this.active=true;
    for(let j=0;j<oceanSize;j++)for(let i=0;i<oceanSize;i++)
      this.depth[j*oceanSize+i]=clamp(-this.floor(x+i*wakeCell,z+j*wakeCell),0,24);
  }
  step(s:WaterMotion,out:Uint8Array){
    const old=this.previous??s,elapsed=clamp(s.time-old.time,0,.30),power=pressureStrength(s);
    const x=(Math.floor(s.x/wakeCell)-oceanSize/2)*wakeCell,z=(Math.floor(s.z/wakeCell)-oceanSize/2)*wakeCell;
    if(!this.active||Math.abs(x-this.x)+Math.abs(z-this.z)>=wakeCell*3)this.shift(x,z);
    const steps=Math.max(1,Math.ceil(elapsed*45)),dt=elapsed/steps;
    for(let n=0;n<steps;n++){
      const blend=(n+1)/steps;
      const cx=(old.x+(s.x-old.x)*blend-this.x)/wakeCell;
      const cz=(old.z+(s.z-old.z)*blend-this.z)/wakeCell;
      for(let j=1;j<oceanSize-1;j++)for(let i=1;i<oceanSize-1;i++){
        const at=j*oceanSize+i,depth=this.depth[at];
        if(depth<=0){this.spare[at]=0;this.dh[at]=0;this.foam[at]=0;continue;}
        const h=this.h[at],lap=this.h[at-1]+this.h[at+1]+this.h[at-oceanSize]+this.h[at+oceanSize]-4*h;
        const separation=(cx-i)**2+(cz-j)**2;
        const pump=power&&separation<20?Math.exp(-separation*.34)*power:0;
        const edge=Math.min(i,j,oceanSize-1-i,oceanSize-1-j);
        const damping=edge<5?3.1:.78;
        this.dh[at]=(this.dh[at]+(9.81*depth*lap/(wakeCell*wakeCell)-22*pump)*dt)/(1+dt*damping);
        this.spare[at]=clamp(h+this.dh[at]*dt,-1.55,1.55);
        this.foam[at]=Math.max(this.foam[at]*(1-dt*.53),pump*.93,clamp(Math.max(0,h-.09)*2.1,0,.83));
      }
      [this.h,this.spare]=[this.spare,this.h];
    }
    for(let j=0;j<oceanSize;j++)for(let i=0;i<oceanSize;i++){
      const at=j*oceanSize+i,p=at*4;
      const edge=Math.min(i,j,oceanSize-1-i,oceanSize-1-j),fade=clamp(edge*.2,0,1);
      out[p]=encode(this.h[at]*fade);out[p+1]=255*fade*this.foam[at];
      out[p+2]=encode((this.h[at+(i<oceanSize-1?1:0)]-this.h[at-(i>0?1:0)])*fade);
      out[p+3]=encode((this.h[at+(j<oceanSize-1?oceanSize:0)]-this.h[at-(j>0?oceanSize:0)])*fade);
    }
    this.previous=s;
  }
}
