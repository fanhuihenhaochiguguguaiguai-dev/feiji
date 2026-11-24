declare const __FLAGSHIP_QA__:boolean;
import { Game, openEngine } from './engine';
import { GraphicsFailure,type OpenEngine } from './scene-runtime';
import { loadPersistentProfile } from './profile';
import { loadTerrain } from './terrain';
import { theatres } from './data';
import { asset,deadline,recoveryUrl,startupFailure,startupStatus } from './startup';

async function start(){
  const params=new URL(location.href).searchParams,mode=params.get('graphics');
  const safe=mode==='safe',compat=safe||mode==='compat';
  let entry:OpenEngine|undefined,phase='assets',recovering=false;
  const recover=(error:unknown)=>{
    if(recovering)return;
    recovering=true;
    if(safe){startupFailure('WebGL2 安全模式也无法出图。你可以重新连接，或换用支持硬件加速的浏览器。',error);return;}
    console.warn('正在恢复图形设备',error);
    startupStatus('图形设备已中断，正在切换兼容模式');
    const retry=()=>location.replace(recoveryUrl(entry?.backend==='gpu'?'compat':'safe'));
    if(document.hidden){
      const visible=()=>{if(!document.hidden){document.removeEventListener('visibilitychange',visible);retry();}};
      document.addEventListener('visibilitychange',visible);
    }else setTimeout(retry,0);
  };
  try {
    startupStatus('正在读取飞行员档案',12);
    const profile=await loadPersistentProfile();
    startupStatus('正在载入首张地貌',23);
    const initial=theatres[0];
    await deadline(loadTerrain(initial.seed,asset('world/'+initial.id+'.height')),20000,'首张地貌资产读取超时');
    phase='device';startupStatus('正在连接图形设备',36);
    entry=await openEngine(document.getElementById('scene') as HTMLCanvasElement,compat?'gl':profile.settings.backend,safe);
    entry.app.onGraphicsFailure(recover);
    const game=new Game(entry,profile,recover);
    phase='assets';startupStatus('正在载入机库和战机',50);
    if(__FLAGSHIP_QA__){
      const {instrument}=await import('./qa-instrumentation');
      Object.defineProperty(window,'flightQA',{value:game});
      Object.defineProperty(window,'flightProfile',{value:instrument(game,performance.now())});
    }
    await game.init();
    if((import.meta.env.DEV||__FLAGSHIP_QA__)&&params.has('world-forge')){
      const {openFieldLab}=await import('./field-lab');
      openFieldLab(game);
    }
    if(__FLAGSHIP_QA__)performance.mark('flagship-ready');
    if('serviceWorker'in navigator&&isSecureContext){
      void navigator.serviceWorker.register(new URL('sw.js',document.baseURI),{updateViaCache:'none'}).catch(()=>{});
    }
  } catch(error) {
    entry?.app.stop();
    if(phase==='device'||error instanceof GraphicsFailure){recover(error);return;}
    startupFailure('机库或地貌文件未能载入。重新连接可获取当前发布的完整资源。',error);
  }
}
void start();
