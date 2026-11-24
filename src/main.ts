import './style.css';
import './v7-ui.css';
declare const __FLAGSHIP_QA__:boolean;
import { Game, openEngine } from './engine';
import { el } from './interface';
import { loadPersistentProfile } from './profile';
import { loadTerrain } from './terrain';
import { theatres } from './data';
import { asset } from './renderer';
import { deadline,startupFailure,startupStatus } from './startup';

async function start(){
  let activeBackend='';
  const blocked=()=>{try{return sessionStorage.getItem('pixel-sky-webgpu-fallback')==='1';}catch{return false;}};
  try {
    startupStatus('正在读取飞行员档案',12);
    const profile=await loadPersistentProfile();
    startupStatus('正在载入首张地貌',23);
    const initial=theatres[0];
    await deadline(loadTerrain(initial.seed,asset('world/'+initial.id+'.height')),20000,'首张地貌资产读取超时');
    startupStatus('正在连接图形设备',36);
    const mode=new URL(location.href).searchParams.get('graphics');
    const entry=await openEngine(el<HTMLCanvasElement>('scene'),blocked()||mode==='safe'||mode==='compat'?'gl':profile.settings.backend);
    activeBackend=entry.backend;
    startupStatus('正在载入机库和战机',50);
    const game=new Game(entry,profile);
    if(__FLAGSHIP_QA__){
      const {instrument}=await import('./qa-instrumentation');
      Object.defineProperty(window,'flightQA',{value:game});
      Object.defineProperty(window,'flightProfile',{value:instrument(game,performance.now())});
    }
    await game.init();
    if((import.meta.env.DEV||__FLAGSHIP_QA__)&&new URL(location.href).searchParams.has('world-forge')){
      const {openFieldLab}=await import('./field-lab');
      openFieldLab(game);
    }
    if(__FLAGSHIP_QA__)performance.mark('flagship-ready');
    if('serviceWorker'in navigator&&isSecureContext){
      void navigator.serviceWorker.register(new URL('sw.js',document.baseURI),{updateViaCache:'none'}).catch(()=>{});
    }
  } catch(error) {
    if(activeBackend==='gpu'&&!blocked()){
      try {sessionStorage.setItem('pixel-sky-webgpu-fallback','1');location.reload();return;}catch{/* Report below. */}
    }
    startupFailure('机库、图形设备或地貌文件未能载入。请尝试重新连接或使用 WebGL2。',error);
  }
}
void start();
