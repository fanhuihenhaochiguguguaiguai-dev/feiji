declare const __GAME_RELEASE__:string;
export const release=__GAME_RELEASE__;

export const asset=(path:string)=>{
  const url=new URL(path,document.baseURI);
  if(url.origin===location.origin&&!/\/assets\//.test(url.pathname))url.searchParams.set('release',release);
  return url.href;
};

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

export function startupStatus(message:string){
  document.getElementById('boot')!.hidden=false;
  document.getElementById('boot-text')!.textContent=message;
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
