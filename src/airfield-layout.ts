// Shared by the rendering and the collision floor. Coordinates are game metres.
export const base={x:-2970,z:1250,y:31,near:490,far:2100,half:66};
type VolumeKind='runway'|'apron'|'hangar'|'roof'|'tower'|'glass'|'signal';
interface Volume {kind:VolumeKind;x:number;y:number;z:number;w:number;h:number;l:number}
export const airfield:Volume[]=[
  {kind:'runway',x:base.x,y:31.6,z:1295,w:132,h:.93,l:1610},
  {kind:'apron',x:base.x+147,y:31.41,z:base.z,w:162,h:.91,l:819},
  ...Array.from({length:3},(_,i):Volume[]=>[
    {kind:'hangar',x:base.x+217,y:43,z:995+i*190,w:97,h:24,l:104},
    {kind:'roof',x:base.x+217,y:55.3,z:995+i*190,w:47,h:.68,l:93},
  ]).flat(),
  {kind:'tower',x:base.x+244,y:55,z:1519,w:28,h:47,l:25},
  {kind:'glass',x:base.x+244,y:79,z:1519,w:36,h:10,l:27},
  {kind:'tower',x:base.x+244,y:85,z:1519,w:42,h:3,l:33},
  {kind:'signal',x:base.x+244,y:87,z:1519,w:3,h:2,l:3}
];
export function structureTop(x:number,z:number){
  if(x<base.x-68||x>base.x+282||z<base.near||z>base.far)return -Infinity;
  let top=-Infinity;
  for(const a of airfield)if(Math.abs(x-a.x)<=a.w*.5&&Math.abs(z-a.z)<=a.l*.5)top=Math.max(top,a.y+a.h*.5);
  return top;
}
