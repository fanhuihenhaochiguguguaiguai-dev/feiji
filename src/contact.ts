import { Vector3,Quaternion } from '@babylonjs/core/Maths/math.vector';
import type { Airframe } from './flight';
import type { Terrain } from './terrain';

const relativeStart=new Vector3(),relativeEnd=new Vector3(),inverse=Quaternion.Identity();
const noContact=Infinity;

// Solve in the moving target's frame. The generous dimensions retain the game's
// existing arcade hit envelope while distinguishing wings, fuselage and proximity fuzes.
export function aircraftContact(start:Vector3,end:Vector3,target:Airframe,proximity:boolean){
  start.subtractToRef(target.previous,relativeStart);
  end.subtractToRef(target.position,relativeEnd);
  const padding=proximity?18:5.5;
  const radius=Math.max(target.type.length*.53,target.type.span*.55)+padding;
  if(Math.min(relativeStart.lengthSquared(),relativeEnd.lengthSquared())>
    (radius+Vector3.Distance(relativeStart,relativeEnd))**2)return noContact;
  target.orientation.conjugateToRef(inverse);
  relativeStart.rotateByQuaternionToRef(inverse,relativeStart);
  relativeEnd.rotateByQuaternionToRef(inverse,relativeEnd);
  return ellipsoid(relativeStart,relativeEnd,target.type.span*.48+padding,target.type.span*.13+padding,target.type.length*.50+padding);
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
