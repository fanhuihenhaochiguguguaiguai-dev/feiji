import './style.css';
import './v7-ui.css';
import { startupFailure } from './startup';

import('./main').catch(error=>startupFailure('启动文件未能载入。请重试，或使用 WebGL2 安全模式。',error));
addEventListener('vite:preloadError',event=>{
  if(document.getElementById('application')?.dataset.screen==='loading')return;
  startupFailure('发布文件未能载入。重新连接可读取本次发布的完整文件。',event);
});
