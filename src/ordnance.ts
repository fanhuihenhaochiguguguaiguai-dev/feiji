import type { PlaneSpec } from './data';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';

type Cannon=[interval:number, speed:number, spread:number, damage:number];
const weapons:Record<string,Cannon>={
  dr1:[.085,1250,.0046,34],camel:[.073,1275,.0041,31],
  zero:[.080,1340,.0042,27],bf109:[.103,1390,.0036,31],p51:[.066,1430,.0031,21],spitfire:[.074,1410,.0034,25],
  me262:[.103,1420,.0046,31],mig21:[.080,1510,.0039,20],g91:[.071,1460,.0035,18],alphajet:[.099,1470,.0038,22],
  a10:[.050,1590,.0031,23],hornet:[.061,1625,.0029,15],f16:[.065,1660,.0028,15.5],
  su35:[.087,1630,.0033,20],mirage:[.083,1570,.0032,17.5],gripen:[.076,1610,.0030,16.8],
  j10:[.078,1620,.0031,17],j20:[.082,1680,.0027,16.5]
};
export const cannonFor=(air:PlaneSpec):Cannon=>weapons[air.id]??[.095,1500,.0037,17];
export const gunZeroRange=650;
export const gunSight=(position:Vector3,forward:Vector3,out:Vector3)=>
  out.copyFrom(position).addInPlaceFromFloats(forward.x*gunZeroRange,forward.y*gunZeroRange,forward.z*gunZeroRange);
export function gunDamage(air:PlaneSpec,power=1){return cannonFor(air)[3]*air.gunPower*power;}
export const gunCycle=(air:PlaneSpec)=>cannonFor(air)[0];
export const missileCycle=()=>.96;
export const guidedStrike={speed:835,damage:175};
export const thrustDuration=.085;
export const standardGravity=9.81;
export const releaseDropSpeed=5;
