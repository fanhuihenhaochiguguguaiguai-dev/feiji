declare const __GAME_RELEASE__:string;
export const release=__GAME_RELEASE__;

export function deadline<T>(work:Promise<T>,ms:number,message:string,onTimeout?:()=>void):Promise<T>{
  return new Promise<T>((resolve,reject)=>{
    const timer=setTimeout(()=>{onTimeout?.();reject(new Error(message));},ms);
    void work.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});
  });
}

export function recoveryUrl(mode?:'compat'|'safe'){
  const url=new URL(location.href);
  if(mode)url.searchParams.set('graphics',mode);
  else url.searchParams.delete('graphics');
  url.searchParams.set('fresh',release);
  return url.href;
}

export function startupStatus(message:string,progress?:number){
  document.getElementById('boot')!.hidden=false;
  const status=document.getElementById('boot-text')!;
  if(status.textContent!==message)status.textContent=message;
  if(progress!==undefined){
    const value=Math.round(Math.min(100,Math.max(0,progress)));
    (document.getElementById('boot-progress') as HTMLProgressElement).value=value;
    document.getElementById('boot-percent')!.textContent=value+'%';
  }
}

export function loadMilestones<T>(jobs:readonly Promise<T>[],message:string,low:number,high:number,timeout:number){
  let done=0,active=true;
  const completion=Promise.all(jobs.map(job=>job.then(value=>{
    if(active)startupStatus(message,low+(high-low)*++done/jobs.length);
    return value;
  })));
  return deadline(completion,timeout,message+'超时').finally(()=>{active=false;});
}

export function startupFailure(message:string,error:unknown){
  console.error(error);
  startupStatus('暂时无法显示游戏画面');
  const detail=document.getElementById('boot-error')!;
  detail.textContent=message;
  detail.hidden=false;
  document.getElementById('boot-actions')!.hidden=false;
  document.getElementById('boot-retry')!.setAttribute('href',recoveryUrl());
  document.getElementById('boot-safe')!.setAttribute('href',recoveryUrl('safe'));
}
