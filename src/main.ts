import './style.css';
import './v7-ui.css';
declare const __FLAGSHIP_QA__:boolean;
import { Game, openEngine } from './engine';
import { el } from './interface';
import { loadPersistentProfile } from './profile';
import { loadTerrain } from './terrain';
import { theatres } from './data';
import { loading } from './loading';

async function start(){
  let activeBackend='';
  const blocked=()=>{try{return sessionStorage.getItem('pixel-sky-webgpu-fallback')==='1';}catch{return false;}};
  try {
    loading(6,'正在读取飞行员档案');
    const profile=await loadPersistentProfile();
    loading(19,'正在打开图形设备');
    const entry=await openEngine(el<HTMLCanvasElement>('scene'),blocked()?'gl':profile.settings.backend);
    activeBackend=entry.backend;
    loading(31,'正在读取机库地貌');
    const initial=theatres[0];
    await loadTerrain(initial.seed,new URL('world/'+initial.id+'.height',document.baseURI).href);
    loading(43,'正在读取机库与战机素材');
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
    console.error(error);
    el('boot-text').textContent='游戏无法启动';
    const box=el('boot-error');box.hidden=false;
    box.textContent='请使用支持 WebGL2 的 Chrome 或 Edge，开启图形加速后重新载入。';
  }
}
void start();
