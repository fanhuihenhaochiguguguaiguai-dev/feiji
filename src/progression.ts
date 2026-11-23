export const levelThreshold=(level:number)=>Math.round(210*(level-1)+24*(level-1)**2);
export function pilotLevel(xp:number){
  return Math.max(1,Math.floor((Math.sqrt(210**2+96*(Math.max(0,xp)+.5))-210)/48)+1);
}
export function levelProgress(xp:number){
  const level=pilotLevel(xp),floor=levelThreshold(level),ceiling=levelThreshold(level+1);
  return {level,progress:xp-floor,required:ceiling-floor};
}
export const airframeLevels:Readonly<Record<string,number>>={mirage:4,hornet:6,gripen:7,su35:10,ea6b:11};
export function levelReward(level:number):[string,number][]{
  const rewards:[string,number][]=[['credits',160+level*36],[level%2?'alloy':'circuit',1+Math.floor(level/6)]];
  const aircraft=level===4?'mirage':level===8?'hornet':level===12?'su35':null;
  if(aircraft)rewards.push(['air-'+aircraft,1]);
  if(level===6)rewards.push(['flarewing',1]);
  if(level===10)rewards.push(['reserve',2]);
  return rewards;
}
