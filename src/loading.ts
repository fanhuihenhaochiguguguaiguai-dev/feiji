export function loading(value:number,message:string){
  (document.getElementById('boot-progress') as HTMLProgressElement).value=value;
  document.getElementById('boot-percent')!.textContent=value+'%';
  document.getElementById('boot-text')!.textContent=message;
}

export async function milestones(jobs:readonly Promise<unknown>[],start:number,end:number,message:string){
  let count=0,active=true;
  try{
    await Promise.all(jobs.map(job=>job.then(()=>{
      if(active)loading(Math.round(start+(end-start)*(++count/jobs.length)),message);
    })));
  }finally{active=false;}
}
