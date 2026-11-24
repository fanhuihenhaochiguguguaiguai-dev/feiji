import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Airframe } from './flight';
import { clamp, type Terrain } from './terrain';

const lockAngle=.43;
export const lockRadius=(fov:number,height:number)=>height*.5*Math.tan(lockAngle)/Math.tan(fov*.5);
type LockProjection=(position:Vector3)=>number;

export class TargetDirector {
  target:Airframe|null=null;
  progress=0;
  inside=false;
  projection:LockProjection|null=null;
  private selectedAt=-10;
  private seenAt=-10;
  private remembered:Airframe|null=null;
  private rememberedGeneration=0;
  private memoryUntil=0;
  private readonly relative=new Vector3();
  private readonly speed=new Vector3();

  reset(){
    this.target=this.remembered=null;this.progress=0;this.inside=false;
    this.selectedAt=this.seenAt=-10;
  }

  update(pilot:Airframe,contacts:readonly Airframe[],terrain:Terrain,rangeLimit:number,acquire:number,
    time:number,dt:number,steering:number,threat:Airframe|null){
    const incumbent=this.target;
    let selected:Airframe|null=null,best=-Infinity,selectedRatio=1,incumbentVisible=false;
    for(const contact of contacts){
      if(!contact.alive)continue;
      contact.position.subtractToRef(pilot.position,this.relative);
      const range=this.relative.length();
      if(range<70||range>rangeLimit)continue;
      const align=Vector3.Dot(pilot.forward,this.relative)/range;
      if(align<=0)continue;
      const ratio=this.projection?.(contact.position)??Math.acos(clamp(align,-1,1))/lockAngle;
      if(ratio>1||!Number.isFinite(ratio))continue;
      const p=pilot.position,c=contact.position;
      if(terrain.terrainMasks(p.x,p.y,p.z,c.x,c.y,c.z))continue;
      let score=align*.42+(1-ratio)*(.54+.27*steering)+(1-range/rangeLimit)*.24;
      if(contact===threat||contact.lockAt!==null)score+=.10;
      if(contact===incumbent){score+=time-this.selectedAt<.50?.28:.14;incumbentVisible=true;}
      if(score>best){selected=contact;best=score;selectedRatio=ratio;}
    }
    this.inside=!!selected;
    // Hold the cue briefly through a crossing at the edge, while suspending launch permission.
    if(incumbent?.alive&&!incumbentVisible&&time-this.seenAt<.26){
      this.inside=false;this.progress=Math.max(0,this.progress-dt*.95);
      return false;
    }
    if(selected!==incumbent){
      const reacquired=selected&&selected===this.remembered&&selected.generation===this.rememberedGeneration&&time<this.memoryUntil;
      if(incumbent){
        this.remembered=incumbent;this.rememberedGeneration=incumbent.generation;this.memoryUntil=time+1.35;
      }
      this.target=selected;this.progress=reacquired?.32:0;this.selectedAt=time;
    }
    if(!selected)return false;
    this.seenAt=time;
    const previous=this.progress;
    const dwell=acquire*(.79+.48*selectedRatio);
    this.progress=Math.min(1,previous+dt/dwell);
    return previous<1&&this.progress===1;
  }

  lead(pilot:Airframe,muzzleSpeed:number,result:Vector3){
    const enemy=this.target;
    if(!this.inside||!enemy?.alive)return false;
    enemy.position.subtractToRef(pilot.position,this.relative);
    const span=this.relative.lengthSquared();
    if(span>1200**2)return false;
    enemy.velocity.subtractToRef(pilot.velocity,this.speed);
    const a=this.speed.lengthSquared()-muzzleSpeed*muzzleSpeed;
    const b=2*Vector3.Dot(this.relative,this.speed),root=b*b-4*a*span;
    if(root<0)return false;
    // This radical form stays stable when relative speed approaches muzzle speed.
    const denominator=Math.sqrt(root)-b;
    if(denominator<=0)return false;
    const time=2*span/denominator;
    if(time<=0||time>1.15)return false;
    result.copyFrom(enemy.position).addInPlaceFromFloats(this.speed.x*time,this.speed.y*time,this.speed.z*time);
    return true;
  }
}
