import './style.css';
import './v7-ui.css';
declare const __FLAGSHIP_QA__:boolean;
import { Game, openEngine } from './engine';
import { el } from './interface';
import { loadPersistentProfile } from './profile';
import { loadTerrain } from './terrain';
import { theatres } from './data';

async function start(){
  let activeBackend='';
  const blocked=()=>{try{return sessionStorage.getItem('pixel-sky-webgpu-fallback')==='1';}catch{return false;}};
  try {
    const profile=await loadPersistentProfile();
    const entry=await openEngine(el<HTMLCanvasElement>('scene'),blocked()?'gl':profile.settings.backend);
    activeBackend=entry.backend;
    const initial=theatres[0];
    await loadTerrain(initial.seed,new URL('world/'+initial.id+'.height',document.baseURI).href);
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
      console.warn('WebGPU 场景初始化失败，尝试 WebGL2',String(error));
      try {sessionStorage.setItem('pixel-sky-webgpu-fallback','1');location.reload();return;}catch{/* Report below. */}
    }
    console.error(error);
    el('boot-text').textContent='游戏无法启动';
    const box=el('boot-error');box.hidden=false;
    box.textContent='请使用支持 WebGL2 的 Chrome 或 Edge，开启图形加速后重新载入。';
  }
}
void start();
