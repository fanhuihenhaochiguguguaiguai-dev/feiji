// Startup status and milestone tracking adapted from V11.
export function deadline<T>(work:Promise<T>,ms:number,message:string):Promise<T>{
  return new Promise<T>((resolve,reject)=>{
    const timer=setTimeout(()=>{reject(new Error(message));},ms);
    void work.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});
  });
}

export function loading(progress:number,message:string){
  const value=Math.round(Math.min(100,Math.max(0,progress)));
  (document.getElementById('boot-progress') as HTMLProgressElement).value=value;
  document.getElementById('boot-percent')!.textContent=value+'%';
  document.getElementById('boot-text')!.textContent=message;
}

export function milestones(jobs:readonly Promise<unknown>[],start:number,end:number,message:string){
  let done=0,active=true;
  const completion=Promise.all(jobs.map(job=>job.then(()=>{
    if(active)loading(start+(end-start)*++done/jobs.length,message);
  })));
  return deadline(completion,90000,message+'超时').finally(()=>{active=false;});
}

export function startupFailure(message:string,error:unknown){
  console.error(error);
  document.getElementById('boot-text')!.textContent='暂时无法显示游戏画面';
  const detail=document.getElementById('boot-error')!;
  detail.textContent=message;
  detail.hidden=false;
  document.getElementById('boot-actions')!.hidden=false;
}
