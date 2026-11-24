import { Vector3,Quaternion } from '@babylonjs/core/Maths/math.vector';
import type { Airframe } from './flight';
import type { Terrain } from './terrain';

const relativeStart=new Vector3(),relativeEnd=new Vector3(),inverse=Quaternion.Identity();
const noContact=Infinity;

// Each sweep runs in the moving target's frame, so relative motion cannot tunnel.
export function aircraftContact(start:Vector3,end:Vector3,target:Airframe,proximity:boolean,hullOnly=false){
  start.subtractToRef(target.previous,relativeStart);
  end.subtractToRef(target.position,relativeEnd);
  const padding=proximity?18:hullOnly?.35:5.5;
  const radius=Math.max(target.type.length*.53,target.type.span*.55)+padding;
  if(Math.min(relativeStart.lengthSquared(),relativeEnd.lengthSquared())>
    (radius+Vector3.Distance(relativeStart,relativeEnd))**2)return noContact;
  target.orientation.conjugateToRef(inverse);
  relativeStart.rotateByQuaternionToRef(inverse,relativeStart);
  relativeEnd.rotateByQuaternionToRef(inverse,relativeEnd);
  const {span,length}=target.type;
  if(proximity||!hullOnly)return ellipsoid(relativeStart,relativeEnd,span*.48+padding,span*.13+padding,length*.50+padding);
  const fuselage=ellipsoid(relativeStart,relativeEnd,span*.105+padding,span*.12+padding,length*.48);
  relativeStart.z-=length*.04;relativeEnd.z-=length*.04;
  const wing=ellipsoid(relativeStart,relativeEnd,span*.48+padding,span*.035+padding,length*.23);
  relativeStart.z-=length*.32;relativeEnd.z-=length*.32;
  const tail=ellipsoid(relativeStart,relativeEnd,span*.24+padding,span*.086+padding,length*.155);
  return Math.min(fuselage,wing,tail);
}

export function ellipsoid(start:Vector3,end:Vector3,width:number,height:number,length:number){
  const x=start.x/width,y=start.y/height,z=start.z/length;
  const dx=end.x/width-x,dy=end.y/height-y,dz=end.z/length-z;
  const c=x*x+y*y+z*z-1;
  if(c<=0)return 0;
  const a=dx*dx+dy*dy+dz*dz,b=x*dx+y*dy+z*dz;
  const discriminant=b*b-a*c;
  if(a<1e-12||b>=0||discriminant<0)return noContact;
  const entry=(-b-Math.sqrt(discriminant))/a;
  return entry>=0&&entry<=1?entry:noContact;
}

export function terrainContact(world:Terrain,start:Vector3,end:Vector3,time:number,clearance=0){
  const dx=end.x-start.x,dy=end.y-start.y,dz=end.z-start.z;
  const distance=Math.hypot(dx,dz);
  const floor=(x:number,z:number)=>world.at(x,z,time)+clearance;
  if(Math.min(start.y,end.y)>world.flightCeiling+clearance)return noContact;
  if(start.y<=floor(start.x,start.z))return 0;
  const steps=Math.max(2,Math.min(80,Math.ceil(distance/4)));
  let low=0,high=1;
  for(let index=1;index<=steps;index++){
    high=index/steps;
    if(start.y+dy*high>floor(start.x+dx*high,start.z+dz*high)){low=high;continue;}
    for(let iter=0;iter<9;iter++){
      const middle=(high+low)*.5;
      if(start.y+dy*middle>floor(start.x+dx*middle,start.z+dz*middle))low=middle;else high=middle;
    }
    return high;
  }
  return noContact;
}
